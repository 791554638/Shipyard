# Scripts

辅助脚本集合。

| 脚本 | 用途 |
|---|---|
| `deploy.sh` | K8s 一键部署：构建镜像 → apply manifest → 等待就绪 |
| `init-es-indices.sh` | 创建带 IK 分词器的 ES 索引，并灌入测试数据 |
| `cleanup-old-dirs.sh` | 清理本次目录重构遗留的旧空目录 |

使用前记得 `chmod +x scripts/*.sh`。