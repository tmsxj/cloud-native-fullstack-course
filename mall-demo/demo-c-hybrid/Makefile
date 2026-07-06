# =============================================================================
# Demo-C Hybrid Microservices - Makefile
# =============================================================================
# Spring Boot + Go 混合微服务商城Demo
# 总内存: ~550MB (比纯Spring Boot节省约200MB)
# =============================================================================

REGISTRY   ?= 192.168.1.61:80
IMAGE_REPO ?= $(REGISTRY)/mall
VERSION    ?= latest
TAG        ?= $(VERSION)

# Go服务
GO_SERVICES   = api-gateway user-service payment-service notification-service
# Spring Boot服务
JAVA_SERVICES = order-service inventory-service
ALL_SERVICES  = $(GO_SERVICES) $(JAVA_SERVICES)

.PHONY: all build push clean help $(ALL_SERVICES)

# 默认目标: 显示帮助
help: ## 显示帮助信息
	@echo "Demo-C Hybrid Microservices Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# 构建所有服务
all: build ## 构建所有服务镜像

# 构建所有Go服务
go-build: $(GO_SERVICES) ## 构建所有Go服务镜像

# 构建所有Spring Boot服务
java-build: $(JAVA_SERVICES) ## 构建所有Spring Boot服务镜像

# 构建单个Go服务
$(GO_SERVICES):
	@echo "==> Building Go service: $@"
	docker build -t $(IMAGE_REPO)/demo-c-$@:$(TAG) ./$@
	@echo "==> Built: $(IMAGE_REPO)/demo-c-$@:$(TAG)"

# 构建单个Spring Boot服务
$(JAVA_SERVICES):
	@echo "==> Building Spring Boot service: $@"
	docker build -t $(IMAGE_REPO)/demo-c-$@:$(TAG) ./$@
	@echo "==> Built: $(IMAGE_REPO)/demo-c-$@:$(TAG)"

# 推送所有镜像
push: ## 推送所有镜像到Harbor
	@for svc in $(ALL_SERVICES); do \
		echo "==> Pushing demo-c-$$svc:$(TAG)"; \
		docker push $(IMAGE_REPO)/demo-c-$$svc:$(TAG); \
	done

# 推送Go服务镜像
go-push:
	@for svc in $(GO_SERVICES); do \
		docker push $(IMAGE_REPO)/demo-c-$$svc:$(TAG); \
	done

# 推送Spring Boot服务镜像
java-push:
	@for svc in $(JAVA_SERVICES); do \
		docker push $(IMAGE_REPO)/demo-c-$$svc:$(TAG); \
	done

# 清理所有镜像
clean: ## 清理所有本地镜像
	@for svc in $(ALL_SERVICES); do \
		docker rmi $(IMAGE_REPO)/demo-c-$$svc:$(TAG) 2>/dev/null || true; \
	done
	@echo "==> Cleaned all images"

# 列出所有镜像
list: ## 列出所有Demo-C镜像
	@docker images | grep "demo-c-" || echo "No demo-c images found"

# 显示镜像大小统计
stats: ## 显示镜像大小统计
	@echo "Demo-C Hybrid Image Sizes:"
	@echo "=========================="
	@for svc in $(ALL_SERVICES); do \
		size=$$(docker image inspect $(IMAGE_REPO)/demo-c-$$svc:$(TAG) --format='{{.Size}}' 2>/dev/null || echo "0"); \
		if [ "$$size" != "0" ]; then \
			echo "  $$svc: $$(($$size / 1024 / 1024))MB"; \
		else \
			echo "  $$svc: not built"; \
		fi; \
	done

# 运行Go服务本地开发环境
dev-go: ## 本地启动所有Go服务
	@echo "Starting Go services locally..."
	@for svc in $(GO_SERVICES); do \
		echo "Starting $$svc..."; \
		(cd ./$$svc && go run main.go &); \
	done

# 运行Spring Boot服务本地开发环境
dev-java: ## 本地启动所有Spring Boot服务
	@echo "Starting Spring Boot services locally..."
	@for svc in $(JAVA_SERVICES); do \
		echo "Starting $$svc..."; \
		(cd ./$$svc && mvn spring-boot:run &); \
	done
