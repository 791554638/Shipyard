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
├── .gitignore
│
├── app/                      ← PHP 业务代码
│   ├── public/index.php      ← 入口（通过 Nginx + PHP-FPM）
│   ├── src/                  ← 业务逻辑
│   └── composer.json
│
├── docker/                   ← 自定义镜像构建
│   ├── app/Dockerfile        ← PHP 应用镜像
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
│   ├── namespace.yaml
│   ├── secret.yaml           ← 密码（学习用明文，生产换 Sealed Secrets/Vault）
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
│   └── deploy.md             ← 详细部署步骤
│
└── scripts/
    ├── init-es-indices.sh    ← ES 索引初始化（IK 分词）
    ├── deploy.sh             ← K8s 一键部署
    └── cleanup-old-dirs.sh   ← 清理历史遗留空目录
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

### 5.2 默认账号密码（⚠️ 仅本地学习用）

| 服务 | 地址 | 账号 | 密码 |
|---|---|---|---|
| Kibana | http://localhost:5601 | `elastic` | `Cfa@Elastic2026` |
| ES API | http://localhost:9200 | `elastic` | `Cfa@Elastic2026` |
| MySQL | localhost:3306 | `root` / `cfa` | `rootpass` / `cfapass` |
| Logstash | localhost:5044（tcp 直推） | 无需认证 | - |

> 改 ES 密码：`export ELASTIC_PASSWORD="xxx"` 后 `docker compose up -d`；
> 或 API：`PUT /_security/user/elastic/_password`（改后同步 Kibana/Logstash 环境变量）。

### 5.3 验证日志链路

```bash
# 1. ES 插件与分词
curl -u elastic:Cfa@Elastic2026 "localhost:9200/_cat/plugins?v"

# 2. Logstash 处理统计
curl "localhost:9600/_node/stats/pipelines?pretty"

# 3. 发一条测试日志
echo '{"type":"php-error","level":"ERROR","message":"hello elk","timestamp":"'$(date +%Y-%m-%dT%H:%M:%S%z)'"}' \
  | nc localhost 5044

# 4. Kibana → Discover → 创建数据视图 app-* 查看日志
```

### 5.4 K8s 集群

> 前置：已安装 kubectl 并配置好集群（minikube / kind / 任意云厂商均可）

```bash
# 一键部署
./scripts/deploy.sh

# 或分步执行
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml
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
>   curl -u elastic:$ELASTIC_PASSWORD -X PUT \
>   "localhost:9200/_security/user/kibana_system/_password" \
>   -H "Content-Type: application/json" -d '{"password":"Cfa@Elastic2026"}'
> ```

## 6. 学习路径建议

按下面顺序阅读源码与 manifest，每步都能跑通：

1. **本地 docker-compose** —— 看 `docker-compose.yml`，理解服务如何编排、健康检查与启动顺序
2. **从无状态开始** —— `k8s/nginx/` + `k8s/php/`：Deployment + Service + ConfigMap
3. **ConfigMap 与 Secret** —— `k8s/config/` + `k8s/secret.yaml`：配置与密钥分离
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
* **Navicat 连 MySQL 报 "caching_sha2_password cannot be loaded"？** Navicat 版本太老（<12.1），执行 `ALTER USER 'cfa'@'%' IDENTIFIED WITH mysql_native_password BY 'cfapass';`

## 8. 安全声明

本仓库**有意**包含学习用的明文密码（`docker-compose.yml` / `k8s/secret.yaml`），目的是降低初学者门槛。**生产环境请务必**：

* 使用 Sealed Secrets / External Secrets / Vault 管理密钥
* 开启 ES 的 TLS（`xpack.security.http.ssl.enabled: true`）
* 为 Kibana / Logstash 创建最小权限专用账户，不用 elastic 超级用户
* 通过 CI 注入密码，绝不提交到 git
