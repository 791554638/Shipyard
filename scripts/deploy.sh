#!/usr/bin/env bash
# K8s 一键部署脚本
#
# 前置条件：
#   1. 已安装 kubectl 并能连上集群（kubectl cluster-info）
#   2. 集群有默认 StorageClass（kubectl get sc）
#   3. 已创建 .env（cp .env.example .env）—— learn 模式渲染 Secret 必需
#   4. 已构建自定义镜像：cfa/php:8.2 与 cfa/nginx:1.25
#      docker build -t cfa/php:8.2  -f docker/app/Dockerfile .
#      docker build -t cfa/nginx:1.25 -f docker/nginx/Dockerfile .
#
# 用法：
#   ./scripts/deploy.sh                          # 默认 learn 模式
#   ./scripts/deploy.sh --mode=prod              # 生产模式（apply SealedSecret）
#   ./scripts/deploy.sh --skip-build             # 跳过镜像构建（CI/CD 场景）
#   ./scripts/deploy.sh --skip-ingress           # 跳过 Ingress（裸集群无 Controller）
#
# 模式说明：
#   learn（默认）：从 .env 渲染 k8s/secret.yaml.tpl 注入（与 CI 同构，明文不落盘、不进 git）
#   prod         ：apply k8s/sealed-secret.yaml（密文，controller 自动转 Secret）
#                 需先运行 ./scripts/seal-secret.sh 生成

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

MODE="learn"
SKIP_BUILD=0
SKIP_INGRESS=0
for arg in "$@"; do
    case "${arg}" in
        --mode=learn)   MODE="learn" ;;
        --mode=prod)    MODE="prod" ;;
        --skip-build)   SKIP_BUILD=1 ;;
        --skip-ingress) SKIP_INGRESS=1 ;;
        -h|--help)
            sed -n '2,22p' "$0"
            exit 0
            ;;
    esac
done

# 颜色
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# 检查前置
if ! command -v kubectl >/dev/null 2>&1; then
    echo "错误: 未找到 kubectl"
    exit 1
fi

info "集群信息："
kubectl cluster-info

# prod 模式前置检查（早失败，避免白白构建镜像）
if [[ "${MODE}" == "prod" ]]; then
    if [[ ! -f k8s/sealed-secret.yaml ]]; then
        echo "错误: --mode=prod 但 k8s/sealed-secret.yaml 不存在"
        echo "      请先运行：./scripts/seal-secret.sh 生成密文"
        exit 1
    fi
    if ! kubectl get crd sealedsecrets.bitnami.com >/dev/null 2>&1; then
        echo "错误: 集群未安装 Sealed Secrets controller"
        echo "      请先运行：./scripts/install-sealed-secrets.sh"
        exit 1
    fi
fi

# 构建镜像
if [[ ${SKIP_BUILD} -eq 0 ]]; then
    info "构建自定义镜像"
    docker build -t cfa/php:8.2    -f docker/app/Dockerfile   .
    docker build -t cfa/nginx:1.25 -f docker/nginx/Dockerfile .

    # kind / minikube 需要把镜像加载到集群
    if command -v kind >/dev/null 2>&1; then
        info "kind 检测到，加载镜像到集群"
        kind load docker-image cfa/php:8.2
        kind load docker-image cfa/nginx:1.25
    elif command -v minikube >/dev/null 2>&1; then
        info "minikube 检测到，加载镜像到集群"
        minikube image load cfa/php:8.2
        minikube image load cfa/nginx:1.25
    fi
fi

info "应用 Namespace / Secret / ConfigMap"
kubectl apply -f k8s/namespace.yaml

# 双模式：learn 从 .env 渲染模板（与 CI 注入同构），prod 用密文 sealed-secret.yaml
if [[ "${MODE}" == "prod" ]]; then
    info "[mode=prod] 应用 SealedSecret（controller 将自动解密为 Secret）"
    kubectl apply -f k8s/sealed-secret.yaml
else
    info "[mode=learn] 从 .env 渲染 Secret（模板 + 环境变量注入，明文不落盘、不进 git）"
    if [[ ! -f .env ]]; then
        echo "错误: 未找到 .env —— 请先执行：cp .env.example .env"
        exit 1
    fi
    command -v envsubst >/dev/null 2>&1 \
        || { echo "错误: 未找到 envsubst（brew install gettext / apt install gettext-base）"; exit 1; }

    # 导出 .env 全部变量（密码只存在于本进程环境）
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a

    # 与 CI secret-render 相同的防线：空值检查 + 占位符替换检查
    for var in MYSQL_ROOT_PASSWORD MYSQL_PASSWORD ELASTIC_PASSWORD; do
        [[ -n "$(printenv "$var")" ]] || { echo "错误: .env 中 ${var} 为空"; exit 1; }
    done
    RENDERED="$(envsubst < k8s/secret.yaml.tpl)"
    if printf '%s' "$RENDERED" | grep -qE '\$\{[A-Z_]+\}'; then
        echo "错误: 占位符未被替换（检查 .env 与 secret.yaml.tpl 变量名一致性）"
        exit 1
    fi
    # 管道直传 kubectl，渲染结果不写文件（结构校验由 CI kubeconform 承担）
    printf '%s' "$RENDERED" | kubectl apply -f -
fi

kubectl apply -f k8s/config/

info "应用有状态服务（按 MySQL → Redis → ES 顺序）"
kubectl apply -f k8s/mysql/
info "等待 MySQL 就绪..."
kubectl wait --for=condition=ready pod -l app=mysql -n cfa --timeout=180s || warn "MySQL 等待超时，继续下一步"

kubectl apply -f k8s/redis/
info "等待 Redis 就绪..."
kubectl wait --for=condition=ready pod -l app=redis -n cfa --timeout=120s || warn "Redis 等待超时"

kubectl apply -f k8s/elasticsearch/
info "等待 Elasticsearch 就绪（首次启动较慢，约 1-3 分钟）..."
kubectl wait --for=condition=ready pod -l app=elasticsearch -n cfa --timeout=300s || warn "ES 等待超时"

info "应用无状态服务"
kubectl apply -f k8s/kibana/
kubectl apply -f k8s/php/
kubectl apply -f k8s/nginx/

if [[ ${SKIP_INGRESS} -eq 0 ]]; then
    info "应用 Ingress"
    kubectl apply -f k8s/ingress.yaml || warn "Ingress 应用失败（可能未安装 Ingress Controller）"
fi

echo
info "部署完成！查看状态："
kubectl get all -n cfa
echo
info "访问方式："
echo "  - 端口转发（最快）："
echo "      kubectl port-forward -n cfa svc/nginx 8080:80"
echo "  - Ingress（生产）："
echo "      在 /etc/hosts 添加：\$(minikube ip) cfa.local"
echo "      然后访问 http://cfa.local"