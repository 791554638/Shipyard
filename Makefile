# CFA 个人研发环境入口（v0.6.0 内循环）
# make help 查看全部目标

KIND_CONTEXT ?= kind-cfa
NAMESPACE    ?= cfa
PORT         ?= 8080

.DEFAULT_GOAL := help
.PHONY: help init dev logs ui status registry clean

help: ## 显示本帮助
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-10s\033[0m %s\n", $$1, $$2}'

init: ## 首次部署：建 kind 集群 + registry + Secret + 全量资源（等待就绪）
	./scripts/dev-deploy.sh --init

dev: ## 迭代部署：build → push → apply → rollout status（日常唯一入口）
	./scripts/dev-deploy.sh

logs: ## 跟随 php 应用日志
	kubectl --context $(KIND_CONTEXT) logs -f -n $(NAMESPACE) -l app=php --tail=50

ui: ## 端口转发并访问应用（Ctrl+C 结束转发）
	@echo "→ http://localhost:$(PORT)  (Ctrl+C 结束转发)"
	kubectl --context $(KIND_CONTEXT) port-forward -n $(NAMESPACE) svc/nginx $(PORT):80

status: ## 查看命名空间内全部资源
	kubectl --context $(KIND_CONTEXT) get all -n $(NAMESPACE)

registry: ## 查看本地 registry 状态与已推送镜像
	./scripts/dev-cluster.sh status

clean: ## 删除 kind 集群与本地 registry（数据不保留）
	./scripts/dev-cluster.sh delete
