# 密钥与参数管理方案（Secrets Management Plan）

> 状态：**规划稿** —— 对应版本路线 v0.3.0 → v0.5.0
> 关联：README 第 8 节「安全声明」、`.github/workflows/lint.yml`

---

## 1. 背景与现状

### 1.1 密码分布盘点（v0.2.0）

| 位置 | 密码项 | 形式 | 支持外部注入 |
|---|---|---|---|
| `k8s/secret.yaml` | MYSQL_ROOT_PASSWORD / MYSQL_PASSWORD / ELASTIC_PASSWORD | **明文** | ❌ |
| `docker-compose.yml` | MySQL 两项 | **明文硬编码** | ❌ |
| `docker-compose.yml` | ELASTIC_PASSWORD | `${VAR:-默认值}` | ⚠️ 半支持（`.env` 可覆盖） |

### 1.2 设计矛盾

学习项目要求**开箱即用**（clone 即跑），生产实践要求**密码不进 git**。
两者不可兼得 → 方案核心是**双模式**：默认学习模式保留明文，生产模式全链路注入。

---

## 2. 设计原则

1. **单一事实来源（SSOT）**：每个密码只有一处"权威定义"，其他全是引用或生成物
2. **默认值不破坏开箱即用**：所有参数化都带学习用默认值兜底
3. **渐进式演进**：每个版本引入一层能力，可独立验收、可回滚
4. **生产演示价值**：CI 注入不是摆设，产出物（渲染后的 manifest）要真实可部署
5. **git 历史零真实密码**（生产模式下）：从 v0.4.0 起，生产密码只存在于 GitHub Secrets 与运行时内存

---

## 3. 目标架构（双模式）

```
┌─────────────────── 学习模式（默认，开箱即用）───────────────────┐
│                                                                  │
│  git clone → kubectl apply -f k8s/ → 起床（明文 secret.yaml）    │
│             → docker compose up   → 起床（默认值兜底）           │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────── 生产模式（v0.5.0 完整形态）──────────────────┐
│                                                                  │
│  开发者本地                GitHub                     K8s 集群   │
│  ───────────             ────────                    ────────    │
│  secret.tpl.yaml  ──▶  Actions Secrets ──▶ envsubst ──▶ 渲染后   │
│  （占位符模板，          （加密存储，          （CI 内存中）     apply │
│    可安全提交）            仅 CI 可读）                        │
│                                     │                           │
│                                     ▼（v0.5.0 替代路径）        │
│                              kubeseal 加密 → SealedSecret       │
│                              （密文可安全提交 git）              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. 版本计划总览

| 版本 | 主题 | 核心交付 | 复杂度 |
|---|---|---|---|
| **v0.3.0** | 本地参数化 | `.env` 机制全量覆盖 docker-compose | ★☆☆ |
| **v0.4.0** | CI 参数注入 | GitHub Secrets + 模板渲染 CI job | ★★☆ |
| **v0.5.0** | K8s 原生密钥管理 | Sealed Secrets 加密提交 | ★★★ |

每个版本独立发布 tag，单独走 dev → PR → main 流程。

---

## 5. v0.3.0 — 本地 `.env` 参数化

> **状态：✅ 已实施（2026-09-18）** —— 验收四项全部通过：无 `.env` 时 `docker compose config` 与改造前逐字节一致；`.env` 覆盖全部 7 处密码引用（含 MySQL healthcheck）；`.env` 被 gitignore 拦截；CI 全绿。

### 范围
- docker-compose.yml **全部**密码参数化（补齐 MySQL 硬编码）
- 引入 `.env.example` 模板 + `.env` 本地覆盖机制

### 交付物

1. **`.env.example`**（提交 git，密码为学习默认值）

   ```bash
   # 复制为 .env 后修改。.env 已被 gitignore，绝不提交
   MYSQL_ROOT_PASSWORD=rootpass
   MYSQL_PASSWORD=cfapass
   ELASTIC_PASSWORD=Cfa@Elastic2026
   ```

2. **`.gitignore`** 追加 `.env`（防误提交）

3. **`docker-compose.yml`** 改造（3 处）

   ```yaml
   # 改造前（硬编码）
   MYSQL_ROOT_PASSWORD: rootpass
   # 改造后（默认值兜底 = 开箱即用）
   MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:-rootpass}
   ```

4. **`scripts/README.md`** 补 `.env` 使用说明

### 验收标准
- [ ] 无 `.env` 时 `docker compose config` 输出与改造前**逐字节一致**（默认值兜底）
- [ ] 有 `.env` 时 `docker compose config` 中密码为覆盖值
- [ ] `git status` 中 `.env` 不出现（gitignore 生效）
- [ ] CI 五项检查全绿

### 不做的事
- 不动 `k8s/secret.yaml`（K8s 侧留给 v0.4.0）
- 不引入新工具

---

## 6. v0.4.0 — CI 参数注入（本方案核心）

### 范围
- K8s Secret 模板化 + GitHub Actions Secrets 渲染流水线

### 架构决策记录（ADR）

| 决策点 | 选择 | 理由 |
|---|---|---|
| 模板引擎 | `envsubst` | runner 自带、无依赖；sed 多行易错 |
| 占位符语法 | `${VAR}` | envsubst 原生语法，零转换成本 |
| 模板文件名 | `k8s/secret.yaml.tpl` | `.tpl` 后缀显式区分，kubeconform 可跳过 |
| 密码存储 | GitHub Actions Secrets | 免费项目可用、与 CI 同平台零集成成本 |
| 渲染产物 | **不落盘、不传 artifact** | 密码只存在于 job 内存与 K8s API |
| `secret.yaml`（明文版）去留 | **保留** | 学习模式开箱即用；README 标注两种模式切换 |

### 交付物

1. **`k8s/secret.yaml.tpl`**（新增，占位符模板）

   ```yaml
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
   ```

2. **GitHub 仓库 Secrets 配置**（手动，Settings → Secrets → Actions）

   ```
   ELASTIC_PASSWORD   = <生产真实密码>
   MYSQL_ROOT_PASSWORD = <生产真实密码>
   MYSQL_PASSWORD      = <生产真实密码>
   ```

3. **CI 新增 job：`secret-render-dryrun`**

   ```yaml
   secret-render:
     name: Secret template render (dry-run)
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4

       # 原理：Secrets 以环境变量进入 job → envsubst 渲染 →
       #       kubeconform 校验渲染结果 → 全程不落盘不打印
       - name: Render & validate secret template
         env:
           MYSQL_ROOT_PASSWORD: ${{ secrets.MYSQL_ROOT_PASSWORD }}
           MYSQL_PASSWORD: ${{ secrets.MYSQL_PASSWORD }}
           ELASTIC_PASSWORD: ${{ secrets.ELASTIC_PASSWORD }}
         run: |
           set -euo pipefail
           export TF_PLUGIN_MAGIC_COOKIE=dummy   # envsubst 需要非空环境即可
           # 渲染到变量（内存），不写文件
           RENDERED=$(envsubst < k8s/secret.yaml.tpl)
           # 校验渲染结果是否仍是合法 K8s manifest（走 stdin，不落盘）
           echo "$RENDERED" | kubeconform -strict -summary -ignore-missing-schemas -
           # 确认占位符已被替换（未替换说明 Secret 名字写错）
           if echo "$RENDERED" | grep -qE '\$\{[A-Z_]+\}'; then
             echo "::error::占位符未被替换，检查 secrets 名称"; exit 1
           fi
           echo "✅ 模板渲染 + 校验通过（密码未落盘、未打印）"
   ```

   > 复用 kubeconform 安装步骤（与 `k8s-dry-run` job 合并为 `needs` 或重复安装均可，取简单）。

4. **CI 安全自检 job：`secret-leak-guard`**

   ```yaml
   - name: 检查 .env / 明文密码未被提交（防回归）
     run: |
       # .env 不应出现在 git 中
       ! git ls-files | grep -q '^\.env$'
       # 模板文件不应包含真实密码默认值（只允许 ${} 占位符）
       ! grep -qE 'rootpass|cfapass|Cfa@' k8s/secret.yaml.tpl
   ```

5. **README 更新**：9.5 CI 表格加两行；第 8 节改为指向本文档

### 密码流转链路（安全审查视角）

```
GitHub Secrets（加密存储）
   │  仅 CI job 内可见
   ▼
env 环境变量（job 内存）
   │  envsubst
   ▼
$RENDERED 变量（shell 内存）
   │  管道 stdin
   ▼
kubeconform 校验 → 成功即丢弃
   ✗ 不写文件  ✗ 不上传 artifact  ✗ 不 echo（GitHub 自动 mask）
```

### 验收标准
- [ ] 三个 Secrets 配置后，job 绿且日志无明文密码（GitHub 自动 mask 为 `***`）
- [ ] 故意改错一个 Secret 名 → job 红，报"占位符未被替换"
- [ ] 渲染产物通过 kubeconform strict 校验
- [ ] `git log -p` 全历史搜不到生产密码

---

## 7. v0.5.0 — Sealed Secrets（K8s 原生方案）

### 范围
解决"渲染后的 Secret 怎么安全地到达集群"——CI 产出 SealedSecret（密文），可安全提交 git，集群内 controller 解密。

### 交付物

1. **`k8s/sealed-secrets/`**：controller 部署 manifest（或 Helm values 说明）
2. **`scripts/seal-secret.sh`**：本地一键加密

   ```bash
   # 用法：.env 读取明文 → 渲染模板 → kubeseal 加密 → 输出 SealedSecret
   ./scripts/seal-secret.sh > k8s/sealed-secret.yaml
   ```

3. **`k8s/sealed-secret.yaml`**：加密产物（可安全提交）
4. **部署脚本 `scripts/deploy.sh` 增加 `--mode=learn|prod` 参数**：
   - `learn`（默认）：apply 明文 `secret.yaml`
   - `prod`：apply `sealed-secret.yaml`

### 验收标准
- [ ] `kubeseal` 加密产物提交 git 后，`git log -p` 无任何可逆明文
- [ ] 集群内 controller 能解密并生成同内容的 Secret
- [ ] 私钥只在集群内（泄露 git 不影响安全）

---

## 8. 风险与对策

| 风险 | 概率 | 对策 | 版本 |
|---|---|---|---|
| `.env` 误提交 | 中 | gitignore + CI `secret-leak-guard` | v0.3.0 |
| `secret.yaml`（明文）与 `.tpl` 内容漂移 | 中 | CI 检查两者字段名一致（可加 diff 脚本） | v0.4.0 |
| Secret 名写错 → 渲染出空密码 | 低 | 占位符替换检查（见 6.3） | v0.4.0 |
| GitHub Secrets 被有仓库写权限的人读取 | 低 | 单人项目；多人时配合 branch protection + environments 审批 | v0.4.0 |
| Sealed Secrets 私钥随集群重建丢失 | 中 | 文档记录私钥备份/轮换流程（`kubeseal --re-cert`） | v0.5.0 |

---

## 9. 里程碑检查清单

- [ ] **v0.3.0**：`.env.example` / compose 全参数化 / gitignore / 验收 4 项
- [ ] **v0.4.0**：`.tpl` 模板 / 3 个 GitHub Secrets / 2 个新 CI job / README 同步
- [ ] **v0.5.0**：Sealed Secrets controller / seal-secret.sh / deploy.sh 双模式
- [ ] 每版本：dev 开发 → CI 全绿 → PR → main → tag

---

## 10. 明确不做（Out of Scope）

- ❌ Vault / External Secrets Operator（需要额外基础设施，超出学习项目边界，v1.0 再议）
- ❌ ES TLS 证书自动化（独立话题，与密码注入无关）
- ❌ 删除明文 `secret.yaml`（学习模式的核心保留项）
