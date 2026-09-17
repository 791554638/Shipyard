# 架构说明

## 1. 整体架构

```
                            ┌─────────────────┐
                            │  Ingress (80)   │
                            └────────┬────────┘
                                     │
                              ┌──────▼──────┐
                              │   Nginx     │
                              │  (1 副本)   │
                              └──────┬──────┘
                                     │ fastcgi
                              ┌──────▼──────┐
                              │  PHP-FPM    │
                              │  (2 副本)   │
                              └──┬───────┬──┘
                                 │       │
                  ┌──────────────▼─┐   ┌─▼─────────────┐
                  │     MySQL      │   │     Redis     │
                  │ (StatefulSet)  │   │ (StatefulSet) │
                  └───────────────┘   └───────────────┘

                  ┌───────────────────────────────┐
                  │  Elasticsearch (StatefulSet)  │
                  │  + IK Analyzer (initContainer)│
                  └───────────────┬───────────────┘
                                  │
                          ┌───────▼───────┐
                          │    Kibana     │
                          │  (Deployment) │
                          └───────────────┘
```

## 2. 组件职责

| 组件 | 角色 | 有状态？ | 副本数（学习） | 副本数（生产） |
|---|---|---|---|---|
| Nginx | 反向代理、静态资源 | 无 | 1 | 2+ |
| PHP-FPM | 业务逻辑 | 无 | 2 | 3+ |
| MySQL | 主存储 | 有 | 1 | 主从 |
| Redis | 缓存 / Session | 有 | 1 | 主从 + 哨兵 |
| Elasticsearch | 全文检索 | 有 | 1 | 3+（集群） |
| Kibana | ES 可视化 | 无 | 1 | 2+ |

## 3. 关键 K8s 概念映射

| K8s 资源 | 项目中的具体应用 |
|---|---|
| Namespace | `cfa`（隔离环境） |
| ConfigMap | ES / MySQL / Redis / Kibana / Nginx / PHP 的配置文件 |
| Secret | MySQL root 密码、应用连接密码 |
| PVC + PV | MySQL / Redis / ES 的数据持久化 |
| Deployment | Nginx / PHP / Kibana（无状态） |
| StatefulSet | MySQL / Redis / ES（有状态，固定网络标识） |
| Service (ClusterIP) | 集群内 DNS 寻址 |
| Service (Headless) | StatefulSet 配套（statefulset 内已自动创建） |
| Ingress | 外部访问入口 |
| InitContainer | ES 安装 IK 插件 |

## 4. 网络通信

K8s 集群内通过 **Service 名**访问（同 namespace 下可直接用短名）：

* PHP → MySQL: `mysql:3306`
* PHP → Redis: `redis:6379`
* Kibana → ES: `elasticsearch:9200`
* Nginx → PHP: `php:9000`

## 5. 持久化策略

| 组件 | volume 大小 | 回收策略 | 备份建议 |
|---|---|---|---|
| MySQL | 8Gi | Retain | mysqldump 定时备份 |
| Redis | 1Gi | Retain | AOF/RDB |
| ES | 30Gi | Retain | 快照仓库到 S3/OSS |

> 学习用默认 `Delete` 也无妨；本仓库所有 PVC 使用 `Retain` 防止误删。