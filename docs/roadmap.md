# 后续版本路线图

> **定位**：K8s 概念覆盖（学习）+ 可演示链路（作品集）交替推进
> **依据**：项目目标第 1 条 ——「用一个真实可跑的项目把 K8s 核心概念串起来」
> **节奏**：延续 v0.3.0 → v0.5.0 的做法 —— 一版一主题、可独立验收、可单独发 tag

---

## 0. 已走过的路

| 版本 | 主题 | 主线 |
|---|---|---|
| v0.1.1 | 项目骨架 + CI lint + 分支流程 | 能跑起来 |
| v0.2.0 | CI 增强（Docker 构建 + K8s schema 校验） | 能验证 |
| v0.3.0 | 本地 `.env` 参数化 | 能安全地跑起来 |
| v0.4.0 | CI 参数注入（Secret 渲染 + 防泄漏守卫） | 能安全地跑起来 |
| v0.5.0 | Sealed Secrets（K8s 原生密钥管理） | 能安全地跑起来 |

主线演进：**能跑 → 能验证 → 能安全地跑**。下一个自然的问题：
**改一次代码，集群里能自动变成新版本吗？**

---

## 1. 先澄清：部署有两条循环

| | **内循环**（Dev Loop） | **外循环**（CI/CD） |
|---|---|---|
| 谁触发 | 我改代码 | push / tag |
| 频率 | **分钟级** | 小时 / 天级 |
| 目标 | 本地集群跑上新代码 | 可分享、可复现、可回滚的产物 |
| 关键工具 | kind + 本地 registry + kubectl/脚本 | GitHub Actions + GHCR + ArgoCD |
| 难点 | 几乎没有（全在本机） | 需要 registry，且集群可被触达 |

**结论**：先做内循环（零阻塞、收益最高），但它不是终点。
内循环产出的**镜像构建方式、tag 策略、manifest 参数化**，正是外循环要直接复用的地基。

---

## 2. 现状盘点

| 维度 | 现状 | 问题 |
|---|---|---|
| 自定义镜像 | `cfa/php:8.2`、`cfa/nginx:1.25` | 只存在于本机 Docker，**无 registry** |
| K8s 引用 | `image: cfa/php:8.2` + 注释"需先构建" | 手动改 manifest 才能换版本 |
| 组件版本 | 硬编码在各 manifest（`mysql:8.0`、`redis:7-alpine`、`elasticsearch:8.11.0`…） | 换版本要逐个手改 |
| PHP 扩展 | `docker-php-ext-install pdo pdo_mysql opcache` 写死 | 不能按需裁剪 |
| 部署 | 手动 `./scripts/deploy.sh` | apply 完就返回，**不验证是否真的跑起来** |
| CI | 7 个 job 全静态校验 | `docker-build` 写明 "no push"（外循环的事，暂不动） |

---

## 3. 推进序列

| 版本 | 主题 | 所属层 | 侧重 |
|---|---|---|---|
| **v0.6.0** | 个人研发环境部署闭环 | 内循环 | 开发体验 |
| **v0.7.0** | 组件化与可配置栈 | 配置层 | 工程 |
| **v0.8.0** | 可视化管理 | 呈现层 | 概念 + 演示 |
| **v0.9.0** | 交付外循环（GHCR + CI 发布） | 外循环 | 作品集 |
| **v1.0.0** | GitOps 自动同步（ArgoCD） | 外循环 | 概念 |
| **v1.1.0** | 弹性与自愈 | 集群 | 概念 |
| **v1.2.0** | 多环境与治理（overlay） | 集群 | 工程 |
| **v1.3.0** | 数据可靠性 | 集群 | 演示 |

> 叙事连贯性：v0.6.0 引入 Kustomize 作为镜像注入手段 → v0.7.0 顺势拆成 components（组件组合）
> → v1.2.0 再叠加 overlay（多环境）。**同一条技术路线的三级递进**，不是三次重写。

---

## 4. v0.6.0 个人研发环境部署闭环

### 4.1 目标

改一行代码 → **一条命令** → 集群里跑的就是新代码，全程零手工作业。

### 4.2 三个决定性选型

#### ① 用本地 registry，而不是 `kind load`

| 方案 | 问题 / 优势 |
|---|---|
| `kind load docker-image` | 每次传完整镜像层，慢；镜像名不便带 registry 前缀 |
| **kind 内置本地 registry**（`localhost:5001`） | 一次 push、全节点共享；**镜像引用格式与 GHCR 同构** |

> ⚠️ **最容易踩的坑**：kind 节点是容器，节点内的 `localhost:5001` **不等于**宿主机端口。
> 必须在 kind 配置里加 `containerdConfigPatches`，把节点内的 `localhost:5001` mirror 到 registry 容器，否则必然 `ImagePullBackOff`。

#### ② tag 用 git sha，不用 `latest`

- `localhost:5001/cfa-php:sha-<7位>` —— 与 `ghcr.io/<owner>/cfa-php:sha-<7位>` **结构完全一致**
- 将来切 GHCR **只需换前缀**；配合 `imagePullPolicy: IfNotPresent`

#### ③ 用 Kustomize 注入镜像，不硬编码

| 方式 | 评价 |
|---|---|
| 直接改 manifest | ❌ 每次部署污染 git 工作区 |
| `kubectl set image` | ⚠️ 造成 git 与集群漂移，不可复现 |
| **Kustomize `images:`** | ✅ 声明式、`kubectl` 内置、为 components/overlay 铺路 |

### 4.3 闭环的终点是「验证」，不是「apply 完成」

```bash
kubectl apply -k k8s/
kubectl rollout status deployment/cfa-php -n cfa --timeout=120s
```

失败要**非零退出**并打印定位命令。做不到这点就不叫闭环。

### 4.4 交付物清单

1. `kind-config.yaml` —— 含 registry mirror 配置（关键）
2. `scripts/dev-deploy.sh` —— build → push → apply → rollout status（fail fast）
3. `k8s/kustomization.yaml` —— 镜像 override
4. `Makefile` —— `make dev` / `make logs` / `make ui` / `make clean`
5. **Dockerfile 参数化**（见 4.5）
6. 文档：更新 `deploy.md`，补内循环说明

### 4.5 Dockerfile 参数化（为 v0.7.0 预埋）

```dockerfile
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-alpine
ARG PHP_EXTENSIONS="pdo_mysql opcache"
```

**理由**：这本来就是"构建镜像"的一部分，放这里边际成本最低；
v0.7.0 的"PHP 多版本 + 扩展可选"直接复用它，不用回头重构。

### 4.6 验收标准

- [x] 改一行 PHP → `make dev` → 浏览器看到新内容，**零手工步骤**（2026-09-18 kind 集群实测通过：新内容 + Pod 滚动更新）
- [x] 部署失败时脚本退出码非零，并给出定位命令（实测触发多次：.env 缺失 / namespace 缺失 / Kustomize 路径错误，均正确失败）
- [x] 集群 Deployment 的 image 是 sha tag（实测：`localhost:5001/cfa-php:sha-8430146-dirty951965`）
- [x] 连续 `make dev` 结果幂等（dirty 内容 hash 确定性 tag，重复部署无变化）
- [x] 镜像引用格式与 GHCR 同构（迁移只换前缀 `localhost:5001/` → `ghcr.io/<owner>/`）

> 实测过程中顺手修复的存量 bug（kind 集群才暴露）：
> ① `storageClassName: ""` 语义误用（禁用动态供给 → PVC 永远 Pending），改为省略字段走默认 SC
> ② ES config 目录整挂 ConfigMap 只读 → keystore 写入失败 CrashLoop，改为 subPath 单文件挂载
> ③ ES 探针 httpGet 无认证 → 401 循环重启，改为 exec + curl 带密码
> ④ ES initContainer 用 busybox 的 curl/wget 均不可用（无 curl / TLS 栈过老），改用 curlimages/curl
> ⑤ php Deployment 漏注入 ELASTIC_PASSWORD（应用 /es 路由 401），已补 secretKeyRef
> 待办：kind 节点拉 Docker Hub 不稳定（401/EOF），官方镜像目前靠宿主机 `docker save | ctr import` 导入；
> containerd 已警告 `mirrors` 配置将在 v2.4 移除，届时 kind-config.yaml 需迁移到 `config_path` 方式

### 4.7 明确不做

- 不碰 GitHub Actions（外循环版本的事）
- 不做多节点 / HA / 存储高可用
- 不引入 Tilt / Skaffold —— 先用透明脚本；等重复劳动真的明显了再上

---

## 5. v0.7.0 组件化与可配置栈

### 5.1 目标

把项目从「**一份写死的栈**」变成「**可参数化的组件目录**」：
组件可自由组合、各组件版本可选、PHP 多版本可选、PHP 扩展按需管理。

### 5.2 四个能力的技术落点

| 能力 | 技术落点 | 难度 |
|---|---|---|
| 组件版本可选 | manifest 镜像 tag 参数化（Kustomize `images:`） | 低 |
| 组件自由组合 | Kustomize `components`（每组件一个 component，按需启用） | 中 |
| PHP 多版本 | 1 个 Dockerfile + `ARG PHP_VERSION` + CI 矩阵 | 低 |
| **PHP 扩展自由管理** | `ARG PHP_EXTENSIONS` + **扩展映射表** | **高** |

### 5.3 硬约束一：PHP 扩展不是「拼字符串」

三类扩展，装法完全不同，必须维护映射表：

| 扩展 | 装法 | 前置系统依赖 |
|---|---|---|
| `pdo_mysql` `opcache` `bcmath` `sockets` | `docker-php-ext-install` | — |
| `gd` | `docker-php-ext-install` | `libpng-dev libjpeg-turbo-dev freetype-dev` |
| `redis` `mongodb` `xdebug` | `pecl install` + `docker-php-ext-enable` | `$PHPIZE_DEPS` |
| `imagick` | `pecl install` + 启用 | `imagemagick-dev` |

扩展之间还存在互相依赖与冲突。因此实现形态是**带映射表的构建脚本**，而非 `for ext in $EXTENSIONS`。

> 附带收益：当前 `docker-php-ext-install pdo pdo_mysql opcache` 写死；参数化后可按需裁剪，
> **镜像体积是可测量的成果指标**（对比 minimal / standard / full 三档）。

### 5.4 硬约束二：「自由组合」在 CI 上会爆炸

4 个 PHP 版本 × 3 个 nginx 版本 × 扩展子集 → 组合数不可穷举。收敛策略：

- **版本维度** → CI 矩阵**全量**构建（可控）
- **扩展维度** → **预设套餐（minimal / standard / full）+ 按需自定义构建**，绝不预构建所有组合

```yaml
strategy:
  matrix:
    php: ['8.2', '8.3', '8.4', '8.5']
    flavor: [minimal, standard, full]
```

### 5.5 硬约束三：版本范围由 EOL 状态驱动

截至 2026-09，活跃支持：**8.2 / 8.3 / 8.4 / 8.5**（8.1 已 EOL；**8.2 将于 2026-12 EOL**）。

→ 版本列表不应是无限下拉框，而应只提供**仍在安全支持期内**的版本。
把 EOL 数据做成配置项，这本身就是个经得起追问的设计点。

### 5.6 组件组合的形态

现状是 `k8s/` 下按组件分目录（mysql / redis / elasticsearch / kibana / logstash / filebeat / php / nginx / config）。
Kustomize 化后，每个组件 = 一个 component，根 `kustomization.yaml` 决定启用哪些：

```yaml
components:
  - components/mysql        # 换 MySQL → 删这行，改用 components/postgres
  - components/redis
  - components/elasticsearch
  - components/php
  - components/nginx
```

### 5.7 交付物清单

1. `k8s/` 改造为 Kustomize 结构（base + components）
2. Dockerfile 扩展映射表脚本（扩展 → 装法 → 系统依赖）
3. 扩展套餐定义（minimal / standard / full）
4. 组件版本参数表（单一事实来源，避免各 manifest 各写各的）
5. `make config` —— 打印当前组合（组件 + 版本 + 扩展）
6. 文档：新增可配置栈说明

### 5.8 验收标准

- [ ] 通过 `make config` 能一眼看清当前启用了哪些组件、什么版本、装了哪些扩展
- [ ] 增删组件只需改 `kustomization.yaml`，不碰其他文件
- [ ] 切换 PHP 版本只需改一个参数
- [ ] 扩展从 `minimal` 切到 `full`，镜像体积差异可测量
- [ ] 组件版本只有一个定义点（改一处、全局生效）

### 5.9 明确不做

- **不自研 Web 可视化控制台**（见第 6 节）
- 不做组件依赖自动求解（如自动判断"装了 X 必须装 Y"）—— 显式声明优于魔法
- 不预构建所有版本 × 扩展组合

---

## 6. 关于「可视化管理」：分三层，只做前两层

可视化不是独立一层，它是**每一层的呈现方式**。按粒度分三段：

| 层次 | 看什么 | 承载 | 建议 |
|---|---|---|---|
| **① 状态可见** | Pod / Deploy / PVC / 事件 | k9s、Kubernetes Dashboard、Lens / Headlamp | **并入 v0.6.0**（约半天） |
| **② 配置可见** | 当前启用了什么组件、什么版本、什么扩展 | `make config`（CLI）；可选只读 Web 总览 | **v0.7.0 配套** |
| **③ 可操作** | 网页勾选版本扩展 → 点按钮部署 | 需自研平台（Rancher / Backstage / Port / KubeVela） | ❌ **不自研** |

**③ 的替代方案**：`make config` 交互式 CLI（或 TUI）能覆盖 90% 的诉求，
成本却是自研 Web 控制台的百分之几，且不偏离 K8s 主线。
若后续确实需要 Web 操作面，直接用 **ArgoCD UI**（v1.0.0 会有）承载，不另造轮子。

---

## 7. 与上一版规划的差异

| 项 | 最初规划 | 本版 | 原因 |
|---|---|---|---|
| v0.6.0 | 交付闭环（GHCR + CD） | 个人研发环境部署闭环 | 内循环零阻塞、收益更高 |
| 组件化 / 多版本 / 扩展管理 | 未提及 | **新增 v0.7.0** | 本次构想引入 |
| 可视化 | 未单列 | v0.8.0（只做前两层） | ③ 不自研 |
| Dockerfile 参数化 | 未提及 | **并入 v0.6.0** | 边际成本低，且是 v0.7.0 前置 |
| GHCR / CI 发布 | v0.6.0 | v0.9.0 | 内循环镜像方案可直接复用 |
| ArgoCD | v0.7.0 | v1.0.0 | 依赖前序 |
| 多环境 overlay | v1.0.0 | v1.2.0 | Kustomize 化后自然顺延 |

---

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| kind 节点内 `localhost:5001` 解析失败 | 必须配 `containerdConfigPatches` mirror（见 4.2①）——首要排查项 |
| registry 端口被占用 | 脚本前置检查端口；端口可配置 |
| `make dev` 只 apply 不验证，假成功 | 强制 `rollout status` + 非零退出（见 4.3） |
| 扩展组合导致镜像构建时间与体积失控 | 预设套餐 + 按需构建；记录各档体积基线 |
| 扩展映射表漏项（装了扩展但缺系统依赖） | 常见扩展全覆盖 + 构建时失败即报错，不静默跳过 |
| Kustomize 改造面过大，一次动全部 manifest | 分两步：v0.6.0 只做镜像注入，v0.7.0 才拆 components |
| 版本序列拉长，动力衰减 | 每版独立发 tag + 独立验收清单，保持"可交付"感 |
| 用 minikube 时本地 registry 做法不同 | 内循环方案以 kind 为主路径；minikube 走 `minikube image load` 回退 |

---

## 9. 待确认

1. **顺序**：认可「内循环闭环 → 组件化可配置栈 → 可视化 → 外循环 → GitOps → 集群迭代」吗？
2. **可视化边界**：同意「只做状态可见 + 配置可见，不自研 Web 操作台」吗？
3. **扩展管理形态**：接受「映射表 + 预设套餐 + 按需构建」，而不是完全自由的组合吗？
4. **registry 方案**：认可 kind 内置本地 registry + mirror 配置吗？（v0.6.0 技术核心）
5. **集群类型**：内循环主路径定为 **kind** 吗？（现文档同时支持 minikube/kind/Docker Desktop）
