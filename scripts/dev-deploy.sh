#!/usr/bin/env bash
# v0.6.0 内循环核心：改代码 → make dev → 集群里跑的就是新代码
#
# 用法：
#   ./scripts/dev-deploy.sh             # 迭代部署：build → push → apply → rollout status
#   ./scripts/dev-deploy.sh --init      # 首次部署：确保集群/registry + Secret + 全量资源 + 等待就绪
#   ./scripts/dev-deploy.sh --skip-build
#
# 铁律（见 docs/roadmap.md §4.3）：闭环的终点是「验证」而非「apply 完成」
#   rollout status 失败 → 非零退出 + 打印定位命令
#
# 镜像 tag 策略：git sha（与 GHCR 引用同构）
#   干净工作区  → localhost:5001/cfa-php:sha-a1b2c3d
#   有未提交改动 → sha-a1b2c3d-dirty174530（追加后缀，确保触发重新拉取）

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

KIND_CONTEXT="kind-cfa"
NAMESPACE="cfa"
REGISTRY="localhost:5001"
TIMEOUT="120s"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

INIT=0
SKIP_BUILD=0
for arg in "$@"; do
    case "${arg}" in
        --init)       INIT=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        -h|--help)    sed -n '2,14p' "$0"; exit 0 ;;
        *)            err "未知参数：${arg}（--init / --skip-build）"; exit 1 ;;
    esac
done

# 失败诊断：非零退出前必须给出定位命令
on_fail() {
    echo
    err "部署失败！定位命令："
    echo "  kubectl --context ${KIND_CONTEXT} get pods -n ${NAMESPACE} -o wide"
    echo "  kubectl --context ${KIND_CONTEXT} describe pod -n ${NAMESPACE} -l app=php"
    echo "  kubectl --context ${KIND_CONTEXT} logs -n ${NAMESPACE} -l app=php --tail=50"
}
trap on_fail ERR

# ---------- 1. 前置检查 ----------
command -v kubectl >/dev/null 2>&1 || { err "未找到 kubectl"; exit 1; }

if [[ "${INIT}" -eq 1 ]]; then
    ./scripts/dev-cluster.sh ensure
fi

# context 守卫：防止误部署到 docker-desktop 等其他集群
CURRENT_CTX="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${CURRENT_CTX}" != "${KIND_CONTEXT}" ]]; then
    err "当前 kubectl context 是 '${CURRENT_CTX}'，内循环要求 '${KIND_CONTEXT}'"
    echo "  切换：kubectl config use-context ${KIND_CONTEXT}"
    echo "  或创建：./scripts/dev-cluster.sh create && make init"
    exit 1
fi

if [[ "${INIT}" -ne 1 ]]; then
    # 迭代模式前置：首次部署必须走 --init
    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 \
        || ! kubectl get secret cfa-secret -n "${NAMESPACE}" >/dev/null 2>&1; then
        err "namespace/${NAMESPACE} 或 secret/cfa-secret 不存在 —— 首次部署请用：make init"
        exit 1
    fi
fi

# ---------- 2. 镜像构建 + 推送 ----------
# tag 策略：干净工作区 → git sha；有改动 → sha-dirty<内容hash>（确定性后缀：
# 内容不变则 tag 不变，--skip-build / 镜像缓存均可安全复用）
SHA="$(git rev-parse --short=7 HEAD)"
if git diff --quiet HEAD -- app/ docker/; then
    TAG="sha-${SHA}"
else
    DIRTY_HASH="$(git diff HEAD -- app/ docker/ | shasum | cut -c1-6)"
    TAG="sha-${SHA}-dirty${DIRTY_HASH}"
    warn "app/ 或 docker/ 有未提交改动 → tag: ${TAG}"
    warn "提交后 tag 恢复干净的 sha 形式，可追溯性更好"
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
    info "构建镜像（tag: ${TAG}）"
    docker build -f docker/app/Dockerfile \
        -t "${REGISTRY}/cfa-php:${TAG}" \
        -t cfa/php:dev .
    docker build -f docker/nginx/Dockerfile \
        -t "${REGISTRY}/cfa-nginx:${TAG}" \
        -t cfa/nginx:dev \
        docker/nginx

    info "推送到本地 registry ${REGISTRY}"
    docker push "${REGISTRY}/cfa-php:${TAG}"
    docker push "${REGISTRY}/cfa-nginx:${TAG}"
fi

# ---------- 3. 临时 overlay：镜像注入（git 零污染） ----------
# 注意：Kustomize 的 resources 不接受绝对路径（"new root cannot be absolute"），
# 因此 overlay 必须建在项目内、用相对路径引用 ../k8s（目录已在 .gitignore，用后即删）
OVERLAY_DIR="${PROJECT_ROOT}/.ktmp"
rm -rf "${OVERLAY_DIR}"
mkdir -p "${OVERLAY_DIR}"
trap 'rm -rf "${OVERLAY_DIR}"' EXIT
cat > "${OVERLAY_DIR}/kustomization.yaml" <<EOF
# 自动生成（scripts/dev-deploy.sh），勿提交
resources:
  - ../k8s
images:
  - name: cfa/php
    newName: ${REGISTRY}/cfa-php
    newTag: ${TAG}
  - name: cfa/nginx
    newName: ${REGISTRY}/cfa-nginx
    newTag: ${TAG}
EOF

# ---------- 4. 部署 ----------
if [[ "${INIT}" -eq 1 ]]; then
    # Secret：learn 模式，从 .env 渲染（与 deploy.sh / CI secret-render 同构）
    if [[ ! -f .env ]]; then
        err "未找到 .env —— 请先执行：cp .env.example .env"
        exit 1
    fi
    command -v envsubst >/dev/null 2>&1 \
        || { err "未找到 envsubst（brew install gettext）"; exit 1; }
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
    for var in MYSQL_ROOT_PASSWORD MYSQL_PASSWORD ELASTIC_PASSWORD; do
        [[ -n "$(printenv "$var")" ]] || { err ".env 中 ${var} 为空"; exit 1; }
    done
    RENDERED="$(envsubst < k8s/secret.yaml.tpl)"
    if printf '%s' "$RENDERED" | grep -qE '\$\{[A-Z_]+\}'; then
        err "占位符未被替换（检查 .env 与 secret.yaml.tpl 变量名一致性）"
        exit 1
    fi
    info "[init] 应用 Secret（.env 渲染，明文不落盘、不进 git）"
    # namespace 必须先于 Secret 存在（Secret 是 namespace 级资源）
    kubectl apply -f k8s/namespace.yaml
    printf '%s' "$RENDERED" | kubectl apply -f -
fi

info "应用资源（Kustomize overlay 注入镜像 ${TAG}）"
kubectl apply -k "${OVERLAY_DIR}"

if [[ "${INIT}" -eq 1 ]]; then
    # 有状态服务就绪等待（首次启动较慢；超时警告不中断，问题会在 rollout status 暴露）
    info "[init] 等待 MySQL / Redis / ES 就绪（ES 首次启动约 1-3 分钟）..."
    kubectl wait --for=condition=ready pod -l app=mysql -n "${NAMESPACE}" --timeout=180s \
        || warn "MySQL 等待超时"
    kubectl wait --for=condition=ready pod -l app=redis -n "${NAMESPACE}" --timeout=120s \
        || warn "Redis 等待超时"
    kubectl wait --for=condition=ready pod -l app=elasticsearch -n "${NAMESPACE}" --timeout=300s \
        || warn "ES 等待超时"
fi

# ---------- 5. 验证（闭环终点） ----------
info "等待 rollout 完成（失败即中止）"
kubectl rollout status deployment/php -n "${NAMESPACE}" --timeout="${TIMEOUT}"
kubectl rollout status deployment/nginx -n "${NAMESPACE}" --timeout="${TIMEOUT}"

echo
info "✅ 部署完成（image: ${TAG}）"
kubectl get deployment php nginx -n "${NAMESPACE}" \
    -o custom-columns='DEPLOYMENT:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas'
echo
info "访问：make ui   （port-forward + 打开浏览器）"
info "日志：make logs"
