# 部署指南

## 0. 前置条件

* **kubectl** ≥ 1.24
* 一个可用的 K8s 集群：
  * 本地：[minikube](https://minikube.sigs.k8s.io/) / [kind](https://kind.sigs.k8s.io/) / Docker Desktop
  * 云端：阿里云 ACK / 腾讯云 TKE / AWS EKS / GCP GKE
* 默认 StorageClass（`kubectl get sc` 应至少有一个）
* Ingress Controller（默认会装 nginx-ingress）
  * minikube: `minikube addons enable ingress`
  * kind: 参考 [kind 文档](https://kind.sigs.k8s.io/) 装 contour / nginx-ingress

## 快速路径：内循环部署（v0.6.0，推荐）

> 改一行代码 → `make dev` → 集群里跑的就是新代码，全程零手工作业。
> 需要自建 kind 集群（现成集群如 docker-desktop 无法配置 containerd mirror，本地 registry 方案不可用）。

**前置**：`brew install kind`（一次性）

```bash
# 首次：创建 kind 集群 + 本地 registry + 全量部署（等待所有服务就绪）
make init

# 日常迭代：build → push → apply → rollout status（唯一入口）
make dev

# 访问（端口转发，Ctrl+C 结束）
make ui

# 其他：make logs / make status / make registry / make clean
```

### 架构：本地 registry + containerd mirror

```
宿主机 docker ──push──→ localhost:5001 ─┐
                                         ▼
                              registry 容器（cfa-registry，kind 网络）
                                         ▲
kind 节点 ──pull localhost:5001──mirror──┘（kind-config.yaml containerdConfigPatches）
```

* **镜像 tag = git sha**：`localhost:5001/cfa-php:sha-a1b2c3d`，与 GHCR 引用（`ghcr.io/<owner>/cfa-php:sha-a1b2c3d`）**结构完全同构**，v0.9.0 切换外循环只需换前缀
* **工作区有未提交改动时**：tag 自动追加 `-dirty<时间戳>` 后缀（确保集群重新拉取），提交后恢复干净的 sha 形式
* **闭环终点是验证**：`make dev` 内置 `kubectl rollout status`，失败非零退出并打印定位命令——不会"apply 完就假成功"
* **Secret 注入与 CI 同构**：`make init` 从 `.env` 渲染 `k8s/secret.yaml.tpl`（envsubst 管道，明文不落盘、不进 git）

### 镜像注入方式：Kustomize 临时 overlay

`scripts/dev-deploy.sh` 在临时目录生成只含 `images:` override 的 Kustomization，指向 `k8s/`（见 `k8s/kustomization.yaml`）——git 工作区零污染，且为 v0.7.0 components / v1.2.0 多环境 overlay 铺路。**不要**用 `kubectl set image`（会造成 git 与集群漂移）或手改 manifest（污染工作区）。

## 1. 一键部署

```bash
cd cfa
cp .env.example .env   # 首次使用：创建密码文件（deploy.sh 从它渲染 Secret）
./scripts/deploy.sh
```

脚本会依次 apply 所有 manifest，最后给出访问地址与端口转发命令。

## 2. 分步部署（推荐学习用）

每一步用 `kubectl get pods -n cfa` 看 Pod 状态，等 `Running` 后再走下一步。

```bash
# 2.1 Namespace
kubectl apply -f k8s/namespace.yaml

# 2.2 Secret（MySQL / 应用密码）—— 从 .env 渲染注入，明文不进 git
set -a; source .env; set +a
envsubst < k8s/secret.yaml.tpl | kubectl apply -f -

# 2.3 ConfigMap（所有配置）
kubectl apply -f k8s/config/

# 2.4 有状态基础（先有 MySQL/Redis/ES，再起应用）
kubectl apply -f k8s/mysql/
kubectl apply -f k8s/redis/
kubectl apply -f k8s/elasticsearch/

# 2.5 无状态应用
kubectl apply -f k8s/kibana/
kubectl apply -f k8s/php/
kubectl apply -f k8s/nginx/

# 2.6 外部入口
kubectl apply -f k8s/ingress.yaml
```

## 3. 验证

```bash
# 所有 Pod 都 Running
kubectl get pods -n cfa

# 端口转发（如果不想用 Ingress）
kubectl port-forward -n cfa svc/nginx 8080:80   # 应用入口
kubectl port-forward -n cfa svc/kibana 5601:5601
kubectl port-forward -n cfa svc/elasticsearch 9200:9200
```

打开 http://localhost:8080 看 PHP 应用首页。

## 4. 初始化 ES 索引（可选）

```bash
./scripts/init-es-indices.sh
```

会创建一个使用 IK 分词器的 `articles` 索引。

## 5. 清理

```bash
kubectl delete namespace cfa
# PVC 是 Retain 策略，namespace 删了 PVC 还在，需要手动清理：
kubectl get pvc -A | grep cfa
kubectl delete pvc <name> -n cfa
```

## 6. 常见问题排查

### Pod Pending
通常是 PVC 等不到 Volume。`kubectl describe pod <name> -n cfa` 看 Events，确认 StorageClass 是否存在。

### ES 启动 OOM
JVM 默认用了容器内存的 50%，本项目限定为 512M。如果机器内存小，可以再调小 `ES_JAVA_OPTS`。

### PHP 连不上 MySQL
K8s 内 DNS 解析需要时间。Pod 启动后等几秒；也可以 exec 进 Pod 手动 `nslookup mysql` 验证。

### Ingress 不通
* `kubectl get ingress -n cfa` 看 ADDRESS 是否分配
* 本地集群（minikube/kind）需要 `minikube tunnel` 或端口转发

## 7. CI 中的 manifest 校验

每次 push/PR，GitHub Actions 会用 [kubeconform](https://github.com/yannh/kubeconform) 对 `k8s/` 全部 manifest 做**离线 schema 校验**（strict 模式，锁定 K8s 1.29 schema），不依赖真实集群：

```yaml
# .github/workflows/lint.yml（节选）
- name: Validate manifests against K8s schema
  run: kubeconform -strict -summary -ignore-missing-schemas -kubernetes-version 1.29.0 k8s/
```

> 注意：升级 K8s 目标版本时，记得同步改 `-kubernetes-version` 参数。

本地复现同样的校验（无需安装 kubectl）：

```bash
docker run --rm -v "$(pwd)/k8s:/k8s:ro" ghcr.io/yannh/kubeconform:latest \
  -strict -ignore-missing-schemas /k8s
```

常见报错：

| 报错 | 原因 |
|---|---|
| `could not find schema for X` | apiVersion 拼错或版本不存在（如还在用 `extensions/v1beta1`） |
| `missing property "xxx"` | 字段名拼写错误或位置不对（strict 模式） |
| `forbidden property "xxx"` | 该资源版本已废弃此字段（如 1.25+ 移除的字段） |