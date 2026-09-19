#!/usr/bin/env bash
# kind 集群 + 本地 registry 生命周期管理（v0.6.0 内循环基础设施）
#
# 用法：
#   ./scripts/dev-cluster.sh create    # 创建集群 + 启动本地 registry（幂等）
#   ./scripts/dev-cluster.sh delete    # 删除集群与 registry
#   ./scripts/dev-cluster.sh status    # 查看集群 / registry / registry 连通性
#   ./scripts/dev-cluster.sh ensure    # 不存在则创建（供 dev-deploy.sh --init 调用）
#
# 架构（见 kind-config.yaml）：
#   宿主机 --(localhost:5001)--> registry 容器 <--(cfa-registry:5000, kind 网络)-- kind 节点
#   镜像 tag 结构：localhost:5001/cfa-php:sha-xxxxxxx（与 GHCR 引用同构，v0.9.0 只换前缀）

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

CLUSTER_NAME="cfa"
REGISTRY_NAME="cfa-registry"
REGISTRY_PORT="5001"   # 宿主机端口（5000 常被 macOS AirPlay Receiver 占用，避开）
KIND_CONTEXT="kind-${CLUSTER_NAME}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() { sed -n '2,12p' "$0"; exit 1; }

# ---------- 前置检查 ----------
require_kind() {
    command -v kind >/dev/null 2>&1 \
        || { err "未找到 kind，请先安装：brew install kind"; exit 1; }
}

require_docker() {
    docker info >/dev/null 2>&1 \
        || { err "Docker 未运行，请先启动 Docker Desktop"; exit 1; }
}

cluster_exists() {
    kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"
}

registry_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || echo false)" = "true" ]
}

# ---------- registry ----------
start_registry() {
    if registry_running; then
        info "本地 registry ${REGISTRY_NAME} 已在运行"
        # 确保挂在 kind 网络上（集群重建后网络会换新）
        docker network connect "kind" "${REGISTRY_NAME}" 2>/dev/null || true
        return
    fi
    # 同名容器存在但已停止 → 先清理
    docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true

    info "启动本地 registry（宿主机 localhost:${REGISTRY_PORT}）"
    docker run -d \
        --name "${REGISTRY_NAME}" \
        --restart=always \
        --network kind \
        -p "127.0.0.1:${REGISTRY_PORT}:5000" \
        registry:2 >/dev/null
}

# ---------- 子命令 ----------
do_create() {
    require_kind
    require_docker

    # 端口占用前置检查（风险表：registry 端口被占用）
    if lsof -nP -iTCP:"${REGISTRY_PORT}" -sTCP:LISTEN >/dev/null 2>&1 \
        && ! registry_running; then
        err "端口 ${REGISTRY_PORT} 已被其他进程占用（lsof -i:${REGISTRY_PORT} 查看）"
        exit 1
    fi

    if cluster_exists; then
        info "kind 集群 ${CLUSTER_NAME} 已存在，跳过创建"
    else
        info "创建 kind 集群 ${CLUSTER_NAME}（双节点，含 containerd registry mirror）..."
        kind create cluster --config kind-config.yaml --wait 60s
    fi

    start_registry

    info "当前 kubectl context → ${KIND_CONTEXT}"
    kubectl config use-context "${KIND_CONTEXT}"
    echo
    info "集群就绪。下一步：make init（首次全量部署）"
}

do_delete() {
    require_kind
    require_docker
    if cluster_exists; then
        warn "将删除 kind 集群 ${CLUSTER_NAME}（集群内数据不保留）"
        kind delete cluster --name "${CLUSTER_NAME}"
    else
        info "集群 ${CLUSTER_NAME} 不存在"
    fi
    if docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1; then
        info "已删除本地 registry 容器 ${REGISTRY_NAME}（镜像数据随之清空，可随时重新 push）"
    fi
}

do_status() {
    echo "=== kind 集群 ==="
    if cluster_exists; then
        kubectl --context "${KIND_CONTEXT}" get nodes
    else
        echo "未创建（./scripts/dev-cluster.sh create）"
    fi
    echo
    echo "=== 本地 registry ==="
    if registry_running; then
        echo "容器 ${REGISTRY_NAME} 运行中 → 宿主机 localhost:${REGISTRY_PORT}"
        if curl -sf "localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null; then
            echo "已推送镜像："
            curl -s "localhost:${REGISTRY_PORT}/v2/_catalog" | sed 's/.*repositories":\[/  /; s/\].*/]/'
        fi
    else
        echo "未运行"
    fi
}

do_ensure() {
    if ! cluster_exists; then
        do_create
    else
        require_docker
        start_registry
    fi
}

case "${1:-}" in
    create) do_create ;;
    delete) do_delete ;;
    status) do_status ;;
    ensure) do_ensure ;;
    *)      usage ;;
esac
