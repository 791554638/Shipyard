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

## 1. 一键部署

```bash
cd cfa
./scripts/deploy.sh
```

脚本会依次 apply 所有 manifest，最后给出访问地址与端口转发命令。

## 2. 分步部署（推荐学习用）

每一步用 `kubectl get pods -n cfa` 看 Pod 状态，等 `Running` 后再走下一步。

```bash
# 2.1 Namespace
kubectl apply -f k8s/namespace.yaml

# 2.2 Secret（MySQL / 应用密码）
kubectl apply -f k8s/secret.yaml

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