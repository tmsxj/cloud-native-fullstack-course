# 模块09：OpenTelemetry与可观测性

---

## 1. 概述与架构图

### 1.1 可观测性三大支柱

```
+============================================================+
|                    可观测性 (Observability)                  |
+============================================================+
|                                                              |
|  +----------------+  +----------------+  +----------------+ |
|  |   Traces       |  |   Metrics      |  |   Logs         | |
|  |   (分布式追踪)  |  |   (指标监控)    |  |   (日志记录)    | |
|  +----------------+  +----------------+  +----------------+ |
|  | 回答: 请求经过  |  | 回答: 系统当前  |  | 回答: 发生了    | |
|  | 了哪些服务?     |  | 状态如何?       |  | 什么? 为什么?   | |
|  | 耗时多少?       |  | 有多少错误?     |  | 错误详情?       | |
|  +----------------+  +----------------+  +----------------+ |
|         |                  |                  |             |
|         v                  v                  v             |
|  +------------------------------------------------------+  |
|  |              OpenTelemetry Collector                   |  |
|  |  +----------+ +----------+ +----------+ +----------+  |  |
|  |  | Receiver | |Processor | |Processor | | Exporter |  |  |
|  |  +----------+ +----------+ +----------+ +----------+  |  |
|  +------------------------------------------------------+  |
|         |                  |                  |             |
|         v                  v                  v             |
|  +----------+    +----------+    +---------------------+   |
|  | Tempo    |    | Prometheus|   | Loki / Elasticsearch|   |
|  | (Trace)  |    | (Metrics) |   | (Logs)              |   |
|  +----------+    +----------+    +---------------------+   |
|         \                |                /               |
|          \               v               /                |
|           +------------------------------+                |
|           |        Grafana               |                |
|           |  统一面板 & 关联跳转          |                |
|           +------------------------------+                |
+============================================================+
```

### 1.2 OpenTelemetry Collector 架构

```
                    Applications (Java/Go/Python/Node.js)
                              |
                    +---------+---------+
                    |  OTel SDK/Agent  |
                    |  (Auto-Instrument)|
                    +---------+---------+
                              |
                    OTLP (gRPC/HTTP) :4317/:4318
                              |
              +===============+===============+
              |   OpenTelemetry Collector     |
              |                               |
              |  +-------+  +-------+        |
              |  | otlp  |  | jaeger|  <-- Receivers
              |  | recv  |  | recv  |        |
              |  +---+---+  +---+---+        |
              |      |          |             |
              |  +---+----------+---+        |
              |  |    batch processor|        |  <-- Processors
              |  |    memory_limiter  |        |
              |  |    filter/transform|        |
              |  +---+----------+---+        |
              |      |          |             |
              |  +---+---+  +---+---+        |
              |  | otlp  |  |prometheus|     |  <-- Exporters
              |  | export|  | export   |     |
              |  +---+---+  +---+---+        |
              +======|==========|============+
                     |          |
          +----------+    +----+-----------+
          |               |                |
     +----+----+   +-----+------+   +-----+------+
     | Tempo   |   | Prometheus |   | Loki       |
     | (Trace) |   | (Metrics)  |   | (Logs)     |
     +---------+   +------------+   +------------+
           \              |              /
            \             v             /
             +--------+-------+-------+
             |      Grafana     |
             |  Explore/Dash   |
             +-----------------+
```

### 1.3 方案对比总览

```
+========================+========================+========================+
|  方案A: Grafana Stack  |  方案B: ELK Stack      |  方案C: 混合架构        |
+========================+========================+========================+
|  Tempo (Trace)         |  Elasticsearch (All)   |  Tempo (Trace)         |
|  Prometheus (Metrics)  |  Logstash (Collect)    |  Prometheus (Metrics)  |
|  Loki (Logs)           |  Kibana (Visualize)    |  Elasticsearch (Logs)  |
|  Grafana (Visualize)   |  APM (Trace)           |  Grafana (Visualize)   |
|                        |                        |  Kibana (日志分析)      |
+========================+========================+========================+
```

---

## 2. 理论基础

### 2.1 OpenTelemetry 概述

**OpenTelemetry (OTel)** 是 CNCF 的可观测性框架项目，由 OpenTracing 和 OpenCensus 合并而来，提供统一的 API 和 SDK 用于生成、收集和导出遥测数据（Traces、Metrics、Logs）。

| 组件 | 说明 |
|------|------|
| API | 提供与具体实现无关的编程接口（Tracer、Meter、Logger） |
| SDK | API 的具体实现，负责数据生成、处理和导出 |
| Collector（采集器） | 独立的代理/网关进程，接收、处理和导出遥测数据 |
| Operator（K8s 运算器） | Kubernetes Operator，简化 Collector 在 K8s 中的部署 |
| Auto-Instrumentation（自动埋点） | 自动埋点代理，无需修改应用代码即可采集遥测数据 |

**OTel 数据模型：**

| 信号类型 | 说明 | 数据模型 |
|----------|------|----------|
| Traces（分布式追踪） | 记录请求在服务间的传播路径 | Span（操作）、SpanContext（上下文传播） |
| Metrics（指标） | 记录系统状态的时间序列数据 | Counter、Gauge、Histogram、Summary |
| Logs（日志） | 结构化日志，记录离散事件 | LogRecord |

### 2.2 Collector Pipeline 组件

```
Pipeline = Receiver(s) -> Processor(s) -> Exporter(s)

Receiver:  接收遥测数据（支持多种协议：OTLP、Jaeger、Zipkin、Prometheus）
Processor: 处理数据（批处理、采样、过滤、转换、属性操作）
Exporter:  导出数据到后端（Tempo、Prometheus、Loki、Elasticsearch、Jaeger）
Connector: 在不同信号类型间转发（如 Trace -> Metrics）
```

**常用 Processor：**

| Processor | 功能 |
|-----------|------|
| batch | 批量发送，减少网络开销（推荐始终启用） |
| memory_limiter | 内存限制，防止 OOM |
| filter | 基于条件过滤遥测数据 |
| attributes | 添加/删除/修改 Span 属性 |
| resource | 添加/修改资源属性（如 K8s metadata） |
| transform | 通用数据转换 |
| tail_sampling | 基于策略的尾部采样（如只保留错误 Trace） |
| probabilistic_sampler | 概率采样 |
| k8s_attributes | 自动添加 K8s 元数据（Pod、Node、Namespace） |

### 2.3 Trace 核心概念

```
Trace: 一次完整的请求链路（由多个 Span 组成）
  |
  +-- Span 1: API Gateway (root span)
  |     |
  |     +-- Span 2: User Service
  |     |     |
  |     |     +-- Span 3: MySQL Query
  |     |
  |     +-- Span 4: Order Service
  |           |
  |           +-- Span 5: Inventory Service
  |           |
  |           +-- Span 6: Redis Cache

Span 属性:
  - TraceID: 全局唯一 Trace 标识
  - SpanID: 当前 Span 标识
  - ParentSpanID: 父 Span 标识（根 Span 为空）
  - OperationName: 操作名称（如 HTTP GET /api/orders）
  - StartTime / EndTime: 开始和结束时间
  - Attributes: 键值对属性（如 http.status_code=200）
  - Events: 事件（如错误、日志）
  - Status: OK / Error
```

### 2.4 方案对比详解

#### 方案A：Grafana Stack（推荐）

| 组件 | 角色 | 优势 |
|------|------|------|
| Tempo | 分布式追踪后端 | 与 Grafana 原生集成，TraceID 查询高效 |
| Prometheus | 指标存储 | K8s 生态标准，PromQL 查询强大 |
| Loki | 日志聚合 | 轻量级，索引标签而非全文，资源消耗低 |
| Grafana | 统一可视化 | 三大支柱统一面板，Trace->Logs->Metrics 关联跳转 |

#### 方案B：ELK Stack

| 组件 | 角色 | 优势 |
|------|------|------|
| Elasticsearch | 全文搜索引擎 | 强大的全文检索能力，日志分析体验好 |
| Logstash | 数据收集处理 | 丰富的 Filter 插件，数据转换能力强 |
| Kibana | 可视化平台 | 日志分析和仪表板功能成熟 |
| APM | 应用性能监控 | 内置 Trace 采集和分析能力 |

#### 方案C：混合架构

| 组件 | 角色 | 说明 |
|------|------|------|
| Tempo | Trace 存储 | 保留 Grafana Stack 的 Trace 能力 |
| Prometheus | Metrics 存储 | 保留 Prometheus 生态 |
| Elasticsearch | Logs 存储 | 利用 ELK 的全文检索能力分析日志 |
| Grafana | 统一面板 | 通过 Data Source Plugin 关联 ES |
| Kibana | 日志深度分析 | 复杂日志查询和分析场景 |

#### 三方案对比表

| 维度 | 方案A: Grafana Stack | 方案B: ELK Stack | 方案C: 混合架构 |
|------|---------------------|------------------|----------------|
| **资源消耗** | 低（Loki 轻量） | 高（ES 内存密集） | 中-高 |
| **Trace 查询性能** | 优秀（TraceID 直查） | 良好（APM） | 优秀 |
| **日志全文检索** | 一般（Loki 标签索引） | 优秀（ES 全文索引） | 优秀 |
| **Metrics 查询** | 优秀（PromQL） | 一般（Kibana） | 优秀 |
| **统一面板** | 原生支持 | 需 Kibana + APM | 需配置多数据源 |
| **运维复杂度** | 低 | 高 | 高 |
| **学习曲线** | 低-中 | 中-高 | 高 |
| **K8s 集成** | 原生 | 需 Filebeat/Logstash | 需 Filebeat |
| **关联跳转** | 原生（TraceID） | 支持（APM） | 需配置 |
| **适用场景** | K8s 原生、资源有限 | 日志密集型、全文检索 | 大规模、需全文+Trace |
| **最低资源** | 4C8G | 8C32G | 8C16G |
| **推荐规模** | <500 Pods | <200 Pods | 200-1000 Pods |
| **离线集群适配** | 支持（资源已优化） | 不推荐 | 不推荐 |

---

## 2.5 离线前置准备

> **说明：** 本节所有操作需在有外网访问的机器上完成，完成后将产物传输到离线集群使用。

### 2.5.1 Helm Chart 离线包

```bash
# 在有外网的机器上执行

# 添加 Helm 仓库
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 拉取 Chart 到本地
helm pull prometheus-community/kube-prometheus-stack --version 58.0.0
helm pull grafana/loki --version 6.7.0
helm pull grafana/promtail --version 6.16.0
helm pull grafana/tempo --version 1.7.0

# 将 .tgz 文件传到离线集群 Master 节点 /root/offline/ 目录
scp *.tgz root@<master-ip>:/root/offline/
```

### 2.5.2 OTel Operator YAML 离线化

```bash
# 在有外网的机器上执行

# 下载 Operator YAML
wget https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# 替换 YAML 中所有镜像地址为 Harbor 地址
sed -i 's|ghcr.io/open-telemetry/opentelemetry-operator/|192.168.1.61:80/otel/|g' opentelemetry-operator.yaml
sed -i 's|quay.io/jaegertracing/|192.168.1.61:80/otel/|g' opentelemetry-operator.yaml

# 传到离线集群
scp opentelemetry-operator.yaml root@<master-ip>:/root/offline/
```

### 2.5.3 镜像预推送清单

以下镜像需在有外网的机器上拉取、打标签后推送到 Harbor（192.168.1.61:80）：

```bash
# ===== OTel 相关镜像 =====

# 1. OTel Operator
docker pull ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:latest
docker tag ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:latest \
  192.168.1.61:80/otel/opentelemetry-operator:latest
docker push 192.168.1.61:80/otel/opentelemetry-operator:latest

# 2. OTel Collector Contrib
docker pull docker.io/otel/opentelemetry-collector-contrib:0.96.0
docker tag docker.io/otel/opentelemetry-collector-contrib:0.96.0 \
  192.168.1.61:80/otel/opentelemetry-collector-contrib:0.96.0
docker push 192.168.1.61:80/otel/opentelemetry-collector-contrib:0.96.0

# 3. OTel Java Agent（自动注入用）
docker pull ghcr.io/open-telemetry/opentelemetry-javaagent:1.33.0
docker tag ghcr.io/open-telemetry/opentelemetry-javaagent:1.33.0 \
  192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0
docker push 192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0

# ===== Grafana Stack 镜像（kube-prometheus-stack Chart 依赖） =====

# 4. Prometheus
docker pull docker.io/prom/prometheus:v2.54.1
docker tag docker.io/prom/prometheus:v2.54.1 192.168.1.61:80/prom/prometheus:v2.54.1
docker push 192.168.1.61:80/prom/prometheus:v2.54.1

# 5. Grafana
docker pull docker.io/grafana/grafana:11.3.0
docker tag docker.io/grafana/grafana:11.3.0 192.168.1.61:80/grafana/grafana:11.3.0
docker push 192.168.1.61:80/grafana/grafana:11.3.0

# 6. Alertmanager
docker pull docker.io/prom/alertmanager:v0.27.0
docker tag docker.io/prom/alertmanager:v0.27.0 192.168.1.61:80/prom/alertmanager:v0.27.0
docker push 192.168.1.61:80/prom/alertmanager:v0.27.0

# ===== Loki 相关镜像 =====

# 7. Loki
docker pull docker.io/grafana/loki:2.9.8
docker tag docker.io/grafana/loki:2.9.8 192.168.1.61:80/grafana/loki:2.9.8
docker push 192.168.1.61:80/grafana/loki:2.9.8

# 8. Promtail
docker pull docker.io/grafana/promtail:2.9.8
docker tag docker.io/grafana/promtail:2.9.8 192.168.1.61:80/grafana/promtail:2.9.8
docker push 192.168.1.61:80/grafana/promtail:2.9.8

# ===== Tempo 相关镜像 =====

# 9. Tempo
docker pull docker.io/grafana/tempo:2.4.0
docker tag docker.io/grafana/tempo:2.4.0 192.168.1.61:80/grafana/tempo:2.4.0
docker push 192.168.1.61:80/grafana/tempo:2.4.0

# ===== 其他依赖镜像（kube-prometheus-stack Chart 依赖） =====

# 10. kube-state-metrics
docker pull docker.io/bitnami/kube-state-metrics:2.13.0
docker tag docker.io/bitnami/kube-state-metrics:2.13.0 192.168.1.61:80/bitnami/kube-state-metrics:2.13.0
docker push 192.168.1.61:80/bitnami/kube-state-metrics:2.13.0

# 11. node-exporter
docker pull docker.io/prom/node-exporter:v1.8.2
docker tag docker.io/prom/node-exporter:v1.8.2 192.168.1.61:80/prom/node-exporter:v1.8.2
docker push 192.168.1.61:80/prom/node-exporter:v1.8.2

# 12. prometheus-adapter
docker pull docker.io/k8s.gcr.io/prometheus-adapter:v0.11.2
docker tag docker.io/k8s.gcr.io/prometheus-adapter:v0.11.2 192.168.1.61:80/prom/prometheus-adapter:v0.11.2
docker push 192.168.1.61:80/prom/prometheus-adapter:v0.11.2

# 13. busybox（initContainer 使用）
docker pull busybox:1.36
docker tag busybox:1.36 192.168.1.61:80/library/busybox:1.36
docker push 192.168.1.61:80/library/busybox:1.36
```

### 2.5.4 Helm Chart 镜像地址替换

```bash
# 在离线集群 Master 节点上，解压 Chart 并替换镜像地址

# 解压 kube-prometheus-stack Chart
tar -zxf /root/offline/kube-prometheus-stack-58.0.0.tgz -C /root/offline/

# 批量替换 Chart 中的镜像仓库地址
find /root/offline/kube-prometheus-stack/ -name '*.yaml' -o -name '*.tpl' | xargs \
  sed -i 's|docker.io/|192.168.1.61:80/|g; s|quay.io/|192.168.1.61:80/|g; s|ghcr.io/|192.168.1.61:80/|g; s|gcr.io/|192.168.1.61:80/|g; s|k8s.gcr.io/|192.168.1.61:80/|g'

# 重新打包
cd /root/offline/kube-prometheus-stack && tar -czf /root/offline/kube-prometheus-stack-58.0.0.tgz .

# 对 Loki、Promtail、Tempo Chart 执行相同操作
for chart in loki-6.7.0 promtail-6.16.0 tempo-1.7.0; do
  tar -zxf /root/offline/${chart}.tgz -C /root/offline/
  find /root/offline/${chart}/ -name '*.yaml' -o -name '*.tpl' | xargs \
    sed -i 's|docker.io/|192.168.1.61:80/|g; s|quay.io/|192.168.1.61:80/|g; s|ghcr.io/|192.168.1.61:80/|g; s|gcr.io/|192.168.1.61:80/|g; s|k8s.gcr.io/|192.168.1.61:80/|g'
  cd /root/offline/${chart} && tar -czf /root/offline/${chart}.tgz .
done
```

### 2.5.5 Harbor 项目创建

```bash
# 在 Harbor 上创建以下项目（通过 Harbor UI 或 API）
# 项目列表：
#   otel       - OpenTelemetry 相关镜像
#   prom       - Prometheus 相关镜像
#   grafana    - Grafana/Loki/Tempo 相关镜像
#   bitnami    - Bitnami 镜像
#   library    - 基础镜像（busybox 等）

# Harbor 登录（所有 Worker 节点均需配置）
docker login 192.168.1.61:80 -u admin -p Harbor12345

# 配置 K8s 节点信任 Harbor HTTP 仓库
# 在所有 K8s 节点上执行：
cat > /etc/containerd/config.toml.d/harbor.toml <<'EOF'
[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61:80".tls]
  insecure_skip_verify = true

[plugins."io.containerd.grpc.v1.cri".registry.configs."192.168.1.61:80".auth]
  username = "admin"
  password = "Harbor12345"
EOF
systemctl restart containerd
```

---

## 3. 部署实战

### 3.1 部署 Prometheus Stack

```bash
# ===== 离线 Helm 安装方式 =====
# 步骤1：在有外网的机器上拉取 Chart
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm repo update
# helm pull prometheus-community/kube-prometheus-stack --version 58.0.0
# 将 kube-prometheus-stack-58.0.0.tgz 传到离线集群 Master 节点

# 步骤2：修改 Chart 中的镜像地址为 Harbor（见离线前置准备章节）

# 创建命名空间
kubectl create namespace monitoring

# 安装 Prometheus Stack（包含 Prometheus、Grafana、Alertmanager）
helm install prometheus /root/offline/kube-prometheus-stack-58.0.0.tgz \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=7d \          # 数据保留 7 天
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=local-path \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=30Gi \
  --set prometheus.prometheusSpec.resources.requests.cpu=250m \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.cpu=1000m \
  --set prometheus.prometheusSpec.resources.limits.memory=2Gi \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=32000 \
  --set grafana.adminPassword=Admin@123 \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=5Gi \
  --set grafana.persistence.storageClassName=local-path \
  --set grafana.resources.requests.cpu=50m \
  --set grafana.resources.requests.memory=128Mi \
  --set grafana.resources.limits.cpu=250m \
  --set grafana.resources.limits.memory=512Mi \
  --set alertmanager.alertmanagerSpec.resources.requests.cpu=100m \
  --set alertmanager.alertmanagerSpec.resources.requests.memory=256Mi \
  --set kubeStateMetrics.enabled=true \
  --set nodeExporter.enabled=true \
  --wait --timeout 300s

# 验证
kubectl get pods -n monitoring
# 预期：prometheus-xxx, grafana-xxx, alertmanager-xxx Running

# 访问 Grafana：http://192.168.1.54:32000 (admin/Admin@123)
```

### 3.2 部署 Loki

```bash
# ===== 离线 Helm 安装方式 =====
# 步骤1：在有外网的机器上拉取 Chart
# helm repo add grafana https://grafana.github.io/helm-charts
# helm repo update
# helm pull grafana/loki --version 6.7.0
# helm pull grafana/promtail --version 6.16.0
# helm pull grafana/tempo --version 1.7.0
# 将所有 .tgz 文件传到离线集群 Master 节点

# 安装 Loki（单节点模式，适合中小规模）
helm install loki /root/offline/loki-6.7.0.tgz \
  --namespace monitoring \
  --set loki.auth_enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem \                    # 文件系统存储
  --set singleBinary.replicas=1 \                         # 单实例部署
  --set singleBinary.persistence.size=10Gi \
  --set singleBinary.persistence.storageClassName=local-path \
  --set singleBinary.resources.requests.cpu=100m \
  --set singleBinary.resources.requests.memory=256Mi \
  --set singleBinary.resources.limits.cpu=500m \
  --set singleBinary.resources.limits.memory=1Gi \
  --set loki.schemaConfig.configs[0].from=2024-01-01 \
  --set loki.schemaConfig.configs[0].store=tsdb \
  --set loki.schemaConfig.configs[0].object_store=filesystem \
  --set loki.schemaConfig.configs[0].schema=v13 \
  --set loki.schemaConfig.configs[0].index.prefix=index_ \
  --set loki.schemaConfig.configs[0].index.period=24h \
  --wait --timeout 120s

# 验证 Loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=10
```

### 3.3 部署 Promtail（日志采集）

```bash
# 安装 Promtail
helm install promtail /root/offline/promtail-6.16.0.tgz \
  --namespace monitoring \
  --set config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=64Mi \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=256Mi \
  --wait --timeout=120s

# 验证 Promtail
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=10
```

### 3.4 部署 Tempo（分布式追踪后端）

```bash
# 安装 Tempo
helm install tempo /root/offline/tempo-1.7.0.tgz \
  --namespace monitoring \
  --set tempo.receivers.jaeger.protocols.grpc.enabled=true \
  --set tempo.receivers.jaeger.protocols.thrift_http.enabled=true \
  --set tempo.receivers.otlp.protocols.grpc.enabled=true \
  --set tempo.receivers.otlp.protocols.http.enabled=true \
  --set tempo.storage.trace.backend=local \          # 本地存储后端
  --set tempo.storage.trace.local.path=/var/tempo/traces \
  --set tempo.storage.trace.wal.path=/var/tempo/wal \  # WAL 预写日志路径
  --set tempo.metricsGenerator.enabled=true \          # 启用 Trace 转 Metrics
  --set tempo.metricsGenerator.storage.path=/var/tempo/generator-wal \
  --set tempo.metricsGenerator.remoteWrite.url=http://prometheus-operated.monitoring.svc.cluster.local:9090/api/v1/write \
  --set tempo.resources.requests.cpu=100m \
  --set tempo.resources.requests.memory=256Mi \
  --set tempo.resources.limits.cpu=500m \
  --set tempo.resources.limits.memory=1Gi \
  --set distributor.resources.requests.cpu=50m \
  --set distributor.resources.requests.memory=128Mi \
  --set ingester.resources.requests.cpu=50m \
  --set ingester.resources.requests.memory=128Mi \
  --set querier.resources.requests.cpu=50m \
  --set querier.resources.requests.memory=128Mi \
  --set persistence.enabled=true \
  --set persistence.size=10Gi \
  --set persistence.storageClassName=local-path \
  --wait --timeout 120s

# 验证 Tempo
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=10
```

### 3.5 部署 OpenTelemetry Collector

```bash
# 安装 OTel Operator（离线方式）
# 步骤1：在有外网的机器上下载 Operator YAML
# wget https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# 步骤2：修改 YAML 中所有镜像地址，替换为 Harbor 地址
# 原始镜像示例：
#   ghcr.io/open-telemetry/opentelemetry-operator/opentelemetry-operator:latest
#   quay.io/jaegertracing/jaeger-operator:latest
# 替换为：
#   192.168.1.61:80/otel/opentelemetry-operator:latest
#   192.168.1.61:80/otel/jaeger-operator:latest
# 具体方法：
#   sed -i 's|ghcr.io/open-telemetry/opentelemetry-operator/|192.168.1.61:80/otel/|g' opentelemetry-operator.yaml
#   sed -i 's|quay.io/jaegertracing/|192.168.1.61:80/otel/|g' opentelemetry-operator.yaml

# 步骤3：将修改后的 YAML 传到离线集群 Master 节点，执行安装
kubectl apply -f /root/offline/opentelemetry-operator.yaml

# 验证 Operator
kubectl get pods -n opentelemetry-operator-system

# 创建 Collector 配置
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector    # OTel Collector CRD
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  image: 192.168.1.61:80/otel/opentelemetry-collector-contrib:0.96.0
  mode: deployment               # 部署模式
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
  ports:
  - name: otlp-grpc
    port: 4317                   # OTLP gRPC 接收端口
    protocol: TCP
  - name: otlp-http
    port: 4318                   # OTLP HTTP 接收端口
    protocol: TCP
  - name: jaeger-grpc
    port: 14250                  # Jaeger gRPC 接收端口
    protocol: TCP
  - name: jaeger-thrift
    port: 14268                  # Jaeger Thrift 接收端口
    protocol: TCP
  - name: prometheus
    port: 8889                   # Prometheus 指标暴露端口
    protocol: TCP
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      jaeger:
        protocols:
          grpc:
            endpoint: 0.0.0.0:14250
          thrift_http:
            endpoint: 0.0.0.0:14268

    processors:
      # ========== Batch Processor: 批量处理，减少网络开销 ==========
      batch:
        timeout: 5s                    # 批量发送超时时间
        send_batch_size: 1024          # 批量发送大小
        send_batch_max_size: 2048      # 最大批量大小
      
      # ========== Memory Limiter: 内存限制，防止OOM ==========
      memory_limiter:
        check_interval: 5s             # 内存检查间隔
        limit_mib: 768                 # 内存上限（MiB）
        spike_limit_mib: 384           # 内存峰值限制（MiB）
      
      # ========== Resource Processor: 添加资源属性 ==========
      resource:
        attributes:
          - key: environment
            value: production
            action: upsert
          - key: cluster.name
            value: k8s-production
            action: upsert
          - key: host.name
            from_attribute: k8s.node.name
            action: upsert
      
      # ========== Resource Detection: 自动检测云环境属性 ==========
      resourcedetection:
        detectors: [env, system, k8s]
        timeout: 5s
        override: false
      
      # ========== K8s Attributes: 自动添加K8s元数据 ==========
      k8sattributes:
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.namespace.name
            - k8s.node.name
            - k8s.deployment.name
            - k8s.statefulset.name
            - k8s.daemonset.name
            - k8s.cronjob.name
            - k8s.job.name
          labels:
            - tag_name: app.label
              key: app
              from: pod
        pod_association:
          - sources:
              - from: resource_attribute
                name: k8s.pod.uid
      
      # ========== Filter Processor: 过滤无价值数据 ==========
      filter/health:
        error_mode: ignore
        traces:
          span:
            - 'attributes["http.route"] == "/health"'
            - 'attributes["http.route"] == "/actuator/health"'
            - 'attributes["http.route"] == "/readyz"'
            - 'attributes["http.route"] == "/livez"'
            - 'attributes["http.route"] == "/metrics"'
            - 'attributes["user_agent.original"] == "Prometheus/*"'
      
      # ========== Attributes Processor: 修改/添加属性 ==========
      attributes:
        actions:
          - key: http.method
            from_attribute: http.request.method
            action: upsert
          - key: http.status_code
            from_attribute: http.response.status_code
            action: upsert
      
      # ========== Probabilistic Sampler: 概率采样 ==========
      probabilistic_sampler:
        sampling_percentage: 10.0
        hash_seed: 22
      
      # ========== Tail Sampling: 尾部采样策略 ==========
      tail_sampling:
        decision_wait: 10s           # 等待 Trace 完成时间
        num_traces: 50000            # 内存中缓冲的 Trace 数量
        expected_new_traces_per_sec: 100
        policies:
          - name: errors
            type: status_code
            status_code:
              status_codes: [ERROR]  # 保留所有错误 Trace
          - name: slow
            type: latency
            latency:
              threshold_ms: 1000     # 保留延迟超过 1 秒的 Trace

    exporters:
      # ========== OTLP Exporter: 发送到Tempo ==========
      otlp/tempo:
        endpoint: tempo.monitoring.svc.cluster.local:4317  # Tempo 地址
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
          initial_interval: 5s
          max_interval: 30s
          max_elapsed_time: 300s
        sending_queue:
          enabled: true
          num_consumers: 10
          queue_size: 1000
      
      # ========== Prometheus Exporter: 暴露指标端点 ==========
      prometheus:
        endpoint: 0.0.0.0:8889
        resource_to_telemetry_conversion:
          enabled: true
        const_labels:
          source: otel-collector
      
      # ========== OTLP HTTP Exporter: 发送到Loki ==========
      otlphttp/loki:
        endpoint: http://loki.monitoring.svc.cluster.local:3100/otlp/v1/logs
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
        sending_queue:
          enabled: true
      
      # ========== Debug Exporter: 调试输出 ==========
      debug:
        verbosity: detailed
        sampling_initial: 2
        sampling_thereafter: 500

    connectors:
      # ========== SpanMetrics Connector: Trace转Metrics ==========
      spanmetrics:
        histogram:
          explicit:
            buckets: [2ms, 4ms, 6ms, 8ms, 10ms, 50ms, 100ms, 200ms, 400ms, 800ms, 1s, 5s]
        dimensions:                  # 指标维度标签
          - name: http.method
          - name: http.status_code
          - name: k8s.namespace.name
        dimensions_cache_size: 1000

    service:
      # ========== Pipeline配置：多路由策略 ==========
      pipelines:
        # Traces Pipeline: 完整处理链
        traces:
          receivers: [otlp, jaeger]
          processors: 
            - memory_limiter      # 第1步：内存限制
            - resourcedetection   # 第2步：自动检测资源属性
            - k8sattributes       # 第3步：添加K8s元数据
            - resource            # 第4步：添加自定义资源属性
            - filter/health       # 第5步：过滤健康检查
            - probabilistic_sampler  # 第6步：概率采样
            - tail_sampling       # 第7步：尾部采样
            - attributes          # 第8步：属性规范化
            - batch               # 第9步：批量处理
          exporters: [otlp/tempo, spanmetrics]
        
        # Metrics Pipeline
        metrics:
          receivers: [otlp, spanmetrics]
          processors:
            - memory_limiter
            - resourcedetection
            - k8sattributes
            - resource
            - batch
          exporters: [prometheus]
        
        # Logs Pipeline
        logs:
          receivers: [otlp]
          processors:
            - memory_limiter
            - resourcedetection
            - k8sattributes
            - resource
            - batch
          exporters: [otlphttp/loki]
      
      # ========== 遥测配置：监控Collector自身 ==========
      telemetry:
        logs:
          level: info
          development: false
          encoding: json
        metrics:
          level: detailed
          address: 0.0.0.0:8888
      
      # ========== 扩展配置 ==========
      extensions: [health_check, pprof, zpages]

  # ========== Collector扩展组件 ==========
  extensions:
    health_check:
      endpoint: 0.0.0.0:13133
      path: /health/status
    pprof:
      endpoint: 0.0.0.0:1777
    zpages:
      endpoint: 0.0.0.0:55679
EOF

# 验证 Collector
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector --tail=20
```

### 3.5.2 多Exporter路由配置详解

**场景：不同数据路由到不同后端**

```
+================================================================================+
|                    多Exporter路由架构                                           |
+================================================================================+
|                                                                                |
|   +-------------------+                                                        |
|   |   Applications    |                                                        |
|   +---------+---------+                                                        |
|             |                                                                  |
|             v                                                                  |
|   +-------------------+                                                        |
|   | OTel Collector    |                                                        |
|   |  (Gateway Mode)   |                                                        |
|   +---------+---------+                                                        |
|             |                                                                  |
|    +--------+--------+--------+                                                |
|    |                 |         |                                                |
|    v                 v         v                                                |
| +--------+    +----------+  +----------+                                      |
| | Tempo  |    | Jaeger   |  |  S3      |  <-- Trace Backends                  |
| | (Dev)  |    | (Prod)   |  | (Archive)|                                      |
| +--------+    +----------+  +----------+                                      |
|                                                                                |
| +--------+    +----------+  +----------+                                      |
| |Prometheus|  | Thanos   |  |  Kafka   |  <-- Metrics Backends                |
| | (Local) |   | (Long)   |  | (Stream) |                                      |
| +--------+    +----------+  +----------+                                      |
|                                                                                |
| +--------+    +----------+  +----------+                                      |
| | Loki   |    |ES/Splunk |  |  S3      |  <-- Logs Backends                   |
| | (K8s)  |    | (SIEM)   |  | (Archive)|                                      |
| +--------+    +----------+  +----------+                                      |
|                                                                                |
+================================================================================+
```

**多路由Collector配置：**

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector-gateway
  namespace: monitoring
spec:
  mode: deployment
  replicas: 2
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      # 路由决策处理器
      routing:
        from_attribute: environment
        attribute_source: resource
        default_exporters: [otlp/tempo-dev]
        table:
          - value: production
            exporters: [otlp/tempo-prod, otlp/jaeger]
          - value: staging
            exporters: [otlp/tempo-staging]
          - value: development
            exporters: [otlp/tempo-dev]
      
      # 数据分类处理器
      filter/metrics-only:
        metrics:
          metric:
            - 'name != "http_server_requests_seconds_count"'
      
      filter/traces-only:
        traces:
          span:
            - 'attributes["http.route"] == "/health"'

    exporters:
      # ========== Trace Exporters ==========
      # 开发环境Tempo
      otlp/tempo-dev:
        endpoint: tempo-dev.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      
      # 生产环境Tempo
      otlp/tempo-prod:
        endpoint: tempo-prod.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
        retry_on_failure:
          enabled: true
        sending_queue:
          enabled: true
          num_consumers: 20
      
      # Jaeger备份
      otlp/jaeger:
        endpoint: jaeger-collector.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      
      # S3归档
      awsxray:
        region: us-west-2
        no_verify_ssl: false
        local_mode: false
      
      # ========== Metrics Exporters ==========
      # 本地Prometheus
      prometheus:
        endpoint: 0.0.0.0:8889
      
      # Thanos远程写入
      prometheusremotewrite/thanos:
        endpoint: http://thanos-receive.monitoring.svc.cluster.local:19291/api/v1/receive
        tls:
          insecure: true
      
      # Kafka流式处理
      kafka/metrics:
        brokers:
          - kafka-0.kafka.monitoring.svc.cluster.local:9092
          - kafka-1.kafka.monitoring.svc.cluster.local:9092
        topic: otel-metrics
        encoding: otlp_proto
      
      # ========== Logs Exporters ==========
      # Loki
      otlphttp/loki:
        endpoint: http://loki.monitoring.svc.cluster.local:3100/otlp/v1/logs
        tls:
          insecure: true
      
      # Elasticsearch
      elasticsearch:
        endpoints:
          - http://elasticsearch.monitoring.svc.cluster.local:9200
        index: otel-logs
        mapping:
          mode: bodymap
      
      # S3归档
      awss3:
        region: us-west-2
        s3uploader:
          bucket: otel-logs-archive
          region: us-west-2

    service:
      pipelines:
        # Traces多路由
        traces/dev:
          receivers: [otlp]
          processors: [routing, batch]
          exporters: [otlp/tempo-dev]
        
        traces/prod:
          receivers: [otlp]
          processors: [routing, tail_sampling, batch]
          exporters: [otlp/tempo-prod, otlp/jaeger]
        
        # Metrics多路由
        metrics/local:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus]
        
        metrics/longterm:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheusremotewrite/thanos]
        
        metrics/streaming:
          receivers: [otlp]
          processors: [filter/metrics-only, batch]
          exporters: [kafka/metrics]
        
        # Logs多路由
        logs/k8s:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/loki]
        
        logs/siem:
          receivers: [otlp]
          processors: [batch]
          exporters: [elasticsearch]
        
        logs/archive:
          receivers: [otlp]
          processors: [batch]
          exporters: [awss3]
```

**基于属性的智能路由：**

```yaml
processors:
  # 根据服务名称路由
  routing/service:
    from_attribute: service.name
    default_exporters: [otlp/tempo-default]
    table:
      - value: payment-service
        exporters: [otlp/tempo-critical, otlp/jaeger]
      - value: auth-service
        exporters: [otlp/tempo-security]
      - value: order-service
        exporters: [otlp/tempo-prod]

  # 根据错误状态路由
  resource/error-routing:
    attributes:
      - key: routing.destination
        from_attribute: http.status_code
        action: insert

  # 根据命名空间路由
  routing/namespace:
    from_attribute: k8s.namespace.name
    default_exporters: [otlp/tempo-default]
    table:
      - value: production
        exporters: [otlp/tempo-prod]
      - value: staging
        exporters: [otlp/tempo-staging]
      - value: monitoring
        exporters: [otlp/tempo-internal]
```

**离线环境多路由配置：**

```yaml
# 离线环境：不同数据保留策略路由
processors:
  # 短保留路由（开发测试数据）
  filter/short-retention:
    traces:
      span:
        - 'attributes["retention"] == "short"'
  
  # 长保留路由（生产关键数据）
  filter/long-retention:
    traces:
      span:
        - 'attributes["retention"] == "long"'

exporters:
  # 短保留后端（本地存储，3天）
  otlp/tempo-short:
    endpoint: tempo-short.monitoring.svc.cluster.local:4317
    tls:
      insecure: true
  
  # 长保留后端（对象存储，30天）
  otlp/tempo-long:
    endpoint: tempo-long.monitoring.svc.cluster.local:4317
    tls:
      insecure: true

service:
  pipelines:
    traces/short:
      receivers: [otlp]
      processors: [filter/short-retention, batch]
      exporters: [otlp/tempo-short]
    
    traces/long:
      receivers: [otlp]
      processors: [filter/long-retention, tail_sampling, batch]
      exporters: [otlp/tempo-long]
```

### 3.6 Java Spring Boot 应用接入 OTel Agent

```bash
# 方法一：使用 OTel Java Agent（推荐，无需修改代码）
# 下载 Agent JAR（在有外网的机器上执行）
OTEL_VERSION="1.33.0"
# curl -L -o /tmp/opentelemetry-javaagent.jar \
#   "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_VERSION}/opentelemetry-javaagent.jar"
# docker pull ghcr.io/open-telemetry/opentelemetry-javaagent:${OTEL_VERSION}
# docker tag ghcr.io/open-telemetry/opentelemetry-javaagent:${OTEL_VERSION} 192.168.1.61:80/otel/opentelemetry-javaagent:${OTEL_VERSION}
# docker push 192.168.1.61:80/otel/opentelemetry-javaagent:${OTEL_VERSION}
# 将 Agent JAR 打包到应用镜像中，或使用 initContainer 从 Harbor 拉取

# 方法二：在 K8s Deployment 中配置自动注入
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: demo
  labels:
    app: api-server
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
        version: v1
    spec:
      initContainers:
      - name: otel-agent-init
        image: 192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0
        command: ['sh', '-c', 'cp /opentelemetry-javaagent.jar /otel-auto-instrumentation/javaagent.jar']
        volumeMounts:
        - name: otel-agent
          mountPath: /otel-auto-instrumentation
      containers:
      - name: api-server
        image: 192.168.1.61:80/demo/api-server:v1
        ports:
        - containerPort: 8080
        env:
        - name: JAVA_OPTS
          value: >-
            -javaagent:/otel-auto-instrumentation/javaagent.jar
        - name: OTEL_SERVICE_NAME
          value: "api-server"
        - name: OTEL_SERVICE_VERSION
          value: "v1.0.0"
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector.monitoring.svc.cluster.local:4317"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "grpc"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=production,service.namespace=demo"
        - name: OTEL_TRACES_SAMPLER
          value: "parentbased_traceidratio"
        - name: OTEL_TRACES_SAMPLER_ARG
          value: "0.1"
        - name: OTEL_LOGS_EXPORTER
          value: "otlp"
        - name: OTEL_METRICS_EXPORTER
          value: "otlp"
        - name: OTEL_INSTRUMENTATION_SPRING_WEB_ENABLED
          value: "true"
        - name: OTEL_INSTRUMENTATION_SPRING_WEBMVC_ENABLED
          value: "true"
        - name: OTEL_INSTRUMENTATION_MICROMETER_ENABLED
          value: "true"
        - name: OTEL_INSTRUMENTATION_JDBC_ENABLED
          value: "true"
        - name: OTEL_INSTRUMENTATION_REDISCALA_ENABLED
          value: "true"
        - name: OTEL_INSTRUMENTATION_KAFKA_ENABLED
          value: "true"
        - name: OTEL_JAVA_ENABLED_RESOURCE_PROVIDERS
          value: "process-runtime"
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        volumeMounts:
        - name: otel-agent
          mountPath: /otel-auto-instrumentation
      volumes:
      - name: otel-agent
        emptyDir: {}
EOF

# 方法三：使用 OTel Operator 自动注入（最优雅）
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation           # OTel 自动注入资源 CRD
metadata:
  name: java-instrumentation
  namespace: monitoring
spec:
  exporter:
    endpoint: http://otel-collector.monitoring.svc.cluster.local:4317  # Collector 地址
  propagators:                    # 上下文传播协议
    - tracecontext               # W3C Trace Context 标准
    - baggage
    - b3                          # Zipkin B3 格式
  sampler:
    type: parentbased_traceidratio
    arg: "0.1"                    # 10% 采样率
  java:
    image: 192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 512Mi
EOF

# 在 Deployment 中引用 Instrumentation
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: demo
  labels:
    app: api-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
        instrumentation.opentelemetry.io/inject-java: "monitoring/java-instrumentation"
    spec:
      containers:
      - name: api-server
        image: 192.168.1.61:80/demo/api-server:v1
        ports:
        - containerPort: 8080
        env:
        - name: OTEL_SERVICE_NAME
          value: "api-server"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=production"
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
EOF
```

### 3.7 配置 Grafana 数据源

```bash
# 添加 Tempo 数据源
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-tempo
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  tempo.yaml: |-
    apiVersion: 1
    datasources:
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo.monitoring.svc.cluster.local:3100
      uid: tempo
      editable: false
      isDefault: false
      jsonData:
        httpMethod: GET
        tracesToLogs:
          datasourceId: 2
          tags: ['k8s.namespace.name', 'k8s.pod.name']
          mappedTags: [{tagKey: 'k8s.namespace.name', datasourceTagKey: 'namespace'}, {tagKey: 'k8s.pod.name', datasourceTagKey: 'pod'}]
          mapTagToLabel: 'k8s.pod.name'
          labelValues: true
        tracesToMetrics:
          datasourceId: 1
          tags: [{key: 'k8s.namespace.name', value: 'namespace'}, {key: 'k8s.pod.name', value: 'pod'}]
          queries:
          - name: 'Request Rate'
            query: 'rate(http_server_requests_seconds_count{namespace="$namespace",pod="$pod"}[5m])'
          - name: 'Error Rate'
            query: 'rate(http_server_requests_seconds_count{namespace="$namespace",pod="$pod",status=~"5.."}[5m])'
          - name: 'Latency P99'
            query: 'histogram_quantile(0.99, rate(http_server_requests_seconds_bucket{namespace="$namespace",pod="$pod"}[5m]))'
        serviceMap:
          datasourceId: 1
        nodeGraph:
          enabled: true
        traceQuery:
          timeShiftEnabled: true
          spanStartTimeShift: '-30s'
          spanEndTimeShift: '30s'
          minDuration: '1ms'
          maxDuration: '60s'
          limit: 1000
EOF

# 添加 Loki 数据源
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-loki
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  loki.yaml: |-
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
      uid: loki
      editable: false
      isDefault: false
      jsonData:
        maxLines: 1000
        derivedFields:
        - datasourceUid: tempo
          matcherRegex: '"traceId":"([a-f0-9]+)"'
          name: TraceID
          url: '$${__value.raw}'
          urlDisplayLabel: 'View Trace'
EOF

# 重启 Grafana 使数据源生效
kubectl rollout restart deployment prometheus-grafana -n monitoring
kubectl rollout status deployment prometheus-grafana -n monitoring --timeout=120s
```

---

## 4. 配置详解 / 高级功能

### 4.1 Tail Sampling（尾部采样）

```bash
# 更新 Collector 配置，添加尾部采样
cat <<'EOF' | kubectl apply -f -
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 5s
        send_batch_size: 1024
      memory_limiter:
        check_interval: 5s
        limit_mib: 768
        spike_limit_mib: 384
      tail_sampling:
        decision_wait: 10s
        num_traces: 50000
        expected_new_traces_per_sec: 100
        policies:
          - name: errors-policy
            type: status_code
            status_code:
              status_codes: [ERROR]
          - name: slow-requests-policy
            type: latency
            latency:
              threshold_ms: 1000
          - name: health-check-policy
            type: string_attribute
            string_attribute:
              key: http.route
              values: ["/health", "/actuator/health"]
              enabled: false
          - name: probabilistic-policy
            type: probabilistic
            probabilistic:
              sampling_percentage: 10

    exporters:
      otlp:
        endpoint: tempo.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      prometheus:
        endpoint: 0.0.0.0:8889

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, tail_sampling, batch]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, batch]
          exporters: [prometheus]
EOF
```

### 4.2 SpanMetrics Connector（Trace 转 Metrics）

```bash
# SpanMetrics 自动从 Trace 中提取 RED 指标
# Rate（请求速率）、Errors（错误率）、Duration（延迟）
# 已在 Collector 配置中启用，验证生成的指标：
curl -s http://otel-collector.monitoring.svc.cluster.local:8889/metrics | grep spanmetrics
# 预期输出：
# spanmetrics_duration_seconds_bucket{...}
# spanmetrics_calls_total{service_name="api-server",span_name="GET /api/orders",...}
# spanmetrics_size_total{...}
```

### 4.3 自定义 Grafana Dashboard

```bash
# 导入 JVM (Micrometer) Dashboard
# Dashboard ID: 4701 (JVM (Micrometer))
# Dashboard ID: 12900 (Spring Boot 2.1 Statistics)
# Dashboard ID: 1860 (Node Exporter Full)
# Dashboard ID: 16098 (Istio Workload Dashboard)

# 创建自定义 Dashboard（Trace 关联）
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-observability
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  observability.json: |-
    {
      "dashboard": {
        "title": "可观测性总览",
        "uid": "observability-overview",
        "panels": [
          {
            "title": "请求速率 (QPS)",
            "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "targets": [
              {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": "sum(rate(http_server_requests_seconds_count{namespace=\"demo\"}[5m])) by (service_name)"
              }
            ]
          },
          {
            "title": "错误率 (%)",
            "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
            "targets": [
              {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": "sum(rate(http_server_requests_seconds_count{namespace=\"demo\",status=~\"5..\"}[5m])) / sum(rate(http_server_requests_seconds_count{namespace=\"demo\"}[5m])) * 100"
              }
            ]
          },
          {
            "title": "P99 延迟",
            "type": "timeseries",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
            "targets": [
              {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": "histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace=\"demo\"}[5m])) by (le, service_name))"
              }
            ]
          },
          {
            "title": "最近错误日志",
            "type": "logs",
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16},
            "targets": [
              {
                "datasource": {"type": "loki", "uid": "loki"},
                "expr": "{namespace=\"demo\", container!~\"istio-proxy|otel-collector\"} |= \"ERROR\" | json"
              }
            ]
          }
        ]
      }
    }
EOF
```

### 4.4 告警规则配置

```bash
# 创建 Prometheus 告警规则
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule            # Prometheus 自定义规则 CRD
metadata:
  name: demo-alerts
  namespace: monitoring
  labels:
    prometheus: kube-prometheus    # 匹配 Prometheus RuleSelector
spec:
  groups:
  - name: demo-service-alerts
    rules:
    - alert: HighErrorRate        # 高错误率告警
      expr: |
        sum(rate(http_server_requests_seconds_count{namespace="demo",status=~"5.."}[5m]))
        / sum(rate(http_server_requests_seconds_count{namespace="demo"}[5m])) > 0.05
      for: 5m                     # 持续 5 分钟触发
      labels:
        severity: critical
      annotations:
        summary: "服务 {{ $labels.service_name }} 错误率超过 5%"
        description: "命名空间 demo 中 {{ $labels.service_name }} 的 5xx 错误率为 {{ $value | humanizePercentage }}"

    - alert: HighLatencyP99
      expr: |
        histogram_quantile(0.99,
          sum(rate(http_server_requests_seconds_bucket{namespace="demo"}[5m])) by (le, service_name)
        ) > 2
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "服务 {{ $labels.service_name }} P99 延迟超过 2s"
        description: "当前 P99 延迟为 {{ $value }}s"

    - alert: HighCPUUsage
      expr: |
        process_cpu_usage{namespace="demo"} > 0.8
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "服务 {{ $labels.service_name }} CPU 使用率超过 80%"

    - alert: OtelCollectorHighMemory
      expr: |
        container_memory_working_set_bytes{namespace="monitoring",container="otel-collector"}
        / container_spec_memory_limit_bytes{namespace="monitoring",container="otel-collector"} > 0.85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "OTel Collector 内存使用率超过 85%"
EOF

# 验证告警规则
kubectl get prometheusrule -n monitoring
```

---

## 4.5 采样策略配置

### 4.5.1 采样策略概述

采样（Sampling）是控制可观测性数据量的核心机制，合理的采样策略能在保证问题可定位性的同时，大幅降低存储和传输成本。

```
+================================================================================+
|                        采样策略对比图                                          |
+================================================================================+
|                                                                                |
|   头部采样 (Head-based Sampling)      尾部采样 (Tail-based Sampling)            |
|   +---------------------+            +---------------------+                   |
|   | 请求进入时即决定     |            | 等待Trace完成后决定  |                   |
|   | 是否采集该Trace    |            | 根据完整信息过滤     |                   |
|   +---------------------+            +---------------------+                   |
|          |                                    |                                |
|          v                                    v                                |
|   优点: 实现简单                    优点: 智能保留错误/慢请求                   |
|   缺点: 可能丢弃关键Trace           缺点: 需要内存缓冲完整Trace                  |
|                                                                                |
+================================================================================+
```

**采样策略对比：**

| 特性 | 头部采样 | 尾部采样 |
|------|----------|----------|
| 决策时机 | Trace开始时 | Trace完成后 |
| 实现复杂度 | 低 | 高（需缓冲） |
| 资源消耗 | 低 | 高（需缓冲） |
| 错误Trace保留 | 不确定 | 可确保保留 |
| 适用场景 | 高流量、资源受限 | 问题排查、生产环境 |

### 4.5.2 头部采样配置

**概率采样（Probabilistic Sampling）：**

```yaml
# OTel SDK 环境变量配置（应用侧）
env:
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"  # 基于父Span的采样率
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # 10% 采样率
```

**采样器类型说明：**

| 采样器 | 说明 | 适用场景 |
|--------|------|----------|
| `always_on` | 始终采样 | 开发/测试环境 |
| `always_off` | 从不采样 | 临时关闭追踪 |
| `traceidratio` | 基于TraceID的固定比例 | 无父Span的场景 |
| `parentbased_always_on` | 跟随父Span，根Span始终采样 | 默认推荐 |
| `parentbased_traceidratio` | 跟随父Span，根Span按比例采样 | 生产环境推荐 |

**Collector 概率采样配置：**

```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10.0  # 10% 采样
    hash_seed: 22  # 哈希种子，确保多Collector实例一致性
```

### 4.5.3 尾部采样配置

**基于延迟的尾部采样：**

```yaml
processors:
  tail_sampling:
    decision_wait: 10s  # 等待Trace完成的最长时间
    num_traces: 50000   # 内存中缓冲的Trace数量上限
    expected_new_traces_per_sec: 100  # 预期每秒新Trace数
    policies:
      - name: slow-requests
        type: latency
        latency:
          threshold_ms: 1000  # 保留延迟>1s的请求
```

**基于错误的尾部采样：**

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    expected_new_traces_per_sec: 100
    policies:
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]  # 保留所有错误Trace
```

**组合策略（AND/OR）：**

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 100000
    expected_new_traces_per_sec: 1000
    policies:
      # 策略1: 保留所有错误Trace
      - name: error-policy
        type: status_code
        status_code:
          status_codes: [ERROR]
      
      # 策略2: 保留慢请求
      - name: latency-policy
        type: latency
        latency:
          threshold_ms: 500
      
      # 策略3: 对特定路径进行概率采样
      - name: probabilistic-policy
        type: probabilistic
        probabilistic:
          sampling_percentage: 5
      
      # 策略4: 组合策略 - 保留错误且延迟>100ms的Trace
      - name: error-and-slow
        type: and
        and:
          and_sub_policy:
            - name: error-sub
              type: status_code
              status_code:
                status_codes: [ERROR]
            - name: slow-sub
              type: latency
              latency:
                threshold_ms: 100
      
      # 策略5: 排除健康检查
      - name: exclude-health
        type: string_attribute
        string_attribute:
          key: http.route
          values: ["/health", "/actuator/health", "/readyz", "/livez"]
          enabled: false  # 不匹配这些路径
```

**尾部采样策略类型详解：**

| 策略类型 | 配置参数 | 说明 |
|----------|----------|------|
| `always_sample` | 无 | 始终采样 |
| `latency` | `threshold_ms` | 延迟超过阈值采样 |
| `status_code` | `status_codes` | 指定状态码采样 |
| `string_attribute` | `key`, `values` | 字符串属性匹配采样 |
| `numeric_attribute` | `key`, `min_value`, `max_value` | 数值属性范围采样 |
| `probabilistic` | `sampling_percentage` | 概率采样 |
| `rate_limiting` | `spans_per_second` | 速率限制采样 |
| `and` | `and_sub_policy` | 组合多个策略（AND） |
| `composite` | `composite_sub_policy` | 优先级组合策略 |

### 4.5.4 采样策略选择决策树

```
+================================================================================+
|                        采样策略选择决策树                                       |
+================================================================================+
|                                                                                |
|                         开始选择采样策略                                        |
|                              |                                                 |
|              +---------------+---------------+                                 |
|              |                               |                                 |
|        开发/测试环境?                 生产环境?                                 |
|              |                               |                                 |
|              v                               v                                 |
|      +---------------+            +-------------------+                        |
|      | always_on     |            | 流量 > 1000 TPS?  |                        |
|      | 100%采样      |            +---------+---------+                        |
|      +---------------+                      |                                   |
|                                             |                                   |
|                              +--------------+--------------+                   |
|                              |                             |                   |
|                            是                             否                   |
|                              |                             |                   |
|                              v                             v                   |
|                    +-------------------+          +-------------------+        |
|                    | 头部采样 1-10%    |          | 头部采样 10-50%   |        |
|                    | + 尾部采样错误    |          | + 尾部采样错误    |        |
|                    +-------------------+          +-------------------+        |
|                              |                             |                   |
|                              v                             v                   |
|                    +-------------------+          +-------------------+        |
|                    | 保留所有错误      |          | 保留所有错误      |        |
|                    | 保留延迟>500ms    |          | 保留延迟>1000ms   |        |
|                    +-------------------+          +-------------------+        |
|                                                                                |
+================================================================================+
```

**生产环境推荐配置：**

```yaml
# 生产环境最佳实践：头部+尾部组合采样
processors:
  # 第一步：头部概率采样，减少基础数据量
  probabilistic_sampler:
    sampling_percentage: 10.0
  
  # 第二步：尾部智能采样，确保关键Trace保留
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    expected_new_traces_per_sec: 100
    policies:
      # 优先级1: 始终保留错误
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      
      # 优先级2: 保留慢请求
      - name: slow
        type: latency
        latency:
          threshold_ms: 1000
      
      # 优先级3: 对采样后的数据再进行概率采样
      - name: probabilistic
        type: probabilistic
        probabilistic:
          sampling_percentage: 50

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, probabilistic_sampler, tail_sampling, batch]
      exporters: [otlp]
```

**离线环境适配说明：**

```yaml
# 离线环境资源受限时的采样配置
processors:
  tail_sampling:
    decision_wait: 5s  # 减少等待时间，降低内存占用
    num_traces: 10000  # 减少缓冲数量
    expected_new_traces_per_sec: 50
    policies:
      - name: errors-only
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: very-slow
        type: latency
        latency:
          threshold_ms: 3000  # 只保留非常慢的请求
```

---

## 5. 验证与测试

### 5.1 验证 Trace 采集

```bash
# 发送测试请求生成 Trace
for i in $(seq 1 10); do
  curl -s http://192.168.1.54:31080/api/orders -H "Host: api.demo.local" > /dev/null
done

# 在 Grafana 中查看 Trace
# 1. 打开 Grafana: http://192.168.1.54:32000
# 2. 进入 Explore -> 选择 Tempo 数据源
# 3. 查询: {service.name="api-server"}
# 4. 应能看到 Trace 列表

# 通过 API 查询 Tempo
curl -s "http://192.168.1.54:32000/api/datasources/proxy/uid/tempo/api/search?service=api-server&limit=20" \
  -H "Authorization: Bearer $(kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" | jq .

# 查询具体 Trace
TRACE_ID=$(curl -s "http://192.168.1.54:32000/api/datasources/proxy/uid/tempo/api/search?service=api-server&limit=1" \
  -H "Authorization: Bearer $(kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" | jq -r '.traces[0].traceID')
echo "TraceID: $TRACE_ID"

curl -s "http://192.168.1.54:32000/api/datasources/proxy/uid/tempo/api/traces/$TRACE_ID" \
  -H "Authorization: Bearer $(kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d)" | jq '.batches[0].spans | length'
```

### 5.2 验证 Metrics 采集

```bash
# 查询 OTel Collector 自身指标
kubectl port-forward -n monitoring svc/otel-collector 8889:8889 &
curl -s http://localhost:8889/metrics | grep spanmetrics | head -10

# 查询 Prometheus 中的 spanmetrics
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s "http://localhost:9090/api/v1/query?query=spanmetrics_calls_total" | jq '.data.result[] | {metric: .metric.service_name, value: .value[1]}'

# 查询 JVM 指标
curl -s "http://localhost:9090/api/v1/query?query=jvm_memory_used_bytes{namespace=\"demo\"}" | jq '.data.result[] | {instance: .metric.instance, area: .metric.area, value: .value[1]}'
```

### 5.3 验证 Logs 采集

```bash
# 查询 Loki 日志
curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query_range?query=%7Bnamespace%3D%22demo%22%7D&limit=10&direction=backward&start=$(date -d '5 minutes ago' +%s)000000000&end=$(date +%s)000000000" | jq '.data.result[].values[][1]' | head -20

# 验证日志中包含 TraceID
curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query?query=%7Bnamespace%3D%22demo%22%7D%20%7C%3D%20%22traceId%22&limit=5" | jq '.data.result[].values[][1]' | head -5
```

### 5.4 验证 Trace -> Logs -> Metrics 关联跳转

```
验证步骤：
1. 打开 Grafana Explore，选择 Tempo 数据源
2. 搜索 service.name="api-server" 的 Trace
3. 点击一个 Trace 查看 Span 详情
4. 在 Span 详情中点击 "Linked Logs" 按钮 -> 自动跳转到 Loki 显示该 Span 对应的日志
5. 在 Span 详情中点击 "Linked Metrics" 按钮 -> 自动跳转到 Prometheus 显示该服务的 RED 指标
6. 在 Loki 中搜索包含 traceId 的日志，点击 traceId 链接 -> 自动跳转到 Tempo 显示对应 Trace
7. 验证三个数据源之间的关联跳转均正常工作
```

---

## 5.5 Trace-Log-Metric 三支柱关联

### 5.5.1 统一TraceID贯穿三支柱架构

```
+================================================================================+
|                    三支柱关联架构图                                             |
+================================================================================+
|                                                                                |
|   +-------------------+        +-------------------+        +----------------+ |
|   |   Application     |        |   Application     |        |  Application   | |
|   |   (Service A)     |--------|   (Service B)     |--------|  (Service C)   | |
|   +-------------------+        +-------------------+        +----------------+ |
|            |                            |                            |         |
|            | TraceID: abc123...         | TraceID: abc123...         |         |
|            v                            v                            v         |
|   +======================================================================+     |
|   |                    OpenTelemetry Collector                           |     |
|   |  +-------------+  +-------------+  +-------------+                   |     |
|   |  |  Receiver   |  |  Processor  |  |  Exporter   |                   |     |
|   |  +-------------+  +-------------+  +-------------+                   |     |
|   +======================================================================+     |
|            |                            |                            |         |
|            v                            v                            v         |
|   +-------------------+        +-------------------+        +----------------+ |
|   |     Tempo         |        |   Prometheus      |        |     Loki       | |
|   |   (Traces)        |        |   (Metrics)       |        |   (Logs)       | |
|   |   traceId=abc123  |        |   traceId=abc123  |        | traceId=abc123 | |
|   +-------------------+        +-------------------+        +----------------+ |
|            \                            |                            /          |
|             \                           v                           /           |
|              \                  +-------------------+              /            |
|               \                 |     Grafana       |             /             |
|                \                |  (统一查询面板)    |            /              |
|                 \               +-------------------+           /               |
|                  \                      |                      /                |
|                   +---------------------+----------------------+                |
|                              关联跳转                                          |
|                    Metric -> Trace -> Logs -> Metric                           |
|                                                                                |
+================================================================================+
```

**三支柱关联的核心价值：**

| 关联方向 | 使用场景 | 实现方式 |
|----------|----------|----------|
| Metric → Trace | 从异常指标定位具体请求 | 在Grafana中点击异常数据点跳转 |
| Trace → Log | 从慢请求/错误查看详细日志 | Trace详情中点击Linked Logs |
| Log → Trace | 从错误日志定位调用链路 | 日志中的TraceID链接跳转 |
| Trace → Metric | 查看服务的整体性能趋势 | Trace详情中点击Linked Metrics |

### 5.5.2 日志中注入TraceID

**Spring Boot + Logback 配置：**

```xml
<!-- logback-spring.xml -->
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <!-- 包含TraceID和SpanID -->
            <includeMdcKeyName>trace_id</includeMdcKeyName>
            <includeMdcKeyName>span_id</includeMdcKeyName>
            <includeMdcKeyName>trace_flags</includeMdcKeyName>
        </encoder>
    </appender>
    
    <!-- 或者使用Pattern -->
    <appender name="PATTERN_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] [%X{trace_id:-}/%X{span_id:-}] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>
    
    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
</configuration>
```

**Go应用日志注入TraceID：**

```go
package main

import (
    "context"
    "log"
    
    "go.opentelemetry.io/otel/trace"
)

func logWithTrace(ctx context.Context, msg string) {
    span := trace.SpanFromContext(ctx)
    traceID := span.SpanContext().TraceID().String()
    spanID := span.SpanContext().SpanID().String()
    
    log.Printf("[trace_id=%s span_id=%s] %s", traceID, spanID, msg)
}
```

**Python应用日志注入TraceID：**

```python
import logging
from opentelemetry import trace

class TraceIdFilter(logging.Filter):
    def filter(self, record):
        span = trace.get_current_span()
        span_context = span.get_span_context()
        
        record.trace_id = format(span_context.trace_id, '032x') if span_context.trace_id else '00000000000000000000000000000000'
        record.span_id = format(span_context.span_id, '016x') if span_context.span_id else '0000000000000000'
        return True

# 配置日志
logging.basicConfig(
    format='%(asctime)s [%(trace_id)s/%(span_id)s] %(levelname)s %(name)s - %(message)s'
)
logger = logging.getLogger(__name__)
logger.addFilter(TraceIdFilter())
```

**OTel Java Agent自动注入MDC：**

```yaml
# 无需修改代码，Agent自动将TraceID注入MDC
# 只需配置日志格式即可

# application.yml
logging:
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] [%X{trace_id}/%X{span_id}] %-5level %logger{36} - %msg%n"
```

### 5.5.3 Grafana统一查询面板配置

**Tempo数据源配置（关联Logs和Metrics）：**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-tempo
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  tempo.yaml: |-
    apiVersion: 1
    datasources:
    - name: Tempo
      type: tempo
      access: proxy
      url: http://tempo.monitoring.svc.cluster.local:3100
      uid: tempo
      editable: false
      jsonData:
        httpMethod: GET
        
        # Trace -> Logs 关联配置
        tracesToLogs:
          datasourceUid: loki
          tags: ['k8s.namespace.name', 'k8s.pod.name', 'k8s.container.name']
          mappedTags:
            - tagKey: 'k8s.namespace.name'
              datasourceTagKey: 'namespace'
            - tagKey: 'k8s.pod.name'
              datasourceTagKey: 'pod'
            - tagKey: 'k8s.container.name'
              datasourceTagKey: 'container'
          mapTagToLabel: 'k8s.pod.name'
          spanStartTimeShift: '-30s'
          spanEndTimeShift: '30s'
          filterByTraceID: true
          filterBySpanID: false
        
        # Trace -> Metrics 关联配置
        tracesToMetrics:
          datasourceUid: prometheus
          tags:
            - key: 'k8s.namespace.name'
              value: 'namespace'
            - key: 'k8s.pod.name'
              value: 'pod'
            - key: 'service.name'
              value: 'service'
          queries:
            - name: 'Request Rate'
              query: 'sum(rate(http_server_requests_seconds_count{namespace="$namespace",pod="$pod"}[5m]))'
            - name: 'Error Rate'
              query: 'sum(rate(http_server_requests_seconds_count{namespace="$namespace",pod="$pod",status=~"5.."}[5m]))'
            - name: 'P99 Latency'
              query: 'histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace="$namespace",pod="$pod"}[5m])) by (le))'
        
        # 服务图配置
        serviceMap:
          datasourceUid: prometheus
        
        # 节点图配置
        nodeGraph:
          enabled: true
```

**Loki数据源配置（关联Traces）：**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-loki
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  loki.yaml: |-
    apiVersion: 1
    datasources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki.monitoring.svc.cluster.local:3100
      uid: loki
      editable: false
      jsonData:
        maxLines: 1000
        
        # 从日志中提取TraceID生成跳转链接
        derivedFields:
          # JSON格式日志中的traceId字段
          - name: TraceID
            datasourceUid: tempo
            matcherRegex: '"traceId":"([a-f0-9]+)"'
            url: '$${__value.raw}'
            urlDisplayLabel: 'View Trace'
          
          # 纯文本格式日志中的trace_id
          - name: TraceID
            datasourceUid: tempo
            matcherRegex: 'trace_id=([a-f0-9]+)'
            url: '$${__value.raw}'
            urlDisplayLabel: 'View Trace'
          
          # 方括号格式的trace_id
          - name: TraceID
            datasourceUid: tempo
            matcherRegex: '\[([a-f0-9]{32})/[a-f0-9]{16}\]'
            url: '$${__value.raw}'
            urlDisplayLabel: 'View Trace'
```

**Prometheus数据源配置（关联Traces）：**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources-prometheus
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  prometheus.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus-operated.monitoring.svc.cluster.local:9090
      uid: prometheus
      editable: false
      jsonData:
        httpMethod: POST
        manageAlerts: true
        prometheusType: Prometheus
        
        # Metrics -> Trace 关联配置
        exemplarTraceIdDestinations:
          - name: trace_id
            datasourceUid: tempo
            urlDisplayLabel: 'View Trace'
```

### 5.5.4 从Metric跳转到Trace

**在Grafana中配置Exemplar（示例点）：**

```yaml
# Prometheus配置启用exemplar存储
# prometheus.yml
global:
  external_labels:
    cluster: production

storage:
  tsdb:
    exemplars:
      max_size: 10000000  # 10MB exemplar存储

# 应用代码中记录exemplar（OTel自动完成）
# Exemplar会自动关联到TraceID
```

**Grafana Panel配置Exemplar：**

```json
{
  "targets": [
    {
      "expr": "histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace=\"demo\"}[5m])) by (le))",
      "legendFormat": "P99 Latency",
      "exemplar": true
    }
  ],
  "fieldConfig": {
    "defaults": {
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "linear",
        "showPoints": "auto"
      },
      "links": [
        {
          "title": "View Trace",
          "url": "",
          "internal": {
            "query": {
              "query": "${__value.raw}",
              "queryType": "traceId"
            },
            "datasourceUid": "tempo"
          }
        }
      ]
    }
  }
}
```

### 5.5.5 从Trace查看日志

**Trace详情中的日志关联：**

```
+================================================================================+
|  Trace: abc123...                                                              |
|  Duration: 1.23s  |  Spans: 15  |  Services: 3                                |
+================================================================================+
|                                                                                |
|  [Span] api-gateway: GET /api/orders  |  Duration: 1.23s  |  Status: OK       |
|  |                                                                             |
|  +-- [Span] user-service: GET /users/123  |  Duration: 0.5s  |  Status: OK     |
|  |                                                                             |
|  +-- [Span] order-service: POST /orders  |  Duration: 0.8s  |  Status: OK      |
|      |                                                                         |
|      +-- [Span] mysql: SELECT * FROM orders  |  Duration: 0.3s                |
|                                                                                |
|  +------------------+  +------------------+  +------------------+             |
|  | Linked Logs      |  | Linked Metrics   |  | Service Map      |             |
|  | (查看相关日志)    |  | (查看性能指标)    |  | (服务拓扑)       |             |
|  +------------------+  +------------------+  +------------------+             |
|                                                                                |
+================================================================================+
```

**点击Linked Logs后的Loki查询：**

```logql
# 自动生成的Loki查询
{namespace="demo", pod=~"api-gateway-.*"} 
  | json
  | traceId="abc123def456789"
  | timestamp >= "2024-01-15T10:30:00Z"
  | timestamp <= "2024-01-15T10:32:00Z"
```

### 5.5.6 统一Dashboard示例

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-correlation
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  correlation.json: |-
    {
      "dashboard": {
        "title": "三支柱关联分析面板",
        "uid": "correlation-dashboard",
        "panels": [
          {
            "title": "RED指标概览",
            "type": "timeseries",
            "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
            "targets": [
              {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": "sum(rate(http_server_requests_seconds_count{namespace=\"demo\"}[5m])) by (service)",
                "legendFormat": "{{service}} - QPS",
                "exemplar": true
              }
            ]
          },
          {
            "title": "错误日志",
            "type": "logs",
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
            "targets": [
              {
                "datasource": {"type": "loki", "uid": "loki"},
                "expr": "{namespace=\"demo\"} |= \"ERROR\" | json",
                "refId": "A"
              }
            ]
          },
          {
            "title": "最近Trace",
            "type": "traces",
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
            "targets": [
              {
                "datasource": {"type": "tempo", "uid": "tempo"},
                "query": "{service.name=\"api-server\"}",
                "queryType": "traceql",
                "refId": "A"
              }
            ]
          }
        ],
        "templating": {
          "list": [
            {
              "name": "namespace",
              "type": "custom",
              "query": "demo,production,staging",
              "current": {"text": "demo", "value": "demo"}
            },
            {
              "name": "service",
              "type": "query",
              "query": "label_values(http_server_requests_seconds_count, service)",
              "datasource": {"type": "prometheus", "uid": "prometheus"}
            }
          ]
        }
      }
    }
```

**离线环境适配说明：**

```yaml
# 离线环境三支柱关联配置要点

# 1. 确保所有组件使用内部DNS名称通信
# tempo.monitoring.svc.cluster.local
# loki.monitoring.svc.cluster.local
# prometheus-operated.monitoring.svc.cluster.local

# 2. 如果资源受限，可以关闭部分关联功能
jsonData:
  tracesToLogs:
    enabled: true
    # 减少查询时间范围
    spanStartTimeShift: '-10s'
    spanEndTimeShift: '10s'
  
  tracesToMetrics:
    enabled: true
    # 只保留关键查询
    queries:
      - name: 'Error Rate'
        query: 'sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))'

# 3. 日志格式统一使用JSON，便于提取TraceID
# 避免复杂的正则匹配
```

---

## 6. CKA/CKS 考点融入

### 6.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Resource Monitoring | kubectl top pods/nodes、Metrics Server | 3.1 节 |
| Resource Quotas | LimitRange、ResourceQuota | 3.5 节 |
| Debugging | kubectl logs、kubectl describe、事件查看 | 5.x 节 |
| ConfigMap/Secret | 配置管理、敏感信息 | 3.7 节 |

### 6.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Audit Logging | API Server 审计日志 | 3.3 节 |
| Network Policies | 日志采集网络策略 | 3.3 节 |
| Secret 管理 | Grafana 密码、数据源凭证 | 3.7 节 |
| Supply Chain Security | 镜像安全、OTel Agent 来源验证 | 3.6 节 |
| RBAC | ServiceAccount 权限最小化 | 3.5 节 |

### 6.3 CKS 新增考点详解

#### 6.3.1 日志审计与追踪

**CKS考点要求：**
- 配置 Kubernetes API Server 审计日志
- 理解审计策略（Audit Policy）
- 实现审计日志与可观测性系统的集成

**API Server 审计日志配置：**

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # 记录所有请求（元数据级别）
  - level: Metadata
    omitStages:
      - RequestReceived
  
  # 记录对 Secrets、ConfigMaps 的修改（RequestResponse级别）
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets", "configmaps"]
    verbs: ["create", "update", "patch", "delete"]
  
  # 记录对 Pod 的创建（包含请求体）
  - level: Request
    resources:
      - group: ""
        resources: ["pods"]
    verbs: ["create"]
  
  # 记录对 RBAC 的修改
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["create", "update", "patch", "delete"]
  
  # 忽略健康检查和监控端点
  - level: None
    nonResourceURLs:
      - /healthz*
      - /version
      - /swagger*
```

```yaml
# kube-apiserver 启动参数配置
# /etc/kubernetes/manifests/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
  namespace: kube-system
spec:
  containers:
  - name: kube-apiserver
    command:
    - kube-apiserver
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
    - --audit-log-format=json
    volumeMounts:
    - name: audit-policy
      mountPath: /etc/kubernetes/audit-policy.yaml
      readOnly: true
    - name: audit-log
      mountPath: /var/log/kubernetes/audit
  volumes:
  - name: audit-policy
    hostPath:
      path: /etc/kubernetes/audit-policy.yaml
      type: File
  - name: audit-log
    hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
```

**审计日志与 Loki 集成：**

```yaml
# Promtail 配置采集审计日志
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
  namespace: monitoring
data:
  promtail.yaml: |
    server:
      http_listen_port: 9080
      grpc_listen_port: 0
    
    positions:
      filename: /tmp/positions.yaml
    
    clients:
      - url: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
    
    scrape_configs:
      # 采集 Kubernetes 审计日志
      - job_name: kubernetes-audit
        static_configs:
          - targets:
              - localhost
            labels:
              job: kubernetes-audit
              __path__: /var/log/kubernetes/audit/*.log
        pipeline_stages:
          - json:
              expressions:
                timestamp: requestReceivedTimestamp
                level: level
                verb: verb
                user: user.username
                resource: objectRef.resource
                namespace: objectRef.namespace
                name: objectRef.name
                response_code: responseStatus.code
          - timestamp:
              source: timestamp
              format: RFC3339Nano
          - labels:
              level:
              verb:
              resource:
              namespace:
              response_code:
```

**审计日志分析查询（LogQL）：**

```logql
# 查询所有对 Secrets 的访问
{job="kubernetes-audit", resource="secrets"}

# 查询失败的认证尝试
{job="kubernetes-audit", response_code=~"4..|5.."}

# 查询特权操作（删除、修改 RBAC）
{job="kubernetes-audit", verb=~"delete|update|patch", resource=~"roles|rolebindings|clusterroles|clusterrolebindings"}

# 查询特定用户的操作
{job="kubernetes-audit", user="admin@example.com"}

# 统计各资源类型的操作频率
sum by (resource, verb) (count_over_time({job="kubernetes-audit"}[1h]))
```

**CKS考试重点：**

| 审计级别 | 记录内容 | 使用场景 |
|----------|----------|----------|
| `None` | 不记录 | 健康检查、高频只读操作 |
| `Metadata` | 请求元数据（用户、时间、资源、动词） | 常规监控 |
| `Request` | 元数据 + 请求体 | 需要审查请求内容的场景 |
| `RequestResponse` | 元数据 + 请求体 + 响应体 | 安全审计、合规要求 |

---

#### 6.3.2 安全上下文与可观测性

**CKS考点要求：**
- 配置 Pod 安全上下文（Security Context）
- 理解可观测性组件的安全运行要求
- 实现最小权限原则

**Collector 安全上下文配置：**

```yaml
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  mode: deployment
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    fsGroup: 65532
    seccompProfile:
      type: RuntimeDefault
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
  config: |
    # Collector 配置
```

**Promtail 安全上下文配置：**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: promtail
  namespace: monitoring
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 0  # 需要 root 权限读取容器日志
      containers:
      - name: promtail
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
```

**Grafana 安全上下文配置：**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 472
        runAsGroup: 472
        fsGroup: 472
      containers:
      - name: grafana
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        volumeMounts:
        - name: grafana-storage
          mountPath: /var/lib/grafana
```

**NetworkPolicy 限制可观测性组件访问：**

```yaml
# 限制 Collector 只能被特定命名空间访问
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: otel-collector-network-policy
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: otel-collector
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # 只允许来自应用命名空间的 OTLP 流量
  - from:
    - namespaceSelector:
        matchLabels:
          name: demo
    - namespaceSelector:
        matchLabels:
          name: production
    ports:
    - protocol: TCP
      port: 4317
    - protocol: TCP
      port: 4318
  # 允许来自 monitoring 命名空间的指标抓取
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8889
  egress:
  # 只允许访问 Tempo、Loki、Prometheus
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: tempo
    ports:
    - protocol: TCP
      port: 4317
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: loki
    ports:
    - protocol: TCP
      port: 3100
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - protocol: TCP
      port: 9090
  # DNS 查询
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
```

**Pod Security Standards 合规：**

```yaml
# 为 monitoring 命名空间应用 Restricted 策略
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**CKS考试重点检查清单：**

```yaml
# Pod 安全上下文检查清单
securityContext:
  # 1. 以非 root 用户运行
  runAsNonRoot: true
  runAsUser: <非0用户>
  
  # 2. 禁止特权提升
  allowPrivilegeEscalation: false
  
  # 3. 只读根文件系统
  readOnlyRootFilesystem: true
  
  # 4. 丢弃所有 capabilities
  capabilities:
    drop:
      - ALL
  
  # 5. 使用 Seccomp 默认配置
  seccompProfile:
    type: RuntimeDefault
  
  # 6. 限制权限组
  runAsGroup: <用户组>
  fsGroup: <文件组>
```

**可观测性数据安全最佳实践：**

| 安全领域 | 措施 | 实现方式 |
|----------|------|----------|
| 传输加密 | mTLS | Collector 与后端之间启用 TLS |
| 数据脱敏 | 过滤敏感字段 | 使用 attributes processor 删除敏感信息 |
| 访问控制 | RBAC | Grafana 数据源权限控制 |
| 审计追踪 | 审计日志 | 记录所有可观测性数据访问 |
| 密钥管理 | Secret 加密 | 使用 Sealed Secrets 或 External Secrets |
| 网络隔离 | NetworkPolicy | 限制组件间通信 |

**敏感数据过滤配置：**

```yaml
processors:
  # 删除敏感属性
  attributes/redact-sensitive:
    actions:
      - key: http.request.body
        action: delete
      - key: http.response.body
        action: delete
      - key: db.statement
        action: delete
      - key: password
        action: delete
      - key: token
        action: delete
      - key: authorization
        action: delete
      - key: cookie
        action: delete
  
  # 哈希化用户ID（保留关联性但脱敏）
  attributes/hash-userid:
    actions:
      - key: user.id
        action: hash
      - key: user.email
        action: hash
```

---

## 6.5 可观测性成本估算与优化

### 6.5.1 Trace数据量计算公式

**Trace数据量估算模型：**

```
+================================================================================+
|                        Trace数据量计算公式                                      |
+================================================================================+
|                                                                                |
|  每日Trace数据量(GB) = 请求量 × 平均Span数 × 平均Span大小 × 采样率 × 时间(天)  |
|                                                                                |
|  参数说明：                                                                     |
|  ───────────────────────────────────────────────────────────────────────────── |
|  请求量(QPS)     = 每秒请求数 × 86400秒                                        |
|  平均Span数      = 单个Trace包含的Span数量（微服务数量+数据库调用+缓存调用）     |
|  平均Span大小    = 单个Span的字节数（通常 1-5KB，含属性、事件、标签）           |
|  采样率          = 实际采集比例（0.01-1.0）                                    |
|                                                                                |
+================================================================================+
```

**计算示例：**

| 场景 | QPS | 平均Span数 | Span大小 | 采样率 | 日数据量 | 月数据量 |
|------|-----|-----------|----------|--------|---------|---------|
| 小型服务 | 100 | 5 | 2KB | 10% | 8.6 GB | 258 GB |
| 中型服务 | 1000 | 10 | 3KB | 10% | 259 GB | 7.8 TB |
| 大型服务 | 10000 | 15 | 4KB | 5% | 2.6 TB | 78 TB |
| 超大规模 | 100000 | 20 | 5KB | 1% | 8.6 TB | 258 TB |

**详细计算过程（中型服务）：**

```
日请求量 = 1000 QPS × 86400 秒 = 86,400,000 请求/天
日Span数 = 86,400,000 × 10 = 864,000,000 Span/天
采样后Span数 = 864,000,000 × 10% = 86,400,000 Span/天
日数据量 = 86,400,000 × 3KB = 259,200,000 KB ≈ 259 GB/天
月数据量 = 259 GB × 30 = 7,770 GB ≈ 7.8 TB/月
```

### 6.5.2 存储成本估算表

**各组件存储成本对比：**

| 组件 | 存储类型 | 单位成本 | 压缩比 | 备注 |
|------|----------|----------|--------|------|
| Tempo | 对象存储 | $0.023/GB/月 | 5:1 | S3标准存储 |
| Tempo | 本地SSD | $0.10/GB/月 | 5:1 | 高性能查询 |
| Prometheus | 本地磁盘 | $0.10/GB/月 | 3:1 | TSDB格式 |
| Loki | 对象存储 | $0.023/GB/月 | 10:1 | 仅索引标签 |
| Elasticsearch | 本地SSD | $0.15/GB/月 | 1.5:1 | 全文索引 |

**月度成本估算（1000 QPS场景）：**

| 组件 | 原始数据量 | 压缩后 | 存储成本 | 查询成本 | 总成本 |
|------|-----------|--------|---------|---------|--------|
| Tempo (S3) | 7.8 TB | 1.56 TB | $36 | $20 | $56 |
| Prometheus | 500 GB | 167 GB | $17 | - | $17 |
| Loki (S3) | 2 TB | 200 GB | $5 | $10 | $15 |
| **合计** | - | - | **$58** | **$30** | **$88** |

**不同规模集群成本估算：**

| 集群规模 | Pods数量 | 日Trace数据 | 日日志数据 | 月存储成本 | 月计算成本 | 总计 |
|----------|----------|------------|-----------|-----------|-----------|------|
| 小型 | <50 | 50 GB | 100 GB | $15 | $50 | $65 |
| 中型 | 50-200 | 259 GB | 500 GB | $45 | $200 | $245 |
| 大型 | 200-500 | 1 TB | 2 TB | $150 | $500 | $650 |
| 超大型 | 500+ | 5 TB | 10 TB | $600 | $2000 | $2600 |

### 6.5.3 采样策略对成本的影响

**采样率与成本关系：**

```
+================================================================================+
|                    采样率 vs 成本曲线                                          |
+================================================================================+
|                                                                                |
|  成本($)                                                                        |
|    ^                                                                           |
| 3000|                                          xxxxx                           |
|     |                                     xxxx     xxx                         |
| 2000|                                xxxx             xx                       |
|     |                           xxxx                    x                      |
| 1000|                      xxxx                          x                     |
|     |                 xxxx                                x                    |
|  500|            xxxx                                      x                   |
|     |       xxxx                                            x                  |
|  100|  xxxx                                                  x                 |
|     |________________________________________________________x______________>  |
|       0%  10%  20%  30%  40%  50%  60%  70%  80%  90%  100%  采样率            |
|                                                                                |
|  推荐区域: [1%]----[10%]==================                                     |
|                                                                                |
+================================================================================+
```

**采样优化效果对比（1000 QPS场景）：**

| 采样策略 | 采样率 | 日数据量 | 月存储成本 | 成本节省 |
|----------|--------|---------|-----------|---------|
| 无采样 | 100% | 2590 GB | $600 | - |
| 头部采样 | 10% | 259 GB | $60 | 90% |
| 头部+尾部 | 10%头部+错误100% | 280 GB | $65 | 89% |
| 智能采样 | 5%头部+慢请求+错误 | 150 GB | $35 | 94% |

**采样策略ROI分析：**

```
采样策略实施成本：
- Collector内存增加：约 20%（尾部采样缓冲）
- CPU开销增加：约 10%（采样决策计算）
- 开发成本：低（配置调整）

采样策略收益：
- 存储成本降低：80-95%
- 网络带宽降低：80-95%
- 查询性能提升：指数级（数据量减少）

ROI = (节省成本 - 额外成本) / 额外成本 × 100%
    = ($500 - $50) / $50 × 100% = 900%
```

### 6.5.4 数据保留分层策略

**热/温/冷分层架构：**

```
+================================================================================+
|                    数据保留分层架构                                             |
+================================================================================+
|                                                                                |
|   +-------------------+  +-------------------+  +-------------------+         |
|   |     热数据层       |  |     温数据层       |  |     冷数据层       |         |
|   |   (Hot Tier)      |  |   (Warm Tier)      |  |   (Cold Tier)      |         |
|   +-------------------+  +-------------------+  +-------------------+         |
|   | 保留期: 1-3天     |  | 保留期: 7-30天    |  | 保留期: 30天-1年  |         |
|   | 存储: SSD/本地    |  | 存储: 标准磁盘    |  | 存储: 对象存储    |         |
|   | 查询延迟: <100ms  |  | 查询延迟: <1s     |  | 查询延迟: 5-30s   |         |
|   | 成本: 高          |  | 成本: 中          |  | 成本: 极低        |         |
|   +-------------------+  +-------------------+  +-------------------+         |
|          |                       |                       |                    |
|          v                       v                       v                    |
|   +---------------------------------------------------------------+         |
|   |                        Grafana查询路由                         |         |
|   |  自动根据时间范围选择数据源：近3天->热层，3-30天->温层，>30天->冷层  |         |
|   +---------------------------------------------------------------+         |
|                                                                                |
+================================================================================+
```

**Tempo分层存储配置：**

```yaml
# tempo.yaml - 分层存储配置
storage:
  trace:
    backend: s3  # 主存储使用对象存储
    s3:
      bucket: tempo-traces
      endpoint: minio.monitoring.svc.cluster.local:9000
      insecure: true
    
    # 本地缓存（热数据层）
    local:
      path: /var/tempo/traces
    
    # WAL配置
    wal:
      path: /var/tempo/wal
      
# 保留策略
compactor:
  compaction:
    block_retention: 168h  # 7天保留
    compacted_block_retention: 336h  # 14天压缩后保留

# 查询前端缓存
query_frontend:
  cache:
    memcached:
      addresses: memcached.monitoring.svc.cluster.local:11211
```

**Loki分层存储配置：**

```yaml
# loki.yaml - 分层存储配置
schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  # 热数据（最近24小时）
  filesystem:
    directory: /var/loki/chunks
  
  # 冷数据（超过24小时）
  aws:
    s3: s3://loki-chunks/
    s3forcepathstyle: true
    endpoint: minio.monitoring.svc.cluster.local:9000
    insecure: true

# 保留配置
table_manager:
  retention_deletes_enabled: true
  retention_period: 720h  # 30天保留

# 分层查询
query_range:
  cache_results: true
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100
```

**Prometheus分层存储（Thanos）：**

```yaml
# thanos-sidecar配置
# 本地保留2小时，其余上传到对象存储

# thanos-store-gateway配置
# 对象存储中的历史数据查询

# thanos-compactor配置
# 数据压缩和降采样
compactor:
  retentionResolutionRaw: 30d      # 原始数据保留30天
  retentionResolution5m: 120d      # 5分钟降采样保留120天
  retentionResolution1h: 1y        # 1小时降采样保留1年
```

**分层策略成本对比：**

| 策略 | 热层(1-3天) | 温层(7-30天) | 冷层(30天+) | 月成本 |
|------|------------|-------------|------------|--------|
| 全热存储 | 100% | - | - | $1000 |
| 热+温 | 20% | 80% | - | $400 |
| 热+温+冷 | 10% | 30% | 60% | $150 |
| 仅冷存储 | - | - | 100% | $50 |

**离线环境分层配置建议：**

```yaml
# 离线环境资源受限时的简化分层

# Tempo配置
storage:
  trace:
    backend: local
    local:
      path: /data/tempo

compactor:
  compaction:
    block_retention: 72h  # 仅保留3天（热层）

# Loki配置
storage_config:
  filesystem:
    directory: /data/loki

table_manager:
  retention_period: 168h  # 仅保留7天

# Prometheus配置
prometheus:
  prometheusSpec:
    retention: 7d  # 本地保留7天
    retentionSize: "50GB"  # 或按大小限制
```

**成本优化检查清单：**

| 检查项 | 优化前 | 优化后 | 节省比例 |
|--------|--------|--------|---------|
| 启用采样 | 100% | 10% | 90% |
| 分层存储 | 全热存储 | 热+温+冷 | 85% |
| 数据压缩 | 无压缩 | 启用压缩 | 70% |
| 日志过滤 | 全量采集 | 过滤健康检查 | 20% |
| 指标降采样 | 原始数据 | 1h降采样 | 95% |
| 定期清理 | 永久保留 | 30天保留 | 可变 |

---

## 7. 高频面试题

### Q1: OpenTelemetry 的三大信号是什么？它们之间有什么关系？（难度：简单）

**答案：** OpenTelemetry 的三大信号是 **Traces（分布式追踪）**、**Metrics（指标）** 和 **Logs（日志）**。Traces 记录请求在分布式系统中的传播路径和每个操作的耗时，回答"请求经过了哪些服务，每一步花了多少时间"；Metrics 记录系统状态的时间序列数据（如 QPS、错误率、延迟），回答"系统当前状态如何"；Logs 记录离散的事件和错误详情，回答"具体发生了什么问题"。三者之间的关系：Trace 是骨架，提供请求的完整链路视图；Metrics 是脉搏，提供系统健康状态的实时监控；Logs 是细节，提供问题排查的上下文信息。通过 TraceID 可以将三者关联起来：从 Trace 中的某个 Span 跳转到对应的日志条目和指标数据，实现从宏观到微观的问题定位。OTel Collector 的 Connector（如 spanmetrics）还能自动从 Trace 中提取 Metrics，实现信号间的自动转换。

### Q2: OTel Collector 的 Pipeline 是什么？有哪些核心组件？（难度：中等）

**答案：** OTel Collector 的 Pipeline 定义了遥测数据从接收到导出的完整处理流程，公式为 Pipeline = Receiver(s) -> Processor(s) -> Exporter(s)。**Receiver** 负责接收数据，支持多种协议（OTLP gRPC/HTTP、Jaeger、Zipkin、Prometheus），每个 Receiver 可以监听不同端口接收不同格式的数据。**Processor** 负责数据处理，常用 Processor 包括：batch（批量发送减少网络开销）、memory_limiter（内存限制防 OOM）、k8sattributes（自动添加 K8s 元数据）、filter（过滤不需要的数据）、tail_sampling（尾部采样策略）。**Exporter** 负责导出数据到后端系统（Tempo、Prometheus、Loki、Elasticsearch）。**Connector** 是特殊组件，可以在不同信号类型间转发数据（如 spanmetrics 将 Trace 转为 Metrics）。一个 Collector 可以配置多个 Pipeline，每种信号类型（traces/metrics/logs）有独立的 Pipeline。

### Q3: 什么是尾部采样（Tail Sampling）？与头部采样有什么区别？（难度：困难）

**答案：** 采样是减少 Trace 数据量的关键策略。**头部采样（Head Sampling）** 在 Trace 开始时就决定是否采集，通常基于概率（如 10% 采样率），优点是实现简单、资源消耗低，缺点是无法保证采集到有价值的 Trace（如错误 Trace 可能被丢弃）。**尾部采样（Tail Sampling）** 等待 Trace 完成后根据完整信息决定是否保留，可以基于多种策略：status_code（保留错误 Trace）、latency（保留慢请求）、string_attribute（保留特定属性的 Trace）、and/or 组合策略。尾部采样的优势是能确保所有错误和慢请求都被保留，缺点是需要内存缓冲完整 Trace（memory_limiter 配置），增加了 Collector 的资源消耗。生产环境推荐组合使用：先设置较低的头部采样率（如 10%）减少数据量，再通过尾部采样保留所有错误和慢请求 Trace。

### Q4: 如何实现 Trace 到 Logs 的关联？（难度：中等）

**答案：** Trace 到 Logs 的关联核心是通过 TraceID 将两者串联。实现步骤：1）应用日志框架需要将当前 Span 的 TraceID 写入日志中，OTel Java Agent 会自动将 TraceID 注入到 MDC（Mapped Diagnostic Context），日志框架（如 Logback）通过 pattern 配置输出 TraceID；2）Loki 收集到日志后，通过 derivedFields 配置从日志中提取 TraceID 并生成跳转链接；3）Grafana 中配置 Tempo 数据源的 tracesToLogs，指定关联的 Loki 数据源和匹配标签（如 k8s.namespace.name、k8s.pod.name）。当用户在 Tempo 中查看某个 Span 时，点击 "Linked Logs" 按钮会自动跳转到 Loki 并过滤出对应 Pod 和时间范围的日志。关键配置是 Grafana Tempo 数据源中的 `tracesToLogs.datasourceId` 和 `tracesToLogs.tags`，确保 Trace 和 Log 的标签能够匹配。

### Q5: Prometheus 和 Loki 的存储引擎有什么区别？（难度：困难）

**答案：** Prometheus 使用 **TSDB（Time Series Database）** 存储引擎，数据模型是时间序列（metric name + labels + timestamp + value），采用追加写入（append-only）模式，通过倒排索引加速标签查询，适合存储数值型指标数据。Prometheus 的查询语言 PromQL 专门针对时间序列计算设计（rate、histogram_quantile 等）。Loki 使用 **Label Index + Chunk Store** 存储引擎，只对标签建立索引，不对日志正文建立索引。查询时先通过标签过滤缩小范围，再对日志正文进行暴力搜索（grep 模式）。这种设计使得 Loki 的存储成本远低于 Elasticsearch（通常为 ES 的 1/5 到 1/10），但全文检索性能不如 ES。Loki 2.0+ 引入了 TSDB 存储模式，将标签索引存储在 TSDB 中，进一步提升了查询性能。选择建议：需要全文检索用 ES，K8s 原生场景优先用 Loki。

### Q6: OTel Java Agent 的自动埋点原理是什么？（难度：困难）

**答案：** OTel Java Agent 基于 Java Instrumentation API（java.lang.instrument）实现字节码增强（Bytecode Instrumentation）。启动时通过 -javaagent 参数加载 Agent JAR，Agent 在类加载阶段拦截目标类的字节码，注入遥测数据采集代码。具体过程：1）Agent 注册 ClassFileTransformer，监听类加载事件；2）当目标类（如 Spring MVC 的 DispatcherServlet、JDBC 的 Statement）被加载时，Transformer 修改字节码，在方法入口和出口插入 Span 创建、属性设置、Span 关闭等代码；3）Agent 内置了数百个 Instrumentation Library，覆盖常见的框架和库（Spring Web、Spring Cloud、gRPC、JDBC、Redis、Kafka、HTTP Client 等）；4）上下文传播通过 ThreadLocal 和 Context Propagation API 实现，确保 TraceID 在线程间、服务间正确传递。自动埋点的优势是无需修改业务代码，劣势是 Agent JAR 体积较大（约 30-50MB），启动时会增加 2-5 秒的类加载时间。

### Q7: 如何优化 OTel Collector 的性能？（难度：中等）

**答案：** OTel Collector 性能优化的关键点：1）**批处理**：配置 batch processor 的 timeout（5s）和 send_batch_size（1024），减少网络请求次数；2）**内存限制**：配置 memory_limiter 防止 OOM，建议 limit 设为容器内存限制的 80%；3）**尾部采样**：使用 tail_sampling 替代全局采样，只保留有价值的 Trace，减少后端存储压力；4）**过滤健康检查**：使用 filter processor 过滤健康检查、metrics 端点等无价值 Trace；5）**并发**：Collector 的 sending_queue 配置 enabled=true 和 num_consumers 增加并发导出；6）**gRPC 优化**：使用 OTLP gRPC 协议替代 HTTP，性能更好；7）**水平扩展**：使用 Deployment 模式部署多副本 Collector，通过 Service 负载均衡；8）**资源分配**：建议 Collector 的 memory limit 至少 1Gi，CPU limit 至少 1 核。监控 Collector 自身的指标（otelcol_processor_*）来评估性能瓶颈。

### Q8: Grafana Stack 和 ELK Stack 如何选择？（难度：中等）

**答案：** 选择取决于业务场景和团队能力。**Grafana Stack 适合**：K8s 原生环境、资源有限（Loki 内存消耗约为 ES 的 1/5）、需要 Trace/Metrics/Logs 统一面板、团队熟悉 Prometheus 生态、中小规模集群（<500 Pods）。**ELK Stack 适合**：日志密集型业务（如安全审计、合规场景）、需要强大的全文检索和聚合分析、团队已有 ELK 运维经验、非 K8s 环境。**混合架构适合**：大规模集群（500+ Pods）、既需要 Trace 关联又需要全文检索、有充足的硬件资源。关键决策因素：如果主要需求是监控 K8s 上的微服务，Grafana Stack 是首选；如果主要需求是日志分析和全文检索，ELK 更合适。实际生产中，混合架构越来越流行，用 Tempo 做 Trace、Prometheus 做 Metrics、ES 做日志深度分析，Grafana 做统一面板。

### Q9: 什么是 RED 方法和 USE 方法？（难度：简单）

**答案：** RED 和 USE 是两种服务监控方法论。**RED 方法**（Rate、Errors、Duration）适用于服务层面监控：Rate（请求速率）衡量服务负载，通常用 QPS 表示；Errors（错误率）衡量服务质量，通常用 5xx 百分比表示；Duration（延迟）衡量服务性能，通常用 P50/P90/P99 表示。RED 方法源自 Google 的 "Four Golden Signals"（延迟、流量、错误、饱和度）。**USE 方法**（Utilization、Saturation、Errors）适用于资源层面监控：Utilization（使用率）资源使用百分比；Saturation（饱和度）资源排队或等待的程度（如 CPU run queue length、TCP 连接队列）；Errors（错误数）资源相关的错误计数。最佳实践：对服务使用 RED 方法，对基础设施（CPU、内存、磁盘、网络）使用 USE 方法，两者互补形成完整的监控体系。

### Q10: 如何实现可观测性的 SLI/SLO？（难度：困难）

**答案：** SLI（Service Level Indicator）是衡量服务质量的具体指标，SLO（Service Level Objective）是基于 SLI 设定的目标值。实现步骤：1）定义 SLI：常用 SLI 包括可用性（成功请求比例 = 成功请求数/总请求数）、延迟（P99 < 500ms 的请求比例）、正确性（无错误返回的请求比例）；2）设定 SLO：如"API 可用性 >= 99.9%"、"P99 延迟 < 500ms"；3）基于 OTel 数据实现：通过 spanmetrics 自动生成 RED 指标，在 Prometheus 中定义 SLI 查询（如 `sum(rate(http_server_requests_seconds_count{status!~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count[5m]))`）；4）创建 Grafana Dashboard 展示 SLI/SLO 达标情况；5）配置告警：SLO burn rate 超过阈值时触发告警（如 1 小时内消耗了超过 5% 的错误预算）；6）定期回顾和调整 SLO。错误预算 = 1 - SLO，如 99.9% 可用性意味着每月允许 43 分钟的停机时间。

### Q11: OTel 的上下文传播（Context Propagation）是如何工作的？（难度：困难）

**答案：** 上下文传播是分布式追踪的核心机制，确保 TraceID 在服务间调用链中正确传递。OTel 支持多种传播格式：**W3C Trace Context**（标准格式，推荐使用）：通过 `traceparent` Header 传递 TraceID、SpanID 和采样标志（格式：`00-<traceid>-<spanid>-<flags>`），通过 `tracestate` Header 传递供应商特定的上下文；**B3**（Zipkin 格式）：通过 `X-B3-TraceId`、`X-B3-SpanId`、`X-B3-ParentSpanId` 等 Header 传递；**Baggage**：通过 `baggage` Header 传递业务级别的键值对。传播过程：1）客户端发起请求时，OTel SDK 从当前 Context 中提取 TraceID 和 SpanID，注入到 HTTP Header 中；2）服务端接收请求时，OTel SDK 从 Header 中提取上下文，创建子 Span；3）服务端继续向下游传播上下文。Java Agent 自动处理常见 HTTP 客户端和服务端的上下文传播，无需手动配置。

### Q12: 如何监控 OTel Collector 自身的健康状态？（难度：中等）

**答案：** OTel Collector 内置了丰富的自身指标，关键指标包括：`otelcol_processor_accepted_spans`（Processor 接收的 Span 数量）、`otelcol_processor_refused_spans`（Processor 拒绝的 Span 数量，非零表示有问题）、`otelcol_processor_dropped_spans`（Processor 丢弃的 Span 数量）、`otelcol_exporter_send_failed_spans`（Exporter 发送失败的 Span 数量）、`otelcol_receiver_accepted_spans`（Receiver 接收的 Span 数量）、`otelcol_receiver_refused_spans`（Receiver 拒绝的 Span 数量）。监控建议：1）在 Prometheus 中配置 Collector 的 ServiceMonitor 或 PodMonitor；2）创建 Grafana Dashboard 展示 Collector 的吞吐量、延迟、错误率；3）配置告警规则：`otelcol_processor_dropped_spans > 0`（数据丢失）、`otelcol_exporter_send_failed_spans rate > 0`（导出失败）、Collector Pod 重启。 Collector 还支持健康检查端点（`--health-check`）和 pprof 端点用于性能分析。

### Q13: 在高并发场景下如何处理 Trace 数据暴增？（难度：困难）

**答案：** 高并发场景下 Trace 数据量可能非常大，需要多层面优化：1）**采样策略**：头部采样设置合理比例（如 1%-10%），尾部采样只保留错误和慢请求；2）**过滤无价值 Trace**：使用 filter processor 过滤健康检查、Prometheus metrics 抓取、K8s 探针等产生的 Trace；3）**Span 层面优化**：配置 spanmetrics connector 从 Trace 中提取 RED 指标后，可以降低 Trace 采样率，因为 Metrics 已经覆盖了监控需求；4）**Collector 扩展**：使用 Gateway 模式部署 Collector，前端 Collector 接收数据并做预处理，后端 Collector 负责导出；5）**后端优化**：Tempo 配置合理的 retention（如 7 天）、使用对象存储（S3/MinIO）替代本地存储、启用 compaction 压缩；6）**自适应采样**：OTel 支持自适应采样（Adaptive Sampling），根据流量自动调整采样率，在低流量时提高采样率，高流量时降低采样率。目标是平衡可观测性和成本。

### Q14: 如何实现跨语言服务的 Trace 关联？（难度：中等）

**答案：** 跨语言 Trace 关联依赖统一的上下文传播协议。关键步骤：1）所有服务使用相同的传播格式（推荐 W3C Trace Context），确保 TraceID 格式一致；2）所有服务将 OTel 数据发送到同一个 Collector（或 Collector 集群），确保数据汇聚到同一后端；3）服务名称命名规范统一（如 `service.namespace/service.name`），便于在 Grafana 中过滤和聚合；4）HTTP Header 透传：如果使用了 API Gateway 或 Ingress Controller，确保它们透传 Trace Header（Nginx 需要配置 `proxy_set_header traceparent $http_traceparent`）；5）消息队列场景：Kafka/RabbitMQ 消息需要将 TraceContext 注入到消息 Header 中，消费者从 Header 中提取上下文。OTel 提供了各语言的 SDK 和 Agent，只要正确配置，跨语言 Trace 关联是自动的。Java 使用 Agent，Go/Python 使用 SDK，Node.js 使用 SDK。

### Q15: Loki 的标签（Label）设计有什么最佳实践？（难度：中等）

**答案：** Loki 的性能高度依赖标签设计，因为 Loki 只对标签建立索引。**最佳实践**：1）标签基数（Cardinality）控制：低基数标签（如 namespace、app、container）适合作为标签，高基数标签（如 user_id、request_id、trace_id）不应作为标签，应放在日志正文中通过全文搜索查询；2）推荐标签集：`{namespace="demo", app="api-server", container="api-server", pod="api-server-xxx"}`，通常 5-10 个标签足够；3）避免动态标签：不要将可能无限增长的值作为标签（如 IP 地址、UUID）；4）使用 Pipeline Stage：在 Promtail 中使用 json/pipeline/regex stage 从日志中提取结构化字段，这些字段不需要作为标签；5）日志格式统一：使用 JSON 格式日志，便于 Promtail 解析和 Loki 查询；6）定期审查标签：使用 Loki 的 `label_values` 和 `series` API 检查标签基数，发现异常增长及时处理。标签设计不当会导致 Loki 的索引膨胀，查询性能急剧下降。

---

## 8. 故障排查案例

### 案例 1：OTel Agent 注入后应用启动失败

**现象：**
```bash
kubectl logs deploy/api-server -n demo -c api-server
# Error: Could not create the Java Virtual Machine
# Error: A fatal exception has occurred. Program will exit.
# Error occurred during initialization of VM
# agent library failed to init: instrument
```

**排查步骤：**
```bash
# 1. 检查 Agent JAR 是否存在
kubectl exec -it deploy/api-server -n demo -- ls -la /otel-auto-instrumentation/
# 发现：javaagent.jar 不存在（initContainer 下载失败）

# 2. 检查 initContainer 日志
kubectl logs deploy/api-server -n demo -c otel-agent-init
# 发现：wget: bad address 'github.com'

# 3. 检查 Pod DNS 配置
kubectl exec -it deploy/api-server -n demo -- cat /etc/resolv.conf
# 发现：nameserver 配置正确

# 4. 测试网络连通性
kubectl exec -it deploy/api-server -n demo -- nslookup github.com
# 发现：无法解析外部域名（CoreDNS 配置问题或网络策略限制）
```

**解决方案：**
```bash
# 方案一：预下载 Agent JAR 并推送到 Harbor（在有外网的机器上执行）
docker pull ghcr.io/open-telemetry/opentelemetry-javaagent:1.33.0
docker tag ghcr.io/open-telemetry/opentelemetry-javaagent:1.33.0 192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0
docker push 192.168.1.61:80/otel/opentelemetry-javaagent:1.33.0

# 方案二：使用 initContainer 从 Harbor 拉取
# 修改 initContainer 镜像为内部 Harbor 地址

# 方案三：使用 OTel Operator 自动注入（Operator 会从配置的镜像仓库拉取）
```

### 案例 2：Trace 数据未出现在 Tempo 中

**现象：**
```
Grafana Tempo Explore 中搜索不到任何 Trace，但应用日志显示 OTel Agent 已加载。
```

**排查步骤：**
```bash
# 1. 检查 OTel Collector 接收情况
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector | grep "accepted_spans"
# 发现：otelcol_receiver_accepted_spans 无数据

# 2. 检查应用 OTel 配置
kubectl exec -it deploy/api-server -n demo -- env | grep OTEL
# 发现：OTEL_EXPORTER_OTLP_ENDPOINT 设置正确

# 3. 测试 Collector 连通性
kubectl exec -it deploy/api-server -n demo -- curl -v http://otel-collector.monitoring.svc.cluster.local:4317
# 发现：Connection refused

# 4. 检查 Collector Service
kubectl get svc -n monitoring otel-collector
# 发现：Service 存在但 Endpoints 为空

# 5. 检查 Collector Pod
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
# 发现：Collector Pod 处于 CrashLoopBackOff
```

**解决方案：**
```bash
# 查看 Collector 崩溃原因
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector --previous
# 发现：memory limit exceeded

# 增大 Collector 内存限制
kubectl patch otelcollector otel-collector -n monitoring --type merge \
  -p '{"spec":{"resources":{"limits":{"memory":"2Gi"}}}}'

# 等待 Collector 恢复
kubectl rollout status deployment/otel-collector -n monitoring
```

### 案例 3：Grafana 中 Trace 无法跳转到 Logs

**现象：**
```
在 Grafana Tempo 中查看 Trace，点击 "Linked Logs" 按钮后 Loki 面板无数据。
```

**排查步骤：**
```bash
# 1. 检查 Tempo 数据源配置
kubectl get configmap -n monitoring -l grafana_datasource=1 -o yaml | grep -A 20 "tracesToLogs"
# 发现：datasourceId 配置错误

# 2. 查询 Loki 中是否有对应日志
curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/labels" | jq .
# 发现：namespace 标签存在

# 3. 检查日志中是否包含 TraceID
curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query?query=%7Bnamespace%3D%22demo%22%7D%20%7C%3D%20%22traceId%22&limit=5" | jq .
# 发现：日志中不包含 traceId 字段

# 4. 检查应用日志格式
kubectl logs deploy/api-server -n demo -c api-server --tail=20
# 发现：日志格式为纯文本，未包含 TraceID
```

**解决方案：**
```bash
# 问题原因：应用日志框架未配置输出 TraceID

# 方案一：配置 Logback 输出 TraceID（Spring Boot）
# 在 application.yml 中添加：
# logging:
#   pattern:
#     console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] [%X{trace_id}/%X{span_id}] %-5level %logger{36} - %msg%n"

# 方案二：使用 OTel Log Bridge 自动桥接
# 在 OTEL 环境变量中添加：
# OTEL_LOGS_EXPORTER=otlp
```

### 案例 4：Prometheus 存储空间不足

**现象：**
```bash
kubectl describe pod -n monitoring -l app.kubernetes.io/name=prometheus | tail -20
# Warning  FailedScheduling  2m  0/5 nodes are available: persistentvolumeclaim "prometheus-prometheus-db" not found.

kubectl get pvc -n monitoring
# prometheus-prometheus-db   Pending
```

**排查步骤：**
```bash
# 1. 检查 StorageClass
kubectl get storageclass
# 发现：local-path StorageClass 存在

# 2. 检查节点磁盘空间
df -h
# 发现：Worker 节点磁盘使用率 95%

# 3. 检查 Prometheus 数据大小
kubectl exec -it -n monitoring prometheus-prometheus-0 -- du -sh /prometheus/
# 发现：48Gi（接近 50Gi 限制）

# 4. 检查 TSDB 状态
kubectl exec -it -n monitoring prometheus-prometheus-0 -- promtool tsdb status /prometheus/
```

**解决方案：**
```bash
# 方案一：清理旧数据（调整 retention）
helm upgrade prometheus /root/offline/kube-prometheus-stack-58.0.0.tgz \
  --namespace monitoring \
  --reuse-values \
  --set prometheus.prometheusSpec.retention=3d

# 方案二：增大存储卷
kubectl patch pvc prometheus-prometheus-db -n monitoring \
  --type merge -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# 方案三：优化采集目标，减少不必要的指标
# 排查高基数指标
kubectl exec -it -n monitoring prometheus-prometheus-0 -- \
  promtool tsdb analyze /prometheus/ | head -20
```

### 案例 5：Loki 查询超时

**现象：**
```
Grafana Loki 面板查询经常超时，返回 "query timeout" 错误。
```

**排查步骤：**
```bash
# 1. 检查 Loki 日志
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50
# 发现：level=warn msg="query timeout" elapsed=60s

# 2. 检查标签基数
curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/series?match[]={namespace=\"demo\"}" | jq '.data | length'
# 发现：标签序列数超过 100 万（标签爆炸）

# 3. 检查 Promtail 配置
kubectl get configmap -n monitoring -l app.kubernetes.io/name=promtail -o yaml | grep -A 30 "pipeline_stages"
# 发现：未配置 pipeline_stages，所有日志字段都被提取为标签

# 4. 检查日志格式
kubectl logs deploy/api-server -n demo --tail=5
# 发现：日志包含动态字段（如 request_id、session_id）被自动提取为标签
```

**解决方案：**
```bash
# 优化 Promtail 配置，限制标签数量
helm upgrade promtail /root/offline/promtail-6.16.0.tgz \
  --namespace monitoring \
  --reuse-values \
  --set config.clients[0].url=http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push \
  --set-file config.snippets.extraRelabelRules=<(cat <<'EOF'
relabel_rules:
  - source_labels: ['__meta_kubernetes_pod_label_app']
    target_label: app
  - source_labels: ['__meta_kubernetes_namespace']
    target_label: namespace
  - source_labels: ['__meta_kubernetes_pod_name']
    target_label: pod
  - regex: '(?!app|namespace|pod|container|stream).*'
    action: labeldrop
EOF
)

# 清理 Loki 中的历史数据（重建索引）
helm upgrade loki /root/offline/loki-6.7.0.tgz \
  --namespace monitoring \
  --reuse-values \
  --set singleBinary.extraArgs[0]="--compactor.retention-delete=true" \
  --set singleBinary.extraArgs[1]="--compactor.retention-delete-stale=true"
```

### 案例 6：Tempo 查询返回空结果

**现象：**
```
Grafana Tempo 中搜索 service.name="api-server" 返回空结果，但 Collector 日志显示 Span 已导出。
```

**排查步骤：**
```bash
# 1. 检查 Tempo 接收情况
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo --tail=50 | grep -i "trace"
# 发现：Tempo 正在接收数据

# 2. 检查 Tempo 存储状态
kubectl exec -it -n monitoring -l app.kubernetes.io/name=tempo -- ls -la /var/tempo/traces/
# 发现：trace 文件存在

# 3. 检查 Tempo 查询配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 5 "exporters"
# 发现：OTLP exporter endpoint 配置正确

# 4. 检查 Tempo 的 traceID 查询
curl -s "http://tempo.monitoring.svc.cluster.local:3100/api/search?tags=service.name%3Dapi-server&limit=10" | jq .
# 发现：返回空结果

# 5. 检查 Tempo 的 retention
kubectl logs -n monitoring -l app.kubernetes.io/name=tempo | grep -i "retention"
# 发现：traces 已过期被清理
```

**解决方案：**
```bash
# 问题原因：Tempo 默认 retention 可能过短，或 traces 被错误清理

# 增大 Tempo retention
helm upgrade tempo /root/offline/tempo-1.7.0.tgz \
  --namespace monitoring \
  --reuse-values \
  --set tempo.receivers.otlp.protocols.grpc.enabled=true \
  --set 'tempo.compactor.compaction.block_retention=168h' \
  --set 'tempo.compactor.compaction.compacted_block_retention=336h'

# 发送新请求生成 Trace 后重新查询
for i in $(seq 1 5); do
  curl -s http://192.168.1.54:31080/api/orders -H "Host: api.demo.local" > /dev/null
done
```

### 案例 7：OTel Collector 内存持续增长导致 OOM

**现象：**
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
# otel-collector-xxx  0/1 OOMKilled

kubectl describe pod -n monitoring -l app.kubernetes.io/name=otel-collector
# Last State: Terminated, Reason: OOMKilled, Exit Code: 137
```

**排查步骤：**
```bash
# 1. 检查 Collector 资源配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 10 "resources"
# 发现：memory limits=512Mi

# 2. 检查 memory_limiter 配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 5 "memory_limiter"
# 发现：limit_mib=512（与容器 limit 相同，无缓冲空间）

# 3. 检查 tail_sampling 缓冲
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 10 "tail_sampling"
# 发现：num_traces=100000（缓冲 10 万条完整 Trace）

# 4. 检查流量
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector | grep "accepted_spans" | tail -5
# 发现：每秒接收 5000+ Spans
```

**解决方案：**
```bash
# 优化 Collector 配置
# 1. 增大内存限制
# 2. 调整 memory_limiter（设为容器 limit 的 75%）
# 3. 减少尾部采样缓冲数量

kubectl patch otelcollector otel-collector -n monitoring --type merge \
  -p '{"spec":{"resources":{"limits":{"memory":"2Gi"}}}}'

# 更新 memory_limiter 配置
# limit_mib: 1536 (2Gi * 75%)
# spike_limit_mib: 768

# 减少尾部采样缓冲
# num_traces: 50000 (从 10 万降到 5 万)
```

### 案例 8：Promtail 无法采集 Pod 日志

---

### 案例 9：采样导致 Trace 不完整

**现象：**
```
在 Grafana Tempo 中查看 Trace，发现某些 Span 缺失，Trace 链路断裂。
例如：API Gateway -> User Service 的调用可见，但 User Service -> Database 的调用缺失。
```

**排查步骤：**

```bash
# 1. 检查应用的采样配置
kubectl exec -it deploy/user-service -n demo -- env | grep OTEL_TRACES
# 发现：OTEL_TRACES_SAMPLER=parentbased_traceidratio
#       OTEL_TRACES_SAMPLER_ARG=0.1

# 2. 检查 Collector 的采样配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 10 "probabilistic_sampler"
# 发现：sampling_percentage: 10.0

# 3. 检查应用的采样策略是否与 Collector 一致
# 应用采样 10%，Collector 再采样 10%，实际采样率 = 10% * 10% = 1%

# 4. 查看 Collector 的采样决策日志
kubectl logs -n monitoring -l app.kubernetes.io/name=otel-collector | grep "dropped"
# 发现：大量 Span 被 probabilistic_sampler 丢弃

# 5. 检查 tail_sampling 配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 20 "tail_sampling"
# 发现：decision_wait: 10s，某些快速完成的 Trace 可能未被正确评估
```

**问题根因：**

```
+================================================================================+
|                    双重采样导致Trace不完整                                      |
+================================================================================+
|                                                                                |
|   Application (10%采样)          Collector (10%采样)                           |
|   +------------------+           +------------------+                          |
|   | Span A: 采样     |---------->| Span A: 采样     |                          |
|   | Span B: 采样     |           | Span B: 丢弃(90%)| <-- 链路断裂             |
|   | Span C: 采样     |           | Span C: 采样     |                          |
|   +------------------+           +------------------+                          |
|                                                                                |
|   实际采样率 = 10% * 10% = 1%，且 Span 级别采样导致 Trace 不完整               |
|                                                                                |
+================================================================================+
```

**解决方案：**

```yaml
# 方案一：只在应用侧或 Collector 侧采样，不要双重采样

# 应用侧配置：100% 采样（由 Collector 统一控制）
env:
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_always_on"  # 始终跟随父Span

# Collector 侧配置：统一采样策略
processors:
  # 只保留 Collector 的概率采样
  probabilistic_sampler:
    sampling_percentage: 10.0
  
  # 或使用尾部采样替代概率采样
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    policies:
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow
        type: latency
        latency:
          threshold_ms: 1000
      - name: probabilistic
        type: probabilistic
        probabilistic:
          sampling_percentage: 10
```

```yaml
# 方案二：使用一致的采样策略（应用和 Collector 使用相同的采样率）

# 应用侧
env:
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "1.0"  # 应用100%采样，由 Collector 控制

# Collector 侧
processors:
  probabilistic_sampler:
    sampling_percentage: 10.0
```

```bash
# 验证修复
# 1. 重启应用和 Collector
kubectl rollout restart deployment/user-service -n demo
kubectl rollout restart deployment/otel-collector -n monitoring

# 2. 发送测试请求
for i in $(seq 1 20); do
  curl -s http://192.168.1.54:31080/api/users/123 > /dev/null
done

# 3. 在 Grafana 中验证 Trace 完整性
# 应该能看到完整的链路：API Gateway -> User Service -> Database
```

**预防措施：**

```yaml
# 1. 建立采样策略规范
# 应用侧：始终使用 parentbased_always_on，不设置采样率
# Collector 侧：统一配置采样策略

# 2. 监控采样指标
# 配置 Prometheus 告警规则
- alert: InconsistentSampling
  expr: |
    rate(otelcol_processor_dropped_spans[5m]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "OTel Collector 正在丢弃 Span"
    description: "请检查采样配置是否双重采样"
```

---

### 案例 10：TraceID 在日志中丢失

**现象：**
```
在 Loki 中查看日志，发现日志中没有 TraceID，无法从日志跳转到 Trace。
日志格式：2024-01-15 10:30:00 [INFO] UserService - User login success
缺少：[trace_id=abc123.../span_id=def456...]
```

**排查步骤：**

```bash
# 1. 检查应用日志配置
kubectl exec -it deploy/user-service -n demo -- cat /app/logback-spring.xml
# 发现：没有配置 TraceID 输出

# 2. 检查 OTel Agent 是否正确注入 MDC
kubectl logs deploy/user-service -n demo | grep "trace_id"
# 发现：日志中没有 trace_id 字段

# 3. 检查 OTel Agent 版本
kubectl exec -it deploy/user-service -n demo -- env | grep OTEL_JAVAAGENT_VERSION
# 发现：使用较旧版本，可能不支持自动 MDC 注入

# 4. 检查应用是否使用了正确的日志框架
kubectl exec -it deploy/user-service -n demo -- ls -la /app/WEB-INF/lib/ | grep log
# 发现：使用了 log4j 1.x，不支持 MDC

# 5. 检查 OTel 日志桥接配置
kubectl exec -it deploy/user-service -n demo -- env | grep OTEL_LOGS
# 发现：OTEL_LOGS_EXPORTER 未设置或设置为 none
```

**问题根因：**

```
+================================================================================+
|                    TraceID丢失的常见原因                                        |
+================================================================================+
|                                                                                |
|  1. 日志框架不支持MDC                                                          |
|     - Log4j 1.x 不支持 MDC                                                     |
|     - 需要升级到 Log4j 2.x 或 Logback                                          |
|                                                                                |
|  2. 日志模式未配置TraceID                                                      |
|     - 需要在 pattern 中包含 %X{trace_id}                                       |
|                                                                                |
|  3. OTel Agent未启用日志桥接                                                   |
|     - 需要设置 OTEL_LOGS_EXPORTER=otlp                                         |
|     - 或配置日志框架的 OTel Appender                                           |
|                                                                                |
|  4. 异步日志上下文丢失                                                         |
|     - 使用 ThreadPoolTaskExecutor 时上下文未传递                               |
|                                                                                |
+================================================================================+
```

**解决方案：**

```xml
<!-- 方案一：Spring Boot + Logback 配置 -->
<!-- logback-spring.xml -->
<configuration>
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <!-- 关键：包含 trace_id 和 span_id -->
            <pattern>
                %d{yyyy-MM-dd HH:mm:ss.SSS} 
                [%thread] 
                [%X{trace_id:-}/%X{span_id:-}]  <!-- 这里注入 TraceID -->
                %-5level 
                %logger{36} - 
                %msg%n
            </pattern>
        </encoder>
    </appender>
    
    <!-- JSON格式输出（推荐） -->
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdcKeyName>trace_id</includeMdcKeyName>
            <includeMdcKeyName>span_id</includeMdcKeyName>
            <includeMdcKeyName>trace_flags</includeMdcKeyName>
        </encoder>
    </appender>
    
    <root level="INFO">
        <appender-ref ref="CONSOLE"/>
    </root>
</configuration>
```

```yaml
# 方案二：Deployment 环境变量配置
env:
  # 启用 OTel 日志导出
  - name: OTEL_LOGS_EXPORTER
    value: "otlp"
  
  # 启用 OTel 日志桥接
  - name: OTEL_INSTRUMENTATION_LOGBACK_APPENDER_EXPERIMENTAL
    value: "true"
  
  # 启用 MDC 注入
  - name: OTEL_INSTRUMENTATION_LOG4J_APPENDER_EXPERIMENTAL
    value: "true"
```

```java
// 方案三：手动注入 TraceID（当自动注入不可用时）
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import io.opentelemetry.context.Scope;
import org.slf4j.MDC;

public class TracedService {
    
    public void processWithTrace() {
        Span span = Span.current();
        SpanContext spanContext = span.getSpanContext();
        
        // 手动注入 MDC
        try (Scope scope = span.makeCurrent()) {
            MDC.put("trace_id", spanContext.getTraceId());
            MDC.put("span_id", spanContext.getSpanId());
            
            logger.info("Processing request with trace");
            
            // 业务逻辑
            doWork();
        } finally {
            MDC.remove("trace_id");
            MDC.remove("span_id");
        }
    }
}
```

```java
// 方案四：异步任务上下文传递
import io.opentelemetry.context.Context;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;

public class AsyncService {
    
    public CompletableFuture<Void> asyncOperation() {
        // 捕获当前上下文
        Context context = Context.current();
        
        return CompletableFuture.runAsync(() -> {
            // 在异步线程中恢复上下文
            try (Scope scope = context.makeCurrent()) {
                logger.info("Async operation with trace");
                // 现在日志中会包含 TraceID
            }
        }, executorService);
    }
}
```

```bash
# 验证修复
# 1. 重启应用
kubectl rollout restart deployment/user-service -n demo

# 2. 发送测试请求
curl -s http://192.168.1.54:31080/api/users/123

# 3. 检查日志中是否包含 TraceID
kubectl logs deploy/user-service -n demo | grep "trace_id"
# 预期输出：2024-01-15 10:30:00 [http-nio-8080-exec-1] [abc123.../def456...] INFO ...

# 4. 在 Loki 中验证
# 查询：{namespace="demo", app="user-service"} |= "trace_id"
# 应该能看到包含 trace_id 的日志条目
```

---

### 案例 11：Collector 内存溢出（OOMKilled）

**现象：**
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector
# NAME                              READY   STATUS      RESTARTS   AGE
# otel-collector-7d9f4b8c5-x2v9p   0/1     OOMKilled   5          10m

kubectl describe pod -n monitoring otel-collector-7d9f4b8c5-x2v9p
# Last State: Terminated
# Reason: OOMKilled
# Exit Code: 137
```

**排查步骤：**

```bash
# 1. 检查 Collector 资源限制
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 10 "resources"
# 发现：limits.memory: 512Mi

# 2. 检查 memory_limiter 配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 5 "memory_limiter"
# 发现：limit_mib: 512（与容器限制相同，无缓冲）

# 3. 检查 tail_sampling 配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 10 "tail_sampling"
# 发现：num_traces: 100000（缓冲10万条Trace）
#       decision_wait: 30s（等待时间过长）

# 4. 检查流量情况
kubectl logs -n monitoring otel-collector-7d9f4b8c5-x2v9p --previous | grep "accepted"
# 发现：每秒接收 10000+ Spans

# 5. 检查 batch 配置
kubectl get otelcollector otel-collector -n monitoring -o yaml | grep -A 5 "batch"
# 发现：send_batch_max_size: 10000（批处理过大）

# 6. 检查是否有内存泄漏
kubectl logs -n monitoring otel-collector-7d9f4b8c5-x2v9p --previous | grep -i "memory"
# 发现：内存持续增长，无释放
```

**问题根因分析：**

```
+================================================================================+
|                    Collector内存溢出原因分析                                    |
+================================================================================+
|                                                                                |
|  1. 内存限制配置不当                                                           |
|     - memory_limiter.limit_mib = 容器内存限制（无缓冲）                        |
|     - 正确配置：limit_mib = 容器限制的 75%                                     |
|                                                                                |
|  2. 尾部采样缓冲过大                                                           |
|     - num_traces = 100000 条Trace缓冲                                          |
|     - 每条Trace平均 10 个Span，每个Span 3KB                                    |
|     - 内存占用 = 100000 * 10 * 3KB = 3GB                                       |
|                                                                                |
|  3. 批处理配置过大                                                             |
|     - send_batch_max_size = 10000                                              |
|     - 批处理队列占用大量内存                                                     |
|                                                                                |
|  4. 高流量无背压控制                                                           |
|     - 接收速率 > 处理速率                                                      |
|     - 数据在内存中堆积                                                         |
|                                                                                |
+================================================================================+
```

**解决方案：**

```yaml
# 方案一：优化内存配置
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector
  namespace: monitoring
spec:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi  # 增加内存限制
  
  config: |
    processors:
      # 优化 memory_limiter
      memory_limiter:
        check_interval: 1s  # 更频繁检查
        limit_mib: 1536     # 2Gi * 75% = 1.5Gi
        spike_limit_mib: 512
      
      # 优化 batch
      batch:
        timeout: 1s         # 减少超时时间
        send_batch_size: 512    # 减小批大小
        send_batch_max_size: 1024  # 减小最大批大小
      
      # 优化 tail_sampling
      tail_sampling:
        decision_wait: 5s   # 减少等待时间
        num_traces: 10000   # 减少缓冲数量（从10万降到1万）
        expected_new_traces_per_sec: 1000
        policies:
          - name: errors
            type: status_code
            status_code:
              status_codes: [ERROR]
```

```yaml
# 方案二：水平扩展（Gateway模式）
apiVersion: opentelemetry.io/v1beta1
kind: OpenTelemetryCollector
metadata:
  name: otel-collector-gateway
  namespace: monitoring
spec:
  mode: deployment
  replicas: 3  # 多副本负载均衡
  resources:
    limits:
      memory: 2Gi
  
  config: |
    processors:
      memory_limiter:
        check_interval: 1s
        limit_mib: 1536
        spike_limit_mib: 512
```

```yaml
# 方案三：启用背压控制
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 1536
    spike_limit_mib: 512
  
  # 添加负载削减
  filter/drop-on-pressure:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'
        - 'attributes["http.route"] == "/metrics"'
        - 'attributes["http.route"] == "/actuator/health"'

exporters:
  otlp:
    endpoint: tempo.monitoring.svc.cluster.local:4317
    tls:
      insecure: true
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 1000  # 限制队列大小
    retry_on_failure:
      enabled: true
      max_elapsed_time: 60s  # 减少重试时间
```

```bash
# 验证修复
# 1. 应用新配置
kubectl apply -f otel-collector-config.yaml

# 2. 监控内存使用
kubectl top pod -n monitoring -l app.kubernetes.io/name=otel-collector
# 预期：内存稳定在 1.5Gi 以下

# 3. 监控 OOM 情况
kubectl get pods -n monitoring -l app.kubernetes.io/name=otel-collector -w
# 预期：RESTARTS 不再增加

# 4. 检查 Collector 自身指标
curl http://otel-collector.monitoring.svc.cluster.local:8888/metrics | grep "otelcol_process_memory"
# 预期：内存使用稳定
```

**预防措施：**

```yaml
# 1. 配置 Prometheus 告警规则
- alert: OtelCollectorHighMemory
  expr: |
    container_memory_working_set_bytes{container="otel-collector"} 
    / container_spec_memory_limit_bytes{container="otel-collector"} > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "OTel Collector 内存使用率超过 80%"
    
- alert: OtelCollectorOOMRisk
  expr: |
    rate(container_memory_failures_total{container="otel-collector"}[5m]) > 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "OTel Collector 存在 OOM 风险"

# 2. 配置 HPA 自动扩缩容
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: otel-collector-hpa
  namespace: monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: otel-collector
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70
```

---

### 案例 8：Promtail 无法采集 Pod 日志

**现象：**
```
Loki 中查不到 demo 命名空间的日志，但 Pod 日志正常输出。
```

**排查步骤：**
```bash
# 1. 检查 Promtail Pod 状态
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
# 发现：promtail Running

# 2. 检查 Promtail 日志
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50
# 发现：level=error msg="failed to watch API" resource="/api/v1/namespaces/demo/pods"

# 3. 检查 Promtail RBAC 权限
kubectl get clusterrolebinding -l app.kubernetes.io/name=promtail -o yaml
# 发现：ClusterRoleBinding 存在，但 ClusterRole 缺少 pods/log 权限

# 4. 检查 NetworkPolicy
kubectl get networkpolicy -n demo
# 发现：存在 NetworkPolicy 阻止了 monitoring 命名空间访问 demo 命名空间的 Pod
```

**解决方案：**
```bash
# 方案一：修复 NetworkPolicy，允许 Promtail 访问
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-promtail
  namespace: demo
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 15090
EOF

# 方案二：修复 Promtail RBAC
kubectl get clusterrole promtail -n monitoring -o yaml
# 确保 ClusterRole 包含以下权限：
# - apiGroups: [""]
#   resources: ["pods", "pods/log", "namespaces", "nodes"]
#   verbs: ["get", "list", "watch"]
```

---

## 9. 持续性能分析（进阶）

### 9.1 什么是持续性能分析

**持续性能分析（Continuous Profiling）** 是一种在生产环境中持续收集和分析应用程序性能数据的技术。它通过定期采样程序的 CPU、内存、锁竞争等运行时信息，帮助开发者深入理解系统行为，发现传统监控无法发现的性能瓶颈。

**为什么是"可观测性第四支柱"？**

传统可观测性三大支柱：
- **Metrics（指标）**：告诉你"发生了什么"（如 CPU 使用率 80%）
- **Logs（日志）**：告诉你"发生了什么事件"（如错误日志）
- **Traces（链路）**：告诉你"请求经过了哪里"（如调用链路）

**Profiling（性能分析）** 则告诉你"为什么会这样"：
- CPU 时间具体花在哪个函数？
- 内存分配热点在哪里？
- 锁竞争发生在哪段代码？

```
+================================================================+
|                   可观测性四支柱关系图                           |
+================================================================+
|                                                                 |
|   Metrics (What)          Logs (What Event)                     |
|   +------------+          +------------+                        |
|   | CPU: 80%   |          | Error: OOM |                        |
|   +------------+          +------------+                        |
|         |                       |                               |
|         v                       v                               |
|   +---------------------------------------------------+         |
|   |              Profiling (Why)                      |         |
|   |  函数热点分析 → 发现 malloc() 占用 60% CPU        |         |
|   |  内存分配追踪 → 发现 string concat 泄漏          |         |
|   +---------------------------------------------------+         |
|         ^                       ^                               |
|         |                       |                               |
|   Traces (Where)           Root Cause Analysis                  |
|   +------------+          +------------+                        |
|   | 调用链路   |--------->| 性能瓶颈   |                        |
|   +------------+          +------------+                        |
|                                                                 |
+================================================================+
```

### 9.2 主流持续性能分析工具

| 工具 | 开发者 | 特点 | 适用场景 |
|------|--------|------|----------|
| **Pyroscope** | Grafana Labs | 多语言支持、Grafana 集成 | Kubernetes 环境 |
| **Parca** | Polar Signals | eBPF 支持、低开销 | 内核级分析 |
| **Continuous Profiler** | Datadog | 商业方案、APM 集成 | 企业级监控 |
| **Pprof** | Google | Go 原生、命令行工具 | Go 应用调试 |

本课程选择 **Pyroscope**，原因：
1. 开源免费，社区活跃
2. 原生支持 Grafana 可视化
3. 支持 Go、Python、Java、Node.js、.NET 等主流语言
4. 部署简单，资源开销低（~50MB 内存）

### 9.3 Pyroscope 离线部署

**镜像准备（在有网机器上执行）：**

```bash
# ==================================================
# 拉取 Pyroscope 镜像
# ==================================================

PYROSCOPE_IMAGES=(
  "grafana/pyroscope:1.6.0"
  "grafana/pyroscope-java-agent:1.6.0"
  "grafana/pyroscope-go-agent:1.6.0"
)

REGISTRY="192.168.1.61:80"

for img in "${PYROSCOPE_IMAGES[@]}"; do
  echo ">>> 处理: $img"
  docker pull "$img"
  
  img_name=$(echo $img | cut -d'/' -f2)
  docker tag "$img" "${REGISTRY}/pyroscope/${img_name}"
  docker push "${REGISTRY}/pyroscope/${img_name}"
done

echo ">>> Pyroscope 镜像已推送到 Harbor"
```

**Helm 部署（离线环境）：**

```bash
# ==================================================
# 在有网机器下载 Helm Chart
# ==================================================
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm pull grafana/pyroscope --version 1.6.0
# 传输 pyroscope-1.6.0.tgz 到离线集群

# ==================================================
# 在离线集群部署
# ==================================================

# 创建 values 文件
cat > pyroscope-values.yaml << 'EOF'
image:
  repository: 192.168.1.61:80/pyroscope/pyroscope
  tag: 1.6.0
  pullPolicy: IfNotPresent

# 单副本部署（离线集群资源有限）
replicaCount: 1

# 资源配置
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# 持久化存储
persistence:
  enabled: true
  size: 10Gi
  storageClass: local-path

# Service 配置
service:
  type: NodePort
  port: 4040
  nodePort: 30040

# 启用微服务模式
pyroscope:
  microservices:
    enabled: false  # 单体模式，资源占用更少
EOF

# 安装
kubectl create namespace pyroscope
helm install pyroscope ./pyroscope \
  --namespace pyroscope \
  -f pyroscope-values.yaml

# 验证
kubectl get pods -n pyroscope
kubectl get svc -n pyroscope
```

**验证 Pyroscope 运行状态：**

```bash
# 查看 Pod 状态
kubectl get pods -n pyroscope
# NAME                         READY   STATUS    RESTARTS   AGE
# pyroscope-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# 访问 Pyroscope UI
# http://<节点IP>:30040

# 检查服务健康
kubectl port-forward -n pyroscope svc/pyroscope 4040:4040 &
curl http://localhost:4040/health
```

### 9.4 应用集成示例

**Go 应用集成：**

```go
// main.go
package main

import (
    "github.com/grafana/pyroscope-go"
)

func main() {
    // 初始化 Pyroscope
    pyroscope.Start(pyroscope.Config{
        ApplicationName: "mall-order-service",
        ServerAddress:   "http://pyroscope.pyroscope.svc:4040",
        Logger:          pyroscope.StandardLogger,
        
        // 上传配置
        UploadRate:      10 * time.Second,  // 每 10 秒上传一次
        
        // Profile 类型
        ProfileTypes: []pyroscope.ProfileType{
            pyroscope.ProfileCPU,
            pyroscope.ProfileAllocObjects,
            pyroscope.ProfileAllocSpace,
            pyroscope.ProfileInuseObjects,
            pyroscope.ProfileInuseSpace,
        },
    })
    
    // 应用逻辑...
    runApplication()
}
```

**Java 应用集成（JVM Agent）：**

```bash
# 下载 Java Agent（在有网环境）
wget https://github.com/grafana/pyroscope-java/releases/download/v1.6.0/pyroscope-java-agent.jar

# 启动 Java 应用
java -javaagent:pyroscope-java-agent.jar \
     -Dpyroscope.application.name=mall-product-service \
     -Dpyroscope.server.address=http://pyroscope.pyroscope.svc:4040 \
     -jar app.jar
```

**Kubernetes Deployment 配置：**

```yaml
# order-service-with-profiling.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: mall
spec:
  template:
    spec:
      containers:
      - name: order-service
        image: 192.168.1.61:80/mall/order-service:v1.0.0
        env:
        # Pyroscope 配置
        - name: PYROSCOPE_APPLICATION_NAME
          value: "mall-order-service"
        - name: PYROSCOPE_SERVER_ADDRESS
          value: "http://pyroscope.pyroscope.svc:4040"
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

### 9.5 Grafana 集成配置

**添加 Pyroscope 数据源：**

```yaml
# grafana-datasource-pyroscope.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-pyroscope
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  pyroscope.yaml: |
    apiVersion: 1
    datasources:
    - name: Pyroscope
      type: grafana-pyroscope-datasource
      url: http://pyroscope.pyroscope.svc:4040
      access: proxy
      isDefault: false
      editable: false
      jsonData:
        customQueryParameters: ''
```

**导入预置 Dashboard：**

```bash
# 在 Grafana 中导入 Pyroscope Dashboard
# Dashboard ID: 18048 (官方 Pyroscope Dashboard)

# 或手动创建
# 1. 打开 Grafana → Dashboards → Import
# 2. 输入 Dashboard ID: 18048
# 3. 选择 Pyroscope 数据源
# 4. 点击 Import
```

**CPU 性能分析面板示例：**

```
+================================================================+
|                 Pyroscope CPU 分析面板                          |
+================================================================+
|                                                                 |
|  应用: mall-order-service    时间范围: Last 1h                  |
|                                                                 |
|  +----------------------------------------------------------+  |
|  |                    CPU 火焰图 (Flamegraph)               |  |
|  |                                                          |  |
|  |     main()  100%                                         |  |
|  |     ├─ processOrder()  45%                               |  |
|  |     │  ├─ validatePayment()  20%  ← 热点                 |  |
|  |     │  │  └─ callPaymentService()  18%                   |  |
|  |     │  └─ updateInventory()  15%                         |  |
|  |     ├─ queryDatabase()  35%                              |  |
|  |     │  └─ executeSQL()  32%  ← 慢查询                    |  |
|  |     └─ sendNotification()  15%                           |  |
|  |                                                          |  |
|  +----------------------------------------------------------+  |
|                                                                 |
|  发现问题:                                                      |
|  1. validatePayment() 占用 20% CPU，建议优化校验逻辑             |
|  2. executeSQL() 占用 32% CPU，存在 N+1 查询问题                |
|                                                                 |
+================================================================+
```

### 9.6 CPU/内存分析实战案例

**案例：发现内存泄漏**

```bash
# 步骤 1: 在 Pyroscope UI 选择应用
# 应用: mall-cart-service
# Profile 类型: inuse_objects (正在使用的对象数)

# 步骤 2: 观察内存分配热点
# 发现: ShoppingCart 对象持续增长

# 步骤 3: 分析火焰图
# 发现热点调用链:
# ShoppingCart.addItem()
#   → CartCache.put()
#     → ConcurrentHashMap.put()
#       → new Node()  // 每次添加创建新节点

# 步骤 4: 定位代码问题
# 原因: 购物车缓存未设置过期时间，对象持续累积

# 步骤 5: 修复并验证
# 添加缓存过期配置后，内存使用恢复正常
```

**案例：发现 CPU 热点**

```bash
# 步骤 1: 查看 CPU Profile
# 应用: mall-search-service
# 发现: JSON 序列化占用 40% CPU

# 步骤 2: 分析调用栈
# SearchService.buildResponse()
#   → ObjectMapper.writeValueAsString()  // Jackson 序列化
#     → SerializerProvider.serializeValue()

# 步骤 3: 优化方案
# 1. 使用 ObjectMapper 单例（避免重复创建）
# 2. 启用 Jackson Afterburner 模块加速
# 3. 考虑使用 Protobuf 替代 JSON

# 优化后 CPU 使用下降 25%
```

### 9.7 成本与资源考量

**Pyroscope 资源开销估算：**

| 组件 | 内存占用 | CPU 占用 | 存储 |
|------|----------|----------|------|
| Pyroscope Server | ~50-100MB | ~0.1-0.5 core | 10-50GB/月 |
| Go Agent | ~5-10MB | ~1-2% | 无 |
| Java Agent | ~20-50MB | ~2-5% | 无 |

**离线集群资源配置建议：**

```yaml
# pyroscope-values-offline.yaml
# 适配 6 节点离线集群（Master 2C4G / Worker 4C8G）

resources:
  requests:
    cpu: 100m      # 最小 0.1 core
    memory: 256Mi  # 最小 256MB
  limits:
    cpu: 500m      # 最大 0.5 core
    memory: 512Mi  # 最大 512MB

# 存储配置（使用本地存储）
persistence:
  enabled: true
  size: 10Gi      # 10GB 足够存储 7 天数据
  storageClass: local-path

# 采样配置（降低开销）
pyroscope:
  scrapeConfigs:
    - interval: 30s  # 采样间隔 30 秒（默认 15s）
```

**成本优化建议：**

| 优化项 | 说明 | 效果 |
|--------|------|------|
| 增加采样间隔 | 从 15s 改为 30s | CPU 开销降低 50% |
| 减少 Profile 类型 | 只采集 CPU 和内存 | 存储/内存降低 40% |
| 设置数据保留期 | 保留 7 天而非 30 天 | 存储降低 75% |
| 选择性启用 | 只对核心服务启用 | 整体开销可控 |

### 9.8 CKA/CKS 考点关联

| 考点 | 关联内容 |
|------|----------|
| **资源限制** | 理解 Profiling Agent 对应用资源的影响 |
| **故障排查** | 使用 Profiling 定位 CPU/内存问题 |
| **可观测性** | 理解四支柱的互补关系 |
| **性能调优** | 基于真实数据优化应用性能 |

**高频面试题：**

1. **Q: 持续性能分析与 APM 有什么区别？**
   - A: APM 关注请求级别的性能（延迟、吞吐），Profiling 关注代码级别的性能（函数热点、内存分配）。两者互补，APM 告诉你"哪个接口慢"，Profiling 告诉你"为什么慢"。

2. **Q: Pyroscope 的性能开销是多少？**
   - A: Go Agent 约 1-2% CPU 开销，Java Agent 约 2-5%。内存开销约 5-50MB。通过调整采样间隔可进一步降低开销。

3. **Q: 火焰图如何解读？**
   - A: 火焰图 X 轴表示时间/采样比例，Y 轴表示调用栈深度。宽度越宽表示该函数占用越多资源，颜色通常无特殊含义。从下往上追踪调用链，找到最宽的块即为热点。

---

## 10. 生产环境建议

### 10.1 资源规划参考

| 组件 | 最低配置 | 推荐配置（<200 Pods） | 本离线集群配置（6节点 K8s） |
|------|---------|---------------------|------------------------|
| Prometheus | 2C4G | 4C8G | 1C2G + 30Gi 存储 |
| Grafana | 1C1G | 2C2G | 0.5C512M + 5Gi 存储 |
| Loki | 1C2G | 2C4G + 50Gi 存储 | 0.5C1G + 10Gi 存储 |
| Tempo | 1C2G | 2C4G + 50Gi 存储 | 0.5C1G + 10Gi 存储 |
| OTel Collector | 1C1G | 2C2G（2 副本） | 0.5C1G（1 副本） |
| Promtail | 0.5C256M | 1C512M（DS 模式） | 0.2C256M（DS 模式） |

### 9.2 生产最佳实践

| 领域 | 建议 |
|------|------|
| **采样策略** | 头部采样 10% + 尾部采样保留错误和慢请求 |
| **数据保留** | Trace 7 天、Metrics 30 天、Logs 30 天 |
| **高可用** | Collector 多副本 + 反亲和性；Prometheus 2 副本（Thanos） |
| **告警配置** | 错误率 > 1%、P99 > 2s、Collector 丢弃数据、存储空间 > 80% |
| **日志格式** | 统一 JSON 格式，包含 traceId、spanId、service、instance |
| **标签管理** | Loki 标签控制在 5-10 个，避免高基数标签 |
| **安全** | Collector 启用 mTLS；Grafana 启用 OAuth/OIDC；数据传输加密 |
| **备份** | Prometheus TSDB 定期备份；Grafana Dashboard JSON 导出备份 |
| **升级** | OTel Collector 滚动升级；Prometheus 热重载配置 |
| **监控自身** | 监控 OTel Collector、Prometheus、Loki、Tempo 自身的健康指标 |
