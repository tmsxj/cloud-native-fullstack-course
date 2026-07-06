# Mall-Demo 微服务演示项目

> 三套轻量级电商微服务Demo，专为云原生课程设计，适配受限资源环境（双4C8G Worker节点）

---

## 📋 项目概述

本项目包含三套微服务架构方案，用于支撑《云原生技术栈实战课程》的14个模块演示：

| Demo | 技术栈 | 总内存 | 适用场景 |
|------|--------|--------|----------|
| **Demo-A** | Spring Boot 3.2 + MyBatis | ~1.5GB | 完整课程演示，功能最丰富 |
| **Demo-B** | Go 1.22 + Gin + gRPC | ~300MB | 资源极限环境，启动最快 |
| **Demo-C** | Go网关 + Spring业务混合 | ~550MB | 生产架构参考，性价比最高 |

**对比开源项目**：
- Google microservices-demo: ~8-10GB ❌
- OpenTelemetry Demo: ~6-8GB ❌
- **Mall-Demo**: ~0.3-1.5GB ✅

---

## 🏗️ 架构设计

### 服务组成（5个业务服务 + 1个网关）

```
                    ┌──────────────┐
                    │  API Gateway │
                    │   (统一入口)  │
                    └──────┬───────┘
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌────────────┐  ┌────────────┐  ┌────────────┐
    │user-service│  │order-service│  │inventory-  │
    │  用户服务   │  │  订单服务   │  │ service    │
    │            │  │            │  │  库存服务   │
    └────────────┘  └──┬────┬───┘  └─────┬──────┘
          │            │    │             │
          ▼            ▼    ▼             ▼
       ┌─────┐    ┌──────┐ ┌──────┐  ┌──────┐
       │MySQL│    │Redis │ │Kafka │  │MySQL │
       └─────┘    └──────┘ └──────┘  └──────┘
                                        
    ┌────────────┐
    │payment-svc │  ~128MB (可选，按需启动)
    └────────────┘
```

### 核心调用链

创建订单时的完整链路：

```
1. Client → API Gateway → order-service
2. order-service → user-service (验证用户)
3. order-service → inventory-service (扣减库存)
4. order-service → payment-service (处理支付)
5. order-service → Kafka → notification-service (发送通知)
```

**链路追踪效果**：7个Span，3层深度，2个并行分支 ✅

---

## 📁 目录结构

```
mall-demo/
├── README.md                    # 本文档
├── demo-a-springboot/           # Spring Boot完整版
│   ├── pom.xml                  # 父POM
│   ├── user-service/            # 用户服务
│   ├── order-service/           # 订单服务
│   ├── inventory-service/       # 库存服务
│   ├── payment-service/         # 支付服务
│   ├── notification-service/    # 通知服务
│   └── api-gateway/             # API网关
│
├── demo-b-golang/               # Go轻量版
│   ├── go.mod                   # Go模块定义
│   ├── cmd/                     # 服务入口
│   │   ├── user-svc/
│   │   ├── order-svc/
│   │   ├── inventory-svc/
│   │   ├── payment-svc/
│   │   ├── notification-svc/
│   │   └── gateway/
│   └── internal/                # 内部包
│       ├── user/
│       ├── order/
│       ├── inventory/
│       ├── payment/
│       ├── notification/
│       ├── gateway/
│       └── pkg/                 # 公共包
│
├── demo-c-hybrid/               # 混合架构版
│   ├── api-gateway/             # Go网关
│   ├── user-service/            # Go用户服务
│   ├── order-service/           # Spring订单服务
│   ├── inventory-service/       # Spring库存服务
│   ├── payment-service/         # Go支付服务
│   ├── notification-service/    # Go通知服务
│   └── Makefile
│
└── k8s-manifests/               # K8s部署清单
    ├── demo-a-springboot/       # Demo-A K8s YAML
    ├── demo-b-golang/           # Demo-B K8s YAML
    ├── demo-c-hybrid/           # Demo-C K8s YAML
    ├── mysql-init/              # 数据库初始化SQL
    ├── helm/                    # Helm Chart
    │   └── mall-demo/
    └── scripts/                 # 运维脚本
        ├── deploy-demo-a.sh
        ├── deploy-demo-b.sh
        ├── deploy-demo-c.sh
        ├── clean-all.sh
        └── generate-traffic.sh
```

---

## 🚀 快速开始

### 前置条件

确保以下基础设施已部署：

| 组件 | 地址 | 用途 |
|------|------|------|
| Harbor | 192.168.1.61:80 | 镜像仓库 |
| MySQL | 192.168.1.61:3306 | 数据持久化 |
| Redis | 192.168.1.61:6379 | 缓存 |
| Kafka | 192.168.1.61:9092 | 消息队列 |
| Nacos | 192.168.1.61:8848 | 服务注册（Demo-A/C） |
| OTel Collector | otel-collector.monitoring:4317 | 链路追踪 |

**密码**: Harbor12345

### 步骤1: 初始化数据库

```bash
# 连接到MySQL
mysql -h 192.168.1.61 -u root -pHarbor12345

# 执行初始化SQL（选择对应Demo）
source k8s-manifests/mysql-init/user-db.sql
source k8s-manifests/mysql-init/order-db.sql
source k8s-manifests/mysql-init/inventory-db.sql
source k8s-manifests/mysql-init/payment-db.sql
```

### 步骤2: 构建镜像

#### Demo-A (Spring Boot)

```bash
cd demo-a-springboot

# Maven构建
mvn clean package -DskipTests

# Docker构建（需要Docker环境）
docker build -t 192.168.1.61:80/mall/demo-a-user-service:v1.0.0 ./user-service
docker build -t 192.168.1.61:80/mall/demo-a-order-service:v1.0.0 ./order-service
docker build -t 192.168.1.61:80/mall/demo-a-inventory-service:v1.0.0 ./inventory-service
docker build -t 192.168.1.61:80/mall/demo-a-payment-service:v1.0.0 ./payment-service
docker build -t 192.168.1.61:80/mall/demo-a-notification-service:v1.0.0 ./notification-service
docker build -t 192.168.1.61:80/mall/demo-a-api-gateway:v1.0.0 ./api-gateway

# 推送到Harbor
docker push 192.168.1.61:80/mall/demo-a-user-service:v1.0.0
# ... 推送其他镜像
```

#### Demo-B (Go)

```bash
cd demo-b-golang

# 编译
make build-all

# Docker构建
make docker-build

# 推送到Harbor
make docker-push
```

#### Demo-C (混合)

```bash
cd demo-c-hybrid

# 一键构建所有
make all

# 推送
make push
```

### 步骤3: 部署到K8s

```bash
cd k8s-manifests

# 部署Demo-A
./scripts/deploy-demo-a.sh

# 或部署Demo-B
./scripts/deploy-demo-b.sh

# 或部署Demo-C
./scripts/deploy-demo-c.sh
```

### 步骤4: 验证部署

```bash
# 查看Pod状态
kubectl get pods -n mall -o wide

# 查看服务
kubectl get svc -n mall

# 查看日志
kubectl logs -n mall -l app=user-service --tail=100

# 测试API
curl http://<gateway-node-ip>:30080/api/users/1
curl -X POST http://<gateway-node-ip>:30080/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId":1,"productId":1,"quantity":1}'
```

### 步骤5: 生成流量

```bash
# 自动流量生成
./scripts/generate-traffic.sh

# 或指定Gateway地址
GATEWAY_URL=http://192.168.1.53:30080 ./scripts/generate-traffic.sh
```

---

## 📚 使用指南

### 按课程模块选择Demo

| 课程模块 | 推荐Demo | 原因 |
|---------|---------|------|
| 05-Calico网络策略 | Demo-B | 资源最轻，专注网络测试 |
| 06-Prometheus监控 | Demo-A | Spring Boot Actuator指标丰富 |
| 07-Loki日志 | Demo-A | 日志格式标准，便于解析 |
| 08-Istio服务网格 | Demo-B | gRPC与Istio配合好 |
| 09-OTel链路追踪 | Demo-C | 混合技术栈体现OTel价值 |
| 10-Kafka消息队列 | Demo-B | gRPC+Kafka调用链清晰 |
| 11-Nacos服务发现 | Demo-A | Spring Cloud Nacos原生支持 |
| 12-ArgoCD GitOps | Demo-A | Helm Chart管理成熟 |
| 13-Tekton CI/CD | Demo-B | Go编译快，CI耗时短 |
| 14-全链路实战 | Demo-C | 最接近生产架构 |

### 错峰部署策略

由于资源受限，建议采用错峰部署：

```bash
# 场景1: 学习可观测性（Prometheus + Loki + OTel）
./scripts/deploy-demo-a.sh
# 使用完毕后清理
./scripts/clean-all.sh demo-a

# 场景2: 学习Kafka消息队列
./scripts/deploy-demo-b.sh
# 使用完毕后清理
./scripts/clean-all.sh demo-b

# 场景3: 学习Istio服务网格
./scripts/deploy-demo-c.sh
# 使用完毕后清理
./scripts/clean-all.sh demo-c
```

### 资源监控

```bash
# 查看资源使用
kubectl top pods -n mall

# 查看节点资源
kubectl top nodes

# 查看Pod分布
kubectl get pods -n mall -o wide --sort-by='.spec.nodeName'
```

---

## 🔧 配置说明

### 环境变量

所有服务支持以下环境变量：

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `MYSQL_HOST` | 192.168.1.61 | MySQL地址 |
| `MYSQL_PORT` | 3306 | MySQL端口 |
| `MYSQL_USER` | root | MySQL用户 |
| `MYSQL_PASSWORD` | Harbor12345 | MySQL密码 |
| `REDIS_HOST` | 192.168.1.61 | Redis地址 |
| `REDIS_PORT` | 6379 | Redis端口 |
| `REDIS_PASSWORD` | Harbor12345 | Redis密码 |
| `KAFKA_BROKERS` | 192.168.1.61:9092 | Kafka地址 |
| `NACOS_SERVER` | 192.168.1.61:8848 | Nacos地址（Demo-A/C） |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | http://otel-collector.monitoring:4317 | OTel Collector |

### 资源限制

| Demo | 服务类型 | Requests | Limits |
|------|---------|----------|--------|
| Demo-A | Spring Boot | 256Mi/100m | 512Mi/500m |
| Demo-B | Go | 64Mi/50m | 128Mi/250m |
| Demo-C | Go | 64Mi/50m | 128Mi/250m |
| Demo-C | Spring | 256Mi/100m | 512Mi/500m |

---

## 🧪 API接口

### 用户服务 (user-service)

```bash
# 用户注册
POST /api/users
{
  "username": "test",
  "email": "test@example.com",
  "phone": "13800138000"
}

# 查询用户
GET /api/users/{id}

# 验证用户
GET /api/users/{id}/verify
```

### 订单服务 (order-service)

```bash
# 创建订单
POST /api/orders
{
  "userId": 1,
  "productId": 1,
  "quantity": 2
}

# 查询订单
GET /api/orders/{orderNo}

# 生成模拟数据
POST /api/orders/demo
```

### 库存服务 (inventory-service)

```bash
# 查询库存
GET /api/inventory/{productId}

# 扣减库存
POST /api/inventory/deduct
{
  "productId": 1,
  "quantity": 1
}

# 恢复库存
POST /api/inventory/restore
{
  "productId": 1,
  "quantity": 1
}
```

### 支付服务 (payment-service)

```bash
# 支付
POST /api/payments/pay
{
  "orderNo": "ORD202401010001",
  "amount": 199.99,
  "paymentMethod": "ALIPAY"
}

# 支付回调
POST /api/payments/callback/{paymentNo}
```

---

## 🐛 故障排查

### 常见问题

#### 1. Pod启动失败

```bash
# 查看事件
kubectl describe pod -n mall <pod-name>

# 查看日志
kubectl logs -n mall <pod-name> --previous
```

#### 2. 数据库连接失败

```bash
# 测试MySQL连接
mysql -h 192.168.1.61 -u root -pHarbor12345 -e "SELECT 1"

# 检查数据库是否存在
mysql -h 192.168.1.61 -u root -pHarbor12345 -e "SHOW DATABASES LIKE 'mall_%'"
```

#### 3. 镜像拉取失败

```bash
# 检查Harbor连通性
curl http://192.168.1.61/api/v2.0/health

# 检查镜像是否存在
curl -u admin:Harbor12345 http://192.168.1.61/api/v2.0/projects/mall/repositories
```

#### 4. 服务间调用失败

```bash
# 检查Service
kubectl get svc -n mall

# 检查Endpoints
kubectl get endpoints -n mall

# 测试DNS解析
kubectl run -it --rm debug --image=busybox:1.36 --restart=Never -- nslookup user-service.mall.svc.cluster.local
```

---

## 📖 开发指南

### 添加新服务

以Demo-A为例：

```bash
# 1. 复制模板
cp -r demo-a-springboot/user-service demo-a-springboot/new-service

# 2. 修改pom.xml
# - artifactId: new-service
# - name: new-service
# - 修改端口: 8086

# 3. 修改包名
# com.demo.user -> com.demo.newservice

# 4. 修改application.yml
# server.port: 8086
# spring.application.name: new-service

# 5. 添加到父POM
# <module>new-service</module>
```

### 本地调试

```bash
# 启动单个服务（Demo-A）
cd demo-a-springboot/user-service
mvn spring-boot:run

# 启动单个服务（Demo-B）
cd demo-b-golang
go run cmd/user-svc/main.go
```

---

## 🤝 贡献指南

欢迎提交Issue和PR：

1. 发现Bug或文档错误
2. 添加新的故障排查案例
3. 优化资源消耗
4. 增加新的演示场景

---

## 📄 许可证

MIT License

---

## 📞 联系方式

如有问题，请在课程仓库提交Issue。

---

> **提示**: 本Demo专为离线环境设计，所有外部依赖已通过Harbor本地化。
