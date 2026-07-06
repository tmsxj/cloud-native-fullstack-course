# 模块07：Loki 日志系统

---

## 1. 概述与架构图

### 1.1 课程目标

本模块全面讲解 Kubernetes 日志系统的设计与实现，基于 Grafana Loki（轻量级日志聚合引擎）构建轻量级、高性能的日志平台。涵盖 Loki vs ELK 对比、Promtail（日志采集 Agent）日志采集、LogQL（Loki 查询语言）查询语言、多行日志匹配（Java 异常栈）、与 Prometheus 联动以及日志告警。完成本模块后，你将具备搭建生产级 K8s 日志系统的能力。

### 1.2 日志系统架构图

```
  +------------------------------------------------------------------+
  |                    Kubernetes Cluster                             |
  +------------------------------------------------------------------+
       |              |              |              |
  +----+----+   +-----+-----+  +----+----+  +----+----+
  | kubelet  |   |  Pod A    |  |  Pod B   |  |  Pod C  |
  | (日志)   |   | (stdout)  |  | (stdout)  |  | (stdout)|
  +----+----+   +-----+-----+  +----+----+  +----+----+
       |              |              |              |
       +--------------+--------------+--------------+
                            |
                    +-------+-------+
                    |   Promtail    |
                    | (DaemonSet)   |
                    | (日志采集)     |
                    | - /var/log/    |
                    | - /var/lib/    |
                    |   docker/      |
                    +-------+-------+
                            |
                    +-------+-------+
                    |     Loki      |
                    | (日志存储)     |
                    | - Label Index |
                    | - Chunk Store |
                    | - Compactor   |
                    +-------+-------+
                            |
              +-------------+-------------+
              |             |             |
     +--------+------+  +--+--------+  +-+----------+
     |   Grafana     |  | Alerting |  | LogQL      |
     | (日志查询)     |  | (日志告警)|  | (查询语言) |
     +--------+------+  +----------+  +------------+
              |
     +--------+------+
     |  Prometheus   |
     | (指标联动)     |
     +---------------+
```

### 1.3 Loki 数据流

```
  应用日志 (stdout/stderr)
       |
       v
  containerd (JSON 日志文件)
  /var/log/containers/*.log
       |
       v
  Promtail (DaemonSet)
  - 发现日志文件
  - 添加 Labels (namespace/pod/container)
  - 解析日志格式 (JSON/Regexp)
  - 推送到 Loki
       |
       v
  Loki Ingester
  - 接收日志流
  - 按 Labels 分组
  - 构建索引 (Label -> Chunk)
       |
       v
  Loki Storage
  - Chunk Store (对象存储/S3/本地)
  - Index Store (BoltDB/S3)
       |
       v
  Grafana / LogQL
  - 查询日志
  - 过滤/聚合/解析
```

### 1.4 Loki vs ELK 对比

```
  +------------------+-------------------+-------------------+
  |      特性         |       Loki        |       ELK        |
  +------------------+-------------------+-------------------+
  | 架构             | 简洁 (2-3 组件)    | 复杂 (5+ 组件)     |
  | 存储             | 仅索引 Labels      | 全文索引           |
  | 资源占用         | 低 (CPU/内存)      | 高 (ES 需大量内存) |
  | 查询语言         | LogQL             | Lucene/KQL        |
  | 全文搜索         | 不支持 (需 grep)   | 原生支持           |
  | 日志解析         | Promtail 管道      | Logstash/Ingest   |
  | 生态集成         | Grafana 原生       | Kibana            |
  | 与 K8s 集成      | 原生支持           | 需要额外配置       |
  | 水平扩展         | 简单 (微服务模式)   | 复杂 (ES 分片)     |
  | 适用规模         | 中大规模           | 大规模             |
  | 运维成本         | 低                 | 高                 |
  | 学习曲线         | 低 (类似 PromQL)   | 中                 |
  +------------------+-------------------+-------------------+
```

---

## 2. 理论基础

### 2.1 Loki 核心概念

| 概念 | 说明 |
|------|------|
| **Log Stream**（日志流） | 具有唯一 Labels 集合的日志流 |
| **Labels**（标签） | 键值对元数据（namespace、pod、container 等） |
| **Log Line**（日志行） | 单条日志记录（时间戳 + 内容） |
| **Chunk**（数据块） | 日志数据块，按时间窗口和 Labels 组织 |
| **Tenant**（租户） | 多租户隔离（单租户模式默认 tenant ID 为空） |

### 2.2 Loki vs ELK 详细对比

| 维度 | Loki | ELK (Elasticsearch + Logstash + Kibana) |
|------|------|----------------------------------------|
| **索引策略** | 仅索引 Labels，不索引日志内容 | 全文索引（倒排索引） |
| **存储成本** | 低（只存储原始日志 + Label 索引） | 高（全文索引占用大量存储） |
| **查询性能** | 基于 Label 过滤快，全文搜索慢 | 全文搜索快，复杂聚合快 |
| **内存占用** | 低（每个实例 ~1-2GB） | 高（ES 堆内存建议 >= 8GB） |
| **部署复杂度** | 低（Loki + Promtail + Grafana） | 高（ES + Logstash + Kibana + Filebeat） |
| **日志解析** | Promtail Pipeline（JSON/Regexp/logfmt） | Logstash Pipeline（Grok/JSON/CSV） |
| **告警** | Loki Ruler（LogQL 告警规则） | ElastAlert / Watcher |
| **多租户** | 原生支持 | 通过 Index/Field Level Security |
| **数据保留** | 按时间/大小自动清理 | ILM 策略 |

### 2.3 LogQL 查询语言

LogQL 是 Loki 的查询语言，语法类似 PromQL。

| 类别 | 说明 | 示例 |
|------|------|------|
| **Log Query** | 日志搜索 | `{namespace="default"} \|= "error"` |
| **Metric Query** | 日志转指标 | `count_over_time({app="nginx"} \|= "error" [5m])`` |
| **Log Pipeline** | 日志解析 | `{app="nginx"} \| json \| line_format "{{.method}} {{.path}}"` |
| **Label Filter** | 标签过滤 | `{namespace=~"dev\|prod", pod="nginx-*"}` |

### 2.4 Promtail Pipeline 处理阶段

```
  原始日志
      |
      v
  +-----------+     +-----------+     +-----------+     +-----------+
  |  json     |---->|  regexp   |---->|  logfmt   |---->|  replace  |
  |  解析器   |     |  正则解析  |     |  KV 解析  |     |  替换     |
  +-----------+     +-----------+     +-----------+     +-----------+
      |
      v
  +-----------+     +-----------+     +-----------+     +-----------+
  |  labels   |---->|  timestamp|---->|  line_fmt |---->|  drop     |
  |  提取标签  |     |  时间戳   |     |  格式化   |     |  丢弃     |
  +-----------+     +-----------+     +-----------+     +-----------+
```

---

## 3. 离线前置准备

> **重要提示：** 本集群为 6 节点 K8s v1.28.15 离线环境，无外网访问。所有 Helm Chart 和容器镜像必须提前下载并推送到内部 Harbor 仓库（192.168.1.61，HTTP，密码 Harbor12345）。Helm 离线操作详细指南请参考 `00-基础设施准备.md`。

### 3.0.1 Helm Chart 离线下载

在**有外网的机器**上执行以下操作，将 Helm Chart 打包后拷贝到离线环境：

```bash
# 1. 添加并更新 Helm 仓库（在有外网的机器上）
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 2. 拉取 Loki Stack Helm Chart（含 Loki、Promtail、Gateway）
helm pull grafana/loki-stack --version 2.9.4 --destination /tmp/charts/

# 3. 将 Chart 包拷贝到离线环境（通过 U 盘/内网 scp 等）
scp /tmp/charts/loki-stack-2.9.4.tgz root@192.168.1.51:/root/charts/
```

### 3.0.2 镜像清单与预推送

以下为 Loki Stack 所需的全部容器镜像，需在有外网的机器上拉取后推送到 Harbor：

| 组件 | 镜像 | 说明 |
|------|------|------|
| **Loki** | `docker.io/grafana/loki:2.9.4` | 日志存储引擎 |
| **Promtail** | `docker.io/grafana/promtail:2.9.4` | 日志采集 Agent（DaemonSet） |
| **Loki Gateway** | `docker.io/grafana/loki-gateway:2.9.4` | Nginx 网关（单入口） |

**镜像预推送脚本（在有外网的机器上执行）：**

```bash
#!/bin/bash
# Loki Stack 镜像预推送脚本
HARBOR_ADDR="192.168.1.61"
HARBOR_PROJECT="k8s"
HARBOR_PASS="Harbor12345"

# 登录 Harbor
echo "$HARBOR_PASS" | docker login http://$HARBOR_ADDR -u admin --password-stdin

# 定义镜像列表
images=(
    "docker.io/grafana/loki:2.9.4"
    "docker.io/grafana/promtail:2.9.4"
    "docker.io/grafana/loki-gateway:2.9.4"
)

# 拉取、打标签、推送
for img in "${images[@]}"; do
    # 提取镜像名和标签
    name=$(echo "$img" | sed 's|.*/||' | cut -d: -f1)
    tag=$(echo "$img" | cut -d: -f2)
    target="${HARBOR_ADDR}/${HARBOR_PROJECT}/${name}:${tag}"

    echo ">>> 处理镜像: $img -> $target"
    docker pull "$img"
    docker tag "$img" "$target"
    docker push "$target"
    docker rmi "$img" "$target" 2>/dev/null
done

echo ">>> 所有镜像推送完成！"
```

**在离线集群的每个 Worker 节点上拉取镜像：**

```bash
# 在每个 Worker 节点上执行
for img in loki:2.9.4 promtail:2.9.4 loki-gateway:2.9.4; do
    crictl pull --creds "admin:Harbor12345" "192.168.1.61/k8s/${img}"
done
```

### 3.0.3 创建命名空间

```bash
kubectl create namespace logging
```

---

## 4. 部署实战

### 4.1 使用离线 Helm Chart 安装 Loki Stack

> **离线安装说明：** 使用 `helm pull` 提前下载的 Chart 包进行本地安装，无需外网。详细 Helm 离线操作请参考 `00-基础设施准备.md`。

```bash
# 使用本地 Chart 包安装（无需 helm repo add）
helm install loki /root/charts/loki-stack-2.9.4.tgz \
    -n logging \
    -f /root/loki-values.yaml \
    --timeout 10m
```

### 4.2 创建 Loki values.yaml

```bash
cat > /root/loki-values.yaml << 'EOF'
# Loki Helm Chart values.yaml

# 全局镜像配置
global:
  imageRegistry: "192.168.1.61/registry.k8s.io"

# Loki 配置
loki:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/loki
    tag: 2.9.4
  replicas: 1                     # Loki 实例副本数
  persistence:
    enabled: true
    size: 50Gi                    # 持久化存储大小
    storageClassName: local-path  # 存储类
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 250m
      memory: 512Mi
  config:
    auth_enabled: false           # 关闭认证（开发/内网环境）
    common_config:
      replication_factor: 1       # 数据复制因子
    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb             # 存储引擎类型
          object_store: filesystem # 对象存储后端
          schema: v13             # Schema 版本
          index:
            prefix: loki_index_
            period: 24h           # 索引时间窗口
    storage_config:
      filesystem:
        directory: /loki/chunks   # 数据存储目录
    compactor:
      working_directory: /loki/compactor
      compaction_interval: 10m    # 压缩执行间隔
      retention_enabled: true     # 启用数据保留策略
      delete_request_store: filesystem
    limits_config:
      reject_old_samples: true    # 拒绝过期日志
      reject_old_samples_max_age: 168h
      max_query_length: 721h      # 最大查询时间范围
      retention_period: 168h      # 日志保留时间（7天）
    ruler:
      enable_api: true            # 启用 Ruler API
      enable_alertmanager: true   # 启用 Alertmanager 集成
      alertmanager_url: http://prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093
      storage:
        type: local
        local:
          directory: /loki/rules  # 告警规则存储目录
    analytics:
      reporting_enabled: false

# Promtail 配置
promtail:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/promtail
    tag: 2.9.4
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
  config:
    clients:
      - url: http://loki.logging.svc.cluster.local:3100/loki/api/v1/push  # Loki 推送地址
    scrape_configs:
      # K8s Pod 日志采集
      - job_name: kubernetes-pods
        kubernetes_sd_configs:       # K8s 服务发现配置
          - role: pod                # 发现所有 Pod
        pipeline_stages:             # 日志处理管道
          - docker: {}               # 解析 Docker JSON 日志
          - json:
              expressions:
                level: level
                msg: msg
                trace_id: trace_id
                span_id: span_id
          - labels:                  # 提取为 Loki 标签
              level:
              trace_id:
          - timestamp:
              source: timestamp
              format: RFC3339Nano
        relabel_configs:             # 标签重写配置
          - source_labels:
              - __meta_kubernetes_pod_label_app
            target_label: app
          - source_labels:
              - __meta_kubernetes_namespace
            target_label: namespace
          - source_labels:
              - __meta_kubernetes_pod_name
            target_label: pod
          - source_labels:
              - __meta_kubernetes_container_name
            target_label: container
          - source_labels:
              - __meta_kubernetes_pod_label_component
            target_label: component

      # K8s 节点日志采集
      - job_name: kubernetes-nodes
        kubernetes_sd_configs:
          - role: node
        pipeline_stages:
          - docker: {}
        relabel_configs:
          - source_labels:
              - __meta_kubernetes_node_name
            target_label: node
          - target_label: __path__
            replacement: /var/log/journal

# Gateway 配置 (单入口网关)
gateway:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/loki-gateway
    tag: 2.9.4
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
  service:
    type: ClusterIP            # 使用 ClusterIP 暴露网关
EOF
```

### 4.3 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n logging -o wide

# 预期输出:
# NAME                    READY   STATUS
# loki-0                  1/1     Running
# loki-gateway-xxxxx      1/1     Running
# promtail-xxxxx          1/1     Running  (每个节点一个)

# 检查 Service
kubectl get svc -n logging
```

### 4.4 配置 Grafana 连接 Loki

```bash
# 在 Grafana 中添加 Loki 数据源
# 方式1: 通过 Helm values（已在模块 06 中配置）
# 方式2: 通过 Grafana UI 手动添加

# 手动添加步骤:
# 1. 访问 Grafana: http://192.168.1.51:30000
# 2. Configuration -> Data Sources -> Add data source
# 3. 选择 Loki
# 4. URL: http://loki-gateway.logging.svc.cluster.local
# 5. Save & Test
```

### 4.5 LogQL 查询实战

#### 4.5.1 基础日志查询

```bash
# 查询指定命名空间的所有日志
{namespace="monitoring"}

# 查询指定 Pod 的日志
{namespace="monitoring", pod="prometheus-loki-0"}

# 模糊匹配 Pod 名称
{namespace="monitoring", pod=~"prometheus-.*"}

# 日志内容过滤（行过滤）
{namespace="monitoring"} |= "error"
{namespace="monitoring"} |= "error" |!= "debug"
{namespace="monitoring"} |~ "error|warn|fatal"

# 正则过滤
{app="nginx"} |~ "GET.*200"
```

#### 4.5.2 JSON 日志解析

```bash
# 解析 JSON 格式日志
{namespace="monitoring"} | json

# 提取 JSON 字段
{namespace="monitoring"} | json | level="error"

# 提取并显示特定字段
{namespace="monitoring"} | json | line_format "{{.timestamp}} {{.level}} {{.msg}}"

# 提取标签
{namespace="monitoring"} | json | label level method
```

#### 4.5.3 多行日志匹配（Java 异常栈）

```bash
# Java 异常栈匹配（多行模式）
{namespace="java-app", container="java-app"} |~ "(?s)Exception.*\\n.*at .*"

# 使用 multiline stage 处理
# 在 Promtail 配置中添加 multiline stage:
# pipeline_stages:
#   - multiline:
#       firstline: '^\d{4}-\d{2}-\d{2}'
#       max_wait_time: 3s
#       max_lines: 128

# 查询包含 Exception 的完整堆栈
{namespace="java-app"} |~ "Exception" |~ "at\\s+"

# 查询特定异常类型
{namespace="java-app"} |~ "NullPointerException|IOException|SQLException"
```

#### 4.5.4 日志转指标

```bash
# 计算错误日志数量（每5分钟）
count_over_time({namespace="monitoring"} |= "error" [5m])

# 计算错误率（百分比）
sum(rate({namespace="monitoring"} |= "error" [5m])) / sum(rate({namespace="monitoring"} [5m])) * 100

# 按命名空间统计错误数量
sum by (namespace) (count_over_time({namespace=~".*"} |= "error" [1h]))

# 计算 HTTP 5xx 数量
count_over_time({app="nginx"} |~ "HTTP/1.1 5[0-9]{2}" [5m])

# 按日志级别统计
sum by (level) (count_over_time({namespace="monitoring"} | json [5m]))
```

#### 4.5.5 日志解析和格式化

```bash
# 提取 IP 地址
{app="nginx"} | regexp "(?P<ip>\\d+\\.\\d+\\.\\d+\\.\\d+) .*"

# 替换敏感信息
{namespace="monitoring"} | replace "password=.*" "password=***"

# 丢弃不需要的日志
{namespace="monitoring"} | json | level="debug" | drop

# 保留特定条件的日志
{namespace="monitoring"} | json | level=~"error|fatal" | keep

# 提取时间范围
{namespace="monitoring"} | json | line_format "{{.timestamp}} [{{.level}}] {{.msg}}"
```

### 4.6 Promtail 多行日志配置

```bash
# 更新 Promtail 配置支持 Java 多行日志
cat > /root/promtail-multiline.yaml << 'EOF'
# Promtail 多行日志配置补丁
promtail:
  extraVolumes:
    - name: multiline-config
      configMap:
        name: promtail-multiline
  extraVolumeMounts:
    - name: multiline-config
      mountPath: /etc/promtail/multiline
EOF

# 创建 multiline 配置 ConfigMap
cat > /root/promtail-multiline-cm.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-multiline
  namespace: logging
data:
  multiline.yaml: |
    pipeline_stages:
      # Java 日志多行匹配
      - multiline:
          firstline: '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}'  # 首行匹配正则
          max_wait_time: 3s          # 等待后续行的最大时间
          max_lines: 256            # 单条日志最大行数
      # Python traceback 多行匹配
      - multiline:
          firstline: '^Traceback \\(most recent call last\\):'
          max_wait_time: 3s
          max_lines: 128
EOF

kubectl apply -f /root/promtail-multiline-cm.yaml
```

### 4.7 与 Prometheus 联动

#### 4.7.1 从日志生成指标（LogQL Metric）

```bash
# 在 Loki 中创建 Recording Rules
cat > /root/loki-rules.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-rules
  namespace: logging
  labels:
    loki_rule: "true"             # Loki Ruler 识别标签
data:
  alerting_rules.yaml: |
    groups:
      - name: log-alerts
        rules:
          # 高错误率告警
          - alert: HighErrorRate
            expr: |
              sum(rate({namespace=~".*"} |= "error" [5m])) by (namespace)
              / sum(rate({namespace=~".*"} [5m])) by (namespace) > 0.05
            for: 10m                # 持续 10 分钟触发
            labels:
              severity: warning
            annotations:
              summary: "命名空间 {{ $labels.namespace }} 错误率过高"
              description: "命名空间 {{ $labels.namespace }} 的错误率为 {{ $value | humanizePercentage }}"

          # OOMKilled 告警
          - alert: OOMKilled
            expr: |
              sum(count_over_time({namespace=~".*"} |= "OOMKilled" [5m])) by (namespace) > 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "命名空间 {{ $labels.namespace }} 检测到 OOMKilled"
              description: "命名空间 {{ $labels.namespace }} 中有 Pod 被 OOMKilled"

          # CrashLoopBackOff 告警
          - alert: CrashLoopBackOff
            expr: |
              sum(count_over_time({namespace=~".*"} |~ "Back-off|CrashLoop" [5m])) by (namespace) > 0
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "命名空间 {{ $labels.namespace }} 检测到 CrashLoopBackOff"
              description: "命名空间 {{ $labels.namespace }} 中有 Pod 处于 CrashLoopBackOff 状态"

          # Java 异常告警
          - alert: JavaException
            expr: |
              sum(count_over_time({namespace=~".*"} |~ "Exception|OutOfMemoryError" [5m])) by (namespace, pod) > 10
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} 检测到大量 Java 异常"
              description: "过去5分钟内检测到 {{ $value }} 个异常"
EOF

kubectl apply -f /root/loki-rules.yaml
```

#### 4.7.2 配置 Loki Ruler

```bash
# 在 Loki values.yaml 中启用 Ruler
# 确保 ruler 配置正确:
# ruler:
#   enable_api: true
#   enable_alertmanager: true
#   alertmanager_url: http://prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093

# 将规则目录挂载到 Loki（使用本地 Chart 包升级）
helm upgrade loki /root/charts/loki-stack-2.9.4.tgz \
    -n logging \
    -f /root/loki-values.yaml \
    --set loki.extraVolumes[0].name=rules \
    --set loki.extraVolumes[0].configMap.name=loki-rules \
    --set loki.extraVolumeMounts[0].name=rules \
    --set loki.extraVolumeMounts[0].mountPath=/loki/rules
```

#### 4.7.3 在 Grafana 中查看 Loki 告警

```bash
# 在 Grafana 中查看 Loki 告警
# 1. 访问 Grafana: http://192.168.1.51:30000
# 2. Alerting -> Alert Rules
# 3. 应看到来自 Loki 的告警规则
```

### 4.8 日志告警（通过 Alertmanager）

```bash
# Loki 的告警通过 Alertmanager 发送
# 确保 Loki Ruler 配置了正确的 Alertmanager URL

# 验证告警链路:
# 1. Loki Ruler 评估规则 -> 生成告警
# 2. 告警发送到 Alertmanager
# 3. Alertmanager 路由到企业微信

# 查看 Loki Ruler 状态
kubectl exec -n logging loki-0 -- wget -qO- http://localhost:3100/loki/api/v1/rules | jq

# 查看 Alertmanager 中的 Loki 告警
# 访问 http://192.168.1.51:9093
```

---

## 5. 配置详解

### 5.1 Loki 存储配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `store` | tsdb | 存储引擎（推荐 TSDB） |
| `object_store` | filesystem | 对象存储（filesystem/s3/gcs） |
| `schema` | v13 | Schema 版本 |
| `retention_period` | 168h | 日志保留时间（7天） |
| `compaction_interval` | 10m | 压缩间隔 |

### 5.2 Promtail 采集配置

| 配置项 | 说明 |
|--------|------|
| `kubernetes_sd_configs` | K8s 服务发现（role: pod/node/service） |
| `pipeline_stages` | 日志处理管道（json/regexp/multiline） |
| `relabel_configs` | 标签重写和过滤 |
| `clients` | Loki 推送地址 |

### 5.3 LogQL 语法速查

| 语法 | 说明 | 示例 |
|------|------|------|
| `\|=` | 包含 | `{app="nginx"} \|= "error"` |
| `\|!=` | 不包含 | `{app="nginx"} \|!= "debug"` |
| `\|~` | 正则匹配 | `{app="nginx"} \|~ "5[0-9]{2}"` |
| `\|!~` | 正则不匹配 | `{app="nginx"} \|!~ "health"` |
| `\| json` | JSON 解析 | `{app="api"} \| json` |
| `\| regexp` | 正则提取 | `{app="nginx"} \| regexp "(?P<ip>\\d+)"` |
| `\| line_format` | 格式化输出 | `\| line_format "{{.msg}}"` |
| `\| label` | 提取为标签 | `\| json \| label level` |
| `\| drop` | 丢弃日志 | `\| json \| level="debug" \| drop` |

---

## 6. 验证与测试

### 6.1 验证日志采集

```bash
# 创建测试 Pod 产生日志
kubectl run log-test --image=192.168.1.61/k8s/busybox:latest -n logging \
    --command -- sh -c 'i=0; while true; do echo "{\"level\":\"info\",\"msg\":\"test log $i\",\"timestamp\":\"$(date -Iseconds)\"}"; i=$((i+1)); sleep 2; done'

# 等待 30 秒后，在 Grafana 中查询
# {namespace="logging", pod="log-test"}

# 验证 Promtail 是否采集到日志
kubectl logs -n logging -l app.kubernetes.io/name=promtail --tail=20 | grep log-test
```

### 6.2 验证 LogQL 查询

```bash
# 在 Grafana Explore 中测试以下查询:

# 1. 查看所有命名空间的日志
{namespace=~".*"} | json

# 2. 过滤错误日志
{namespace=~".*"} | json | level="error"

# 3. 统计错误数量
count_over_time({namespace=~".*"} |= "error" [1h])

# 4. 按命名空间统计
sum by (namespace) (count_over_time({namespace=~".*"} |= "error" [1h]))
```

### 6.3 验证多行日志

```bash
# 创建 Java 应用模拟日志
kubectl run java-log-test --image=192.168.1.61/k8s/busybox:latest -n logging \
    --command -- sh -c '
while true; do
echo "2024-01-15 10:30:00.123 ERROR [main] c.e.App - NullPointerException occurred"
echo "java.lang.NullPointerException"
echo "    at com.example.App.process(App.java:42)"
echo "    at com.example.App.run(App.java:28)"
echo "    at java.lang.Thread.run(Thread.java:829)"
echo "---"
sleep 5
done'

# 在 Grafana 中查询
{namespace="logging", pod="java-log-test"} |~ "NullPointerException"
```

### 6.4 验证日志告警

```bash
# 创建产生大量错误的 Pod 触发告警
kubectl run error-pod --image=192.168.1.61/k8s/busybox:latest -n logging \
    --command -- sh -c 'while true; do echo "{\"level\":\"error\",\"msg\":\"connection timeout\"}"; sleep 1; done'

# 检查 Loki Ruler 状态
kubectl exec -n logging loki-0 -- wget -qO- http://localhost:3100/loki/api/v1/rules | jq

# 检查 Alertmanager
# 访问 http://192.168.1.51:9093
# 应看到 HighErrorRate 告警

# 清理
kubectl delete pod log-test java-log-test error-pod -n logging
```

---

## 7. CKA/CKS 考点融入

### 7.1 CKA 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 日志查看 | kubectl logs 查看容器日志 | 6.1 节 |
| 日志排查 | 通过日志定位 Pod 问题 | 4.5 节 |

### 7.2 CKS 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 审计日志 | 收集和分析 API Server 审计日志 | 4.5 节 |
| 安全告警 | 通过日志检测异常行为 | 4.7 节 |

---

## 8. 高频面试题

### Q1: Loki 和 ELK 有什么区别？如何选择？ [难度: 中]

**答案：** Loki 和 ELK 是两种不同理念的日志系统。Loki 的核心设计思想是"只索引元数据（Labels），不索引日志内容"。这意味着 Loki 的存储成本极低（只有 Label 索引 + 原始日志），查询时先通过 Label 过滤定位到日志流，再在日志流中做全文搜索。缺点是不支持高效的全文索引搜索，大规模日志的全文查询性能不如 ELK。ELK（Elasticsearch + Logstash + Kibana）使用倒排索引对日志内容进行全文索引，支持高效的全文搜索、模糊匹配和复杂聚合。缺点是存储成本高（索引通常是原始数据的 2-3 倍）、资源消耗大（ES 需要大量内存和 CPU）、运维复杂度高。选择建议：如果日志主要用于故障排查（通过 Label 过滤 + 关键词搜索），选择 Loki（成本低、运维简单）；如果需要复杂的全文搜索、日志分析和报表，选择 ELK。在 Kubernetes 环境中，Loki 与 Grafana 深度集成，部署和运维成本远低于 ELK，是目前 K8s 日志的主流选择。

### Q2: Promtail 的工作原理是什么？如何配置日志采集？ [难度: 中]

**答案：** Promtail 是 Loki 的日志采集 Agent，以 DaemonSet 形式运行在每个节点上。工作流程为：首先通过 Kubernetes Service Discovery（kubernetes_sd_configs）自动发现节点上的 Pod 和容器；然后根据发现结果确定需要采集的日志文件路径（`/var/log/pods/<namespace>_<pod>_<container>/*.log`）；接着通过 Pipeline Stages 对日志进行预处理（JSON 解析、正则提取、标签提取、多行合并等）；最后将处理后的日志推送到 Loki。Promtail 的核心配置包括 `scrape_configs`（定义采集目标和处理管道）、`clients`（定义 Loki 推送地址）、`relabel_configs`（标签重写和过滤）。Promtail 支持多种服务发现角色：pod（发现所有 Pod 的容器日志）、node（发现节点日志）、service（发现 Service 关联的 Pod）。在 K8s 环境中，Promtail 通过读取 `/var/log/pods/` 目录下的符号链接文件来采集容器日志，这些符号链接由 kubelet 创建，指向 containerd 的日志目录。

### Q3: LogQL 的常用操作符有哪些？如何实现复杂的日志查询？ [难度: 中]

**答案：** LogQL 是 Loki 的查询语言，分为日志查询和指标查询两类。日志查询操作符包括：行过滤（`\|=` 包含、`\|!=` 不包含、`\|~` 正则匹配、`\|!~` 正则不匹配）、解析器（`\| json` 解析 JSON、`\| logfmt` 解析键值对、`\| regexp` 正则提取）、格式化（`\| line_format` Go 模板格式化）、标签操作（`\| label` 提取字段为标签、`\| drop` 丢弃日志、`\| keep` 保留日志）。指标查询函数包括：`count_over_time()`（时间窗口内日志计数）、`rate()`（每秒日志速率）、`bytes_rate()`（每秒日志字节数）、`sum()`/`avg()`/`max()`/`min()`（聚合函数）。复杂查询示例：`{namespace="prod", app=~"api-.*"} | json | level="error" | regexp "(?P<method>\\w+) (?P<path>\\S+) (?P<status>\\d+)" | status >= "500" | line_format "{{.timestamp}} {{.method}} {{.path}} {{.status}}"`。这个查询从 prod 命名空间的 api Pod 中提取 JSON 日志，过滤错误级别，正则提取 HTTP 方法和路径，过滤 5xx 状态码，最后格式化输出。

### Q4: 如何处理 Java 多行日志（异常栈）？ [难度: 高]

**答案：** Java 异常栈是多行日志的典型场景，一条异常包含多行（异常信息 + 堆栈跟踪），如果不做处理，Promtail 会将每行作为独立的日志条目，导致异常栈被拆散。解决方案是在 Promtail 的 Pipeline Stages 中配置 `multiline` stage。multiline stage 通过 `firstline` 正则表达式识别日志的第一行（如时间戳开头的行），后续行直到下一个匹配 firstline 的行都属于同一条日志。配置示例：`multiline: { firstline: "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}" }`。关键参数：`max_wait_time`（等待后续行的最大时间，默认 3 秒，超时后强制发送）、`max_lines`（单条日志的最大行数，默认 128 行，防止内存溢出）。对于不同的日志格式，firstline 正则需要调整：Java Logback 使用时间戳开头，Python traceback 使用 `Traceback (most recent call last):` 开头，Go error 使用 `goroutine` 开头。配置完成后，在 Grafana 中查询异常时，整个堆栈会作为一条日志显示。

### Q5: Loki 如何与 Prometheus 联动？如何实现日志告警？ [难度: 高]

**答案：** Loki 与 Prometheus 的联动有两种方式。方式一：通过 Grafana 统一查询。在 Grafana Dashboard 中，可以同时使用 Prometheus 数据源（查询指标）和 Loki 数据源（查询日志），通过模板变量联动（如点击 Prometheus 面板中的异常 Pod，自动跳转到 Loki 查看该 Pod 的日志）。方式二：通过 Loki Ruler 实现日志告警。Loki Ruler 内置了告警引擎，使用 LogQL 定义告警规则，当 LogQL 查询结果满足条件时触发告警。告警可以发送到 Alertmanager（与 Prometheus 告警统一管理），也可以发送到 webhook。配置步骤：在 Loki 配置中启用 Ruler（`ruler.enable_api: true`、`ruler.enable_alertmanager: true`、`ruler.alertmanager_url`），创建告警规则 YAML（定义 LogQL 表达式、阈值、持续时间、标签和注解），将规则挂载到 Loki Pod。Loki Ruler 会定期评估规则，触发告警后发送到 Alertmanager，由 Alertmanager 负责路由、分组和通知。此外，Prometheus 的 `loki.rules` 可以通过 PromQL 查询 Loki 的指标（通过 Loki 的 `/loki/api/v1/rules` API），实现跨系统的联合告警。

### Q6: Loki 的存储架构是怎样的？如何实现长期存储？ [难度: 高]

**答案：** Loki 的存储架构分为索引（Index）和数据（Chunks）两部分。索引存储 Labels 到 Chunk 的映射关系，数据存储实际的日志内容。Loki v2.x 支持两种存储模式：Single Binary（单进程模式，所有组件运行在一个进程中）和 Microservices（微服务模式，Ingester、Querier、Compactor、Ruler 等组件独立部署）。在存储层面，Loki v2.9+ 使用 TSDB 引擎，数据以 Chunk 为单位存储，每个 Chunk 包含一个时间窗口内同一日志流的数据。Chunk 先写入 WAL（Write-Ahead Log），然后刷盘为持久化文件。Compactor 负责合并小 Chunk、删除过期数据和清理标记删除的数据。长期存储方案：Loki 支持将 Chunk 存储到对象存储（S3/MinIO/GCS/Azure Blob），将索引存储到 BoltDB（本地）或 DynamoDB/BigTable（云服务）。使用对象存储后，Loki 可以实现几乎无限的存储容量。生产环境推荐使用 MinIO 作为本地对象存储，配置 `storage_config` 的 `aws` 或 `s3` 部分。数据保留通过 `limits_config.retention_period` 控制，Loki 会自动删除过期数据。

### Q7: 如何优化 Loki 的查询性能？ [难度: 高]

**答案：** Loki 查询性能优化需要从多个维度入手。Label 优化：减少高基数标签（如 user_id、request_id），这些标签会导致大量的日志流和索引膨胀；使用 `| json | label` 时只提取必要的字段作为标签；使用 `| drop` 过滤不需要的日志。查询优化：使用精确的 Label 过滤（`{namespace="prod"}` 而不是 `{namespace=~".*"}`），减少扫描的日志流数量；使用 `|=` 行过滤尽早缩小结果集；避免在大量日志流上执行全文搜索。架构优化：使用微服务模式分离 Ingester 和 Querier，避免读写互相影响；使用 Query Frontend 缓存查询结果（`query_scheduler.max_outstanding_per_tenant`）；使用 Query Splitter 并行查询。存储优化：使用对象存储（S3/MinIO）替代本地存储；启用 Compactor 定期压缩 Chunk；调整 `chunk_target_size`（默认 1.5MB）和 `chunk_idle_period`（默认 30m）参数。监控优化：监控 Loki 的 `loki_ingester_flush_duration_seconds`（刷盘延迟）、`loki_query_range_duration_seconds`（查询延迟）和 `loki_request_duration_seconds`（请求延迟）指标。

### Q8: Promtail 的 Pipeline Stages 有哪些？如何实现日志脱敏？ [难度: 中]

**答案：** Promtail 的 Pipeline Stages 是日志处理的核心，支持以下阶段：`docker`（解析 Docker JSON 日志格式）、`cri`（解析 CRI 日志格式）、`json`（解析 JSON 日志并提取字段）、`logfmt`（解析 logfmt 格式）、`regexp`（正则表达式提取字段）、`multiline`（多行日志合并）、`label`（将提取的字段设为 Label）、`timestamp`（设置日志时间戳）、`replace`（替换日志内容）、`drop`（丢弃匹配的日志）、`keep`（保留匹配的日志）、`line_format`（格式化输出）、`metrics`（从日志生成指标）、`output`（发送到额外目标）。日志脱敏实现：使用 `replace` stage 替换敏感信息。例如：`replace: { expression: "password=[^\\s]+" }` 替换为 `password=***`。更复杂的脱敏可以使用 `regexp` stage 提取敏感字段，然后用 `replace` 替换。还可以使用 `mask` stage（Promtail 2.5+）直接遮蔽匹配的内容。注意：脱敏操作应该在日志采集的早期阶段执行（在 `| json` 解析之后），避免敏感信息被存储到 Loki 中。

### Q9: 如何实现基于日志的自动扩缩容？ [难度: 高]

**答案：** 基于日志的自动扩缩容（Log-based HPA）需要将日志数据转换为 K8s Metrics API 可识别的指标。实现方案有两种。方案一：使用 Loki + Prometheus + Prometheus Adapter。Loki Ruler 将 LogQL 查询结果作为指标暴露（`loki_rules_errors_total` 等），Prometheus 采集这些指标，Prometheus Adapter 将其转换为 K8s 自定义指标 API，HPA Controller 查询自定义指标进行扩缩容。方案二：使用自定义指标服务。开发一个 Metric Server，定期查询 Loki API 获取日志指标，暴露为 K8s Metrics API。方案三：使用 Grafana Mimir/Loki 的 ruler 指标。Loki Ruler 评估的告警规则结果会作为 Prometheus 指标暴露（`loki_rule_errors_total`、`loki_rule_evaluation_duration_seconds`），可以直接被 Prometheus 采集。实际应用场景：根据错误日志数量扩缩容（错误率超过阈值时扩容）、根据请求延迟日志扩缩容、根据特定业务事件扩缩容。需要注意的是，日志指标的延迟较高（通常 1-5 分钟），不适合需要快速响应的扩缩容场景。

### Q10: 如何排查 Loki 日志丢失的问题？ [难度: 中]

**答案：** Loki 日志丢失的排查步骤为：首先确认 Promtail 是否正常运行：`kubectl get pods -n logging -l app.kubernetes.io/name=promtail`，检查所有节点都有 Promtail Pod 运行。然后检查 Promtail 日志：`kubectl logs -n logging -l app.kubernetes.io/name=promtail --tail=50`，关注 `connection refused`、`timeout`、`error` 等关键词。接着检查 Promtail 到 Loki 的连通性：`kubectl exec -n logging <promtail-pod> -- wget -qO- http://loki.logging.svc.cluster.local:3100/ready`。然后检查 Loki 的存储空间：`kubectl exec -n logging loki-0 -- df -h /loki/chunks`，确认磁盘未满。接着检查 Loki 的拒绝策略：`limits_config.reject_old_samples` 如果为 true，延迟到达的日志会被丢弃。然后检查 Promtail 的 `positions.yaml`（记录采集进度），确认 Promtail 没有重复读取或跳过日志。最后检查 containerd 日志轮转配置，确认日志文件没有被过早清理。常见原因包括：Promtail OOM 被重启（丢失 positions）、Loki 磁盘满、网络问题导致推送失败、日志文件被轮转删除。

### Q11: 如何在 Grafana 中实现日志和指标的联动分析？ [难度: 中]

**答案：** Grafana 中实现日志和指标联动分析有几种方式。方式一：使用 Grafana 的 Data Links 功能。在 Prometheus Dashboard 面板中配置 Data Link，点击面板中的数据点时自动跳转到 Loki 查询对应的日志。配置示例：`${__data.fields}` 中选择对应的 Label（如 namespace、pod），Data Link URL 为 `explore?left={"datasource":"loki","queries":[{"expr":"{namespace=\\"${namespace}\\",pod=\\"${pod}\\"}"}]}`。方式二：使用 Grafana 的 Template Variables。创建一个变量（如 `pod`），数据源选择 Prometheus，查询 `label_values(kube_pod_info, pod)`，然后在 Loki 面板中使用 `${pod}` 变量。方式三：使用 Grafana 的 Mixed Data Source 面板。在一个 Dashboard 中同时使用 Prometheus 和 Loki 数据源，通过变量联动。方式四：使用 Grafana 的 Trace to Logs 功能（需要 Tempo/Jaeger 集成）。从 Trace 视图直接跳转到对应的日志。推荐使用方式一和方式二，实现简单且效果最好，可以在 Prometheus 面板中一键跳转到 Loki 查看详细日志。

### Q12: Loki 的多租户模式是如何工作的？ [难度: 高]

**答案：** Loki 的多租户模式通过 Tenant ID 隔离不同租户的日志数据。在多租户模式下，每个租户有独立的日志流、索引和存储空间，租户之间完全隔离。Tenant ID 通过 HTTP Header `X-Scope-OrgID` 传递。Promtail 推送日志时，可以在 `clients` 配置中指定 `tenant_id`，不同命名空间或不同团队可以使用不同的 Tenant ID。Loki 存储层面，每个租户的数据存储在独立的目录/前缀下（如 `tenant1/index/`、`tenant1/chunks/`），查询时只能访问自己租户的数据。权限控制通过 `auth_enabled: true` 启用，配合 `basic_auth` 或 `OAuth2` 认证。在 Helm 针对多租户部署时，可以为每个租户创建独立的 Promtail DaemonSet，配置不同的 `tenant_id`。Loki Ruler 也支持多租户，每个租户可以定义自己的告警规则。多租户模式的注意事项：Tenant ID 不能包含特殊字符；每个租户的资源使用（存储空间、查询速率）需要通过 `limits_config` 中的 `per_tenant_override_config` 进行限制；多租户模式会增加运维复杂度，建议在明确需要租户隔离时启用。

---

## 9. 故障排查案例

### 案例 1: Promtail 无法采集 Pod 日志

**现象：**
```bash
# Grafana 中查询不到某些 Pod 的日志
{namespace="monitoring", pod="my-app"}
# No results
```

**排查步骤：**
1. 检查 Promtail Pod 状态：`kubectl get pods -n logging -l app.kubernetes.io/name=promtail`
2. 检查 Promtail 日志：`kubectl logs -n logging -l app.kubernetes.io/name=promtail --tail=50`
3. 检查目标 Pod 的日志文件：`kubectl exec -n logging <promtail-pod> -- ls /var/log/pods/monitoring_my-app-*/`

**解决方案：**
```bash
# 常见原因1: Pod 标签不匹配 Promtail 的 relabel_configs
# 检查 Pod 标签
kubectl get pod my-app -n monitoring --show-labels

# 常见原因2: 日志文件权限问题
kubectl exec -n logging <promtail-pod> -- ls -la /var/log/pods/

# 常见原因3: Promtail 的 positions.yaml 损坏
# 删除 positions 文件让 Promtail 重新扫描
kubectl exec -n logging <promtail-pod> -- rm /var/log/positions.yaml
kubectl delete pod -n logging -l app.kubernetes.io/name=promtail

# 常见原因4: containerd 日志驱动不是 JSON
# 检查 containerd 配置
cat /etc/containerd/config.toml | grep -A5 "sandbox_image"
```

### 案例 2: Loki 存储空间不足

**现象：**
```bash
kubectl exec -n logging loki-0 -- df -h /loki/chunks
# /loki/chunks   50G   49G   1G   98% Full

# Loki 日志报错:
# "context deadline exceeded"
# "no space left on device"
```

**排查步骤：**
1. 检查日志量：`kubectl exec -n logging loki-0 -- du -sh /loki/chunks/*`
2. 检查保留策略：`kubectl exec -n logging loki-0 -- cat /etc/loki/config.yaml | grep retention`
3. 检查 Compactor 状态

**解决方案：**
```bash
# 方案1: 手动触发 Compaction
kubectl exec -n logging loki-0 -- wget -qO- http://localhost:3100/compactor/run

# 方案2: 调整保留策略（缩短保留时间）
# 在 values.yaml 中修改:
# limits_config:
#   retention_period: 72h  (从 168h 缩短到 72h)

# 方案3: 扩大 PVC
kubectl edit pvc -n logging <loki-pvc>
# 或者修改 values.yaml 中的 persistence.size

# 方案4: 清理旧数据
kubectl exec -n logging loki-0 -- wget -qO- \
    "http://localhost:3100/loki/api/v1/delete?query=%7Bnamespace%3D%22default%22%7D&start=1700000000000000000&end=1700100000000000000"

# 升级 Helm release
helm upgrade loki /root/charts/loki-stack-2.9.4.tgz -n logging -f /root/loki-values.yaml
```

### 案例 3: LogQL 查询超时

**现象：**
```
Grafana 中执行 LogQL 查询时超时
"query timed out after 60s"
```

**排查步骤：**
1. 检查查询范围是否过大：是否选择了过长的时间范围
2. 检查 Label 过滤是否精确：`{namespace=~".*"}` 会扫描所有日志流
3. 检查 Loki 查询延迟：`kubectl exec -n logging loki-0 -- wget -qO- http://localhost:3100/metrics | grep loki_query`

**解决方案：**
```bash
# 方案1: 缩小查询范围
# 使用精确的 Label 过滤
{namespace="monitoring", pod="my-app"} |= "error"

# 方案2: 增加查询超时时间
# 在 Loki values.yaml 中:
# limits_config:
#   max_query_length: 0  # 不限制查询时间范围
#   query_timeout: 300s  # 增加查询超时到 5 分钟

# 方案3: 使用更精确的行过滤
# 先用 |= 缩小范围，再做全文搜索
{namespace="monitoring"} |= "error" |~ "NullPointerException"

# 方案4: 减少 Label 数量
# 避免使用过多的高基数 Label
```

### 案例 4: Promtail OOMKilled

**现象：**
```bash
kubectl get pods -n logging -l app.kubernetes.io/name=promtail
# promtail-xxxxx   1/1     Running     3          10m
# Last State: Terminated, Reason: OOMKilled
```

**排查步骤：**
1. 检查 Promtail 内存使用：`kubectl top pods -n logging -l app.kubernetes.io/name=promtail`
2. 检查是否有超大日志文件：`kubectl exec -n logging <promtail-pod> -- du -sh /var/log/pods/*/*`
3. 检查 multiline 配置是否合理

**解决方案：**
```bash
# 方案1: 增加 Promtail 内存限制
# 在 values.yaml 中:
# promtail:
#   resources:
#     limits:
#       memory: 1Gi  (从 512Mi 增加)

# 方案2: 优化 multiline 配置
# 减小 max_lines 和 max_wait_time
# multiline:
#   max_lines: 64     (从 256 减小)
#   max_wait_time: 1s (从 3s 减小)

# 方案3: 使用 drop 过滤不需要的日志
# 在 pipeline_stages 中添加:
# - drop:
#     source: level
#     expression: "debug|trace"

# 方案4: 排除特定命名空间
# 在 relabel_configs 中添加:
# - source_labels: [__meta_kubernetes_namespace]
#   regex: "kube-system"
#   action: drop
```

### 案例 5: Loki 和 Grafana 连接失败

**现象：**
```
Grafana 数据源测试报错:
"Failed to connect to Loki: 502 Bad Gateway"
```

**排查步骤：**
1. 检查 Loki Service：`kubectl get svc -n logging`
2. 检查 Loki Pod 状态：`kubectl get pods -n logging -l app.kubernetes.io/name=loki`
3. 检查网络策略：`kubectl get networkpolicy -n logging -A`
4. 测试连通性：`kubectl exec -n monitoring deploy/prometheus-stack-grafana -- curl -s http://loki.logging.svc.cluster.local:3100/ready`

**解决方案：**
```bash
# 常见原因1: Loki Service 名称错误
# 检查实际 Service 名称
kubectl get svc -n logging
# 如果使用 gateway，URL 应为:
# http://loki-gateway.logging.svc.cluster.local

# 常见原因2: 网络策略阻止
# 创建允许 Grafana 访问 Loki 的 NetworkPolicy
cat > /root/grafana-loki-np.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy             # K8s 网络策略资源
metadata:
  name: allow-grafana-to-loki
  namespace: logging
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: loki
  policyTypes:
    - Ingress                    # 入站规则
  ingress:
    - from:
        - namespaceSelector:     # 命名空间选择器
            matchLabels:
              name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - port: 3100             # Loki 监听端口
EOF
kubectl apply -f /root/grafana-loki-np.yaml

# 常见原因3: Loki 未就绪
kubectl logs -n logging -l app.kubernetes.io/name=loki --tail=50
```

### 案例 6: 日志时间戳不正确

**现象：**
```
Grafana 中显示的日志时间与实际时间不一致
日志显示为未来时间或过去时间
```

**排查步骤：**
1. 检查节点时间：`timedatectl` 确认时间同步
2. 检查 Promtail 的 timestamp stage 配置
3. 检查应用日志的时间戳格式

**解决方案：**
```bash
# 常见原因1: 应用日志使用 UTC 时间，而 Loki 使用本地时间
# 在 Promtail pipeline 中添加 timestamp stage:
# pipeline_stages:
#   - json:
#       expressions:
#         ts: timestamp
#   - timestamp:
#       source: ts
#       format: RFC3339

# 常见原因2: 节点时间不同步
# 检查所有节点的时间
for node in 51 52 53 54 55; do
    echo "192.168.1.${node}: $(ssh root@192.168.1.${node} date)"
done

# 修复时间同步
systemctl restart chrony

# 常见原因3: Promtail 使用了错误的日志时间戳
# 默认 Promtail 使用容器运行时的时间戳
# 如果应用日志有自己的时间戳，需要显式配置
# pipeline_stages:
#   - timestamp:
#       source: timestamp
#       format: "2006-01-02T15:04:05.000Z"
```

---

## 10. 生产环境建议

### 10.1 架构建议

1. **微服务模式**：生产环境建议使用 Loki 微服务模式（Ingester/Querier/Compactor/Ruler 分离部署）
2. **对象存储**：使用 MinIO/S3 作为 Chunk 存储，支持无限扩展
3. **高可用**：Loki 至少 2 副本，Promtail DaemonSet 确保每个节点运行
4. **资源规划**：Loki 2C4G 起步（根据日志量调整），Promtail 256MB-512MB

### 10.2 日志规范

1. **统一格式**：所有应用使用 JSON 格式输出日志，包含 level、msg、timestamp、trace_id 等标准字段
2. **日志级别**：统一使用 DEBUG/INFO/WARN/ERROR/FATAL 五个级别
3. **避免敏感信息**：不在日志中输出密码、Token 等敏感信息
4. **结构化日志**：使用结构化日志库（如 logrus、zap），便于解析和查询
5. **日志轮转**：配置 containerd 日志轮转（max-size: 100M, max-file: 5）

### 10.3 性能优化

1. **Label 优化**：只保留必要的 Label（namespace、pod、app、container），避免高基数标签
2. **Pipeline 优化**：尽早使用 `drop` 过滤不需要的日志，减少 Loki 存储压力
3. **查询优化**：使用精确的 Label 过滤 + 行过滤，避免全文搜索
4. **Compaction**：定期执行 Compaction，合并小 Chunk
5. **缓存**：使用 Query Frontend 缓存查询结果

### 10.4 运维管理

1. **监控**：通过 Prometheus 监控 Loki 指标（ingestion_rate、query_duration、chunk_utilization）
2. **告警**：配置 Loki 日志告警规则（错误率、OOMKilled、CrashLoopBackOff）
3. **容量规划**：监控日志增长速率，提前规划存储扩容
4. **备份**：定期备份 Loki 的 Index 数据（如果使用本地存储）
5. **升级**：Loki 版本升级时注意 Schema 迁移，提前备份

---

> **课程完成！** 恭喜你完成了全部 7 个云原生课程模块的学习。
> 你已经掌握了从环境准备到监控日志的完整 Kubernetes 云原生技术栈。
