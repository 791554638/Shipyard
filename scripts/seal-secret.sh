#!/usr/bin/env bash
# 一键加密 Secret：.env 明文 → 渲染模板 → kubeseal 加密 → 输出 SealedSecret
#
# 用法：
#   ./scripts/seal-secret.sh                          # 默认写到 k8s/sealed-secret.yaml
#   ./scripts/seal-secret.sh --output custom.yaml     # 自定义输出路径
#   ./scripts/seal-secret.sh --dry-run                # 只渲染不加密（调试模板用）
#
# 前置：
#   1. cp .env.example .env 并填入生产密码
#   2. 已部署 Sealed Secrets controller（./scripts/install-sealed-secrets.sh）
#   3. 已安装 kubeseal 客户端（brew install kubeseal）
#   4. kubectl 能连上集群（kubeseal 默认从集群自动取公钥）
#
# 安全：
#   - .env 已在 .gitignore 中
#   - 输出是 SealedSecret（密文），可安全提交到 git
#   - 全流程不打印明文密码（除 --dry-run 外）

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

OUTPUT="k8s/sealed-secret.yaml"
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)        OUTPUT="$2"; shift 2 ;;
        --output=*)      OUTPUT="${1#*=}"; shift ;;
        --dry-run)       DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,18p' "$0"; exit 0 ;;
        *)
            echo "未知参数: $1"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0m'; NC='\033[0m'
info() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

command -v kubectl >/dev/null 2>&1  || { err "未找到 kubectl"; exit 1; }
command -v envsubst >/dev/null 2>&1 || { err "未找到 envsubst（apt install gettext-base / brew install gettext）"; exit 1; }

# kubeseal PATH 兜底（用户常见安装位置：~/bin、Homebrew）
if ! command -v kubeseal >/dev/null 2>&1; then
    for p in "$HOME/bin/kubeseal" /opt/homebrew/bin/kubeseal /usr/local/bin/kubeseal; do
        if [[ -x "$p" ]]; then
            p_dir="$(dirname "$p")"
            export PATH="${p_dir}:$PATH"
            break
        fi
    done
fi
command -v kubeseal >/dev/null 2>&1 || { err "未找到 kubeseal（brew install kubeseal）"; exit 1; }

# 1) .env 必填
if [[ ! -f .env ]]; then
    err ".env 不存在，请先：cp .env.example .env 并填入生产密码"
    exit 1
fi
info ".env 已读取"

# 2) 加载到当前进程（不导出到脚本外，脚本退出后自动失效）
set -a
# shellcheck disable=SC1091
. ./.env
set +a

# 3) 三个 Secret 必填
missing=0
for var in MYSQL_ROOT_PASSWORD MYSQL_PASSWORD ELASTIC_PASSWORD; do
    if [[ -z "${!var:-}" ]]; then
        err ".env 中 $var 为空"
        missing=1
    fi
done
[[ $missing -eq 0 ]] || exit 1

# 4) 渲染模板
RENDERED="$(envsubst < k8s/secret.yaml.tpl)"
if printf '%s' "$RENDERED" | grep -qE '\$\{[A-Z_]+\}'; then
    err "占位符未被替换（检查 .env 变量名与 secret.yaml.tpl 一致性）"
    exit 1
fi

# 5) dry-run 短路
if [[ $DRY_RUN -eq 1 ]]; then
    info "DRY RUN：渲染结果如下（明文，仅用于调试模板）"
    printf '%s\n' "$RENDERED"
    exit 0
fi

# 6) 加密：从集群拉公钥（需 controller 已就绪）
info "从集群获取公钥 + 加密（需 controller 已就绪）..."
SEALED_OUTPUT="$(printf '%s' "$RENDERED" | kubeseal --format yaml)"

# 7) 写文件
printf '%s\n' "$SEALED_OUTPUT" > "${OUTPUT}"
info "✅ 已写入 ${OUTPUT}（密文，可安全提交到 git）"

echo
info "下一步："
echo "    git add ${OUTPUT}"
echo "    git commit -m 'feat: 加密生产密码 (v0.5.0 sealed-secret)'"
echo "    ./scripts/deploy.sh --mode=prod"

# 清内存（脚本结束自动消失，但显式 unset 更稳妥）
unset MYSQL_ROOT_PASSWORD MYSQL_PASSWORD ELASTIC_PASSWORD RENDERED SEALED_OUTPUT