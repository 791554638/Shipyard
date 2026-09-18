# Shipyard — Kubernetes 全栈学习项目

> **Shipyard** — 在这里造你的第一艘船：从 docker-compose 的独木舟，到 Kubernetes 的远洋舰队。
>
> 一个面向 **K8s 初学者** 的全栈示例项目，覆盖 PHP 应用 + MySQL + Redis + ELK 日志栈（Elasticsearch + Kibana + Logstash + Filebeat）+ Nginx 共 8 个组件，所有组件均可在 **本地 docker-compose** 和 **K8s 集群** 中运行。
>
> 命名由来：Kubernetes 源自希腊语"舵手"（helmsman），容器如货轮，本项目就是教你从零造船（构建镜像）、编队（编排服务）、远航（上 K8s 集群）的造船厂。

## 1. 项目目标

* 用一个真实可跑的项目把 K8s 核心概念串起来：Namespace / ConfigMap / Secret / PVC / Deployment / StatefulSet / DaemonSet / Service / Ingress / InitContainer
* 同一份配置（`services/`）在本地与 K8s 中复用，避免"本地能跑、线上跑不起来"
* 提供从 docker-compose 到 K8s 的平滑迁移路径
* 完整的中文日志采集链路：应用/Filebeat → Logstash → Elasticsearch → Kibana

## 2. 架构与数据流

```
                    ┌────────── 应用层 ──────────┐
                    │                            │
Nginx/PHP ──tcp:5044 (json)──┐                  │
                             │                  │
Filebeat ──:5045 (beats)──────┴──→ Logstash ──http+auth──→ Elasticsearch ──→ Kibana(:5601)
（本地：日志目录）              (8.11.0)          (8.11.0)              (8.11.0)
（K8s：DaemonSet 采集容器日志）
```

* **Logstash 双入口**：`5044` 应用直推（json_lines）/ `5045` Filebeat（beats 协议）
* **ES 安全特性**：开启 xpack（HTTP + Basic Auth），中文分词用 IK（启动时自动安装）

## 3. 目录结构

```
shipyard/                    ← 项目根目录（repo 名与目录名可不同）
├── README.md                 ← 本文件
├── docker-compose.yml        ← 本地一键起全部依赖
├── Makefile                  ← 内循环入口：make init / dev / ui / logs（v0.6.0）
├── kind-config.yaml          ← kind 集群配置（本地 registry mirror，v0.6.0）
├── .gitignore
├── .env.example              ← 环境变量模板（复制为 .env 自定义密码）
├── .hadolint.yaml            ← Dockerfile lint 规则（忽略项）
│
├── .github/workflows/        ← CI 流水线（push/PR 自动触发）
│   └── lint.yml              ← 七项校验，见「9.5 CI 流水线」
│
├── app/                      ← PHP 业务代码
│   ├── public/index.php      ← 入口（通过 Nginx + PHP-FPM）
│   ├── src/                  ← 业务逻辑
│   └── composer.json
│
├── docker/                   ← 自定义镜像构建
│   ├── app/Dockerfile        ← PHP 应用镜像（代码进镜像 + ARG 参数化，v0.6.0）
│   └── nginx/Dockerfile      ← Nginx 镜像（含 vhost 配置）
│
├── services/                 ← 各组件的原始配置，与 K8s / docker-compose 共享
│   ├── elasticsearch/conf/elasticsearch.yml
│   ├── kibana/conf/kibana.yml
│   ├── logstash/conf/             ← pipeline + 参考配置
│   │   ├── pipeline/logstash.conf ← 三段式：input→filter→output
│   │   └── logstash.yml           ← ⚠️ 不挂载进容器（见文件内注释）
│   ├── filebeat/conf/filebeat.yml ← Nginx/PHP 日志采集
│   ├── mysql/conf/                ← my.cnf + init.sql
│   ├── redis/conf/redis.conf
│   ├── nginx/conf/nginx.conf
│   ├── php/conf/php.ini
│   └── logs/                      ← 运行时日志（gitignore，filebeat 采集源）
│
├── k8s/                      ← K8s 部署清单
│   ├── kustomization.yaml    ← Kustomize 入口（镜像 tag 由 dev-deploy.sh 注入，v0.6.0）
│   ├── namespace.yaml
│   ├── secret.yaml.tpl       ← Secret 渲染模板（${VAR} 占位符，.env/CI 注入，明文不进 git）
│   ├── sealed-secret.yaml    ← 生产模式密文（v0.5.0 生成，可安全提交）
│   ├── config/               ← ConfigMap：所有组件的配置
│   ├── mysql/                ← StatefulSet + Service
│   ├── redis/                ← StatefulSet + Service
│   ├── elasticsearch/        ← StatefulSet（initContainer 装 IK 分词器）
│   ├── kibana/               ← Deployment + Service（kibana_system 连接）
│   ├── logstash/             ← Deployment + NodePort Service(30444)
│   ├── filebeat/             ← DaemonSet + ConfigMap + RBAC（采集容器日志）
│   ├── php/                  ← Deployment + Service
│   ├── nginx/                ← Deployment + Service
│   ├── ingress.yaml
│   └── README.md             ← 部署指南
│
├── docs/
│   ├── architecture.md       ← 架构图与组件说明
│   ├── deploy.md             ← 详细部署步骤（含 v0.6.0 内循环）
│   ├── roadmap.md            ← 后续版本路线图（v0.6.0→v1.3.0）
│   ├── secrets-management.md ← 密钥/参数管理方案（v0.3.0→v0.5.0 路线图）
│   └── sealed-secrets.md     ← Sealed Secrets 使用指南（v0.5.0）
│
└── scripts/
    ├── init-es-indices.sh          ← ES 索引初始化（IK 分词）
    ├── deploy.sh                   ← K8s 一键部署（--mode=learn|prod）
    ├── dev-cluster.sh              ← kind 集群 + 本地 registry 生命周期（v0.6.0）
    ├── dev-deploy.sh               ← 内循环核心：build→push→apply→verify（v0.6.0）
    ├── install-sealed-secrets.sh   ← 安装 Sealed Secrets controller（v0.5.0）
    ├── seal-secret.sh              ← 一键加密 Secret → SealedSecret（v0.5.0）
    └── cleanup-old-dirs.sh         ← 清理历史遗留空目录
```

## 4. 技术栈

| 组件 | 版本 | 说明 |
|---|---|---|
| PHP | 8.2-FPM | 业务应用 |
| Nginx | 1.25-alpine | 反向代理 + 静态资源 |
| MySQL | 8.0 | 关系数据库 |
| Redis | 7-alpine | 缓存 |
| Elasticsearch | 8.11.0 | 搜索引擎（IK 分词，启动时自动安装） |
| Kibana | 8.11.0 | ES 可视化 + Stack Monitoring |
| Logstash | 8.11.0 | 日志管道（5044 应用直推 / 5045 beats） |
| Filebeat | 8.11.0 | 日志采集（本地读目录 / K8s DaemonSet） |

> ELK 三件套版本必须一致；IK 分词器版本必须与 ES 大版本严格对齐。

## 5. 快速开始

### 5.1 本地（docker-compose）

```bash
# 首次使用：创建本地密码文件（学习默认值见 .env.example）
cp .env.example .env

# 构建自定义镜像（PHP 应用 + Nginx）
docker compose build

# 启动所有服务
docker compose up -d

# 查看状态（ES 健康检查通过后 Kibana/Logstash 才会启动）
docker compose ps

# 访问
open http://localhost:8080      # Nginx → PHP 应用
open http://localhost:5601      # Kibana（登录见下表）

# 关闭
docker compose down
```

### 5.2 账号密码（⚠️ 仅本地学习用）

密码的**唯一事实来源**是 `.env`（从 `.env.example` 复制；compose 与 K8s 部署脚本均从它注入，仓库代码零明文）：

| 服务 | 地址 | 账号 | 密码 |
|---|---|---|---|
| Kibana | http://localhost:5601 | `elastic` | `$ELASTIC_PASSWORD` |
| ES API | http://localhost:9200 | `elastic` | `$ELASTIC_PASSWORD` |
| MySQL | localhost:3306 | `root` / `cfa` | `$MYSQL_ROOT_PASSWORD` / `$MYSQL_PASSWORD` |
| Logstash | localhost:5044（tcp 直推） | 无需认证 | - |

> **查看/修改密码**：直接编辑 `.env`（已被 gitignore，绝不提交），`docker compose up -d` 自动生效。改 ES 密码也可 API 方式：`PUT /_security/user/elastic/_password`。完整密钥管理方案见 [docs/secrets-management.md](docs/secrets-management.md)。

### 5.3 验证日志链路

```bash
# 导出密码供下方命令使用（值来自 .env）
export ELASTIC_PASSWORD="$(grep '^ELASTIC_PASSWORD=' .env | cut -d= -f2)"

# 1. ES 插件与分词
curl -u "elastic:$ELASTIC_PASSWORD" "localhost:9200/_cat/plugins?v"

# 2. Logstash 处理统计
curl "localhost:9600/_node/stats/pipelines?pretty"

# 3. 发一条测试日志
echo '{"type":"php-error","level":"ERROR","message":"hello elk","timestamp":"'$(date +%Y-%m-%dT%H:%M:%S%z)'"}' \
  | nc localhost 5044

# 4. Kibana → Discover → 创建数据视图 app-* 查看日志
```

### 5.4 K8s 集群

**推荐：内循环（v0.6.0，自建 kind 集群 + 本地 registry）**

```bash
brew install kind     # 一次性
make init             # 建集群 + registry + 全量部署
make dev              # 日常迭代：改代码后一条命令上集群
make ui               # 端口转发访问 http://localhost:8080
```

**通用：deploy.sh（任意集群，minikube / kind / 云厂商均可）**

```bash
# 一键部署
./scripts/deploy.sh

# 或分步执行
kubectl apply -f k8s/namespace.yaml

# Secret：从 .env 渲染注入（deploy.sh 已内置此步骤，明文不进 git）
set -a; source .env; set +a
envsubst < k8s/secret.yaml.tpl | kubectl apply -f -
kubectl apply -f k8s/config/
kubectl apply -f k8s/mysql/
kubectl apply -f k8s/redis/
kubectl apply -f k8s/elasticsearch/
kubectl apply -f k8s/kibana/
kubectl apply -f k8s/logstash/
kubectl apply -f k8s/php/
kubectl apply -f k8s/nginx/
kubectl apply -f k8s/filebeat/     # DaemonSet：每节点采集容器日志
kubectl apply -f k8s/ingress.yaml

# 外部 Filebeat / 应用接入 Logstash（NodePort）
# output.logstash.hosts: ["<节点IP>:30444"]
```

> K8s 部署前需先给 `kibana_system` 用户设置密码（一次性）：
> ```bash
> kubectl -n cfa exec -it statefulset/elasticsearch -- \
>   curl -u "elastic:$ELASTIC_PASSWORD" -X PUT \
>   "localhost:9200/_security/user/kibana_system/_password" \
>   -H "Content-Type: application/json" -d "{\"password\":\"$ELASTIC_PASSWORD\"}"
> ```

## 6. 学习路径建议

按下面顺序阅读源码与 manifest，每步都能跑通：

1. **本地 docker-compose** —— 看 `docker-compose.yml`，理解服务如何编排、健康检查与启动顺序
2. **从无状态开始** —— `k8s/nginx/` + `k8s/php/`：Deployment + Service + ConfigMap
3. **ConfigMap 与 Secret** —— `k8s/config/` + `k8s/secret.yaml.tpl`：配置与密钥分离（模板 + 注入）
4. **有状态服务** —— `k8s/mysql/` + `k8s/redis/`：StatefulSet + PVC + headless Service
5. **复杂初始化** —— `k8s/elasticsearch/`：initContainer + 插件安装
6. **日志采集** —— `k8s/logstash/` + `k8s/filebeat/`：Deployment + DaemonSet + RBAC + NodePort
7. **Ingress 暴露** —— `k8s/ingress.yaml`：集群外访问

详见 [`docs/deploy.md`](docs/deploy.md) 与 [`k8s/README.md`](k8s/README.md)。

## 7. 常见问题

* **PVC Pending？** 集群需要默认 StorageClass，本地用 `minikube` 自带，kind 需要手动装
* **ES 启动慢？** 正常现象，JVM 启动 + IK 安装 + 索引恢复需要 1-3 分钟
* **PHP 连不上 MySQL？** K8s 中用 service 名 `mysql`（同 namespace），不是 `localhost`
* **Logstash 崩溃循环 "read-only file system"？** `logstash.yml` 不能只读挂载——官方镜像 entrypoint 要把环境变量写回该文件，配置一律走环境变量
* **Kibana 起不来 "username elastic is forbidden"？** 8.x 禁止用 elastic 超级用户做内部连接，必须用 `kibana_system`（见 5.4 的密码设置命令）
* **Navicat 连 MySQL 报 "caching_sha2_password cannot be loaded"？** Navicat 版本太老（<12.1），执行 `ALTER USER 'cfa'@'%' IDENTIFIED WITH mysql_native_password BY '<你的 MYSQL_PASSWORD>';`

## 8. 安全声明

本仓库**不包含任何明文密码**：学习默认值仅存于 `.env.example`（模板），实际值全部通过注入到达运行时——本地由 `.env`（gitignore）渲染，CI 由 GitHub Secrets 渲染模板，K8s 生产模式由 Sealed Secrets 解密。**生产环境请务必**：

* 使用 Sealed Secrets / External Secrets / Vault 管理密钥
* 开启 ES 的 TLS（`xpack.security.http.ssl.enabled: true`）
* 为 Kibana / Logstash 创建最小权限专用账户，不用 elastic 超级用户
* 通过 CI 注入密码，绝不提交到 git

> 📋 密码从"明文学习模式"到"CI 注入生产模式"再到"K8s 原生密钥管理"的完整演进方案（v0.3.0 → v0.5.0 路线图）见 **[docs/secrets-management.md](docs/secrets-management.md)**。三阶段已全部实施：本地 `.env`（v0.3.0）/ CI Secrets 渲染（v0.4.0）/ SealedSecrets（v0.5.0）；后续收敛：明文 `secret.yaml` 已删除，本地与 CI 统一为模板渲染注入（CI leak-guard 全仓扫描防回归）。

## 9. 贡献指南

### 9.1 分支模型（Git Flow 简化版）

| 分支 | 用途 | 谁能推 |
|---|---|---|
| `main` | 稳定可发布版本，每个 commit 对应一个 release tag | ❌ 仅通过 PR 合并 |
| `dev` | 日常开发集成 | ✅ 直接推送 |
| `feature/*` | 单个功能/修复，用完即删 | ✅ 直接推送 |

> main 的 PR 限制由 GitHub **分支保护规则**（Branch protection rules）强制执行：仓库 Settings → Branches → 对 `main` 启用 *Require a pull request before merging*。启用后任何人都无法直推 main（包括管理员，勾选 *Do not allow bypassing*）。

### 9.2 工作流

```bash
# 1. 从 dev 拉功能分支
git checkout dev
git checkout -b feature/你的功能名

# 2. 开发并提交（提交信息参考 Conventional Commits）
git commit -m "feat: 描述你的改动"
git push -u origin feature/你的功能名

# 3. 在 GitHub 上提 PR：feature/你的功能名 → dev
#    PR 必须通过 CI 五项检查（见 9.5），全绿才能合并 ✅

# 4. PR 合并后删除功能分支
git branch -d feature/你的功能名
git push origin --delete feature/你的功能名

# 5. 集成测试通过后，从 dev 提 PR 到 main
# 6. main 合并后打 tag
git tag v0.x.y
git push --tags
```

### 9.3 提交规范（Conventional Commits）

```
feat:     新功能
fix:      修复
docs:     文档
chore:    构建/工具/杂项
refactor: 重构
test:     测试
```

格式：`<type>(<scope>): <subject>`，scope 可选。例如 `feat(k8s): 加入 Filebeat DaemonSet`。

### 9.4 PR 检查清单

- [ ] 所有 YAML 文件通过 `yamllint`（CI 自动跑）
- [ ] shell 脚本通过 `shellcheck`（CI 自动跑）
- [ ] Dockerfile 通过 `hadolint`（CI 自动跑）
- [ ] K8s manifest 通过 `kubeconform` schema 校验（CI 自动跑）
- [ ] README 与代码同步（新增组件时同时更新目录结构、技术栈表）
- [ ] 涉及 K8s manifest 时同步更新 `docs/deploy.md`
- [ ] 不提交明文密码到 git（学习用密码例外，但生产环境务必替换）

### 9.5 CI 流水线

定义在 `.github/workflows/lint.yml`，**push（dev/main）与 PR 时自动触发**，共七项：

| Job | 工具 | 校验内容 |
|---|---|---|
| YAML syntax & style | `yamllint` | `k8s/`、`services/`、`docker/`、`.github/`、`docker-compose.yml` |
| Shell script lint | `shellcheck` | `scripts/*.sh`（warning 级以上） |
| Dockerfile lint | `hadolint` | `docker/app/Dockerfile`、`docker/nginx/Dockerfile` |
| Docker build (no push) | `docker build` | 两个镜像构建验证，防止 Dockerfile 改坏 |
| K8s manifest schema | `kubeconform` | `k8s/` 全部 30 个资源，strict 模式，锁定 K8s 1.29 schema |
| Secret template render | `envsubst` + `kubeconform` | `k8s/secret.yaml.tpl` 渲染 + 校验，密码全程不落盘不打印 |
| Secret leak guard | `git` + `diff` | `.env` 未被跟踪 / 模板无明文密码 / 明文版与模板字段一致 |

> **为什么不用 `kubectl apply --dry-run=client`？** 新版 kubectl 在 client dry-run 时仍会尝试连接 API server 下载 OpenAPI schema，CI 无集群环境会失败；`--validate=false` 则几乎不校验。`kubeconform` 是 CI 离线 schema 校验的标准做法。

本地跑同样的校验（提交前自检）：

```bash
# YAML
python3 -m pip install yamllint && yamllint -d "{extends: default, rules: {line-length: disable, document-start: disable, comments-indentation: disable}}" k8s/ services/ docker/ .github/ docker-compose.yml

# K8s manifest（无需本地装 kubectl）
docker run --rm -v "$(pwd)/k8s:/k8s:ro" ghcr.io/yannh/kubeconform:latest -strict -ignore-missing-schemas /k8s

# Docker 镜像构建
docker build -t cfa/php:ci -f docker/app/Dockerfile .
docker build -t cfa/nginx:ci docker/nginx
```

## 10. 版本与发布

项目使用 [Semantic Versioning](https://semver.org/)：

* 主版本（`v1.0.0`）：不兼容的架构变更
* 次版本（`v0.1.0`）：向后兼容的新功能
* 修订版（`v0.0.1`）：向后兼容的 bug 修复

查看所有 release：[**Releases**](https://github.com/791554638/Shipyard/releases)
