# Nginx 镜像：自带 vhost 配置
#
# 构建：docker build -t cfa/nginx:1.25 -f docker/nginx/Dockerfile .

FROM nginx:1.25-alpine

# 移除默认配置
RUN rm /etc/nginx/conf.d/default.conf

# 把 vhost 拷进镜像（也可在 K8s 中通过 ConfigMap 挂载，详见 k8s/nginx/deployment.yaml）
COPY default.conf /etc/nginx/conf.d/default.conf

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -q --spider http://localhost/healthz || exit 1

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]