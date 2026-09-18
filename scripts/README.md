# Scripts

辅助脚本集合。

| 脚本 | 用途 |
|---|---|
| `deploy.sh` | K8s 一键部署：构建镜像 → apply manifest → 等待就绪。支持 `--mode=learn`（默认，明文 Secret）/ `--mode=prod`（密文 SealedSecret，需 controller） |
| `install-sealed-secrets.sh` | 一次性安装 Sealed Secrets controller 到集群（固定 v0.27.3） |
| `seal-secret.sh` | 一键加密 Secret：`.env` 明文 → 渲染模板 → `kubeseal` 加密 → 输出 SealedSecret 到 `k8s/sealed-secret.yaml` |
| `init-es-indices.sh` | 创建带 IK 分词器的 ES 索引，并灌入测试数据 |
| `cleanup-old-dirs.sh` | 清理本次目录重构遗留的旧空目录 |

使用前记得 `chmod +x scripts/*.sh`。

完整密钥流转（`.env` → SealedSecret）见 **[docs/sealed-secrets.md](../docs/sealed-secrets.md)**。