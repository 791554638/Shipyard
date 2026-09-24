# Nginx 镜像与本地 vhost 目录

## 文件职责

| 文件 | 职责 | 进入镜像？ |
|---|---|---|
| `Dockerfile` | 生产镜像构建（仅 `COPY default.conf`） | — |
| `default.conf` | 默认站点 vhost（**镜像构建源**） | ✅ 是 |
| `conf.d/default.conf` | 同一文件的副本，供研发模式目录挂载 | ❌ 否 |
| `conf.d/*.conf` | 本地项目 vhost（研发模式专用） | ❌ 否 |

## 研发模式工作方式

`docker-compose.override.yml` 将 `conf.d/` 整体挂载到容器的 `/etc/nginx/conf.d/`，
nginx 主配置的 `include /etc/nginx/conf.d/*.conf` 自动加载目录下全部 vhost。

**新增本地项目**（无需改任何 compose 配置）：

```bash
# 1. 代码放 app/（gitignore + dockerignore 已排除）
# 2. vhost 文件丢进 conf.d/，改 server_name 与 root
cp conf.d/china.conf conf.d/你的项目.conf

# 3. reload 生效
docker exec cfa-nginx nginx -s reload
```

**验证**：`curl -H 'Host: www.你的域名.com' http://localhost:8080/`

## ⚠️ 维护规则

1. **改默认站点**：先改 `default.conf`，再同步副本：
   ```bash
   cp default.conf conf.d/default.conf
   ```
   （目录挂载会遮蔽镜像内文件，副本缺失则研发模式丢失默认站点）
2. **本地项目 vhost 绝不 `COPY` 进镜像**：生产镜像只含 `default.conf`，
   本地项目属于研发模式专属，进镜像即泄漏与膨胀（见根目录 `.dockerignore`）。
3. **PHP 版本**：所有 vhost 共用 `fastcgi_pass php:9000`（PHP 8.2）。
   需要 PHP 7.x 的旧项目（如 Laravel 5.x 的 greenchina）需另起对应版本 php 服务并改指向。

## 访问方式

容器仅映射 `8080:80`，浏览器按域名访问需在 `/etc/hosts` 添加：

```
127.0.0.1 www.greenchina.com
```

然后 `open http://www.greenchina.com:8080`；或用 curl：`curl -H 'Host: www.greenchina.com' http://localhost:8080/`
