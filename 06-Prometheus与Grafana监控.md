# 模块06：Prometheus 与 Grafana 监控

---

## 1. 概述与架构图

### 1.1 课程目标

本模块全面讲解 Kubernetes 监控体系，基于 Prometheus（开源监控告警系统）+ Grafana（可视化面板）构建完整的监控平台。涵盖 Prometheus 四种指标类型、PromQL（Prometheus 查询语言）、kube-prometheus-stack（K8s 监控全家桶 Helm Chart）Helm 部署、自定义告警规则（企业微信）、HPA（水平自动扩缩容）集成、KEDA（事件驱动自动伸缩）以及 Grafana Dashboard 配置。完成本模块后，你将具备搭建生产级 K8s 监控系统的能力。

### 1.2 监控架构图

```
  +------------------------------------------------------------------+
  |                    Kubernetes Cluster                             |
  +------------------------------------------------------------------+
       |              |              |              |
  +----+----+   +-----+-----+  +----+----+  +----+----+
  | kubelet  |   |  Pod A    |  |  Pod B   |  |  Pod C  |
  | /metrics |   | /metrics  |  | /metrics |  | /metrics|
  | (cAdvisor)|   | (app)     |  | (app)    |  | (app)   |
  +----+----+   +-----+-----+  +----+----+  +----+----+
       |              |              |              |
       +--------------+--------------+--------------+
                            |
                    +-------+-------+
                    | Prometheus    |
                    | (Scrape +     |
                    |  Store +      |
                    |  Alert)       |
                    +-------+-------+
                            |
              +-------------+-------------+
              |             |             |
     +--------+------+  +--+--------+  +-+----------+
     | Alertmanager  |  | Grafana   |  | Thanos/    |
     | (告警路由/    |  | (可视化)   |  | VictoriaMetrics|
     |  分组/抑制)   |  |           |  | (长期存储)   |
     +--------+------+  +-----+----+  +-------------+
              |
     +--------+------+
     | 企业微信/钉钉  |
     | 邮件/PagerDuty|
     +---------------+
```

### 1.3 kube-prometheus-stack 组件架构

```
  +------------------------------------------------------------------+
  |              kube-prometheus-stack (Helm Chart)                    |
  +------------------------------------------------------------------+
  |                                                                   |
  |  +-------------------+  +-------------------+                     |
  |  |    Prometheus     |  |    Prometheus     |                     |
  |  |    (StatefulSet)  |  |    (StatefulSet)  |                     |
  |  |    - TSDB         |  |    - TSDB         |                     |
  |  |    - PromQL       |  |    - PromQL       |                     |
  |  |    - Alerting     |  |    - Alerting     |                     |
  |  +-------------------+  +-------------------+                     |
  |                                                                   |
  |  +-------------------+  +-------------------+                     |
  |  |   Alertmanager    |  |   Alertmanager    |                     |
  |  |   (StatefulSet)   |  |   (StatefulSet)   |                     |
  |  |   - 路由          |  |   - 路由          |                     |
  |  |   - 分组          |  |   - 分组          |                     |
  |  |   - 抑制          |  |   - 抑制          |                     |
  |  +-------------------+  +-------------------+                     |
  |                                                                   |
  |  +-------------------+  +-------------------+  +---------------+ |
  |  |   Grafana         |  | node-exporter     |  | kube-state-   | |
  |   (Deployment)      |  | (DaemonSet)        |  | metrics       | |
  |   - Dashboard       |  | - CPU/Memory/Disk  |  | (Deployment)  | |
  |   - 数据源          |  | - Network/FS       |  | - Pod/Node/   | |
  |   - 告警通知        |  |                    |  |   Deployment  | |
  |  +-------------------+  +-------------------+  +---------------+ |
  |                                                                   |
  |  +-------------------+  +-------------------+                     |
  |  | prometheus-       |  | kubelet           |                     |
  |  | adapter           |  | cAdvisor          |                     |
  |  | (HPA 指标适配)    |  | (容器指标)         |                     |
  |  +-------------------+  +-------------------+                     |
  +------------------------------------------------------------------+
```

### 1.4 四种 Metric 类型

```
  Counter (计数器)                    Gauge (仪表盘)
  +----+----+----+----+              +----+----+----+----+
  |    |    |    |    |              |  /\    /\    /\  |
  |    |    |    |    |              | /  \  /  \  /  \ |
  +----+----+----+----+              |/    \/    \/    \|
  只增不减 (单调递增)                  可增可减 (当前值)

  Histogram (直方图)                 Summary (摘要)
  +----+----+----+----+              +----+----+----+----+
  |##  |##  |#   |    |              | p50| p90| p99|    |
  |##  |##  |##  |#   |              | 5ms| 20ms|100ms|   |
  |##  |##  |##  |##  |              +----+----+----+----+
  +----+----+----+----+
  桶分布 + 总计数 + 总和              分位数 + 总计数 + 总和
```

---

## 2. 理论基础

### 2.1 Prometheus 四种 Metric 类型

| 类型 | 说明 | 示例 | 操作 |
|------|------|------|------|
| **Counter**（计数器） | 只增不减的计数器 | `http_requests_total` | `rate()`、`increase()` |
| **Gauge**（仪表盘） | 可增可减的当前值 | `node_memory_available_bytes` | 直接使用、`avg()`、`max()` |
| **Histogram**（直方图） | 分布统计（桶计数） | `http_request_duration_seconds_bucket` | `histogram_quantile()`、`rate()` |
| **Summary**（摘要） | 客户端计算的分位数 | `http_request_duration_seconds` | 直接使用分位数 |

### 2.2 PromQL 核心函数

| 函数 | 说明 | 示例 |
|------|------|------|
| `rate()` | 计算每秒平均增长率 | `rate(http_requests_total[5m])` |
| `increase()` | 计算时间范围内的增量 | `increase(http_requests_total[1h])` |
| `histogram_quantile()` | 计算分位数（P50/P95/P99） | `histogram_quantile(0.99, rate(..._bucket[5m]))` |
| `avg()` | 计算平均值 | `avg(node_cpu_seconds_total)` |
| `sum()` | 计算总和 | `sum(container_memory_usage_bytes)` |
| `topk()` | 取前 K 个 | `topk(5, rate(http_requests_total[5m]))` |
| `by()` | 按标签分组聚合 | `sum by (namespace) (container_memory_usage_bytes)` |
| `offset()` | 时间偏移查询 | `rate(cpu[5m] offset 1w)` |

### 2.3 告警规则级别

| 级别 | 说明 | 响应时间 |
|------|------|---------|
| **critical** | 严重故障，需要立即处理 | < 5 分钟 |
| **warning** | 潜在问题，需要关注 | < 30 分钟 |
| **info** | 信息通知 | 工作时间处理 |

---

## 3. 部署实战

### 3.1 离线前置准备

> **说明：** 本集群为离线环境（无外网），所有安装操作需提前准备好离线资源。请参考 `00-基础设施准备.md` 中的离线 Helm 指南完成 Helm 的离线安装。

#### 3.1.1 确认 StorageClass 已部署

```bash
# 确认 local-path StorageClass 已就绪
kubectl get sc
# 预期输出:
# NAME         PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
# local-path   rancher.io/local-path   Delete          WaitForFirstConsumer

# 如果未部署，参考 00-基础设施准备.md 安装 local-path-provisioner
```

#### 3.1.2 确认 Helm 已离线安装

```bash
# 确认 Helm 已安装（离线方式）
helm version
# 预期输出: version.BuildInfo{...}

# 如果未安装，参考 00-基础设施准备.md 中的离线 Helm 安装指南
```

#### 3.1.3 离线准备 kube-prometheus-stack Helm Chart

```bash
# 在有网络的机器上下载 Chart 包（版本号根据实际需求调整）
helm pull prometheus-community/kube-prometheus-stack --version 56.6.2

# 将下载的 kube-prometheus-stack-56.6.2.tgz 传输到 Master-1 节点
# 例如通过 scp:
# scp kube-prometheus-stack-56.6.2.tgz root@192.168.1.51:/root/
```

#### 3.1.4 需要预推送到 Harbor 的镜像清单

以下镜像需要提前推送到 Harbor（`192.168.1.61`），请参考 `sync_images.sh` 脚本同步镜像。Harbor 登录密码为 `Harbor12345`。

```bash
# 登录 Harbor
docker login 192.168.1.61 -u admin -p Harbor12345

# kube-prometheus-stack 所需镜像清单（版本号根据 Chart 版本调整）
# 格式: 原始镜像 -> Harbor 目标镜像

# Prometheus Operator（K8s 中管理 Prometheus 的控制器）
quay.io/prometheus-operator/prometheus-operator:v0.70.0
# -> 192.168.1.61/k8s/prometheus-operator:v0.70.0

# Prometheus（监控数据采集与存储引擎）
quay.io/prometheus/prometheus:v2.50.0
# -> 192.168.1.61/k8s/prometheus:v2.50.0

# Alertmanager（告警路由与分组组件）
quay.io/prometheus/alertmanager:v0.26.0
# -> 192.168.1.61/k8s/alertmanager:v0.26.0

# Grafana（监控可视化面板）
docker.io/grafana/grafana:10.3.1
# -> 192.168.1.61/k8s/grafana:10.3.1

# node-exporter（节点硬件指标采集器）
quay.io/prometheus/node-exporter:v1.7.0
# -> 192.168.1.61/k8s/node-exporter:v1.7.0

# kube-state-metrics（K8s 资源状态指标采集器）
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.10.1
# -> 192.168.1.61/k8s/kube-state-metrics:v2.10.1

# prometheus-adapter（自定义指标适配器，用于 HPA）
registry.k8s.io/prometheus-adapter/prometheus-adapter:v0.11.2
# -> 192.168.1.61/k8s/k8s-prometheus-adapter:v0.11.2

# kube-rbac-proxy（Sidecar 代理，提供 RBAC 代理）
quay.io/brancz/kube-rbac-proxy:v0.15.0
# -> 192.168.1.61/k8s/kube-rbac-proxy:v0.15.0

# prometheus-config-reloader（Prometheus 配置热重载器）
quay.io/prometheus-operator/prometheus-config-reloader:v0.70.0
# -> 192.168.1.61/k8s/prometheus-config-reloader:v0.70.0

# 企业微信 Webhook 转发服务
docker.io/prometheusalertmanager/prometheus-alertmanager-wechat-hook:0.0.1
# -> 192.168.1.61/k8s/prometheus-alertmanager-wechat-hook:0.0.1

# 使用 sync_images.sh 脚本批量同步（参考 00-基础设施准备.md）
# ./sync_images.sh -r 192.168.1.61 -p Harbor12345 -f image-list.txt
```

### 3.2 创建监控命名空间

```bash
kubectl create namespace monitoring
```

### 3.4 创建自定义 values.yaml

```bash
cat > /root/prometheus-values.yaml << 'EOF'
# kube-prometheus-stack 自定义 values.yaml

# 全局配置
global:
  imageRegistry: "192.168.1.61/registry.k8s.io"

# Prometheus 配置
prometheus:
  enabled: true
  prometheusSpec:
    replicas: 2                    # Prometheus 副本数
    retention: 15d                 # 数据保留时间
    retentionSize: 30Gi            # 数据保留大小上限
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path  # 存储类名称
          resources:
            requests:
              storage: 50Gi               # 持久化存储大小
    resources:
      requests:
        cpu: 250m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
    serviceMonitorSelectorNilUsesHelmValues: false  # 允许发现非 Helm 管理的 ServiceMonitor
    podMonitorSelectorNilUsesHelmValues: false      # 允许发现非 Helm 管理的 PodMonitor
    additionalScrapeConfigs:           # 额外的抓取配置
      - job_name: "harbor"
        static_configs:
          - targets: ["192.168.1.61:8080"]
    alertingRules:                    # 自定义告警规则
      groups:
        - name: custom-alerts
          rules:
            # Pod 重启过多
            - alert: PodRestartTooMany
              expr: increase(kube_pod_container_status_restarts_total[1h]) > 5
              for: 10m
              labels:
                severity: warning
              annotations:
                summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} 重启次数过多"
                description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} 在过去1小时内重启了 {{ $value }} 次"

            # Node 内存使用率过高
            - alert: NodeMemoryUsageHigh
              expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "节点 {{ $labels.instance }} 内存使用率过高"
                description: "节点 {{ $labels.instance }} 内存使用率为 {{ $value }}%"

            # 磁盘空间不足
            - alert: NodeDiskSpaceLow
              expr: (1 - node_filesystem_avail_bytes{fstype=~"ext4|xfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs"}) * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "节点 {{ $labels.instance }} 磁盘空间不足"
                description: "节点 {{ $labels.instance }} 挂载点 {{ $labels.mountpoint }} 使用率为 {{ $value }}%"

            # PVC 存储空间不足
            - alert: PVCStorageUsageHigh
              expr: (1 - kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) * 100 > 85
              for: 5m
              labels:
                severity: warning
              annotations:
                summary: "PVC {{ $labels.persistentvolumeclaim }} 存储使用率过高"
                description: "PVC {{ $labels.persistentvolumeclaim }} 使用率为 {{ $value }}%"

# Alertmanager 配置
alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: 2                    # Alertmanager 副本数
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 100m
        memory: 128Mi
  config:
    global:
      resolve_timeout: 5m          # 告警自动恢复超时
    route:
      group_by: ['alertname', 'namespace', 'pod']  # 告警分组标签
      group_wait: 30s              # 首次告警等待时间
      group_interval: 5m           # 同组告警发送间隔
      repeat_interval: 4h          # 重复告警间隔
      receiver: 'wechat'           # 默认告警接收器
      routes:
        - match:
            severity: critical
          receiver: 'wechat-critical'
          group_wait: 10s
          repeat_interval: 1h
        - match:
            severity: warning
          receiver: 'wechat'
          group_wait: 30s
          repeat_interval: 4h
    receivers:
      - name: 'wechat'
        webhook_configs:
          - url: 'http://alertmanager-wechat:8060/webhook/dingtalk-webhook-token'
            send_resolved: true
      - name: 'wechat-critical'
        webhook_configs:
          - url: 'http://alertmanager-wechat:8060/webhook/dingtalk-webhook-token'
            send_resolved: true
    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'namespace']

# Grafana 配置
grafana:
  enabled: true
  adminPassword: "admin@2024"
  service:
    type: NodePort           # 使用 NodePort 暴露服务
    nodePort: 30000          # 外部访问端口
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 250m
      memory: 256Mi
  persistence:
    enabled: true
    size: 10Gi
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway.logging.svc.cluster.local
      access: proxy
      isDefault: false
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default

# kube-state-metrics 配置
kube-state-metrics:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/kube-state-metrics
  resources:
    requests:
      cpu: 100m
      memory: 128Mi

# node-exporter 配置
nodeExporter:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/node-exporter

# prometheus-adapter (HPA 指标)
prometheusAdapter:
  enabled: true
  image:
    repository: 192.168.1.61/k8s/k8s-prometheus-adapter

# kubelet-cadvisor
kubelet:
  enabled: true

# 默认禁用不需要的组件
kubeEtcd:
  enabled: true
kubeControllerManager:
  enabled: true
kubeScheduler:
  enabled: true
EOF
```

### 3.5 部署 kube-prometheus-stack

```bash
# 使用本地 Chart 包离线安装（Chart 包已通过 3.1.3 节步骤传输到 Master-1）
helm install prometheus-stack /root/kube-prometheus-stack-56.6.2.tgz \
    -n monitoring \
    -f /root/prometheus-values.yaml \
    --timeout 10m
```

### 3.6 验证部署

```bash
# 检查所有 Pod 状态
kubectl get pods -n monitoring -o wide

# 预期输出:
# NAME                                                   READY   STATUS
# alertmanager-prometheus-stack-alertmanager-0           2/2     Running
# prometheus-prometheus-stack-kube-state-metrics-xxxxx    1/1     Running
# prometheus-prometheus-stack-node-exporter-xxxxx        1/1     Running
# prometheus-prometheus-stack-operator-xxxxx             1/1     Running
# prometheus-prometheus-stack-prometheus-0                2/2     Running
# prometheus-stack-grafana-xxxxx                          1/1     Running

# 检查 Service
kubectl get svc -n monitoring
```

### 3.7 访问 Grafana

```bash
# 获取访问地址
echo "Grafana URL: http://192.168.1.51:30000"
echo "Username: admin"
echo "Password: admin@2024"

# 端口转发（如果使用 ClusterIP）
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 --address 0.0.0.0
```

### 3.8 配置企业微信告警

#### 3.8.1 部署企业微信 Webhook 转发服务

```bash
cat > /root/wechat-webhook.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-wechat
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager-wechat
  template:
    metadata:
      labels:
        app: alertmanager-wechat
    spec:
      containers:
        - name: wechat-webhook
          image: 192.168.1.61/k8s/prometheus-alertmanager-wechat-hook:0.0.1
          imagePullPolicy: IfNotPresent  # 镜像拉取策略
          args:
            - "--template.file=/etc/wechat/template.tmpl"
          ports:
            - containerPort: 8060     # Webhook 监听端口
          volumeMounts:
            - name: template
              mountPath: /etc/wechat
      volumes:
        - name: template
          configMap:
            name: wechat-template
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-wechat
  namespace: monitoring
spec:
  selector:
    app: alertmanager-wechat
  ports:
    - port: 8060
      targetPort: 8060
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: wechat-template
  namespace: monitoring
data:
  template.tmpl: |
    {{ define "wechat.default.message" }}
    {{- if gt (len .Alerts.Firing) 0 -}}
    {{- range $index, $alert := .Alerts.Firing -}}
    【告警】{{ $alert.Status }}
    告警级别: {{ $alert.Labels.severity }}
    告警名称: {{ $alert.Labels.alertname }}
    告警详情: {{ $alert.Annotations.description }}
    告警时间: {{ $alert.StartsAt.Format "2006-01-02 15:04:05" }}
    {{- end }}
    {{- end }}
    {{- if gt (len .Alerts.Resolved) 0 -}}
    {{- range $index, $alert := .Alerts.Resolved -}}
    【恢复】{{ $alert.Status }}
    告警名称: {{ $alert.Labels.alertname }}
    恢复时间: {{ $alert.EndsAt.Format "2006-01-02 15:04:05" }}
    {{- end }}
    {{- end }}
    {{ end }}
EOF

kubectl apply -f /root/wechat-webhook.yaml
```

### 3.9 HPA 集成

#### 3.9.1 验证 Prometheus Adapter 指标

```bash
# 检查可用的自定义指标
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces
kubectl top pods -n monitoring
```

#### 3.9.2 创建基于自定义指标的 HPA

```bash
cat > /root/hpa-demo.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-demo
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hpa-demo
  template:
    metadata:
      labels:
        app: hpa-demo
    spec:
      containers:
        - name: hpa-demo
          image: 192.168.1.61/k8s/nginx:alpine
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
          ports:
            - containerPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-demo
  namespace: monitoring
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-demo
  minReplicas: 1                  # 最小副本数
  maxReplicas: 10                 # 最大副本数
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50   # CPU 目标利用率 50%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70   # 内存目标利用率 70%
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
        - type: Pods
          value: 2
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 120
EOF

kubectl apply -f /root/hpa-demo.yaml
```

#### 3.9.3 压力测试 HPA

```bash
# 创建压测工具
kubectl run stress-test --image=192.168.1.61/k8s/busybox:latest -n monitoring \
    --command -- sh -c "while true; do wget -q -O- http://hpa-demo.monitoring.svc.cluster.local/ > /dev/null; done"

# 观察 HPA 扩容
kubectl get hpa -n monitoring -w
# 预期: replicas 从 1 逐渐增加到 10

# 清理
kubectl delete pod stress-test -n monitoring
```

### 3.9b KEDA 事件驱动自动伸缩（进阶）

> KEDA（Kubernetes Event-driven Autoscaling）是 CNCF 已毕业项目，让 Pod 根据**外部事件**（Kafka 消息积压、Redis 队列长度、Cron 定时等）自动扩缩容，而不局限于 CPU/内存指标。

#### KEDA vs 原生 HPA 对比

| 维度 | 原生 HPA | KEDA |
|------|----------|------|
| **触发指标** | CPU / Memory / 自定义 Prometheus 指标 | 60+ 外部事件源 |
| **缩容到零** | ❌ 不支持 minReplicas=0 | ✅ 原生支持（无事件时缩到 0） |
| **架构复杂度** | 简单（K8s 内置） | 需额外部署 KEDA Operator |
| **底层机制** | Metrics API → HPA Controller | ScaledObject → KEDA Operator → HPA |
| **典型场景** | 通用资源伸缩 | 消息队列消费、定时伸缩、事件驱动 |

#### KEDA 架构

```
外部事件源 (Kafka Lag / Redis Queue / Prometheus / Cron / ...)
        |
        v
  ScaledObject (CRD — 定义扩缩容规则)
        |
        v
  KEDA Operator (计算副本数、管理 HPA)
        |
        v
  原生 HPA (执行扩缩容)
        |
        v
  Deployment/StatefulSet 副本数变化
```

**关键设计**：KEDA 不替代 HPA，而是生成 HPA 对象执行。KEDA 可以同时设置 `minReplicaCount: 0` 实现缩容到零。

#### 离线环境部署 KEDA

```bash
# 1. 准备离线镜像
keda_version="2.14.0"
images=(
  "ghcr.io/kedacore/keda:${keda_version}"
  "ghcr.io/kedacore/keda-metrics-apiserver:${keda_version}"
)
for img in "${images[@]}"; do
  docker pull "$img"
  docker tag "$img" "192.168.1.61/k8s/$(basename $img)"
  docker push "192.168.1.61/k8s/$(basename $img)"
done

# 2. Helm 安装（使用本地 Chart + 离线镜像）
helm repo add kedacore https://kedacore.github.io/charts
helm pull kedacore/keda --version ${keda_version}

helm upgrade --install keda /root/keda-${keda_version}.tgz \
  -n keda --create-namespace \
  --set image.keda.repository=192.168.1.61/k8s/keda \
  --set image.metricsApiServer.repository=192.168.1.61/k8s/keda-metrics-apiserver \
  --set image.keda.tag=${keda_version} \
  --set image.metricsApiServer.tag=${keda_version}

# 3. 验证
kubectl get pods -n keda
kubectl get crd | grep keda
```

#### 典型场景 1：Kafka 消息驱动伸缩

```yaml
# ScaledObject: 根据 Kafka 消息积压量自动扩缩容消费者
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: kafka-consumer-deployment   # 目标 Deployment
  minReplicaCount: 0                  # 无消息时缩到 0（省资源）
  maxReplicaCount: 20                 # 最多 20 个消费者
  triggers:
    - type: kafka
      metadata:
        bootstrapServers: "kafka-broker.default.svc:9092"
        consumerGroup: "order-processor"
        topic: "orders"
        lagThreshold: "100"           # 积压 > 100 条就扩容
```

#### 典型场景 2：Cron 定时伸缩（预扩容）

```yaml
# 每天 9:00 扩展到 10 副本，18:00 缩回 2 副本
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: cron-scaler
  namespace: default
spec:
  scaleTargetRef:
    name: api-server
  minReplicaCount: 2
  maxReplicaCount: 10
  triggers:
    - type: cron
      metadata:
        timezone: "Asia/Shanghai"
        start: "0 9 * * 1-5"
        end: "0 18 * * 1-5"
        desiredReplicas: "10"
```

#### 典型场景 3：Prometheus 指标驱动

```yaml
# 根据 Prometheus 查询结果伸缩（复用已有监控体系）
  triggers:
    - type: prometheus
      metadata:
        serverAddress: "http://prometheus-stack-kube-prom-prometheus.monitoring.svc:9090"
        metricName: "http_error_rate"
        threshold: "5"                # 错误率 > 5% 就扩容
        query: |
          sum(rate(http_requests_total{status=~"5.."}[2m]))
          /
          sum(rate(http_requests_total[2m]))
```

#### 验证 KEDA

```bash
# 查看 ScaledObjects
kubectl get scaledobjects -A

# 查看自动生成的 HPA（KEDA 创建）
kubectl get hpa -A | grep keda

# 模拟 Kafka 消息堆积 → 观察扩容
kubectl get deploy kafka-consumer-deployment -w
```

#### 面试要点

> **Q: KEDA 和原生 HPA 的关系是什么？KEDA 会替代 HPA 吗？**
>
> KEDA 不替代 HPA，而是其补充层。KEDA Operator 根据外部事件计算目标副本数，然后创建/更新 HPA 对象，HPA 执行实际的扩缩容操作。KEDA 将 HPA 的能力从 CPU/Memory 扩展到 60+ 事件源，并实现缩容到零（HPA 不支持 minReplicas=0）。核心价值是让 K8s 原生支持事件驱动架构。

### 3.10 Grafana Dashboard 导入

```bash
# 推荐导入的 Dashboard:
# 1. Kubernetes Cluster Overview (ID: 1860)
# 2. Kubernetes Pods (ID: 6417)
# 3. Kubernetes Nodes (ID: 1860)
# 4. Node Exporter Full (ID: 1860)
# 5. Kubernetes / Compute Resources / Cluster (ID: 315)
# 6. Kubernetes / Networking / Cluster (ID: 17922)

# 通过 Helm values 自动导入 Dashboard
cat >> /root/prometheus-values.yaml << 'EOF'
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      kubernetes-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus
      kubernetes-nodes:
        gnetId: 315
        revision: 2
        datasource: Prometheus
EOF

# 升级 Helm release 导入 Dashboard（使用本地 Chart 包）
helm upgrade prometheus-stack /root/kube-prometheus-stack-56.6.2.tgz \
    -n monitoring \
    -f /root/prometheus-values.yaml
```

---

## 4. 配置详解

### 4.1 Prometheus 关键配置

| 参数 | 值 | 说明 |
|------|-----|------|
| `retention` | 15d | 数据保留时间 |
| `retentionSize` | 30Gi | 数据保留大小 |
| `replicas` | 2 | Prometheus 副本数 |
| `storageSpec` | PVC | 持久化存储配置 |
| `scrape_interval` | 15s | 默认抓取间隔 |
| `evaluation_interval` | 15s | 告警规则评估间隔 |

### 4.2 Alertmanager 路由配置

```yaml
route:
  group_by: ['alertname', 'namespace']  # 告警分组标签
  group_wait: 30s                        # 首次等待时间
  group_interval: 5m                     # 同组告警间隔
  repeat_interval: 4h                    # 重复告警间隔
  receiver: 'wechat'                     # 默认接收器
  routes:
    - match:
        severity: critical               # Critical 级别
      receiver: 'wechat-critical'
      group_wait: 10s                    # 更快通知
      repeat_interval: 1h                # 更频繁重复
```

### 4.3 常用 PromQL 查询

```bash
# CPU 使用率（按 Pod）
sum(rate(container_cpu_usage_seconds_total{namespace!="", container!=""}[5m])) by (namespace, pod)

# 内存使用率（按 Pod）
sum(container_memory_working_set_bytes{namespace!=""}) by (namespace, pod)

# Pod 重启次数
increase(kube_pod_container_status_restarts_total[1h])

# 节点 CPU 使用率
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 节点内存使用率
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# 磁盘使用率
(1 - node_filesystem_avail_bytes{fstype=~"ext4|xfs"} / node_filesystem_size_bytes{fstype=~"ext4|xfs"}) * 100

# 网络流量
rate(node_network_receive_bytes_total[5m])
rate(node_network_transmit_bytes_total[5m])

# API Server 请求延迟
histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m]))

# etcd 领导者变更
changes(etcd_server_leader_changes_seen_total[1h])

# PVC 使用率
(1 - kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes) * 100
```

### 4.4 自定义业务指标实践

#### 4.4.1 使用 Micrometer 定义业务指标

**Java Spring Boot 集成 Micrometer 示例：**

```java
// 1. 添加依赖（pom.xml）
/*
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
*/

// 2. 配置 application.yml
/*
management:
  endpoints:
    web:
      exposure:
        include: prometheus,health,info,metrics
  endpoint:
    prometheus:
      enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${ENV:production}
*/

// 3. 自定义业务指标组件
@Component
public class BusinessMetrics {
    
    private final MeterRegistry registry;
    private final Counter orderCounter;
    private final Counter paymentCounter;
    private final DistributionSummary orderAmountSummary;
    private final Timer paymentTimer;
    
    public BusinessMetrics(MeterRegistry registry) {
        this.registry = registry;
        
        // 订单计数器（按状态、类型标签）
        this.orderCounter = Counter.builder("business.orders.total")
            .description("Total number of orders")
            .tag("service", "order-service")
            .register(registry);
        
        // 支付计数器
        this.paymentCounter = Counter.builder("business.payments.total")
            .description("Total number of payments")
            .tag("service", "payment-service")
            .register(registry);
        
        // 订单金额分布
        this.orderAmountSummary = DistributionSummary.builder("business.order.amount")
            .description("Order amount distribution")
            .baseUnit("yuan")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(registry);
        
        // 支付处理时间
        this.paymentTimer = Timer.builder("business.payment.duration")
            .description("Payment processing time")
            .publishPercentileHistogram()
            .sla(Duration.ofMillis(100), Duration.ofMillis(500), Duration.ofSeconds(1))
            .register(registry);
    }
    
    // 记录订单
    public void recordOrder(String status, String type, double amount) {
        orderCounter.tag("status", status)
                    .tag("type", type)
                    .increment();
        orderAmountSummary.record(amount);
    }
    
    // 记录支付（使用 Timer.Sample 精确计时）
    public void recordPayment(Runnable paymentTask) {
        Timer.Sample sample = Timer.start(registry);
        try {
            paymentTask.run();
            paymentCounter.tag("status", "success").increment();
        } catch (Exception e) {
            paymentCounter.tag("status", "failed").increment();
            throw e;
        } finally {
            sample.stop(paymentTimer);
        }
    }
}

// 4. 在业务代码中使用
@Service
public class OrderService {
    
    @Autowired
    private BusinessMetrics metrics;
    
    public Order createOrder(OrderRequest request) {
        // 执行业务逻辑
        Order order = doCreateOrder(request);
        
        // 记录指标
        metrics.recordOrder(
            order.getStatus(),
            order.getType(),
            order.getAmount()
        );
        
        return order;
    }
}
```

#### 4.4.2 RED 方法设计服务级别指标

**RED 方法：Rate (流量), Errors (错误), Duration (延迟)**

```yaml
# red-method-rules.yaml
# 使用 RED 方法设计微服务监控指标
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule            # Prometheus 自定义告警/记录规则 CRD
metadata:
  name: red-method-metrics
  namespace: monitoring
spec:
  groups:
    - name: red.rate
      interval: 15s               # 规则评估间隔
      rules:
        # R - Rate: 每秒请求数（按服务、接口、方法分组）
        - record: red:rate:qps
          expr: |
            sum by (service, route, method) (
              rate(http_requests_total[1m])
            )
        
        # R - Rate: 每分钟请求数
        - record: red:rate:rpm
          expr: |
            sum by (service, route, method) (
              rate(http_requests_total[5m]) * 60
            )
    
    - name: red.errors
      interval: 15s
      rules:
        # E - Errors: 每秒错误数（5xx 状态码）
        - record: red:errors:total
          expr: |
            sum by (service, route, method) (
              rate(http_requests_total{status=~"5.."}[1m])
            )
        
        # E - Errors: 错误率
        - record: red:errors:ratio
          expr: |
            red:errors:total / red:rate:qps
        
        # E - Errors: 每秒客户端错误（4xx 状态码）
        - record: red:errors:client:total
          expr: |
            sum by (service, route, method) (
              rate(http_requests_total{status=~"4.."}[1m])
            )
    
    - name: red.duration
      interval: 15s
      rules:
        # D - Duration: P50 延迟
        - record: red:duration:p50
          expr: |
            histogram_quantile(0.50,
              sum by (service, route, method, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # D - Duration: P95 延迟
        - record: red:duration:p95
          expr: |
            histogram_quantile(0.95,
              sum by (service, route, method, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # D - Duration: P99 延迟
        - record: red:duration:p99
          expr: |
            histogram_quantile(0.99,
              sum by (service, route, method, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # D - Duration: 平均延迟
        - record: red:duration:avg
          expr: |
            sum by (service, route, method) (
              rate(http_request_duration_seconds_sum[5m])
            )
            /
            sum by (service, route, method) (
              rate(http_request_duration_seconds_count[5m])
            )
```

**RED Dashboard 查询示例：**

```bash
# 查看所有服务的 RED 指标

# Rate - 每秒请求数
curl 'http://prometheus:9090/api/v1/query?query=red:rate:qps'

# Errors - 错误率
curl 'http://prometheus:9090/api/v1/query?query=red:errors:ratio'

# Duration - P99 延迟
curl 'http://prometheus:9090/api/v1/query?query=red:duration:p99'

# 综合 RED 查询 - 服务健康度评分
# 健康度 = (可用性 * 0.4) + (1 - 错误率 * 10) * 0.3 + (1 - 延迟超标率) * 0.3
```

#### 4.4.3 Histogram 计算 Apdex 分数

**Apdex (Application Performance Index)：**
- 满意 (Satisfied): 响应时间 <= T
- 容忍 (Tolerating): T < 响应时间 <= 4T
- 失望 (Frustrated): 响应时间 > 4T

```yaml
# apdex-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: apdex-metrics
  namespace: monitoring
spec:
  groups:
    - name: apdex.calculation
      interval: 30s
      rules:
        # Apdex 计算 (T = 200ms)
        # Apdex = (Satisfied + Tolerating/2) / Total
        
        # 满意的请求数 (<= 200ms)
        - record: apdex:satisfied:total
          expr: |
            sum by (service) (
              rate(http_request_duration_seconds_bucket{le="0.2"}[5m])
            )
        
        # 容忍的请求数 (200ms < x <= 800ms)
        - record: apdex:tolerating:total
          expr: |
            sum by (service) (
              rate(http_request_duration_seconds_bucket{le="0.8"}[5m])
            ) - apdex:satisfied:total
        
        # 失望的请求数 (> 800ms)
        - record: apdex:frustrated:total
          expr: |
            sum by (service) (
              rate(http_request_duration_seconds_count[5m])
            ) - sum by (service) (
              rate(http_request_duration_seconds_bucket{le="0.8"}[5m])
            )
        
        # 总请求数
        - record: apdex:total
          expr: |
            sum by (service) (
              rate(http_request_duration_seconds_count[5m])
            )
        
        # Apdex 分数 (0-1)
        - record: apdex:score
          expr: |
            (apdex:satisfied:total + apdex:tolerating:total / 2) / apdex:total
        
        # Apdex 评分等级
        # Excellent: 0.94-1.00
        # Good: 0.85-0.93
        # Fair: 0.70-0.84
        # Poor: 0.50-0.69
        # Unacceptable: 0-0.49
        - record: apdex:rating
          expr: |
            case(
              apdex:score >= 0.94, 5,  # Excellent
              apdex:score >= 0.85, 4,  # Good
              apdex:score >= 0.70, 3,  # Fair
              apdex:score >= 0.50, 2,  # Poor
              1  # Unacceptable
            )
```

**Apdex 告警规则：**

```yaml
# apdex-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: apdex-alerts
  namespace: monitoring
spec:
  groups:
    - name: apdex.alerts
      rules:
        # Apdex 分数低于 Good 等级
        - alert: ApdexScoreLow
          expr: apdex:score < 0.85
          for: 5m
          labels:
            severity: warning
            metric: apdex
          annotations:
            summary: "服务 {{ $labels.service }} Apdex 分数偏低"
            description: "服务 {{ $labels.service }} 的 Apdex 分数为 {{ $value }}，低于 0.85 (Good) 标准"
        
        # Apdex 分数低于 Fair 等级（严重）
        - alert: ApdexScoreCritical
          expr: apdex:score < 0.70
          for: 2m
          labels:
            severity: critical
            metric: apdex
          annotations:
            summary: "服务 {{ $labels.service }} Apdex 分数严重偏低"
            description: "服务 {{ $labels.service }} 的 Apdex 分数为 {{ $value }}，低于 0.70 (Fair) 标准"
        
        # 失望用户比例过高
        - alert: ApdexFrustratedUsersHigh
          expr: |
            (apdex:frustrated:total / apdex:total) > 0.1
          for: 5m
          labels:
            severity: warning
            metric: apdex
          annotations:
            summary: "服务 {{ $labels.service }} 失望用户比例过高"
            description: "超过 10% 的用户体验到了令人失望的响应时间"
```

**Apdex Grafana 面板配置：**

```json
{
  "title": "Apdex 评分面板",
  "type": "stat",
  "targets": [
    {
      "expr": "apdex:score",
      "legendFormat": "{{ service }}"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "none",
      "min": 0,
      "max": 1,
      "thresholds": {
        "steps": [
          {"color": "red", "value": 0},
          {"color": "orange", "value": 0.5},
          {"color": "yellow", "value": 0.7},
          {"color": "light-green", "value": 0.85},
          {"color": "green", "value": 0.94}
        ]
      },
      "custom": {
        "displayMode": "gradient"
      }
    }
  }
}
```

---

## 5. Thanos 长期存储与高可用

### 5.1 Thanos 架构介绍

Thanos 是一套用于 Prometheus 高可用和长期存储的解决方案，通过 Sidecar（边车模式）与 Prometheus 集成，提供全局查询视图和无限存储能力。

#### 5.1.1 Thanos 核心组件

```
  +------------------------------------------------------------------+
  |                      Thanos 架构图                                 |
  +------------------------------------------------------------------+
  |                                                                   |
  |  +----------------+     +----------------+     +----------------+ |
  |  | Prometheus-0   |     | Prometheus-1   |     | Prometheus-N   | |
  |  | +------------+ |     | +------------+ |     | +------------+ | |
  |  | | Sidecar    | |     | | Sidecar    | |     | | Sidecar    | | |
  |  | | - 上传数据  | |     | | - 上传数据  | |     | | - 上传数据  | | |
  |  | | - 本地查询  | |     | | - 本地查询  | |     | | - 本地查询  | | |
  |  | +------+-----+ |     | +------+-----+ |     | +------+-----+ | |
  |  +--------|-------+     +--------|-------+     +--------|-------+ |
  |           |                      |                      |         |
  |           +----------------------+----------------------+         |
  |                                  |                                |
  |                    +-------------+-------------+                  |
  |                    |       Thanos Query       |                  |
  |                    |   (全局查询/去重/合并)    |                  |
  |                    +-------------+-------------+                  |
  |                                  |                                |
  |           +----------------------+----------------------+         |
  |           |                      |                      |         |
  |  +--------v-------+     +--------v-------+     +--------v-------+ |
  |  |  Store Gateway |     |   Compactor    |     |  Query Frontend| |
  |  |  (对象存储查询) |     |  (压缩/降采样)  |     |  (查询缓存)    | |
  |  +--------+-------+     +--------+-------+     +----------------+ |
  |           |                      |                                |
  |           +----------+-----------+                                |
  |                      |                                            |
  |           +----------v-----------+                                |
  |           |      MinIO/S3        |                                |
  |           |   (对象存储后端)      |                                |
  |           +----------------------+                                |
  |                                                                   |
  +------------------------------------------------------------------+
```

**组件说明：**

| 组件 | 功能 | 部署方式 |
|------|------|----------|
| **Sidecar**（边车） | 与 Prometheus 同 Pod 运行，上传数据到对象存储，提供本地 Store API | DaemonSet/Sidecar |
| **Query**（查询） | 聚合多个 Prometheus/Sidecar/Store Gateway 的查询结果，提供全局视图 | Deployment |
| **Store Gateway**（存储网关） | 从对象存储（S3/MinIO）查询历史数据 | StatefulSet |
| **Compactor**（压缩器） | 压缩和降采样对象存储中的历史数据，减少存储成本 | StatefulSet |
| **Query Frontend**（查询前端） | 查询结果缓存和查询拆分，加速大时间范围查询 | Deployment |

#### 5.1.2 Thanos 数据流

```
  Prometheus (本地 TSDB)
         |
         | 每2小时生成 Block
         v
  +------------------+
  |   Thanos Sidecar | ---> 上传到 MinIO (对象存储)
  +------------------+
         |
         | Store API (实时数据)
         v
  +------------------+
  |  Thanos Query    | <--- 聚合查询请求
  +------------------+
         |
         +---> Sidecar (实时数据)
         +---> Store Gateway (历史数据)
         +---> Rule (Recording Rules)
```

### 5.2 离线环境镜像准备

#### 5.2.1 Thanos 镜像清单

```bash
# Thanos 组件镜像（版本 v0.34.0）
quay.io/thanos/thanos:v0.34.0
# -> 192.168.1.61/k8s/thanos:v0.34.0

# MinIO 对象存储镜像（版本 RELEASE.2024-02-24T17-11-14Z）
quay.io/minio/minio:RELEASE.2024-02-24T17-11-14Z
# -> 192.168.1.61/k8s/minio:RELEASE.2024-02-24T17-11-14Z

# MinIO Client 镜像
quay.io/minio/mc:RELEASE.2024-02-24T01-33-20Z
# -> 192.168.1.61/k8s/mc:RELEASE.2024-02-24T01-33-20Z
```

#### 5.2.2 镜像同步脚本

```bash
#!/bin/bash
# thanos-images-sync.sh

HARBOR="192.168.1.61"
PROJECT="k8s"

declare -A IMAGES=(
    ["quay.io/thanos/thanos:v0.34.0"]="thanos:v0.34.0"
    ["quay.io/minio/minio:RELEASE.2024-02-24T17-11-14Z"]="minio:RELEASE.2024-02-24T17-11-14Z"
    ["quay.io/minio/mc:RELEASE.2024-02-24T01-33-20Z"]="mc:RELEASE.2024-02-24T01-33-20Z"
)

for SRC in "${!IMAGES[@]}"; do
    DST="${HARBOR}/${PROJECT}/${IMAGES[$SRC]}"
    echo "Syncing: $SRC -> $DST"
    docker pull $SRC
    docker tag $SRC $DST
    docker push $DST
done
```

### 5.3 MinIO 对象存储部署

#### 5.3.1 创建 MinIO 部署

```bash
cat > /root/thanos-minio.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: thanos
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: thanos
type: Opaque
stringData:
  rootUser: minioadmin
  rootPassword: minioadmin123
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: thanos
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: thanos
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
        - name: minio
          image: 192.168.1.61/k8s/minio:RELEASE.2024-02-24T17-11-14Z
          imagePullPolicy: IfNotPresent
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          env:
            - name: MINIO_ROOT_USER
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: rootUser
            - name: MINIO_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: minio-credentials
                  key: rootPassword
          ports:
            - containerPort: 9000      # MinIO API 端口
              name: api
            - containerPort: 9001      # MinIO 管理控制台端口
              name: console
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minio-data
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: thanos
spec:
  selector:
    app: minio
  ports:
    - port: 9000
      targetPort: 9000
      name: api
    - port: 9001
      targetPort: 9001
      name: console
  type: NodePort
EOF

kubectl apply -f /root/thanos-minio.yaml
```

#### 5.3.2 创建 Thanos Bucket

```bash
# 等待 MinIO 就绪
kubectl wait --for=condition=ready pod -l app=minio -n thanos --timeout=120s

# 创建 Bucket
cat > /root/minio-setup-job.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-setup
  namespace: thanos
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: mc
          image: 192.168.1.61/k8s/mc:RELEASE.2024-02-24T01-33-20Z
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              mc alias set local http://minio:9000 minioadmin minioadmin123
              mc mb local/thanos --ignore-existing
              mc policy set public local/thanos
EOF

kubectl apply -f /root/minio-setup-job.yaml
```

#### 5.3.3 创建对象存储配置文件

```bash
cat > /root/thanos-objstore.yaml << 'EOF'
type: S3
config:
  bucket: "thanos"
  endpoint: "minio.thanos.svc.cluster.local:9000"
  access_key: "minioadmin"
  secret_key: "minioadmin123"
  insecure: true
  signature_version2: false
  put_user_metadata: {}
  http_config:
    idle_conn_timeout: 90s
    response_header_timeout: 2m
    insecure_skip_verify: false
  trace:
    enable: false
  part_size: 134217728
EOF

kubectl create secret generic thanos-objstore -n monitoring \
  --from-file=thanos.yaml=/root/thanos-objstore.yaml
```

### 5.4 Thanos Sidecar 部署配置

#### 5.4.1 更新 Prometheus Values 启用 Sidecar

```bash
# 在 prometheus-values.yaml 中添加 Thanos Sidecar 配置
cat >> /root/prometheus-values-thanos.yaml << 'EOF'
# Thanos Sidecar 配置
prometheus:
  prometheusSpec:
    # 启用 Thanos Sidecar
    thanos:
      image: 192.168.1.61/k8s/thanos:v0.34.0
      objectStorageConfig:
        name: thanos-objstore
        key: thanos.yaml
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          cpu: 100m
          memory: 256Mi
    # 调整 Block 生成时间（默认2小时，可根据需要调整）
    retention: 2h  # 本地只保留2小时，数据上传到对象存储
    retentionSize: "5GB"
EOF
```

#### 5.4.2 独立部署 Thanos Sidecar（如已有 Prometheus）

```bash
cat > /root/thanos-sidecar.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-sidecar
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thanos-sidecar
  template:
    metadata:
      labels:
        app: thanos-sidecar
    spec:
      containers:
        - name: thanos-sidecar
          image: 192.168.1.61/k8s/thanos:v0.34.0
          imagePullPolicy: IfNotPresent
          args:
            - sidecar
            - --tsdb.path=/prometheus
            - --prometheus.url=http://prometheus-operated:9090
            - --objstore.config-file=/etc/thanos/objstore.yaml
            - --http-address=0.0.0.0:10902
            - --grpc-address=0.0.0.0:10901
          ports:
            - containerPort: 10901
              name: grpc
            - containerPort: 10902
              name: http
          volumeMounts:
            - name: prometheus-data
              mountPath: /prometheus
            - name: objstore
              mountPath: /etc/thanos
              readOnly: true
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 100m
              memory: 256Mi
      volumes:
        - name: prometheus-data
          persistentVolumeClaim:
            claimName: prometheus-prometheus-stack-prometheus-db-prometheus-prometheus-stack-prometheus-0
        - name: objstore
          secret:
            secretName: thanos-objstore
EOF
```

### 5.5 Thanos Query 全局查询视图

#### 5.5.1 部署 Thanos Query

```bash
cat > /root/thanos-query.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: monitoring
  labels:
    app: thanos-query
spec:
  replicas: 2
  selector:
    matchLabels:
      app: thanos-query
  template:
    metadata:
      labels:
        app: thanos-query
    spec:
      containers:
        - name: thanos-query
          image: 192.168.1.61/k8s/thanos:v0.34.0
          imagePullPolicy: IfNotPresent
          args:
            - query
            - --http-address=0.0.0.0:9090
            - --grpc-address=0.0.0.0:10901
            - --store=dnssrv+_grpc._tcp.thanos-sidecar.monitoring.svc.cluster.local
            - --store=dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local
            - --query.replica-label=replica
            - --query.auto-downsampling
            - --query.partial-response
          ports:
            - containerPort: 9090
              name: http
            - containerPort: 10901
              name: grpc
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: http
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /-/ready
              port: http
            initialDelaySeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-query
  namespace: monitoring
  labels:
    app: thanos-query
spec:
  selector:
    app: thanos-query
  ports:
    - port: 9090
      targetPort: 9090
      name: http
    - port: 10901
      targetPort: 10901
      name: grpc
  type: NodePort
EOF

kubectl apply -f /root/thanos-query.yaml
```

#### 5.5.2 部署 Thanos Store Gateway

```bash
cat > /root/thanos-store.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-store
  namespace: monitoring
  labels:
    app: thanos-store
spec:
  serviceName: thanos-store
  replicas: 1
  selector:
    matchLabels:
      app: thanos-store
  template:
    metadata:
      labels:
        app: thanos-store
    spec:
      containers:
        - name: thanos-store
          image: 192.168.1.61/k8s/thanos:v0.34.0
          imagePullPolicy: IfNotPresent
          args:
            - store
            - --data-dir=/var/thanos/store
            - --objstore.config-file=/etc/thanos/objstore.yaml
            - --http-address=0.0.0.0:10902
            - --grpc-address=0.0.0.0:10901
            - --index-cache-size=250MB
            - --bucket-cache-size=250MB
            - --sync-block-duration=3m
            - --min-time=-4w
          ports:
            - containerPort: 10901
              name: grpc
            - containerPort: 10902
              name: http
          volumeMounts:
            - name: data
              mountPath: /var/thanos/store
            - name: objstore
              mountPath: /etc/thanos
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: http
            initialDelaySeconds: 30
          readinessProbe:
            httpGet:
              path: /-/ready
              port: http
            initialDelaySeconds: 30
      volumes:
        - name: objstore
          secret:
            secretName: thanos-objstore
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: local-path
        resources:
          requests:
            storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-store
  namespace: monitoring
  labels:
    app: thanos-store
spec:
  selector:
    app: thanos-store
  ports:
    - port: 10901
      targetPort: 10901
      name: grpc
    - port: 10902
      targetPort: 10902
      name: http
  clusterIP: None
EOF

kubectl apply -f /root/thanos-store.yaml
```

#### 5.5.3 部署 Thanos Compactor

```bash
cat > /root/thanos-compactor.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-compactor
  namespace: monitoring
  labels:
    app: thanos-compactor
spec:
  serviceName: thanos-compactor
  replicas: 1
  selector:
    matchLabels:
      app: thanos-compactor
  template:
    metadata:
      labels:
        app: thanos-compactor
    spec:
      containers:
        - name: thanos-compactor
          image: 192.168.1.61/k8s/thanos:v0.34.0
          imagePullPolicy: IfNotPresent
          args:
            - compact
            - --data-dir=/var/thanos/compact
            - --objstore.config-file=/etc/thanos/objstore.yaml
            - --http-address=0.0.0.0:10902
            - --retention.resolution-raw=30d
            - --retention.resolution-5m=120d
            - --retention.resolution-1h=1y
            - --compact.concurrency=1
            - --downsample.concurrency=1
            - --wait
          ports:
            - containerPort: 10902
              name: http
          volumeMounts:
            - name: data
              mountPath: /var/thanos/compact
            - name: objstore
              mountPath: /etc/thanos
              readOnly: true
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: http
            initialDelaySeconds: 30
      volumes:
        - name: objstore
          secret:
            secretName: thanos-objstore
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: local-path
        resources:
          requests:
            storage: 50Gi
EOF

kubectl apply -f /root/thanos-compactor.yaml
```

### 5.6 长期存储与历史数据查询

#### 5.6.1 配置 Grafana 使用 Thanos Query

```bash
# 更新 Grafana 数据源配置
cat > /root/grafana-thanos-datasource.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: thanos-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  thanos.yaml: |
    apiVersion: 1
    datasources:
      - name: Thanos
        type: prometheus
        url: http://thanos-query:9090
        access: proxy
        isDefault: false
        editable: true
        jsonData:
          timeInterval: "5s"
          httpMethod: POST
EOF

kubectl apply -f /root/grafana-thanos-datasource.yaml
```

#### 5.6.2 验证 Thanos 部署

```bash
# 检查所有 Thanos 组件状态
kubectl get pods -n monitoring -l app.kubernetes.io/name=thanos

# 检查 Store API 连接
kubectl port-forward svc/thanos-query 9090:9090 -n monitoring &
curl http://localhost:9090/api/v1/status/stores

# 预期输出应包含 Sidecar 和 Store Gateway

# 查询历史数据（跨 Prometheus 实例）
curl 'http://localhost:9090/api/v1/query?query=up'

# 验证数据去重（如果有多个 Prometheus 副本）
# Thanos Query 会自动根据 replica 标签去重
```

#### 5.6.3 数据保留策略

```
  +-----------------------------------------------------------+
  |                    Thanos 数据保留策略                      |
  +-----------------------------------------------------------+
  |                                                           |
  |  本地 TSDB (Prometheus)                                    |
  |  +------------------+                                     |
  |  | 保留时间: 2小时   |  <-- 高频查询，最新数据               |
  |  | 数据精度: 原始    |                                     |
  |  +------------------+                                     |
  |           |                                               |
  |           v                                               |
  |  对象存储 (MinIO)                                          |
  |  +------------------+  +------------------+              |
  |  | 原始数据: 30天   |  | 5分钟降采样: 120天|              |
  |  | (高精度)         |  | (中精度)         |              |
  |  +------------------+  +------------------+              |
  |  +------------------+                                     |
  |  | 1小时降采样: 1年 |  <-- 长期趋势分析                    |
  |  | (低精度)         |                                     |
  |  +------------------+                                     |
  |                                                           |
  +-----------------------------------------------------------+
```

#### 5.6.4 Thanos 常用查询技巧

```bash
# 查询跨集群数据（通过 Thanos Query）
# Thanos Query 会自动聚合多个 Prometheus 实例的数据

# 查询长期历史数据（自动选择合适的分辨率）
# 查询 30 天前的数据会自动使用 5 分钟降采样数据
# 查询 1 年前的数据会自动使用 1 小时降采样数据

# 验证数据去重
curl 'http://thanos-query:9090/api/v1/query?query=up&dedup=true'

# 查看 Store 状态
curl http://thanos-query:9090/api/v1/status/stores | jq

# 查询特定 Store 的数据
curl 'http://thanos-query:9090/api/v1/query?query=up&store=sidecar-0'
```

---

## 6. 验证与测试

### 5.1 验证 Prometheus 数据采集

```bash
# 检查 Prometheus Targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 --address 0.0.0.0 &

# 浏览器访问 http://192.168.1.51:9090/targets
# 所有 Targets 应为 UP 状态

# 检查指标数据
curl -s http://localhost:9090/api/v1/query?query=up | jq '.data.result[] | .metric.job'
```

### 5.2 验证 Alertmanager

```bash
# 检查 Alertmanager 状态
kubectl port-forward -n monitoring svc/prometheus-stack-alertmanager 9093:9093 --address 0.0.0.0 &

# 浏览器访问 http://192.168.1.51:9093
# 检查告警路由配置
```

### 5.3 验证 Grafana Dashboard

```bash
# 访问 Grafana
# URL: http://192.168.1.51:30000
# 用户名: admin
# 密码: admin@2024

# 检查 Dashboard 列表
# 应包含: Kubernetes Cluster Overview, Nodes, Pods 等
```

### 5.4 触发测试告警

```bash
# 创建一个高内存使用的 Pod 触发告警
kubectl run memory-hog -n monitoring --image=192.168.1.61/k8s/stress \
    -- --vm 1 --vm-bytes 500M --vm-hang 1

# 检查 Prometheus 告警
# 访问 http://192.168.1.51:9090/alerts
# 应看到 NodeMemoryUsageHigh 告警

# 检查 Alertmanager
# 访问 http://192.168.1.51:9093
# 应看到告警被路由到 wechat 接收器

# 清理
kubectl delete pod memory-hog -n monitoring
```

### 5.5 验证 HPA

```bash
# 查看 HPA 状态
kubectl get hpa -n monitoring
# NAME       REFERENCE             TARGETS         MINPODS   MAXPODS   REPLICAS
# hpa-demo   Deployment/hpa-demo   50%/50%         1         10        1

# 查看事件
kubectl describe hpa hpa-demo -n monitoring
```

### 5.6 验证 Thanos 长期存储

```bash
# 检查 Thanos 组件状态
kubectl get pods -n monitoring -l app.kubernetes.io/name=thanos

# 检查 MinIO 对象存储
kubectl get pods -n thanos

# 验证数据上传到 MinIO
kubectl run -it --rm minio-client --image=192.168.1.61/k8s/mc -n thanos -- \
    mc alias set local http://minio:9000 minioadmin minioadmin123 && \
    mc ls local/thanos

# 访问 Thanos Query
kubectl port-forward svc/thanos-query 9091:9090 -n monitoring &
# 浏览器访问 http://192.168.1.51:9091
# 验证可查询历史数据
```

---

## 6. SLO 与错误预算实践

### 6.1 SLI、SLO、SLA 概念

#### 6.1.1 核心概念定义

```
  +-----------------------------------------------------------+
  |              服务级别指标与目标体系                          |
  +-----------------------------------------------------------+
  |                                                           |
  |   SLI (Service Level Indicator，服务级别指标)              |
  |   +--------------------------------------------------+   |
  |   | 服务级别指标 - 衡量服务健康状况的具体指标          |   |
  |   | 示例: 请求成功率、响应延迟、吞吐量                 |   |
  |   | 特点: 客观、可量化、可测量                         |   |
  |   +--------------------------------------------------+   |
  |                              |                            |
  |                              v                            |
  |   SLO (Service Level Objective)                           |
  |   +--------------------------------------------------+   |
  |   | 服务级别目标 - SLI 的目标值                         |   |
  |   | 示例: 可用性 99.9%，P99 延迟 < 200ms               |   |
  |   | 特点: 内部目标，可调整                              |   |
  |   +--------------------------------------------------+   |
  |                              |                            |
  |                              v                            |
  |   SLA (Service Level Agreement)                           |
  |   +--------------------------------------------------+   |
  |   | 服务级别协议 - 对用户的承诺                          |   |
  |   | 示例: 可用性 99.9%，未达到则赔偿                     |   |
  |   | 特点: 对外承诺，具有法律效力                         |   |
  |   +--------------------------------------------------+   |
  |                                                           |
  +-----------------------------------------------------------+
```

#### 6.1.2 常见 SLI 类型

| 类别 | SLI 指标 | 说明 | 测量方式 |
|------|----------|------|----------|
| **可用性** | 服务正常运行时间比例 | 服务可访问的时间占比 | `1 - (故障时间 / 总时间)` |
| **延迟** | 请求响应时间 | 从请求到响应的时间 | Histogram 分位数 |
| **吞吐量** | 每秒请求数 (QPS) | 系统处理能力 | Counter 的 rate |
| **错误率** | 失败请求比例 | 错误请求占总请求比例 | `错误数 / 总数` |
| **饱和度** | 资源使用率 | CPU、内存、磁盘使用率 | Gauge 值 |

#### 6.1.3 SLO 设定原则

| 原则 | 说明 | 示例 |
|------|------|------|
| **可测量** | SLI 必须能通过监控系统获取 | 使用 Prometheus 指标 |
| **可达成** | SLO 应基于历史数据设定，避免过高 | 参考过去 30 天数据 |
| **有意义** | SLO 应反映用户体验 | 关注用户可见的指标 |
| **可执行** | 未达到 SLO 时应有明确的应对措施 | 触发告警、启动预案 |

### 6.2 定义服务级别指标

#### 6.2.1 可用性指标定义

```yaml
# slo-availability-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-availability
  namespace: monitoring
spec:
  groups:
    - name: slo.availability
      interval: 30s
      rules:
        # 记录总请求数（按服务、接口分组）
        - record: slo:requests_total
          expr: |
            sum by (service, route) (
              rate(http_requests_total[5m])
            )
        
        # 记录成功请求数（2xx/3xx 状态码）
        - record: slo:successful_requests_total
          expr: |
            sum by (service, route) (
              rate(http_requests_total{status=~"2..|3.."}[5m])
            )
        
        # 计算可用性（成功率）
        - record: slo:availability:ratio
          expr: |
            slo:successful_requests_total / slo:requests_total
        
        # 计算错误预算消耗速率
        - record: slo:error_budget:burn_rate
          expr: |
            (1 - slo:availability:ratio) / (1 - 0.999)
```

#### 6.2.2 延迟指标定义

```yaml
# slo-latency-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-latency
  namespace: monitoring
spec:
  groups:
    - name: slo.latency
      interval: 30s
      rules:
        # 记录 P99 延迟（按服务分组）
        - record: slo:latency:p99
          expr: |
            histogram_quantile(0.99,
              sum by (service, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # 记录 P95 延迟
        - record: slo:latency:p95
          expr: |
            histogram_quantile(0.95,
              sum by (service, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # 记录 P50 延迟
        - record: slo:latency:p50
          expr: |
            histogram_quantile(0.50,
              sum by (service, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
        
        # 计算满足延迟目标的请求比例
        - record: slo:latency:compliance:ratio
          expr: |
            (
              sum by (service) (
                rate(http_request_duration_seconds_bucket{le="0.2"}[5m])
              )
            ) / (
              sum by (service) (
                rate(http_request_duration_seconds_count[5m])
              )
            )
```

#### 6.2.3 RED 方法指标

```yaml
# slo-red-method.yaml
# RED 方法: Rate (流量), Errors (错误), Duration (延迟)
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-red-method
  namespace: monitoring
spec:
  groups:
    - name: slo.red
      interval: 30s
      rules:
        # R - Rate (每秒请求数)
        - record: slo:red:rate
          expr: |
            sum by (service) (
              rate(http_requests_total[5m])
            )
        
        # E - Errors (每秒错误数)
        - record: slo:red:errors
          expr: |
            sum by (service) (
              rate(http_requests_total{status=~"5..|4.."}[5m])
        
        # E - Error Rate (错误率)
        - record: slo:red:error_rate
          expr: |
            slo:red:errors / slo:red:rate
        
        # D - Duration (P99 延迟)
        - record: slo:red:duration
          expr: |
            histogram_quantile(0.99,
              sum by (service, le) (
                rate(http_request_duration_seconds_bucket[5m])
              )
            )
```

### 6.3 错误预算计算

#### 6.3.1 错误预算概念

```
  +-----------------------------------------------------------+
  |                    错误预算计算模型                         |
  +-----------------------------------------------------------+
  |                                                           |
  |   可用性目标: 99.9%                                       |
  |   错误预算:  0.1% (100% - 99.9%)                          |
  |                                                           |
  |   计算示例 (30天周期):                                     |
  |   +--------------------------------------------------+   |
  |   | 总时间: 30天 × 24小时 × 60分钟 = 43,200分钟       |   |
  |   | 允许停机时间: 43,200 × 0.001 = 43.2分钟           |   |
  |   | 错误预算: 43.2分钟/月                             |   |
  |   +--------------------------------------------------+   |
  |                                                           |
  |   计算示例 (请求数):                                      |
  |   +--------------------------------------------------+   |
  |   | 总请求数: 1,000,000/月                            |   |
  |   | 允许错误数: 1,000,000 × 0.001 = 1,000 次          |   |
  |   | 错误预算: 1,000 次错误/月                         |   |
  |   +--------------------------------------------------+   |
  |                                                           |
  +-----------------------------------------------------------+
```

#### 6.3.2 错误预算告警规则

```yaml
# slo-error-budget-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-error-budget-alerts
  namespace: monitoring
spec:
  groups:
    - name: slo.error_budget
      rules:
        # 快速消耗错误预算 (2% 预算在 1 小时内消耗完)
        - alert: ErrorBudgetBurnRateFast
          expr: |
            (
              (
                1 - avg_over_time(slo:availability:ratio[1h])
              ) / (1 - 0.999)
            ) > 14.4
            and
            (
              (
                1 - avg_over_time(slo:availability:ratio[5m])
              ) / (1 - 0.999)
            ) > 14.4
          for: 2m
          labels:
            severity: critical
            slo: availability
          annotations:
            summary: "服务 {{ $labels.service }} 错误预算快速消耗"
            description: "服务 {{ $labels.service }} 在过去1小时内消耗了超过2%的月度错误预算"
        
        # 中等速度消耗错误预算 (5% 预算在 6 小时内消耗完)
        - alert: ErrorBudgetBurnRateMedium
          expr: |
            (
              (
                1 - avg_over_time(slo:availability:ratio[6h])
              ) / (1 - 0.999)
            ) > 6
            and
            (
              (
                1 - avg_over_time(slo:availability:ratio[30m])
              ) / (1 - 0.999)
            ) > 6
          for: 5m
          labels:
            severity: warning
            slo: availability
          annotations:
            summary: "服务 {{ $labels.service }} 错误预算中等速度消耗"
            description: "服务 {{ $labels.service }} 在过去6小时内消耗了超过5%的月度错误预算"
        
        # 慢速消耗错误预算 (10% 预算在 3 天内消耗完)
        - alert: ErrorBudgetBurnRateSlow
          expr: |
            (
              (
                1 - avg_over_time(slo:availability:ratio[3d])
              ) / (1 - 0.999)
            ) > 1
          for: 1h
          labels:
            severity: info
            slo: availability
          annotations:
            summary: "服务 {{ $labels.service }} 错误预算慢速消耗"
            description: "服务 {{ $labels.service }} 在过去3天内消耗了超过10%的月度错误预算"
```

#### 6.3.3 错误预算消耗速率参考表

| 消耗速度 | 时间窗口 | 消耗比例 | Burn Rate | 响应要求 |
|----------|----------|----------|-----------|----------|
| 极快 | 1小时 | 2% | 14.4 | 立即响应 |
| 快 | 6小时 | 5% | 6 | 1小时内响应 |
| 中等 | 3天 | 10% | 1 | 24小时内响应 |
| 慢 | 30天 | 100% | - | 计划内处理 |

### 6.4 基于 SLO 的告警配置

#### 6.4.1 多窗口多燃烧率告警

```yaml
# slo-multiwindow-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-multiwindow-alerts
  namespace: monitoring
spec:
  groups:
    - name: slo.multiwindow
      rules:
        # 可用性 SLO 告警 (99.9%)
        # 窗口1: 快速燃烧 (1小时窗口, 2%预算)
        - alert: SLOAvailabilityFastBurn
          expr: |
            (
              sum by (service) (rate(http_requests_total{status=~"5.."}[1h]))
              /
              sum by (service) (rate(http_requests_total[1h]))
            ) > (1 - 0.999) * 14.4
          for: 5m
          labels:
            severity: critical
            alert_type: fast_burn
            slo_target: "99.9%"
          annotations:
            summary: "服务 {{ $labels.service }} 可用性快速下降"
            description: "服务 {{ $labels.service }} 在过去1小时内错误率超过预期"
        
        # 窗口2: 慢速燃烧 (3天窗口, 10%预算)
        - alert: SLOAvailabilitySlowBurn
          expr: |
            (
              sum by (service) (rate(http_requests_total{status=~"5.."}[3d]))
              /
              sum by (service) (rate(http_requests_total[3d]))
            ) > (1 - 0.999) * 1
          for: 1h
          labels:
            severity: warning
            alert_type: slow_burn
            slo_target: "99.9%"
          annotations:
            summary: "服务 {{ $labels.service }} 可用性持续下降"
            description: "服务 {{ $labels.service }} 在过去3天内错误率超过预期"
        
        # 延迟 SLO 告警 (P99 < 200ms)
        - alert: SLOLatencyP99Exceeded
          expr: |
            histogram_quantile(0.99,
              sum by (service, le) (rate(http_request_duration_seconds_bucket[5m]))
            ) > 0.2
          for: 10m
          labels:
            severity: warning
            slo_target: "p99<200ms"
          annotations:
            summary: "服务 {{ $labels.service }} P99 延迟超标"
            description: "服务 {{ $labels.service }} P99 延迟为 {{ $value }}s，超过 200ms 目标"
```

#### 6.4.2 SLO 状态 Recording Rules

```yaml
# slo-status-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-status
  namespace: monitoring
spec:
  groups:
    - name: slo.status
      interval: 60s
      rules:
        # 记录当前 SLO 状态 (1=达标, 0=不达标)
        - record: slo:status:availability
          expr: |
            (
              avg_over_time(slo:availability:ratio[30d]) >= 0.999
            )
        
        # 记录剩余错误预算比例
        - record: slo:error_budget:remaining:ratio
          expr: |
            1 - (
              (
                1 - avg_over_time(slo:availability:ratio[30d])
              ) / (1 - 0.999)
            )
        
        # 记录本月已用错误预算
        - record: slo:error_budget:consumed:ratio
          expr: |
            (
              1 - avg_over_time(slo:availability:ratio[30d])
            ) / (1 - 0.999)
```

### 6.5 SLO 仪表板创建

#### 6.5.1 Grafana SLO Dashboard JSON

```json
{
  "dashboard": {
    "title": "SLO / Error Budget 监控",
    "tags": ["slo", "reliability"],
    "timezone": "Asia/Shanghai",
    "panels": [
      {
        "title": "服务可用性 (30天)",
        "type": "stat",
        "targets": [
          {
            "expr": "avg_over_time(slo:availability:ratio[30d])",
            "legendFormat": "{{ service }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 0.999},
                {"color": "green", "value": 0.9995}
              ]
            }
          }
        }
      },
      {
        "title": "剩余错误预算",
        "type": "gauge",
        "targets": [
          {
            "expr": "slo:error_budget:remaining:ratio",
            "legendFormat": "{{ service }}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percentunit",
            "min": 0,
            "max": 1,
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 0.2},
                {"color": "green", "value": 0.5}
              ]
            }
          }
        }
      },
      {
        "title": "错误预算消耗趋势",
        "type": "graph",
        "targets": [
          {
            "expr": "slo:error_budget:consumed:ratio",
            "legendFormat": "{{ service }} 已消耗"
          },
          {
            "expr": "1",
            "legendFormat": "预算上限"
          }
        ]
      },
      {
        "title": "P99 延迟",
        "type": "graph",
        "targets": [
          {
            "expr": "slo:latency:p99",
            "legendFormat": "{{ service }}"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": {"params": [0.2], "type": "gt"},
              "operator": {"type": "and"},
              "query": {"params": ["A", "5m", "now"]},
              "reducer": {"type": "avg"},
              "type": "query"
            }
          ]
        }
      }
    ]
  }
}
```

#### 6.5.2 使用 Grafana UI 创建 SLO 面板

```bash
# 1. 导入 SLO Dashboard
curl -X POST http://admin:admin@192.168.1.51:30000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @slo-dashboard.json

# 2. 验证 Dashboard
echo "访问: http://192.168.1.51:30000/d/slo-dashboard"
```

#### 6.5.3 SLO 报告自动化

```bash
#!/bin/bash
# generate-slo-report.sh
# 生成月度 SLO 报告

END=$(date +%s)
START=$(date -d "30 days ago" +%s)

PROMETHEUS_URL="http://prometheus-operated:9090"

echo "=== SLO 月度报告 ==="
echo "时间范围: $(date -d @$START) 至 $(date -d @$END)"
echo ""

echo "1. 服务可用性:"
curl -s "${PROMETHEUS_URL}/api/v1/query?query=avg_over_time(slo:availability:ratio[30d])" | jq '.data.result[] | "  \(.metric.service): \(.value[1])"'

echo ""
echo "2. 剩余错误预算:"
curl -s "${PROMETHEUS_URL}/api/v1/query?query=slo:error_budget:remaining:ratio" | jq '.data.result[] | "  \(.metric.service): \(.value[1])"'

echo ""
echo "3. P99 延迟:"
curl -s "${PROMETHEUS_URL}/api/v1/query?query=slo:latency:p99" | jq '.data.result[] | "  \(.metric.service): \(.value[1])s"'
```

---

## 7. 告警路由与值班管理

### 6.1 CKA 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 监控集群 | 使用 kubectl top 查看 Pod/Node 资源使用 | 5.5 节 |
| HPA | 基于资源指标和自定义指标的自动扩缩容 | 3.9 节 |
| Metrics Server | 资源指标 API | 3.9 节 |

### 6.2 CKS 相关考点

| 考点 | 说明 | 本模块覆盖 |
|------|------|-----------|
| 审计日志监控 | 监控 API Server 审计日志 | 4.3 节 |
| 安全告警 | 异常行为检测和告警 | 3.4 节 |

---

## 7. 告警路由与值班管理

### 7.1 Alertmanager 路由树配置

#### 7.1.1 路由树架构

```
  +-----------------------------------------------------------+
  |                  Alertmanager 路由树架构                    |
  +-----------------------------------------------------------+
  |                                                           |
  |                    +-------------+                       |
  |                    |   Root      |                       |
  |                    |   Route     |                       |
  |                    |   (default) |                       |
  |                    +------+------+                       |
  |                           |                               |
  |           +---------------+---------------+               |
  |           |               |               |               |
  |    +------v------+ +------v------+ +------v------+      |
  |    | 按严重级别   | |  按团队      | |  按环境      |      |
  |    | 路由        | |  路由        | |  路由        |      |
  |    +------+------+ +------+------+ +------+------+      |
  |           |               |               |               |
  |    +------v------+ +------v------+ +------v------+      |
  |    | critical -> | | backend ->  | | prod ->      |      |
  |    | PagerDuty   | | oncall-dev  | | immediate    |      |
  |    |             | | frontend -> | | staging ->   |      |
  |    | warning ->  | | oncall-fe   | | delayed      |      |
  |    | slack       | | infra ->    | | dev ->       |      |
  |    |             | | oncall-ops  | | log only     |      |
  |    +-------------+ +-------------+ +-------------+      |
  |                                                           |
  +-----------------------------------------------------------+
```

#### 7.1.2 高级路由配置示例

```yaml
# alertmanager-advanced-routing.yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.example.com:587'
  smtp_from: 'alertmanager@example.com'
  smtp_auth_username: 'alertmanager@example.com'
  smtp_auth_password: 'password'
  smtp_require_tls: true
  wechat_api_url: 'https://qyapi.weixin.qq.com/cgi-bin/'
  wechat_api_corp_id: 'wwxxxxxxxxxxxxxxxx'

# 路由树配置
route:
  # 根路由 - 默认接收器
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  
  # 子路由
  routes:
    # 1. 按严重级别路由
    - match:
        severity: critical
      receiver: 'pagerduty-critical'
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 30m
      continue: true  # 继续匹配其他路由
      
    - match:
        severity: warning
      receiver: 'slack-warning'
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 2h
      continue: true
      
    - match:
        severity: info
      receiver: 'email-info'
      group_wait: 1m
      group_interval: 10m
      repeat_interval: 24h
      continue: false
    
    # 2. 按团队路由
    - match_re:
        team: backend|api
      receiver: 'team-backend'
      routes:
        - match:
            severity: critical
          receiver: 'backend-pagerduty'
        - match:
            severity: warning
          receiver: 'backend-slack'
          
    - match_re:
        team: frontend|web
      receiver: 'team-frontend'
      routes:
        - match:
            severity: critical
          receiver: 'frontend-pagerduty'
        - match:
            severity: warning
          receiver: 'frontend-slack'
          
    - match:
        team: infrastructure
      receiver: 'team-infrastructure'
      routes:
        - match:
            severity: critical
          receiver: 'infra-phone'
        - match:
            severity: warning
          receiver: 'infra-slack'
    
    # 3. 按环境路由
    - match:
        environment: production
      receiver: 'prod-oncall'
      routes:
        - match:
            severity: critical
          receiver: 'prod-escalation'
          group_wait: 0s
          repeat_interval: 15m
          
    - match:
        environment: staging
      receiver: 'staging-oncall'
      routes:
        - match:
            severity: critical
          receiver: 'staging-slack'
          repeat_interval: 1h
          
    - match:
        environment: development
      receiver: 'dev-logging'
      group_wait: 5m
      repeat_interval: 24h
    
    # 4. 按时间段路由（工作时间 vs 非工作时间）
    - match:
        severity: warning
      receiver: 'business-hours-only'
      group_wait: 5m
      # 只在工作时间发送
      active_time_intervals:
        - business_hours

# 接收器配置
receivers:
  - name: 'default'
    email_configs:
      - to: 'oncall@example.com'
        send_resolved: true
  
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '<pagerduty-service-key>'
        severity: critical
        description: '{{ .GroupLabels.alertname }}: {{ .CommonAnnotations.summary }}'
  
  - name: 'slack-warning'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#alerts-warning'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
  
  - name: 'team-backend'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#team-backend'
  
  - name: 'team-frontend'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#team-frontend'
  
  - name: 'team-infrastructure'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#team-infrastructure'
  
  - name: 'wechat-webhook'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/send'
        send_resolved: true

# 抑制规则
inhibit_rules:
  # 节点宕机时抑制该节点上的所有 Pod 告警
  - source_match:
      alertname: 'NodeDown'
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['node']
  
  # 集群级别告警抑制命名空间级别告警
  - source_match:
      alertname: 'ClusterNotReady'
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['cluster']

# 时间间隔配置
time_intervals:
  - name: business_hours
    time_intervals:
      - times:
          - start_time: '09:00'
            end_time: '18:00'
        weekdays: ['monday:tuesday', 'wednesday', 'thursday', 'friday']
        location: 'Asia/Shanghai'
```

### 7.2 按严重级别和团队分发

#### 7.2.1 告警分级策略

| 级别 | 条件 | 通知方式 | 响应时间 | 升级策略 |
|------|------|----------|----------|----------|
| **P0 - Critical** | 服务完全不可用、数据丢失 | 电话 + 短信 + 钉钉 | 5分钟 | 15分钟未响应自动升级 |
| **P1 - High** | 核心功能受损、性能严重下降 | 钉钉 + 邮件 | 15分钟 | 1小时未响应升级 |
| **P2 - Medium** | 非核心功能问题 | 钉钉 | 1小时 | 4小时未响应升级 |
| **P3 - Low** | 轻微问题、优化建议 | 邮件 | 24小时 | 不升级 |
| **P4 - Info** | 信息通知 | 日志记录 | - | 不升级 |

#### 7.2.2 团队路由配置

```yaml
# team-routing.yaml
route:
  receiver: 'default'
  routes:
    # 基础设施团队
    - match:
        team: infrastructure
      receiver: 'infra-primary'
      routes:
        - match:
            severity: critical
          receiver: 'infra-escalation'
          continue: false
        - match:
            severity: warning
          receiver: 'infra-secondary'
    
    # 后端开发团队
    - match:
        team: backend
      receiver: 'backend-primary'
      routes:
        - match:
            severity: critical
          receiver: 'backend-escalation'
        - match:
            severity: warning
          receiver: 'backend-secondary'
    
    # 前端开发团队
    - match:
        team: frontend
      receiver: 'frontend-primary'
      routes:
        - match:
            severity: critical
          receiver: 'frontend-escalation'
        - match:
            severity: warning
          receiver: 'frontend-secondary'
    
    # 数据团队
    - match:
        team: data
      receiver: 'data-primary'
      routes:
        - match:
            severity: critical
          receiver: 'data-escalation'
        - match:
            severity: warning
          receiver: 'data-secondary'

receivers:
  # 基础设施团队接收器
  - name: 'infra-primary'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/infra-primary'
  - name: 'infra-secondary'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/infra-secondary'
  - name: 'infra-escalation'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/infra-escalation'
    pagerduty_configs:
      - service_key: '<infra-pagerduty-key>'
  
  # 后端团队接收器
  - name: 'backend-primary'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/backend-primary'
  - name: 'backend-secondary'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/backend-secondary'
  - name: 'backend-escalation'
    webhook_configs:
      - url: 'http://alertmanager-wechat:8060/webhook/backend-escalation'
```

### 7.3 告警抑制与静默

#### 7.3.1 抑制规则详解

```yaml
# inhibition-rules.yaml
inhibit_rules:
  # 规则1: 节点宕机抑制该节点上的 Pod 告警
  - source_match:
      alertname: 'NodeNotReady'
      severity: 'critical'
    target_match_re:
      alertname: 'Pod.*|Kubelet.*|Node.*'
      severity: 'warning|critical'
    equal: ['node', 'instance']
  
  # 规则2: 集群不可用时抑制所有命名空间级别告警
  - source_match:
      alertname: 'K8sClusterNotReady'
      severity: 'critical'
    target_match_re:
      severity: 'warning|critical'
    equal: ['cluster']
  
  # 规则3: 磁盘满时抑制磁盘即将满的告警
  - source_match:
      alertname: 'NodeDiskFull'
      severity: 'critical'
    target_match:
      alertname: 'NodeDiskSpaceLow'
      severity: 'warning'
    equal: ['instance', 'device']
  
  # 规则4: 高内存使用抑制内存警告
  - source_match:
      alertname: 'NodeMemoryCritical'
      severity: 'critical'
    target_match:
      alertname: 'NodeMemoryHigh'
      severity: 'warning'
    equal: ['instance']
  
  # 规则5: 网络分区抑制网络延迟告警
  - source_match:
      alertname: 'NetworkPartition'
      severity: 'critical'
    target_match:
      alertname: 'NetworkLatencyHigh'
      severity: 'warning'
    equal: ['instance']
```

#### 7.3.2 静默管理

```bash
# 创建静默规则（通过 API）
# 1. 在维护窗口期间静默所有告警
curl -X POST http://alertmanager:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [
      {"name": "severity", "value": "warning|critical", "isRegex": true}
    ],
    "startsAt": "2024-01-15T02:00:00Z",
    "endsAt": "2024-01-15T06:00:00Z",
    "createdBy": "ops-team",
    "comment": "Scheduled maintenance window"
  }'

# 2. 静默特定服务的告警
curl -X POST http://alertmanager:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [
      {"name": "service", "value": "payment-service"},
      {"name": "severity", "value": "warning", "isRegex": false}
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "developer",
    "comment": "Deploying new version"
  }'

# 3. 列出所有静默规则
curl http://alertmanager:9093/api/v1/silences | jq

# 4. 删除静默规则
curl -X DELETE http://alertmanager:9093/api/v1/silence/<silence-id>
```

#### 7.3.3 静默模板配置

```yaml
# 在 Alertmanager UI 中预设静默模板
# silence-templates.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: silence-templates
  namespace: monitoring
data:
  templates.json: |
    [
      {
        "name": "Maintenance Window",
        "matchers": [
          {"name": "severity", "value": "warning|critical", "isRegex": true}
        ],
        "duration": "4h"
      },
      {
        "name": "Service Deployment",
        "matchers": [
          {"name": "service", "value": "", "isRegex": false},
          {"name": "severity", "value": "warning", "isRegex": false}
        ],
        "duration": "30m"
      },
      {
        "name": "Node Maintenance",
        "matchers": [
          {"name": "instance", "value": "", "isRegex": false}
        ],
        "duration": "2h"
      }
    ]
```

### 7.4 与钉钉/企业微信集成

#### 7.4.1 钉钉机器人 Webhook 配置

```yaml
# dingtalk-webhook.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-dingtalk
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager-dingtalk
  template:
    metadata:
      labels:
        app: alertmanager-dingtalk
    spec:
      containers:
        - name: dingtalk-webhook
          image: 192.168.1.61/k8s/prometheus-webhook-dingtalk:v2.1.0
          imagePullPolicy: IfNotPresent
          args:
            - --web.listen-address=:8060
            - --config.file=/etc/dingtalk/config.yml
          ports:
            - containerPort: 8060
              name: http
          volumeMounts:
            - name: config
              mountPath: /etc/dingtalk
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      volumes:
        - name: config
          configMap:
            name: dingtalk-config
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-dingtalk
  namespace: monitoring
spec:
  selector:
    app: alertmanager-dingtalk
  ports:
    - port: 8060
      targetPort: 8060
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dingtalk-config
  namespace: monitoring
data:
  config.yml: |
    targets:
      webhook1:
        url: https://oapi.dingtalk.com/robot/send?access_token=<token1>
        secret: <secret1>
        mention:
          all: true
      webhook2:
        url: https://oapi.dingtalk.com/robot/send?access_token=<token2>
        secret: <secret2>
        mention:
          mobiles: ['13800138000', '13900139000']
      infra:
        url: https://oapi.dingtalk.com/robot/send?access_token=<infra-token>
        secret: <infra-secret>
      backend:
        url: https://oapi.dingtalk.com/robot/send?access_token=<backend-token>
        secret: <backend-secret>
      frontend:
        url: https://oapi.dingtalk.com/robot/send?access_token=<frontend-token>
        secret: <frontend-secret>
```

#### 7.4.2 企业微信机器人配置

```yaml
# wechat-webhook-enhanced.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-wechat-enhanced
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alertmanager-wechat-enhanced
  template:
    metadata:
      labels:
        app: alertmanager-wechat-enhanced
    spec:
      containers:
        - name: wechat-webhook
          image: 192.168.1.61/k8s/prometheus-alertmanager-wechat-hook:0.0.1
          imagePullPolicy: IfNotPresent
          args:
            - --template.file=/etc/wechat/template.tmpl
            - --webhook.url=https://qyapi.weixin.qq.com/cgi-bin/webhook/send
          ports:
            - containerPort: 8060
          volumeMounts:
            - name: template
              mountPath: /etc/wechat
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
      volumes:
        - name: template
          configMap:
            name: wechat-template-enhanced
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: wechat-template-enhanced
  namespace: monitoring
data:
  template.tmpl: |
    {{ define "wechat.default.message" }}
    {{ $alertCount := len .Alerts }}
    {{ $firingCount := len .Alerts.Firing }}
    {{ $resolvedCount := len .Alerts.Resolved }}
    
    ## 告警通知
    
    **告警状态:** {{ if gt $firingCount 0 }}🔴 触发中{{ else }}🟢 已恢复{{ end }}
    **告警数量:** {{ $alertCount }}
    **触发中:** {{ $firingCount }}
    **已恢复:** {{ $resolvedCount }}
    
    ---
    
    {{ if gt $firingCount 0 }}
    ### 🔴 触发中的告警
    {{ range .Alerts.Firing }}
    **告警名称:** {{ .Labels.alertname }}
    **严重级别:** {{ .Labels.severity }}
    **服务:** {{ .Labels.service }}
    **实例:** {{ .Labels.instance }}
    **详情:** {{ .Annotations.description }}
    **开始时间:** {{ .StartsAt.Format "2006-01-02 15:04:05" }}
    
    ---
    {{ end }}
    {{ end }}
    
    {{ if gt $resolvedCount 0 }}
    ### 🟢 已恢复的告警
    {{ range .Alerts.Resolved }}
    **告警名称:** {{ .Labels.alertname }}
    **服务:** {{ .Labels.service }}
    **恢复时间:** {{ .EndsAt.Format "2006-01-02 15:04:05" }}
    
    ---
    {{ end }}
    {{ end }}
    {{ end }}
```

#### 7.4.3 Alertmanager 集成配置

```yaml
# alertmanager-receivers.yaml
receivers:
  # 钉钉接收器
  - name: 'dingtalk-critical'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/webhook1/send'
        send_resolved: true
  
  - name: 'dingtalk-warning'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/webhook2/send'
        send_resolved: true
  
  - name: 'dingtalk-infra'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/infra/send'
        send_resolved: true
  
  - name: 'dingtalk-backend'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/backend/send'
        send_resolved: true
  
  - name: 'dingtalk-frontend'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/frontend/send'
        send_resolved: true
  
  # 企业微信接收器
  - name: 'wechat-critical'
    webhook_configs:
      - url: 'http://alertmanager-wechat-enhanced:8060/webhook/send'
        send_resolved: true
  
  - name: 'wechat-warning'
    webhook_configs:
      - url: 'http://alertmanager-wechat-enhanced:8060/webhook/send'
        send_resolved: true
  
  # 多通道组合
  - name: 'multi-channel-critical'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/webhook1/send'
        send_resolved: true
      - url: 'http://alertmanager-wechat-enhanced:8060/webhook/send'
        send_resolved: true
    pagerduty_configs:
      - service_key: '<pagerduty-key>'
```

### 7.5 值班表管理

#### 7.5.1 轮值配置架构

```
  +-----------------------------------------------------------+
  |                    值班表管理架构                           |
  +-----------------------------------------------------------+
  |                                                           |
  |  +----------------+     +----------------+               |
  |  |   值班表配置    |     |   当前值班人员  |               |
  |  |   (ConfigMap)  | --> |   (Annotation) |               |
  |  +----------------+     +--------+-------+               |
  |                                  |                        |
  |                                  v                        |
  |  +----------------+     +----------------+               |
  |  | Alertmanager   | <-- |  Webhook       |               |
  |  | 路由更新       |     |  处理器        |               |
  |  +----------------+     +----------------+               |
  |                                  |                        |
  |                                  v                        |
  |  +----------------+     +----------------+               |
  |  | 钉钉/企业微信  | <-- |  通知发送      |               |
  |  +----------------+     +----------------+               |
  |                                                           |
  +-----------------------------------------------------------+
```

#### 7.5.2 值班表配置

```yaml
# oncall-schedule.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oncall-schedule
  namespace: monitoring
data:
  schedule.json: |
    {
      "teams": {
        "infrastructure": {
          "primary": {
            "name": "张三",
            "phone": "13800138001",
            "dingtalk": "zhangsan",
            "period": "2024-01-01 to 2024-01-07"
          },
          "secondary": {
            "name": "李四",
            "phone": "13800138002",
            "dingtalk": "lisi",
            "period": "2024-01-01 to 2024-01-07"
          }
        },
        "backend": {
          "primary": {
            "name": "王五",
            "phone": "13800138003",
            "dingtalk": "wangwu",
            "period": "2024-01-01 to 2024-01-14"
          },
          "secondary": {
            "name": "赵六",
            "phone": "13800138004",
            "dingtalk": "zhaoliu",
            "period": "2024-01-01 to 2024-01-14"
          }
        },
        "frontend": {
          "primary": {
            "name": "孙七",
            "phone": "13800138005",
            "dingtalk": "sunqi",
            "period": "2024-01-01 to 2024-01-14"
          },
          "secondary": {
            "name": "周八",
            "phone": "13800138006",
            "dingtalk": "zhouba",
            "period": "2024-01-01 to 2024-01-14"
          }
        }
      },
      "escalation": {
        "timeout_minutes": 15,
        "levels": [
          {"level": 1, "notify": "primary"},
          {"level": 2, "notify": "secondary"},
          {"level": 3, "notify": "manager", "manager": "manager@example.com"}
        ]
      }
    }
```

#### 7.5.3 值班轮换脚本

```bash
#!/bin/bash
# rotate-oncall.sh
# 值班轮换脚本

NAMESPACE="monitoring"
CONFIGMAP="oncall-schedule"

# 获取当前值班表
kubectl get configmap $CONFIGMAP -n $NAMESPACE -o jsonpath='{.data.schedule\.json}' > /tmp/current-schedule.json

# 轮换逻辑（示例：每周轮换）
# 实际生产环境可对接日历系统或专门的值班管理工具

# 更新 Alertmanager 配置中的接收器
update_alertmanager_receivers() {
    local team=$1
    local primary=$2
    local secondary=$3
    
    # 生成新的 Alertmanager 配置片段
    cat > /tmp/receiver-${team}.yaml << EOF
  - name: '${team}-primary'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/${primary}/send'
  - name: '${team}-secondary'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/${secondary}/send'
EOF
    
    echo "Updated receivers for team: $team"
}

# 主逻辑
echo "Rotating on-call schedule..."

# 解析 JSON 并更新配置
jq -r '.teams | keys[]' /tmp/current-schedule.json | while read team; do
    primary=$(jq -r ".teams.${team}.primary.dingtalk" /tmp/current-schedule.json)
    secondary=$(jq -r ".teams.${team}.secondary.dingtalk" /tmp/current-schedule.json)
    update_alertmanager_receivers $team $primary $secondary
done

# 重新加载 Alertmanager 配置
curl -X POST http://alertmanager:9093/-/reload

echo "On-call rotation completed!"
```

#### 7.5.4 值班通知模板

```yaml
# oncall-notification-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oncall-notification-template
  namespace: monitoring
data:
  critical.tmpl: |
    {{ define "oncall.critical.message" }}
    🚨 **Critical Alert - Immediate Action Required**
    
    **Current On-Call Engineer:**
    - Name: {{ .Oncall.Primary.Name }}
    - Phone: {{ .Oncall.Primary.Phone }}
    - DingTalk: @{{ .Oncall.Primary.Dingtalk }}
    
    **Escalation Contact:**
    - Name: {{ .Oncall.Secondary.Name }}
    - Phone: {{ .Oncall.Secondary.Phone }}
    
    **Alert Details:**
    {{ range .Alerts }}
    - {{ .Labels.alertname }}: {{ .Annotations.description }}
    {{ end }}
    
    **Auto-escalation in 15 minutes if not acknowledged.**
    {{ end }}
  
  handoff.tmpl: |
    {{ define "oncall.handoff.message" }}
    📋 **On-Call Handoff**
    
    **Previous Shift:** {{ .Previous.Name }} ({{ .Previous.Period }})
    **Current Shift:** {{ .Current.Name }} ({{ .Current.Period }})
    
    **Pending Issues:**
    {{ range .PendingAlerts }}
    - {{ .Labels.alertname }}: {{ .Annotations.description }}
    {{ end }}
    
    **Recent Incidents:**
    {{ range .RecentIncidents }}
    - {{ .Time }}: {{ .Description }} (Resolved: {{ .Resolved }})
    {{ end }}
    {{ end }}
```

---

## 8. 高频面试题

### Q1: Prometheus 的四种 Metric 类型分别是什么？各有什么特点？ [难度: 中]

**答案：** Prometheus 定义了四种核心 Metric 类型。Counter（计数器）是一个只增不减的累加值，用于记录事件发生的总次数，如 HTTP 请求总数、错误总数。Counter 的典型操作是 `rate()`（计算每秒平均增长率）和 `increase()`（计算时间范围内的总增量）。注意 Counter 重置（如进程重启）时，Prometheus 会自动处理。Gauge（仪表盘）是一个可增可减的当前值，用于记录某一时刻的状态，如 CPU 使用率、内存使用量、温度。Gauge 可以直接使用，也可以通过 `avg()`、`max()`、`min()` 等聚合函数计算。Histogram（直方图）用于观测值分布统计，在客户端将数据分桶（Bucket）计数，记录每个桶的累计计数、总观测次数和总观测值之和。Histogram 支持在服务端计算任意分位数（通过 `histogram_quantile()`），适合聚合计算。Summary（摘要）与 Histogram 类似，但在客户端直接计算分位数（如 p50、p90、p99），服务端直接使用。Summary 的缺点是分位数无法跨实例聚合。

### Q2: PromQL 中 rate() 和 increase() 有什么区别？ [难度: 中]

**答案：** `rate()` 和 `increase()` 都是用于处理 Counter 类型指标的函数，但计算方式和适用场景不同。`rate()` 计算的是时间窗口内每秒的平均增长率（即斜率），返回值是浮点数（单位为/秒），适合计算 QPS、带宽等速率指标。`increase()` 计算的是时间窗口内的总增量（即总量变化），返回值是浮点数（单位为计数），适合计算一段时间内的总请求数、总错误数等。数学关系：`increase(metric[5m])` 约等于 `rate(metric[5m]) * 300`（5分钟 = 300秒）。区别在于：`rate()` 对 Counter 重置（如进程重启导致的计数器归零）的处理更智能，会自动调整计算；`increase()` 在 Counter 重置时可能产生不准确的结果。使用建议：计算速率用 `rate()`，计算总量用 `increase()`；在告警规则中，`rate()` 更常用；在 Dashboard 中展示趋势时，两者都可以使用。注意两个函数都要求时间窗口至少覆盖 4 个抓取间隔（默认 15s 抓取间隔下，至少 60s）。

### Q3: Alertmanager 的路由、分组、抑制和静默有什么区别？ [难度: 中]

**答案：** Alertmanager 提供了四种告警管理机制。路由（Routing）根据告警的标签（Labels）将告警发送到不同的接收器（Receiver），支持树形路由结构，子路由可以覆盖父路由的配置。分组（Grouping）将具有相同标签的告警合并为一条通知，减少告警风暴。例如将同一个命名空间的所有告警合并为一条消息。分组由 `group_by`、`group_wait`（首次分组等待时间）、`group_interval`（同组新告警等待时间）控制。抑制（Inhibition）定义了告警之间的抑制关系，当高优先级告警触发时，自动抑制低优先级告警。例如当节点宕机告警触发时，自动抑制该节点上的 Pod 告警。静默（Silence）是临时的告警屏蔽规则，在指定时间范围内不发送匹配的告警，适合维护窗口使用。这四种机制协同工作：路由决定告警发往哪里，分组决定如何合并，抑制决定哪些告警不发，静默决定临时屏蔽。

### Q4: 如何实现基于自定义指标的 HPA？ [难度: 高]

**答案：** 基于自定义指标的 HPA 需要三个组件协作：Prometheus（采集和存储自定义指标）、Prometheus Adapter（将 Prometheus 指标转换为 K8s Metrics API）、HPA Controller（根据指标调整副本数）。实现步骤：第一，确保应用暴露了自定义指标端点（`/metrics`），指标格式符合 Prometheus 规范。第二，Prometheus 通过 ServiceMonitor 或 PodMonitor 自动发现并抓取指标。第三，配置 Prometheus Adapter，在 values.yaml 中定义规则，将 Prometheus 指标映射为 K8s 自定义指标 API。例如将 `http_requests_total` 映射为 `requests-per-second` 指标。第四，创建 HPA 对象，指定 `type: Pods` 和 `metrics` 引用自定义指标名称和目标值。HPA Controller 会通过 Metrics API 查询当前指标值，与目标值比较后调整副本数。注意：自定义指标的值必须是速率（per-second），Prometheus Adapter 会自动执行 `rate()` 计算。

### Q5: Prometheus 的数据存储机制是什么？如何处理长期存储？ [难度: 高]

**答案：** Prometheus 使用自研的 TSDB（Time Series Database）作为存储引擎。TSDB 将时序数据按时间分块（Block），每个 Block 包含 2 小时的数据（默认），由多个 Chunk 文件组成。每个 Chunk 存储一个时间序列的一段数据，使用 XOR 压缩算法（Gorilla 压缩），压缩比可达 10-20 倍。TSDB 的写入流程为：数据先写入 WAL（Write-Ahead Log）保证持久性，然后在内存中构建 Chunk，定期刷盘为 Block 文件。查询时，TSDB 会合并内存中的 Chunk 和磁盘上的 Block。Compaction 操作会合并小 Block 为大 Block，并删除过期数据。Prometheus 本地存储的局限性：不支持集群模式（不支持水平扩展）、数据量大时查询性能下降、不适合长期存储（> 30天）。长期存储方案：Thanos（通过 Sidecar 上传数据到对象存储，支持跨 Prometheus 实例的全局查询）、VictoriaMetrics（兼容 Prometheus 的远程存储，支持集群模式）、Cortex（多租户的 Prometheus 长期存储）、Mimir（Grafana Labs 的长期存储方案）。生产环境推荐使用 Thanos 或 VictoriaMetrics。

### Q6: 如何排查 Prometheus Target 不可达的问题？ [难度: 中]

**答案：** Prometheus Target 不可达的排查步骤为：首先在 Prometheus Web UI 的 Targets 页面查看具体的错误信息（如 `connection refused`、`context deadline exceeded`、`401 Unauthorized`）。然后根据错误类型排查：`connection refused` 表示目标端口未监听，检查 Pod 是否运行、端口是否正确；`context deadline exceeded` 表示连接超时，检查网络连通性和防火墙；`401/403` 表示认证失败，检查 ServiceMonitor 的 bearerToken 或 basicAuth 配置；`invalid label` 表示指标格式错误，检查应用的 `/metrics` 端点输出是否符合 Prometheus 格式。还可以通过 `curl` 手动测试 Target 的 `/metrics` 端点：`curl -v http://<pod-ip>:<port>/metrics`。如果是 ServiceMonitor 发现问题，检查 selector 标签是否匹配 Pod 的标签，检查 port 名称是否与 Pod 的 containerPort 名称一致。如果是 PodMonitor，检查 Pod 的 annotations 中是否包含 `prometheus.io/scrape: "true"` 等配置。

### Q7: kube-prometheus-stack 包含哪些组件？各自的作用是什么？ [难度: 中]

**答案：** kube-prometheus-stack 是一个预配置的 Prometheus 监控栈 Helm Chart，包含以下核心组件：Prometheus Operator（核心控制器，负责管理 Prometheus、Alertmanager、ServiceMonitor 等 CRD 的生命周期）；Prometheus（时序数据库，负责采集、存储和查询指标数据）；Alertmanager（告警管理器，负责告警路由、分组、抑制和静默）；Grafana（可视化面板，预置了丰富的 K8s Dashboard）；node-exporter（DaemonSet，采集节点级别的硬件和 OS 指标，如 CPU、内存、磁盘、网络）；kube-state-metrics（Deployment，采集 K8s API Server 中的资源状态指标，如 Pod 状态、Deployment 副本数、Node 条件）；prometheus-adapter（APIService，将 Prometheus 指标转换为 K8s Metrics API，供 HPA 使用）；kubelet-cadvisor（内置于 kubelet，采集容器级别的资源使用指标）。这些组件协同工作，形成了从数据采集、存储、查询、可视化到告警的完整监控链路。

### Q8: 如何优化 Prometheus 的性能？ [难度: 高]

**答案：** Prometheus 性能优化需要从多个维度入手。数据采集优化：减少抓取的指标数量（使用 `metric_relabel_configs` 过滤不需要的指标）、降低抓取频率（非关键指标使用 30s 或 60s 间隔）、使用 ServiceMonitor 的 `sampleLimit` 限制单个 Target 的指标数量。存储优化：调整 WAL 段大小（`--storage.wal-segment-size`）、启用 TSDB 的压缩（默认已启用）、定期清理过期数据（设置合理的 `retention` 和 `retentionSize`）。查询优化：使用 recording rules 预计算常用查询、避免高基数的 `group by` 操作、使用 `@` 修饰符限制查询时间范围。资源优化：增加 Prometheus 的内存和 CPU 限制（TSDB 主要消耗内存）、使用 SSD 存储 WAL 和数据目录、启用内存映射（`--storage.tsdb.wal-compression`）。架构优化：使用 Thanos Query Frontend 缓存查询结果、使用 Thanos Receive 分片写入、将长期数据卸载到对象存储。监控 Prometheus 自身的指标（`prometheus_tsdb_head_*`、`prometheus_engine_query_duration_seconds`）及时发现性能瓶颈。

### Q9: 什么是 ServiceMonitor？如何配置？ [难度: 低]

**答案：** ServiceMonitor 是 Prometheus Operator 引入的 CRD，用于声明式地定义 Prometheus 的抓取目标。与传统的 `static_configs` 不同，ServiceMonitor 通过 Kubernetes 的 Service 发现机制自动关联 Pod，当 Pod 扩缩容时自动更新抓取目标。配置要素：`selector`（选择目标 Service 的标签）、`namespaceSelector`（选择 Service 所在的命名空间）、`endpoints`（定义抓取端口的名称、路径、间隔、认证方式等）。当 Prometheus Operator 发现新的 ServiceMonitor 时，会自动将其配置注入到 Prometheus 的配置文件中，并触发 Prometheus Reload。ServiceMonitor 的优势：声明式配置（GitOps 友好）、自动服务发现（无需手动维护 Target 列表）、支持 TLS 认证和 Bearer Token。示例：创建一个 ServiceMonitor 抓取 Nginx 的 `/metrics` 端点，指定 `port: http`、`path: /metrics`、`interval: 15s`，Prometheus Operator 会自动发现所有标签匹配的 Service 并开始抓取。

### Q10: Grafana 如何与 Prometheus 集成？如何创建自定义 Dashboard？ [难度: 低]

**答案：** Grafana 与 Prometheus 的集成通过配置数据源实现。在 kube-prometheus-stack 中，Helm Chart 自动配置了 Prometheus 作为 Grafana 的数据源。手动配置步骤：进入 Grafana -> Configuration -> Data Sources -> Add data source -> 选择 Prometheus -> 填写 Prometheus 的 Service URL（如 `http://prometheus-operated.monitoring.svc.cluster.local:9090`）-> Save & Test。创建自定义 Dashboard 有三种方式：第一种是通过 UI 手动创建（适合简单 Dashboard），添加 Panel -> 选择数据源 -> 编写 PromQL 查询 -> 配置可视化类型（图表、表格、仪表盘等）。第二种是导入社区 Dashboard（推荐），通过 Dashboard ID 或 JSON 文件导入，Grafana.com 上有大量社区贡献的 Dashboard。第三种是通过配置文件管理（GitOps），使用 Grafana Dashboard Provisioner（Helm values 中的 `dashboards` 配置），将 Dashboard JSON 文件存储在 ConfigMap 中，Grafana 自动加载。推荐使用第三种方式，便于版本管理和团队协作。

### Q11: 如何实现 Prometheus 的高可用？ [难度: 高]

**答案：** Prometheus 高可用有几种方案。方案一：Prometheus Operator + Thanos（推荐）。部署 2 个 Prometheus 副本（通过 StatefulSet），每个副本独立抓取数据，通过 Thanos Sidecar 将数据上传到对象存储（S3/MinIO），使用 Thanos Query 统一查询所有 Prometheus 实例的数据。优点：查询去重（`dedup()` 函数）、长期存储、全局视图。缺点：架构复杂，需要对象存储。方案二：Prometheus Operator + VictoriaMetrics Cluster。使用 vmagent 替代 Prometheus 抓取数据，写入 VictoriaMetrics 的分布式存储集群。优点：写入性能更高、存储成本更低。方案三：多 Prometheus 实例 + 联邦（Federation）。主 Prometheus 通过 `federation` 从子 Prometheus 拉取聚合数据。优点：简单。缺点：联邦查询性能差，不适合大规模。方案四：Cortex/Mimir。多租户的 Prometheus 兼容存储，支持水平扩展。无论哪种方案，Alertmanager 也需要高可用（至少 2 个副本），使用 gossip 协议同步告警状态。

### Q12: 如何监控 etcd 的健康状态？有哪些关键指标？ [难度: 中]

**答案：** etcd 的监控通过 kube-prometheus-stack 内置的 etcd ServiceMonitor 实现，关键指标包括：第一，Leader 变更频率 `etcd_server_leader_changes_seen_total`，正常情况下应为 0 或极低值，频繁变更说明存在网络问题或性能瓶颈。第二，提案延迟 `etcd_disk_wal_fsync_duration_seconds`（WAL 写入延迟）和 `etcd_disk_backend_commit_duration_seconds`（后端提交延迟），正常应 < 10ms，超过 50ms 说明磁盘性能不足。第三，数据库大小 `etcd_debugging_mvcc_db_total_size_in_bytes`，默认配额 2GB，超过 80% 需要告警。第四，对等连接数 `etcd_server_has_leader`，应为 1（有 Leader）。第五，RPC 请求速率和错误率 `grpc_server_handled_total`。第六，客户端连接数 `etcd_network_client_grpc_connections_opened`。建议在 Grafana 中导入 etcd Dashboard（ID 3070），并配置以下告警规则：etcd 无 Leader、Leader 变更频繁、磁盘延迟过高、数据库大小接近配额。

---

## 8. 故障排查案例

### 案例 1: Prometheus Pod 持续 CrashLoopBackOff

**现象：**
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
# prometheus-prometheus-stack-prometheus-0   CrashLoopBackOff
```

**排查步骤：**
1. 查看日志：`kubectl logs -n monitoring prometheus-prometheus-stack-prometheus-0`
2. 查看事件：`kubectl describe pod -n monitoring prometheus-prometheus-stack-prometheus-0`
3. 检查 PVC 状态：`kubectl get pvc -n monitoring`

**解决方案：**
```bash
# 常见原因1: PVC 存储不足或无法挂载
kubectl get pvc -n monitoring
# 如果 PVC 处于 Pending 状态，检查 StorageClass
kubectl get sc

# 常见原因2: TSDB 数据损坏
# 删除 PVC 中的数据（会丢失历史数据）
kubectl delete pvc -n monitoring prometheus-prometheus-stack-prometheus-db

# 常见原因3: 资源限制过低
# 编辑 values.yaml 增大 resources.limits.memory
helm upgrade prometheus-stack /root/kube-prometheus-stack-56.6.2.tgz \
    -n monitoring -f /root/prometheus-values.yaml
```

### 案例 2: Grafana 无法连接 Prometheus 数据源

**现象：**
```
Grafana Dashboard 显示 "No data"
数据源测试报错: "Failed to connect to Prometheus"
```

**排查步骤：**
1. 检查 Prometheus Service：`kubectl get svc -n monitoring prometheus-operated`
2. 检查网络策略：`kubectl get networkpolicy -n monitoring`
3. 测试连通性：`kubectl exec -n monitoring deploy/prometheus-stack-grafana -- curl -s http://prometheus-operated:9090/api/v1/query?query=up`

**解决方案：**
```bash
# 常见原因1: Service 名称或端口错误
# 检查 Grafana 数据源配置
kubectl get configmap -n monitoring -l app.kubernetes.io/name=grafana -o yaml | grep datasource

# 常见原因2: 网络策略阻止
# 创建允许 Grafana 访问 Prometheus 的 NetworkPolicy
cat > /root/grafana-prometheus-np.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-grafana-to-prometheus
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: prometheus
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - port: 9090
EOF
kubectl apply -f /root/grafana-prometheus-np.yaml
```

### 案例 3: 告警未发送到企业微信

**现象：**
```
Alertmanager 中显示告警已触发，但企业微信未收到消息
```

**排查步骤：**
1. 检查 Alertmanager 日志：`kubectl logs -n monitoring alertmanager-prometheus-stack-alertmanager-0`
2. 检查 Webhook 服务状态：`kubectl logs -n monitoring alertmanager-wechat`
3. 检查 Webhook URL 是否正确

**解决方案：**
```bash
# 常见原因1: Webhook ID 错误
# 检查 values.yaml 中的 webhook URL
# 确认企业微信机器人的 Webhook ID 正确

# 常见原因2: Webhook 服务未运行
kubectl get pods -n monitoring -l app=alertmanager-wechat
kubectl logs -n monitoring -l app=alertmanager-wechat

# 常见原因3: 企业微信机器人被限流
# 企业微信机器人限制: 每分钟最多发送 20 条消息
# 解决: 调整 Alertmanager 的 group_interval 和 repeat_interval
# group_interval: 5m
# repeat_interval: 4h

# 常见原因4: 模板错误
kubectl get configmap wechat-template -n monitoring -o yaml
# 检查模板语法是否正确
```

### 案例 4: Prometheus 内存持续增长

**现象：**
```bash
kubectl top pod -n monitoring prometheus-prometheus-stack-prometheus-0
# NAME    CPU    MEMORY
# prometheus   500m   8Gi  (持续增长)
```

**排查步骤：**
1. 检查活跃时间序列数：`curl http://prometheus:9090/api/v1/status/tsdb | jq '.data.stats.numActiveTimeSeries'`
2. 检查抓取的 Target 数量和指标数量
3. 检查是否有高基数标签

**解决方案：**
```bash
# 方案1: 减少采集的指标数量
# 在 values.yaml 中添加 metric_relabel_configs 过滤不需要的指标
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'filtered-metrics'
        metric_relabel_configs:
          - source_labels: [__name__]
            regex: 'go_.+'
            action: drop

# 方案2: 降低抓取频率
# 对非关键指标使用更长的抓取间隔

# 方案3: 增加内存限制
# 编辑 values.yaml 增大 resources.limits.memory

# 方案4: 启用 WAL 压缩
prometheus:
  prometheusSpec:
    extraArgs:
      storage.tsdb.wal-compression: "true"
```

### 案例 5: HPA 无法获取自定义指标

**现象：**
```bash
kubectl get hpa hpa-demo -n monitoring
# Warning: FailedGetResourceMetric: unable to get metrics for resource cpu
```

**排查步骤：**
1. 检查 Metrics Server：`kubectl get deployment metrics-server -n kube-system`
2. 检查 Prometheus Adapter：`kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-adapter`
3. 检查自定义指标 API：`kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1`

**解决方案：**
```bash
# 常见原因1: Metrics Server 未安装（需提前下载到 /root/manifests/ 目录）
kubectl apply -f /root/manifests/metrics-server-components.yaml
# 如果使用 containerd，需要添加 --kubelet-insecure-tls 参数
kubectl patch deployment metrics-server -n kube-system --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 常见原因2: Prometheus Adapter 配置错误
# 检查 adapter 的配置
kubectl get cm -n monitoring -l app.kubernetes.io/name=prometheus-adapter -o yaml

# 常见原因3: HPA 指标名称不匹配
# 确认 HPA 中引用的指标名称与 Prometheus Adapter 暴露的名称一致
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq '.resources[].name'
```

### 案例 6: Grafana Dashboard 数据缺失

**现象：**
```
Grafana Dashboard 部分面板显示 "No data"
但 Prometheus 中有对应的数据
```

**排查步骤：**
1. 检查 Dashboard 的 PromQL 查询是否正确
2. 检查数据源的时间范围设置
3. 检查是否有 Recording Rules 需要预计算

**解决方案：**
```bash
# 常见原因1: Dashboard 导入的 ID 与 Prometheus 版本不兼容
# 解决: 手动修改 Dashboard 中的 PromQL 查询，适配当前指标名称

# 常见原因2: 时间范围不匹配
# Grafana 默认显示最近 5 分钟，如果 Prometheus 刚启动可能没有数据
# 调整时间范围为 Last 1 hour

# 常见原因3: 指标名称变更
# kube-prometheus-stack 不同版本的指标名称可能不同
# 检查 Prometheus 中的实际指标名称
kubectl exec -n monitoring prometheus-prometheus-stack-prometheus-0 -- \
    wget -qO- http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep kube_pod
```

### 案例 7: Thanos 查询超时

**现象：**
```bash
# 通过 Thanos Query 查询历史数据时超时
# Grafana 面板显示 "Gateway Timeout"
# Thanos Query 日志中出现大量 "context deadline exceeded"
```

**排查步骤：**
1. 检查 Store Gateway 状态：`kubectl get pods -n monitoring -l app=thanos-store`
2. 检查 MinIO 连通性：`kubectl exec -n monitoring deploy/thanos-query -- curl -s http://minio.thanos.svc.cluster.local:9000/minio/health/live`
3. 查看 Thanos Query 日志：`kubectl logs -n monitoring deploy/thanos-query --tail=100`
4. 检查 Store Gateway 同步状态：`kubectl logs -n monitoring sts/thanos-store --tail=50 | grep sync`

**解决方案：**
```bash
# 常见原因1: Store Gateway 尚未完成索引同步
# Store Gateway 启动后需要时间来同步对象存储中的索引
# 检查同步进度
kubectl logs -n monitoring sts/thanos-store | grep "loaded new block"

# 常见原因2: MinIO 连接超时
# 增加超时配置
cat > /root/thanos-query-fix.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: monitoring
spec:
  template:
    spec:
      containers:
        - name: thanos-query
          args:
            - query
            - --http-address=0.0.0.0:9090
            - --grpc-address=0.0.0.0:10901
            - --store=dnssrv+_grpc._tcp.thanos-sidecar.monitoring.svc.cluster.local
            - --store=dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local
            - --query.timeout=2m           # 增加查询超时
            - --query.lookback-delta=5m    # 调整回溯窗口
            - --query.max-concurrent=20    # 限制并发查询数
            - --query.replica-label=replica
            - --query.auto-downsampling
            - --query.partial-response     # 允许部分响应
EOF
kubectl apply -f /root/thanos-query-fix.yaml

# 常见原因3: 查询时间范围过大
# 建议: 查询超过7天的数据时，使用降采样数据
# Grafana 中设置查询选项: max data points = 1000

# 常见原因4: Store Gateway 资源不足
# 增加 Store Gateway 的内存和 CPU
kubectl patch sts thanos-store -n monitoring --type=json \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "4Gi"}]'
```

### 案例 8: SLO 计算错误

**现象：**
```bash
# SLO 仪表板显示 NaN 或异常值
# 错误预算计算结果为负数或大于1
# Recording Rules 状态显示 Unknown
```

**排查步骤：**
1. 检查 Recording Rules 语法：`kubectl get prometheusrules -n monitoring slo-availability -o yaml`
2. 验证 PromQL 表达式：`curl 'http://prometheus:9090/api/v1/query?query=slo:availability:ratio'`
3. 检查原始指标是否存在：`curl 'http://prometheus:9090/api/v1/query?query=http_requests_total'`
4. 查看 Prometheus Rule 评估日志：`kubectl logs -n monitoring prometheus-prometheus-stack-prometheus-0 | grep eval`

**解决方案：**
```bash
# 常见原因1: 除零错误（没有请求数据时）
# 修复: 添加条件判断避免除零
# slo-availability-rules-fixed.yaml
cat > /root/slo-rules-fixed.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-availability-fixed
  namespace: monitoring
spec:
  groups:
    - name: slo.availability
      interval: 30s
      rules:
        # 修复: 添加 > 0 判断避免除零
        - record: slo:availability:ratio
          expr: |
            (
              slo:successful_requests_total 
              / 
              slo:requests_total
            ) and (slo:requests_total > 0)
        
        # 或者使用 clamp_min 确保分母不为0
        - record: slo:availability:ratio_safe
          expr: |
            slo:successful_requests_total 
            / 
            clamp_min(slo:requests_total, 1)
EOF
kubectl apply -f /root/slo-rules-fixed.yaml

# 常见原因2: 标签不匹配
# 确保所有向量标签一致
# 使用 on() 和 group_left/right 处理标签差异

# 常见原因3: 时间窗口选择不当
# 确保 rate() 的时间窗口至少覆盖4个抓取间隔
# 默认15s抓取间隔，最小时间窗口应为60s

# 常见原因4: 缺少数据
# 检查原始指标是否存在
kubectl exec -n monitoring prometheus-prometheus-stack-prometheus-0 -- \
    wget -qO- 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result | length'
# 如果结果为0，说明没有抓取到数据
```

### 案例 9: 告警风暴

**现象：**
```bash
# 短时间内收到大量告警通知
# 钉钉/企业微信被刷屏
# Alertmanager 负载飙升
# 同一问题触发多个相关告警
```

**排查步骤：**
1. 检查 Alertmanager 告警组：`curl http://alertmanager:9093/api/v1/alerts | jq '.data | length'`
2. 分析告警关联性：查看同时触发的告警是否有共同标签
3. 检查抑制规则配置：`kubectl get secret alertmanager-prometheus-stack-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d`
4. 查看告警历史：`curl http://alertmanager:9093/api/v1/alerts | jq '.data[].labels.alertname' | sort | uniq -c | sort -rn`

**解决方案：**
```bash
# 方案1: 优化告警分组
cat > /root/alertmanager-grouping-fix.yaml << 'EOF'
route:
  group_by: ['alertname', 'namespace', 'pod', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'
  routes:
    # 按服务分组，减少重复通知
    - match_re:
        severity: critical|warning
      receiver: 'grouped-alerts'
      group_by: ['service', 'severity']
      group_wait: 1m          # 等待1分钟收集相关告警
      group_interval: 10m     # 同组告警10分钟通知一次
      repeat_interval: 1h
EOF

# 方案2: 添加抑制规则
# inhibition-rules-storm.yaml
cat > /root/inhibition-rules-storm.yaml << 'EOF'
inhibit_rules:
  # 节点级别问题抑制 Pod 级别告警
  - source_match:
      alertname: 'NodeNotReady|NodeMemoryPressure|NodeDiskPressure'
      severity: 'critical'
    target_match_re:
      alertname: 'Pod.*|Container.*|Kubelet.*'
      severity: 'warning|critical'
    equal: ['node', 'instance']
  
  # 集群级别问题抑制命名空间级别告警
  - source_match:
      alertname: 'K8sClusterNotReady|Etcd.*|ApiServer.*'
      severity: 'critical'
    target_match_re:
      severity: 'warning|critical'
    equal: ['cluster']
  
  # 磁盘满抑制磁盘空间不足告警
  - source_match:
      alertname: 'NodeDiskFull'
      severity: 'critical'
    target_match:
      alertname: 'NodeDiskSpaceLow|NodeDiskWillFillIn4Hours'
      severity: 'warning'
    equal: ['instance', 'device']
EOF

# 方案3: 使用静默临时屏蔽
# 创建静默规则（API 方式）
curl -X POST http://alertmanager:9093/api/v1/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [
      {"name": "severity", "value": "warning", "isRegex": false}
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "oncall-engineer",
    "comment": "Suppressing warning alerts during incident response"
  }'

# 方案4: 调整告警阈值
# 避免过于敏感的告警触发
# prometheus-values-alert-fix.yaml
cat >> /root/prometheus-values-alert-fix.yaml << 'EOF'
prometheus:
  prometheusSpec:
    alertingRules:
      groups:
        - name: improved-alerts
          rules:
            # 增加持续时间，避免瞬时波动触发
            - alert: HighMemoryUsage
              expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
              for: 10m           # 从 5m 增加到 10m
              labels:
                severity: warning
            
            # 添加速率限制，避免持续告警
            - alert: PodRestarting
              expr: increase(kube_pod_container_status_restarts_total[1h]) > 5
              for: 15m         # 确保问题持续存在
              labels:
                severity: warning
EOF

# 方案5: 告警收敛配置
# 限制每分钟发送的告警数量
cat > /root/alertmanager-rate-limit.yaml << 'EOF'
global:
  # 限制全局通知速率
  smtp_require_tls: true
  
route:
  receiver: 'default'
  # 使用 continue 控制是否继续匹配其他路由
  routes:
    - match:
        severity: critical
      receiver: 'critical-rate-limited'
      continue: false

receivers:
  - name: 'critical-rate-limited'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/webhook1/send'
        send_resolved: true
        # 使用 max_alerts 限制每次发送的告警数量
        max_alerts: 10
EOF
```

---

## 9. 生产环境建议

### 9.1 监控架构建议

1. **高可用**：Prometheus 至少 2 副本 + Thanos 长期存储
2. **持久化**：使用 SSD 存储 TSDB 数据，PVC 大小根据保留时间和指标量计算
3. **网络**：监控组件部署在独立的命名空间，使用 NetworkPolicy 隔离
4. **资源**：Prometheus 至少 4C8G，Grafana 至少 1C2G

### 9.2 告警策略建议

1. **分级告警**：Critical（5分钟响应）、Warning（30分钟响应）、Info（工作时间）
2. **告警抑制**：配置合理的 inhibit_rules，避免告警风暴
3. **告警静默**：维护窗口使用 Silence，避免误报
4. **告警收敛**：合理设置 group_interval 和 repeat_interval
5. **值班轮转**：配置多套接收器，按团队/人员轮转

### 9.3 Dashboard 建议

1. **分层展示**：集群概览 -> 命名空间 -> 工作负载 -> Pod
2. **关键指标**：CPU/内存/磁盘/网络/容器重启数/Pod 状态
3. **业务指标**：QPS/延迟/错误率/饱和度（USE 方法）和 RED 方法（Rate/Errors/Duration）
4. **SLA 监控**：SLO/SLI Dashboard，追踪可用性和延迟
5. **成本监控**：资源使用率和成本分析 Dashboard

### 9.4 长期存储建议

1. **Thanos**：适合已有 S3/MinIO 的环境，支持全局查询
2. **VictoriaMetrics**：性能更好，资源消耗更低，兼容 Prometheus API
3. **Mimir**：Grafana Labs 出品，与 Grafana 深度集成
4. **保留策略**：热数据 15-30 天（本地 TSDB），温数据 90 天（对象存储），冷数据 1 年+

---

## 10. 生产级配置清单

### 10.1 Prometheus 生产 Values

```yaml
# prometheus-production-values.yaml
# Prometheus 生产环境配置清单

# 全局配置
global:
  imageRegistry: "192.168.1.61"

# Prometheus 配置
prometheus:
  enabled: true
  prometheusSpec:
    # 高可用配置
    replicas: 2
    
    # 资源限制（生产环境推荐）
    resources:
      requests:
        cpu: "1000m"
        memory: "4Gi"
      limits:
        cpu: "4000m"
        memory: "16Gi"
    
    # 存储配置
    retention: "15d"
    retentionSize: "100GB"
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd  # 使用 SSD StorageClass
          resources:
            requests:
              storage: 200Gi
    
    # 抓取配置
    scrapeInterval: "15s"
    evaluationInterval: "15s"
    
    # 启用 WAL 压缩
    walCompression: true
    
    # 查询配置
    query:
      maxConcurrency: 20
      timeout: 2m
    
    # 告警管理器配置
    alerting:
      alertmanagers:
        - namespace: monitoring
          name: alertmanager-operated
          port: web
    
    # 规则文件选择器
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    
    # 附加抓取配置
    additionalScrapeConfigs:
      # 自定义业务指标
      - job_name: 'business-metrics'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
                - production
                - api-gateway
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
            action: keep
            regex: true
          - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
            action: replace
            target_label: __metrics_path__
            regex: (.+)
          - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
            action: replace
            regex: ([^:]+)(?::\d+)?;(\d+)
            replacement: $1:$2
            target_label: __address__
          - action: labelmap
            regex: __meta_kubernetes_pod_label_(.+)
          - source_labels: [__meta_kubernetes_namespace]
            action: replace
            target_label: kubernetes_namespace
          - source_labels: [__meta_kubernetes_pod_name]
            action: replace
            target_label: kubernetes_pod_name
    
    # 指标过滤（减少存储压力）
    metricRelabelings:
      # 丢弃高基数指标
      - sourceLabels: [__name__]
        regex: 'go_memstats_frees_total|go_memstats_mallocs_total|go_memstats_lookups_total'
        action: drop
      # 丢弃调试指标
      - sourceLabels: [__name__]
        regex: '.*_debug_.*'
        action: drop
    
    # Thanos Sidecar 配置（长期存储）
    thanos:
      image: 192.168.1.61/k8s/thanos:v0.34.0
      objectStorageConfig:
        name: thanos-objstore
        key: thanos.yaml
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
    
    # 安全性配置
    securityContext:
      runAsUser: 65534
      runAsNonRoot: true
      fsGroup: 65534
    
    # 亲和性配置（Pod 分散部署）
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                    - prometheus
            topologyKey: kubernetes.io/hostname
    
    # 容忍度配置
    tolerations:
      - key: "monitoring"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"

# Alertmanager 配置
alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: 3  # 生产环境至少3副本
    
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    
    # 持久化配置
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          resources:
            requests:
              storage: 10Gi
    
    # 亲和性配置
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                    - alertmanager
            topologyKey: kubernetes.io/hostname
  
  # 配置文件（通过 Secret 挂载）
  config:
    global:
      resolve_timeout: 5m
      smtp_smarthost: 'smtp.company.com:587'
      smtp_from: 'alertmanager@company.com'
    
    route:
      receiver: 'default'
      group_by: ['alertname', 'namespace', 'severity']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - match:
            severity: critical
          receiver: 'critical-oncall'
          group_wait: 0s
          repeat_interval: 30m
          continue: true
        - match:
            severity: warning
          receiver: 'warning-oncall'
          group_wait: 30s
          repeat_interval: 2h
    
    receivers:
      - name: 'default'
        email_configs:
          - to: 'oncall@company.com'
            send_resolved: true
      - name: 'critical-oncall'
        webhook_configs:
          - url: 'http://alertmanager-dingtalk:8060/dingtalk/critical/send'
            send_resolved: true
        pagerduty_configs:
          - service_key: '<pagerduty-key>'
      - name: 'warning-oncall'
        webhook_configs:
          - url: 'http://alertmanager-dingtalk:8060/dingtalk/warning/send'
            send_resolved: true
    
    inhibit_rules:
      - source_match:
          severity: 'critical'
        target_match:
          severity: 'warning'
        equal: ['alertname', 'namespace']

# Grafana 配置
grafana:
  enabled: true
  replicas: 2
  
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  
  # 管理员密码（生产环境使用 Secret）
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password
  
  # 持久化配置
  persistence:
    enabled: true
    type: pvc
    storageClassName: standard
    size: 20Gi
    accessModes: ["ReadWriteOnce"]
  
  # 服务配置
  service:
    type: ClusterIP
    port: 80
    targetPort: 3000
  
  # Ingress 配置
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.company.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.company.com
  
  # 数据源配置
  additionalDataSources:
    - name: Thanos
      type: prometheus
      url: http://thanos-query:9090
      access: proxy
      isDefault: false
      jsonData:
        timeInterval: "5s"
        httpMethod: POST
    - name: Loki
      type: loki
      url: http://loki-gateway.logging.svc.cluster.local
      access: proxy
      isDefault: false
  
  # Dashboard 配置
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'default'
          orgId: 1
          folder: ''
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/default
  
  # 预加载 Dashboard
  dashboards:
    default:
      k8s-cluster:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      k8s-pods:
        gnetId: 6417
        revision: 1
        datasource: Prometheus
      node-exporter:
        gnetId: 1860
        revision: 36
        datasource: Prometheus
      slo-dashboard:
        url: https://raw.githubusercontent.com/company/grafana-dashboards/main/slo-dashboard.json

# kube-state-metrics 配置
kube-state-metrics:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# node-exporter 配置
nodeExporter:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

# prometheus-adapter 配置
prometheusAdapter:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### 10.2 Alertmanager 生产配置

```yaml
# alertmanager-production.yaml
# Alertmanager 生产环境完整配置

global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.company.com:587'
  smtp_from: 'alertmanager@company.com'
  smtp_auth_username: 'alertmanager@company.com'
  smtp_auth_password: '<smtp-password>'
  smtp_require_tls: true
  slack_api_url: '<slack-webhook-url>'
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
  opsgenie_api_url: 'https://api.opsgenie.com/'
  victorops_api_url: 'https://alert.victorops.com/integrations/generic/20131114/alert/'
  wechat_api_url: 'https://qyapi.weixin.qq.com/cgi-bin/'
  wechat_api_corp_id: '<corp-id>'
  wechat_api_secret: '<secret>'

# 模板配置
templates:
  - '/etc/alertmanager/templates/*.tmpl'

# 路由树配置
route:
  receiver: 'default'
  group_by: ['alertname', 'cluster', 'service', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  
  routes:
    # 1. 按严重级别路由
    - match:
        severity: critical
      receiver: 'critical-multi-channel'
      group_wait: 0s
      group_interval: 1m
      repeat_interval: 30m
      continue: true
      
    - match:
        severity: warning
      receiver: 'warning-oncall'
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 2h
      continue: true
      
    - match:
        severity: info
      receiver: 'info-logging'
      group_wait: 1m
      group_interval: 10m
      repeat_interval: 24h
      continue: false
    
    # 2. 按团队路由
    - match_re:
        team: backend|api|order-service
      receiver: 'team-backend'
      routes:
        - match:
            severity: critical
          receiver: 'backend-critical'
        - match:
            severity: warning
          receiver: 'backend-warning'
          
    - match_re:
        team: frontend|web|mobile
      receiver: 'team-frontend'
      routes:
        - match:
            severity: critical
          receiver: 'frontend-critical'
        - match:
            severity: warning
          receiver: 'frontend-warning'
          
    - match:
        team: infrastructure
      receiver: 'team-infrastructure'
      routes:
        - match:
            severity: critical
          receiver: 'infra-critical'
        - match:
            severity: warning
          receiver: 'infra-warning'
    
    - match:
        team: data
      receiver: 'team-data'
      routes:
        - match:
            severity: critical
          receiver: 'data-critical'
        - match:
            severity: warning
          receiver: 'data-warning'
    
    # 3. 按环境路由
    - match:
        environment: production
      receiver: 'prod-oncall'
      routes:
        - match:
            severity: critical
          receiver: 'prod-escalation'
          group_wait: 0s
          repeat_interval: 15m
          
    - match:
        environment: staging
      receiver: 'staging-oncall'
      routes:
        - match:
            severity: critical
          receiver: 'staging-slack'
          repeat_interval: 1h
          
    - match:
        environment: development
      receiver: 'dev-logging'
      group_wait: 5m
      repeat_interval: 24h
    
    # 4. 按时间段路由
    - match:
        severity: warning
      receiver: 'business-hours-only'
      group_wait: 5m
      active_time_intervals:
        - business_hours

# 接收器配置
receivers:
  # 默认接收器
  - name: 'default'
    email_configs:
      - to: 'oncall@company.com'
        send_resolved: true
        headers:
          Subject: 'Alert: {{ .GroupLabels.alertname }}'
  
  # 关键告警 - 多渠道通知
  - name: 'critical-multi-channel'
    email_configs:
      - to: 'critical@company.com'
        send_resolved: true
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#alerts-critical'
        send_resolved: true
        title: '🔴 Critical Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
    pagerduty_configs:
      - service_key: '<pagerduty-service-key>'
        severity: critical
        description: '{{ .GroupLabels.alertname }}'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/critical/send'
        send_resolved: true
      - url: 'http://alertmanager-wechat:8060/webhook/send'
        send_resolved: true
  
  # 警告告警
  - name: 'warning-oncall'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#alerts-warning'
        send_resolved: true
        title: '⚠️ Warning: {{ .GroupLabels.alertname }}'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/warning/send'
        send_resolved: true
  
  # 信息告警
  - name: 'info-logging'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#alerts-info'
        send_resolved: false
  
  # 团队接收器
  - name: 'team-backend'
    slack_configs:
      - channel: '#team-backend-alerts'
  
  - name: 'backend-critical'
    slack_configs:
      - channel: '#team-backend-critical'
    pagerduty_configs:
      - service_key: '<backend-pagerduty-key>'
  
  - name: 'backend-warning'
    slack_configs:
      - channel: '#team-backend-alerts'
  
  - name: 'team-frontend'
    slack_configs:
      - channel: '#team-frontend-alerts'
  
  - name: 'frontend-critical'
    slack_configs:
      - channel: '#team-frontend-critical'
    pagerduty_configs:
      - service_key: '<frontend-pagerduty-key>'
  
  - name: 'frontend-warning'
    slack_configs:
      - channel: '#team-frontend-alerts'
  
  - name: 'team-infrastructure'
    slack_configs:
      - channel: '#team-infrastructure-alerts'
  
  - name: 'infra-critical'
    slack_configs:
      - channel: '#team-infrastructure-critical'
    pagerduty_configs:
      - service_key: '<infra-pagerduty-key>'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/infra-critical/send'
  
  - name: 'infra-warning'
    slack_configs:
      - channel: '#team-infrastructure-alerts'
  
  # 环境接收器
  - name: 'prod-oncall'
    slack_configs:
      - channel: '#production-alerts'
  
  - name: 'prod-escalation'
    slack_configs:
      - channel: '#production-critical'
    pagerduty_configs:
      - service_key: '<production-pagerduty-key>'
    webhook_configs:
      - url: 'http://alertmanager-dingtalk:8060/dingtalk/prod-critical/send'
  
  - name: 'staging-oncall'
    slack_configs:
      - channel: '#staging-alerts'
  
  - name: 'dev-logging'
    slack_configs:
      - channel: '#development-alerts'

# 抑制规则
inhibit_rules:
  # 节点宕机抑制该节点上的所有 Pod 告警
  - source_match:
      alertname: 'NodeNotReady|NodeDown|NodeMemoryPressure|NodeDiskPressure'
      severity: 'critical'
    target_match_re:
      alertname: 'Pod.*|Container.*|Kubelet.*|Node.*'
      severity: 'warning|critical'
    equal: ['node', 'instance']
  
  # 集群不可用时抑制所有命名空间级别告警
  - source_match:
      alertname: 'K8sClusterNotReady|Etcd.*|ApiServer.*'
      severity: 'critical'
    target_match_re:
      severity: 'warning|critical'
    equal: ['cluster']
  
  # 磁盘满时抑制磁盘即将满的告警
  - source_match:
      alertname: 'NodeDiskFull'
      severity: 'critical'
    target_match:
      alertname: 'NodeDiskSpaceLow|NodeDiskWillFillIn4Hours'
      severity: 'warning'
    equal: ['instance', 'device']
  
  # 高内存使用抑制内存警告
  - source_match:
      alertname: 'NodeMemoryCritical'
      severity: 'critical'
    target_match:
      alertname: 'NodeMemoryHigh'
      severity: 'warning'
    equal: ['instance']
  
  # 网络分区抑制网络延迟告警
  - source_match:
      alertname: 'NetworkPartition'
      severity: 'critical'
    target_match:
      alertname: 'NetworkLatencyHigh'
      severity: 'warning'
    equal: ['instance']

# 时间间隔配置
time_intervals:
  - name: business_hours
    time_intervals:
      - times:
          - start_time: '09:00'
            end_time: '18:00'
        weekdays: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
        location: 'Asia/Shanghai'
  
  - name: weekend
    time_intervals:
      - weekdays: ['saturday', 'sunday']
        location: 'Asia/Shanghai'
  
  - name: maintenance_window
    time_intervals:
      - times:
          - start_time: '02:00'
            end_time: '06:00'
        weekdays: ['sunday']
        location: 'Asia/Shanghai'
```

### 10.3 生产环境部署检查清单

```bash
#!/bin/bash
# production-deployment-checklist.sh
# Prometheus 生产环境部署检查清单

echo "=== Prometheus 生产环境部署检查清单 ==="
echo ""

# 1. 基础设施检查
echo "[1/10] 基础设施检查"
echo "  [ ] StorageClass 已配置 (SSD 优先)"
kubectl get sc
echo "  [ ] 节点资源充足"
kubectl top nodes
echo "  [ ] 网络策略允许监控流量"

# 2. 镜像检查
echo ""
echo "[2/10] 镜像检查"
echo "  [ ] 所有镜像已推送到 Harbor"
docker images | grep 192.168.1.61
echo "  [ ] 镜像版本与配置一致"

# 3. 配置检查
echo ""
echo "[3/10] 配置检查"
echo "  [ ] Values 文件已审核"
echo "  [ ] 资源限制已设置"
echo "  [ ] 持久化存储已配置"
echo "  [ ] 告警规则已验证"

# 4. 安全性检查
echo ""
echo "[4/10] 安全性检查"
echo "  [ ] RBAC 配置正确"
kubectl get clusterrole | grep prometheus
echo "  [ ] NetworkPolicy 已应用"
echo "  [ ] Secret 已加密"

# 5. 高可用检查
echo ""
echo "[5/10] 高可用检查"
echo "  [ ] Prometheus 副本数 >= 2"
kubectl get sts -n monitoring prometheus-prometheus-stack-prometheus -o jsonpath='{.spec.replicas}'
echo ""
echo "  [ ] Alertmanager 副本数 >= 3"
kubectl get sts -n monitoring alertmanager-prometheus-stack-alertmanager -o jsonpath='{.spec.replicas}'
echo ""
echo "  [ ] Pod 反亲和性已配置"

# 6. 监控检查
echo ""
echo "[6/10] 监控检查"
echo "  [ ] Targets 全部 UP"
curl -s http://prometheus:9090/api/v1/targets | jq '.data.activeTargets[].health' | grep -v up || echo "All targets healthy"
echo "  [ ] 告警规则已加载"
curl -s http://prometheus:9090/api/v1/rules | jq '.data.groups | length'
echo "  [ ] Recording Rules 正常"

# 7. 告警检查
echo ""
echo "[7/10] 告警检查"
echo "  [ ] Alertmanager 配置有效"
curl -s http://alertmanager:9093/api/v1/status | jq '.config.original'
echo "  [ ] 告警路由测试通过"
echo "  [ ] 抑制规则已配置"

# 8. 存储检查
echo ""
echo "[8/10] 存储检查"
echo "  [ ] PVC 已绑定"
kubectl get pvc -n monitoring
echo "  [ ] 存储容量充足"
kubectl exec -n monitoring prometheus-prometheus-stack-prometheus-0 -- df -h /prometheus

# 9. 备份检查
echo ""
echo "[9/10] 备份检查"
echo "  [ ] Thanos Sidecar 运行正常"
kubectl get pods -n monitoring -l app.kubernetes.io/name=thanos-sidecar
echo "  [ ] 对象存储可访问"
echo "  [ ] 备份策略已配置"

# 10. 文档检查
echo ""
echo "[10/10] 文档检查"
echo "  [ ] 运维手册已更新"
echo "  [ ] 告警响应流程已确认"
echo "  [ ] 值班表已配置"

echo ""
echo "=== 检查完成 ==="
echo "请确认所有 [ ] 项已勾选"
```

---

> **下一模块：** 07-Loki 日志系统 -- 日志采集、LogQL 查询与日志告警
