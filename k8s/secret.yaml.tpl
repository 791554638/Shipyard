# Secret 模板：占位符由 CI（GitHub Secrets + envsubst）渲染
#
# 双模式说明（docs/secrets-management.md）：
#   - 学习模式（默认）：直接 apply k8s/secret.yaml（明文默认值，开箱即用）
#   - 生产模式：本模板 + GitHub Actions Secrets 渲染，真实密码不进 git
#
# 密码流转：GitHub Secrets → job env → envsubst（内存）→ kubeconform 校验
#   ✗ 不落盘  ✗ 不上传 artifact  ✗ 不打印（GitHub 自动 mask 为 ***）

apiVersion: v1
kind: Secret
metadata:
  name: cfa-secret
  namespace: cfa
type: Opaque
stringData:
  MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASSWORD}"
  MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
  ELASTIC_PASSWORD: "${ELASTIC_PASSWORD}"
