HARBOR_REGISTRY=192.168.1.61:80
IMAGE_PREFIX=mall-demo
TAG=latest

SERVICES=user-svc order-svc inventory-svc payment-svc notification-svc gateway

.PHONY: build-all docker-build docker-push clean

# Build all binaries
build-all:
	@echo "Building all services..."
	@for svc in $(SERVICES); do \
		echo "  -> Building $$svc..."; \
		CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o bin/$$svc ./cmd/$$svc; \
	done
	@echo "All services built successfully!"

# Build all Docker images
docker-build:
	@echo "Building all Docker images..."
	@for svc in $(SERVICES); do \
		echo "  -> Building image for $$svc..."; \
		docker build -f docker/Dockerfile.$$svc -t $(HARBOR_REGISTRY)/$(IMAGE_PREFIX)/$$svc:$(TAG) .; \
	done
	@echo "All images built successfully!"

# Push all Docker images to Harbor
docker-push:
	@echo "Pushing all images to Harbor..."
	@for svc in $(SERVICES); do \
		echo "  -> Pushing $$svc..."; \
		docker push $(HARBOR_REGISTRY)/$(IMAGE_PREFIX)/$$svc:$(TAG); \
	done
	@echo "All images pushed successfully!"

# Build a single service
build-%:
	CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o bin/$* ./cmd/$*

# Docker build a single service
docker-build-%:
	docker build -f docker/Dockerfile.$* -t $(HARBOR_REGISTRY)/$(IMAGE_PREFIX)/$*:$(TAG) .

# Docker push a single service
docker-push-%:
	docker push $(HARBOR_REGISTRY)/$(IMAGE_PREFIX)/$*:$(TAG)

# Clean build artifacts
clean:
	rm -rf bin/
