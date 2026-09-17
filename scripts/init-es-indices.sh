#!/usr/bin/env bash
# 初始化 ES 索引（演示 IK 分词）
#
# 用法：
#   ./scripts/init-es-indices.sh                    # 默认连接 localhost:9200
#   ES_URL=http://es.cfa.local ./scripts/init-es-indices.sh
#
# 集群内使用：
#   kubectl exec -n cfa deploy/nginx -- ./scripts/init-es-indices.sh
# 或 kubectl port-forward svc/elasticsearch 9200:9200 -n cfa 后本地跑

set -euo pipefail

ES_URL="${ES_URL:-http://localhost:9200}"

echo "==> ES URL: ${ES_URL}"

# 健康检查
echo "==> 检查集群状态"
if ! curl -sf "${ES_URL}/_cluster/health" > /dev/null; then
    echo "错误: 无法连接 ES，请先 kubectl port-forward 或检查 ES 状态"
    exit 1
fi
curl -s "${ES_URL}/_cluster/health" | python3 -m json.tool || true
echo

# 创建 articles 索引（使用 IK 分词器）
echo "==> 创建 articles 索引"
curl -sX PUT "${ES_URL}/articles" \
    -H 'Content-Type: application/json' \
    -d '{
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "analysis": {
          "analyzer": {
            "ik_smart_pinyin": {
              "type": "custom",
              "tokenizer": "ik_smart"
            }
          }
        }
      },
      "mappings": {
        "properties": {
          "title":   { "type": "text", "analyzer": "ik_max_word", "search_analyzer": "ik_smart" },
          "content": { "type": "text", "analyzer": "ik_max_word", "search_analyzer": "ik_smart" },
          "created_at": { "type": "date" }
        }
      }
    }' | python3 -m json.tool || true

# 灌几条测试数据
echo "==> 灌入测试数据"
for i in 1 2 3; do
    curl -sX POST "${ES_URL}/articles/_doc/${i}?refresh=true" \
        -H 'Content-Type: application/json' \
        -d "{
          \"title\": \"K8s 学习笔记 ${i}\",
          \"content\": \"这是关于 Kubernetes 第 ${i} 篇笔记，介绍 Pod、Service、Ingress 的概念\",
          \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
        }" > /dev/null
done

# 演示中文搜索
echo
echo "==> 测试中文搜索（IK 分词）"
curl -s "${ES_URL}/articles/_search?pretty" \
    -H 'Content-Type: application/json' \
    -d '{
      "query": {
        "match": {
          "content": "Kubernetes"
        }
      }
    }' | python3 -m json.tool || true

echo
echo "==> 完成！"