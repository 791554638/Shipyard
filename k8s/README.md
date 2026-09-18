# K8s 部署清单

本目录包含 CFA 项目所有 K8s 资源定义。

## 文件清单

```
k8s/
├── namespace.yaml         # Namespace: cfa
├── secret.yaml.tpl        # Secret 模板（.env / CI 渲染注入，明文不进 git）
├── config/                # ConfigMap
│   ├── es-config.yaml
│   ├── mysql-config.yaml
│   ├── redis-config.yaml
│   ├── kibana-config.yaml
│   ├── nginx-config.yaml
│   └── php-config.yaml
├── mysql/statefulset.yaml       # StatefulSet + Headless Service
├── redis/statefulset.yaml
├── elasticsearch/statefulset.yaml
├── kibana/deployment.yaml
├── php/deployment.yaml
├── nginx/deployment.yaml
└── ingress.yaml
```

## 资源依赖关系

```
                  ┌──────────────────┐
                  │   namespace      │
                  │   secret         │
                  │   config/*       │
                  └─────────┬────────┘
                            │
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                    ▼
  ┌──────────┐       ┌──────────┐         ┌──────────┐
  │  mysql   │       │  redis   │         │   es     │
  │StatefulSet│       │StatefulSet│        │StatefulSet│
  └────┬─────┘       └────┬─────┘         └────┬─────┘
       │                  │                   │
       └────────┬─────────┴─────────┬─────────┘
                ▼                   ▼
           ┌──────────┐       ┌──────────┐
           │   php    │       │  kibana  │
           │Deployment│       │Deployment│
           └────┬─────┘       └──────────┘
                │
           ┌────▼─────┐
           │  nginx   │
           │Deployment│
           └────┬─────┘
                │
           ┌────▼─────┐
           │ Ingress  │
           └──────────┘
```

## 应用顺序

详见根目录 [`scripts/deploy.sh`](../scripts/deploy.sh)。