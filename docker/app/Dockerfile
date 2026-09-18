# PHP-FPM 镜像：用于 K8s 与 docker-compose 共用
#
# 构建：docker build -t cfa/php:8.2 -f docker/app/Dockerfile .
# 运行：docker run --rm -p 9000:9000 cfa/php:8.2

FROM php:8.2-fpm-alpine

# 安装常用扩展
RUN apk add --no-cache \
        bash \
        curl \
        mysql-client \
    && docker-php-ext-install pdo pdo_mysql opcache

# 启用 OPcache（生产推荐）
RUN echo "memory_limit=256M" > /usr/local/etc/php/conf.d/zz-app.ini

# 配置 www-data 用户的目录权限（与 K8s 中 fsGroup 配合）
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html

# 切换工作目录
WORKDIR /var/www/html

# 健康检查（仅 docker-compose 使用，K8s 用 readinessProbe）
# 用 busybox 自带的 pgrep 检测 php-fpm 主进程（alpine 默认已含）
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -x php-fpm > /dev/null || exit 1

# 暴露 FPM 端口
EXPOSE 9000

CMD ["php-fpm"]