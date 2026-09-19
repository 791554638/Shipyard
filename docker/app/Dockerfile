# PHP-FPM 应用镜像：K8s 与 docker-compose 共用
#
# 构建（K8s 内循环入口是 make dev，无需手动构建）：
#   docker build -t cfa/php:dev -f docker/app/Dockerfile .
# 参数化（v0.7.0「可配置栈」预埋，见 docs/roadmap.md §4.5）：
#   docker build --build-arg PHP_VERSION=8.4 \
#        --build-arg PHP_EXTENSIONS="pdo_mysql opcache bcmath" \
#        -t cfa/php:custom -f docker/app/Dockerfile .
# 注意：build context 必须是项目根目录（要 COPY app/）

# PHP 版本（版本范围由 EOL 驱动，见 docs/roadmap.md §5.5）
ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-fpm-alpine

# 扩展列表（空格分隔）。
# v0.6.0 仅支持无系统依赖的内置扩展；带依赖/pecl 扩展的映射表在 v0.7.0 引入
ARG PHP_EXTENSIONS="pdo_mysql opcache"

RUN apk add --no-cache \
        bash \
        curl \
        mysql-client \
    # shellcheck 扩展列表需要分词展开，不能加引号
    && docker-php-ext-install ${PHP_EXTENSIONS}

# 启用 OPcache（生产推荐）
RUN echo "memory_limit=256M" > /usr/local/etc/php/conf.d/zz-app.ini

# 配置 www-data 用户的目录权限（与 K8s 中 fsGroup 配合）
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html

# 应用代码打进镜像 —— v0.6.0 闭环的根基：
# 改代码 → 新镜像 → 新 sha tag → 部署，全程无手工步骤。
# docker-compose 中被 volume（./app:/var/www/html）覆盖，互不影响。
COPY --chown=www-data:www-data app/ /var/www/html/

# 切换工作目录
WORKDIR /var/www/html

# 健康检查（仅 docker-compose 使用，K8s 用 readinessProbe）
# 用 busybox 自带的 pgrep 检测 php-fpm 主进程（alpine 默认已含）
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -x php-fpm > /dev/null || exit 1

# 暴露 FPM 端口
EXPOSE 9000

CMD ["php-fpm"]
