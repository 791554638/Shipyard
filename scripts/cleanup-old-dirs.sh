#!/usr/bin/env bash
# 清理本次重构遗留的旧空目录
#
# 重构后：
#   - elasticsearch/  → services/elasticsearch/
#   - kibana/         → services/kibana/
#   - mysql/          → services/mysql/
#   - nginx/          → services/nginx/
#   - php/            → services/php/
#   - redis/          → services/redis/
#
# 这些顶层旧目录已是空壳，运行本脚本一次性删除
# 脚本只在确认每个目录为空时才删除，避免误删

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

OLD_DIRS=(
    "elasticsearch"
    "kibana"
    "mysql"
    "nginx"
    "php"
    "redis"
)

for d in "${OLD_DIRS[@]}"; do
    if [[ ! -d "${d}" ]]; then
        echo "[skip] ${d} 不存在"
        continue
    fi

    # 仅当目录为空时删除
    if [[ -z "$(ls -A "${d}" 2>/dev/null)" ]]; then
        echo "[rm]   ${d} （空目录）"
        rmdir "${d}"
    else
        echo "[keep] ${d} 非空，请手动检查：ls -la ${d}"
    fi
done

echo
echo "==> 完成。当前顶层目录："
ls -la