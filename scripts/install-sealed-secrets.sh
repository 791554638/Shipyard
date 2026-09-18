#!/usr/bin/env bash
# 安装 Sealed Secrets controller 到集群（kube-system）
#
# 固定版本：v0.27.3（与客户端 kubeseal 同版本）
#
# 用法：./scripts/install-sealed-secrets.sh
# 环境变量可选：
#   SEALED_SECRETS_VERSION  覆盖默认版本（默认 v0.27.3）
#
# 一次性安装。controller 在集群内自动生成密钥对：
#   - 公钥：kubeseal 客户端通过 kubectl fetch 获取，用于离线加密
#   - 私钥：仅存于集群 kube-system/sealed-secrets-key* Secret，git/外部不可读
# 私钥泄露风险为零——只要集群不被入侵，加密过的 SealedSecret 在 git/外部泄露也是安全的。

set -euo pipefail

SEALED_SECRETS_VERSION="${SEALED_SECRETS_VERSION:-v0.27.3}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

command -v kubectl >/dev/null 2>&1 || { err "未找到 kubectl"; exit 1; }

URL="https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"
MANIFEST="$(mktemp)"
trap 'rm -f "${MANIFEST}"' EXIT

info "下载 Sealed Secrets controller ${SEALED_SECRETS_VERSION}..."
if ! curl -fsSL "${URL}" -o "${MANIFEST}"; then
    err "下载失败：${URL}"
    err "如需离线安装，可手动下载后：kubectl apply -f <path>"
    exit 1
fi

info "应用到集群..."
kubectl apply -f "${MANIFEST}"

info "等待 controller 就绪..."
if ! kubectl wait --for=condition=ready pod \
        -l name=sealed-secrets-controller -n kube-system --timeout=180s; then
    warn "controller 启动超时（可能镜像拉取慢或 registry mirror 受限）"
    echo "      排查：kubectl get pods -n kube-system | grep sealed"
    echo "      日志：kubectl logs -n kube-system -l name=sealed-secrets-controller"
    exit 1
fi

echo
info "✅ Sealed Secrets controller ${SEALED_SECRETS_VERSION} 已部署到 kube-system"
info "客户端安装（macOS）：brew install kubeseal"
info "客户端安装（其他）：从 https://github.com/bitnami-labs/sealed-secrets/releases 下载 ${SEALED_SECRETS_VERSION} 对应平台二进制"
info "下一步：./scripts/seal-secret.sh > k8s/sealed-secret.yaml"