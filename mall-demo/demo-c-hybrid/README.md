# Demo-C Hybrid Microservices
# Spring Boot + Go 混合微服务商城Demo

## 架构概览

```
                    ┌──────────────┐
                    │  API Gateway │  (Go/Gin) ~30MB
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
     ┌────────▼────┐ ┌────▼─────┐ ┌────▼──────────┐
     │ User Service│ │Order Svc │ │Payment Service│
     │ (Go/GORM)   │ │(Spring)  │ │ (Go/Gin)      │
     │ ~40MB       │ │~200MB    │ │ ~40MB         │
     └─────────────┘ └────┬─────┘ └───────────────┘
                         │
              ┌──────────┼──────────┐
              │                     │
     ┌────────▼────────┐    ┌──────▼──────┐
     │Inventory Service│    │   Kafka     │
     │  (Spring Boot)  │    │             │
     │    ~200MB       │    └──────┬──────┘
     └─────────────────┘           │
                          ┌────────▼──────────┐
                          │Notification Service│
                          │ (Go/Gin+Kafka)     │
                          │ ~40MB              │
                          └────────────────────┘
```

## 总内存: ~550MB (比纯Spring Boot节省约200MB)

## 服务列表

| 服务 | 技术栈 | 镜像大小 | 端口 |
|------|--------|---------|------|
| api-gateway | Go (Gin) | ~30MB | 8080 |
| user-service | Go (Gin+GORM) | ~40MB | 8080 |
| order-service | Spring Boot 3.2 | ~200MB | 8080 |
| inventory-service | Spring Boot 3.2 | ~200MB | 8080 |
| payment-service | Go (Gin) | ~40MB | 8080 |
| notification-service | Go (Gin+Kafka) | ~40MB | 8080 |

## 快速开始

### 构建所有镜像
```bash
make all
```

### 推送到Harbor
```bash
make push
```

### 构建单个服务
```bash
make api-gateway
make order-service
```

### 查看镜像大小
```bash
make stats
```

## 环境要求

- Docker & Docker Compose
- Go 1.21+
- Java 17+
- Maven 3.9+
- Harbor: 192.168.1.61:80
- MySQL: 192.168.1.61:3306
- Redis: 192.168.1.61:6379
- Kafka: 192.168.1.61:9092
- Nacos: 192.168.1.61:8848
