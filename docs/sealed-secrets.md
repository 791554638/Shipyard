# Sealed Secrets 使用指南（v0.5.0）

> 关联：[docs/secrets-management.md](secrets-management.md)（完整方案演进）· README 第 8 节

## 1. 是什么

Sealed Secrets 是 K8s 生态的密钥管理方案：**公钥加密的 Secret 可安全提交 git**——只有集群内的 controller 持有私钥，能解密并生成原 Secret。git 泄露不导致密钥泄露。

本项目 v0.5.0 引入双模式部署：

| 模式 | 触发 | 应用资源 |
|---|---|---|
| `learn`（默认） | `./scripts/deploy.sh` | `k8s/secret.yaml`（明文，开箱即用） |
| `prod` | `./scripts/deploy.sh --mode=prod` | `k8s/sealed-secret.yaml`（密文，需 controller） |

## 2. 一键流程

### 第一步：安装 controller（一次性）

```bash
./scripts/install-sealed-secrets.sh
# 固定版本 v0.27.3，应用到 kube-system，等待 ready
```

输出：

```
[INFO] 下载 Sealed Secrets controller v0.27.3...
[INFO] 应用到集群...
[INFO] 等待 controller 就绪...
[INFO] ✅ Sealed Secrets controller v0.27.3 已部署到 kube-system
```

### 第二步：安装客户端（一次性）

```bash
# macOS
brew install kubeseal
# 其他平台：从 https://github.com/bitnami-labs/sealed-secrets/releases 下载
#          与 controller 同版本（v0.27.3）
```

### 第三步：生成 SealedSecret

```bash
# 1. 准备生产密码
cp .env.example .env
vim .env   # 填入生产密码（已被 .gitignore 排除）

# 2. 生成密文
./scripts/seal-secret.sh
# 默认输出到 k8s/sealed-secret.yaml

# 调试模板（只看渲染结果不加密）
./scripts/seal-secret.sh --dry-run
```

输出：

```
[INFO] .env 已读取
[INFO] 从集群获取公钥 + 加密（需 controller 已就绪）...
[INFO] ✅ 已写入 k8s/sealed-secret.yaml（密文，可安全提交到 git）
```

### 第四步：提交 + 部署

```bash
git add k8s/sealed-secret.yaml
git commit -m 'feat: 加密生产密码 (v0.5.0 sealed-secret)'
./scripts/deploy.sh --mode=prod
```

## 3. 关键安全特性

| 特性 | 保障 |
|---|---|
| **私钥只在集群内** | 由 controller 启动时生成，存 `kube-system/sealed-secrets-key*`，外部无法读取 |
| **密文可安全提交** | SealedSecret YAML 是 RSA 加密密文 + 元数据，无明文密码 |
| **证书自动轮换** | controller 默认每 30 天重新生成密钥；已加密的 Secret 不受影响（旧密钥保留可解密） |
| **过期控制** | 单个加密有 TTL（默认 10 年）；可指定 `--cert-expires=8760h`（1 年） |

## 4. 验收测试项
- [ ] 安装 controller 后 `kubectl get pods -n kube-system` 看到 `sealed-secrets-controller` Running
- [ ] `kubeseal --version` 输出 v0.27.3
- [ ] `./scripts/seal-secret.sh` 生成 `k8s/sealed-secret.yaml` 无报错
- [ ] `k8s/sealed-secret.yaml` 中 `grep` 任何 `.env` 明文密码 → 无匹配
- [ ] `./scripts/deploy.sh --mode=prod` 成功 apply；`kubectl get sealedsecret -n cfa` 显示对象
- [ ] 5 秒内 `kubectl get secret -n cfa cfa-secret` 显示对象（controller 已解密）
- [ ] `kubectl get secret -n cfa cfa-secret -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d` 输出密码

## 5. 密钥轮换与灾难恢复

### 证书轮换

controller 自动每 30 天生成新密钥（**已加密的 Secret 不失效**，新旧密钥共存）。

### 集群重建（私钥丢失）

⚠️ **风险**：controller 私钥是解密 SealedSecret 的唯一凭证。私钥丢失则所有 SealedSecret 失效。

**防范——定期备份私钥**：

```bash
# 导出所有私钥
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-keys-backup.yaml
# 加密备份文件，存安全位置（如 Vault / 离线硬盘）
```

**恢复**：

```bash
kubectl apply -f sealed-secrets-keys-backup.yaml
```

## 6. 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| `kubeseal: no Key "h6cN..." in secret` | 私钥不存在（集群刚建/重置） | 备份恢复或重新加密所有 Secret |
| `kubectl wait` 超时 | 镜像拉取慢（registry mirror 受限） | `kubectl describe pod` 看 Events |
| 想要 Apply 已废弃的旧 seed | 私钥已轮换 | 用 `--old-keys` 或备份 |
| 集群切换到新集群 | 旧 cluster 私钥失效 | 备份副本新集群用 |

## 7. 与 v0.3.0/v0.4.0 的关系

```
v0.3.0 .env       ← docker compose 本地（明文入 .env，被 gitignore）
v0.4.0 secret.yaml.tpl + CI Secrets   ← K8s CI 渲染（不落盘不打印）
v0.5.0 sealed-secret.yaml  ← K8s git 安全（密文入 git，本版本）
```

三者覆盖三种场景：

| 场景 | 用 |
|---|---|
| 本地 docker compose 学习 | `.env` |
| CI/CD 自动化部署 | `secret.yaml.tpl` + CI Secrets（v0.4.0） |
| 离线部署 / git 公开仓库 | `SealedSecret`（本版本） |