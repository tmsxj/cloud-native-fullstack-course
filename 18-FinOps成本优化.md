# 模块18：FinOps成本优化

---

## 1. 概述与架构图

### 1.1 什么是FinOps

FinOps(Financial Operations)是一种云财务管理实践和文化，通过数据驱动的决策实现云支出的最大价值。它将财务责任与云资源管理相结合，让工程、财务和业务团队能够协作优化云成本。

**FinOps核心原则：**

| 原则 | 说明 |
|------|------|
| **团队协作** | 工程、财务、业务团队共同参与成本管理 |
| **集中驱动** | 建立FinOps团队或卓越中心(COE, Center of Excellence) |
| **人人有责** | 每个工程师都对自己的资源成本负责 |
| **即时报告** | 实时可见的成本数据驱动决策 |
| **中心化管理** | 集中购买和优化，分散执行 |

### 1.2 云成本挑战

```
+================================================================================+
|                       云成本管理挑战                                            |
+================================================================================+
|                                                                                |
|  挑战1: 资源浪费                                    挑战2: 成本可见性           |
|  +------------------------+                        +------------------------+   |
|  | - 过度配置            |                        | - 缺乏实时成本数据     |   |
|  | - 闲置资源            |                        | - 无法归因到团队/项目  |   |
|  | - 未使用存储          |                        | - 账单延迟             |   |
|  | - 遗留测试环境        |                        | - 复杂定价模型         |   |
|  +------------------------+                        +------------------------+   |
|                                                                                |
|  挑战3: 缺乏治理                                    挑战4: 优化复杂性           |
|  +------------------------+                        +------------------------+   |
|  | - 无预算控制          |                        | - Spot实例管理         |   |
|  | - 缺乏自动清理        |                        | - 预留实例规划         |   |
|  | - 标签策略不一致      |                        | - 工作负载调优         |   |
|  | - 权限过于宽泛        |                        | - 多区域成本优化       |   |
|  +------------------------+                        +------------------------+   |
|                                                                                |
+================================================================================+
```

### 1.3 FinOps生命周期

```
+================================================================================+
|                    FinOps 生命周期 (Inform → Optimize → Operate)                |
+================================================================================+
|                                                                                |
|  +-------------------+     +-------------------+     +-------------------+    |
|  |    Inform         | --> |    Optimize       | --> |    Operate        |    |
|  |   (告知)          |     |   (优化)          |     |   (运营)          |    |
|  +-------------------+     +-------------------+     +-------------------+    |
|                                                                                |
|  - 成本可见性              - 资源优化             - 持续监控                   |
|  - 分摊与归因              - 定价优化             - 自动化治理                 |
|  - 预算与预测              - 架构优化             - 组织协同                   |
|                                                                                |
|  关键活动:                                                                     |
|  +-------------------+     +-------------------+     +-------------------+    |
|  | - 成本仪表盘      |     | - Right-sizing    |     | - 自动扩缩容        |    |
|  | - 标签策略        |     | - Spot实例        |     | - 成本告警          |    |
|  | - 分摊报告        |     | - 预留实例        |     | - 预算执行          |    |
|  | - 异常检测        |     | - 存储分层        |     | - 治理策略          |    |
|  +-------------------+     +-------------------+     +-------------------+    |
|                                                                                |
+================================================================================+
```

### 1.4 成本可观测架构

```
+================================================================================+
|                    K8s 成本可观测架构                                           |
+================================================================================+
|                                                                                |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   数据采集层       |    |   成本计算层       |    |   展示与告警层       |      |
|  +---------+---------+    +---------+---------+    +---------+---------+      |
|            |                       |                       |                   |
|            v                       v                       v                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | - Kubelet Metrics |    | - Kubecost        |    | - Grafana         |      |
|  | - cAdvisor        | -->| - OpenCost        |--> | - 成本仪表盘      |      |
|  | - Prometheus      |    | - 自定义计算       |    | - 分摊报告        |      |
|  | - Cloud API       |    |                   |    | - 告警通知        |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  数据流:                                                                       |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | Pod资源使用       | -> | 成本模型计算      | -> | 团队/项目成本     |      |
|  | (CPU/Memory/GPU)  |    | (单价 × 用量)     |    | 实时可视化        |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  分摊维度:                                                                     |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | - Namespace       |    | - Label           |    | - Team/Project    |      |
|  | - Deployment      |    | - Annotation      |    | - Environment     |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
+================================================================================+
```

---

## 2. 核心概念

### 2.1 成本分摊 (Chargeback/Showback，成本回分/展示)

```
+----------------------------------------------------------+
|                Chargeback vs Showback                     |
+----------------------------------------------------------+
|                                                          |
|  Showback (成本展示)                                      |
|  +--------------------------------------------------+   |
|  |  - 向团队展示成本数据                              |   |
|  |  - 不实际收费                                      |   |
|  |  - 提高成本意识                                    |   |
|  |  - 适合FinOps初期                                  |   |
|  +--------------------------------------------------+   |
|                                                          |
|  Chargeback (成本分摊)                                    |
|  +--------------------------------------------------+   |
|  |  - 将成本分摊到各部门                              |   |
|  |  - 从部门预算扣除                                  |   |
|  |  - 驱动成本优化行为                                |   |
|  |  - 需要成熟的分摊模型                              |   |
|  +--------------------------------------------------+   |
|                                                          |
|  分摊模型演进:                                            |
|  简单分摊 -> 按资源分摊 -> 按使用分摊 -> 按价值分摊       |
|                                                          |
+----------------------------------------------------------+
```

**分摊模型对比：**

| 模型 | 计算方式 | 优点 | 缺点 |
|------|----------|------|------|
| **平均分摊** | 总成本/团队数 | 简单 | 不公平，无法激励优化 |
| **按资源配额** | 基于ResourceQuota | 可预测 | 实际使用可能低于配额 |
| **按实际使用** | 基于监控数据 | 公平 | 需要精确计量 |
| **混合模型** | 基础费+使用费 | 平衡 | 复杂度较高 |

### 2.2 资源利用率指标

| 指标 | 计算公式 | 健康范围 | 优化方向 |
|------|----------|----------|----------|
| **CPU利用率** | 实际使用/请求 | 60-80% | Right-sizing |
| **内存利用率** | 实际使用/请求 | 60-80% | Right-sizing |
| **Pod密度** | Pod数/节点 | 视规格而定 | 节点优化 |
| **存储利用率** | 已用/总量 | 70-85% | 清理+扩容 |
| **请求/限制比** | 请求值/限制值 | 合理配置 | 避免过度配置 |

### 2.3 闲置资源识别

```
+----------------------------------------------------------+
|                闲置资源识别规则                            |
+----------------------------------------------------------+
|                                                          |
|  Pod级别                                                  |
|  +--------------------------------------------------+   |
|  |  - CPU使用率 < 5% 持续7天                         |   |
|  |  - 内存使用率 < 10% 持续7天                       |   |
|  |  - 无网络流量 持续7天                             |   |
|  |  - 重启次数 = 0 且 运行时间 > 30天                |   |
|  +--------------------------------------------------+   |
|                                                          |
|  存储级别                                                 |
|  +--------------------------------------------------+   |
|  |  - PVC挂载但无写入 持续30天                       |   |
|  |  - 快照/备份超过保留策略                          |   |
|  |  - 未绑定PV 持续7天                               |   |
|  +--------------------------------------------------+   |
|                                                          |
|  负载均衡器                                               |
|  +--------------------------------------------------+   |
|  |  - 无后端Endpoint                                 |   |
|  |  - 无流量 持续7天                                 |   |
|  +--------------------------------------------------+   |
|                                                          |
+----------------------------------------------------------+
```

### 2.4 预留实例/Spot策略

| 策略 | 适用场景 | 折扣 | 风险 |
|------|----------|------|------|
| **On-Demand** | 关键业务，不能中断 | 基准价(按需) | 无 |
| **Reserved** | 稳定负载，1-3年承诺 | 40-60% | 锁定(预留实例) |
| **Spot** | 容错工作负载 | 60-90% | 可能被回收(竞价实例) |
| **Savings Plans** | 灵活承诺，跨服务 | 20-40% | 承诺使用量(节省计划) |

---

## 3. 离线前置准备

### 3.1 Kubecost/OpenCost镜像

```bash
# 创建镜像清单文件
mkdir -p /opt/finops-images
cd /opt/finops-images

# ==================== Kubecost 相关镜像 ====================
cat > kubecost-images.txt << 'EOF'
gcr.io/kubecost1/cost-model:latest
gcr.io/kubecost1/frontend:latest
gcr.io/kubecost1/server:latest
quay.io/prometheus/prometheus:v2.45.0
grafana/grafana:10.0.0
EOF

# ==================== OpenCost 相关镜像 ====================
cat > opencost-images.txt << 'EOF'
ghcr.io/opencost/opencost:latest
ghcr.io/opencost/opencost-ui:latest
EOF

# ==================== 成本优化工具 ====================
cat > finops-tools-images.txt << 'EOF'
bitnami/kubectl:latest
busybox:latest
EOF

# 下载脚本
#!/bin/bash
for file in *.txt; do
    echo "Downloading images from $file..."
    while read image; do
        docker pull $image
        tarname=$(echo $image | tr '/:' '_')
        docker save $image -o ${tarname}.tar
    done < $file
done
```

### 3.2 Prometheus指标准备

```bash
# 确保Prometheus已配置以下指标收集
# 在Prometheus配置中添加或确认以下job

cat >> /opt/prometheus/prometheus.yml << 'EOF'
# Kubelet指标 (用于资源使用)
- job_name: 'kubernetes-kubelet'
  kubernetes_sd_configs:
  - role: node
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_node_label_(.+)
  - target_label: __address__
    replacement: kubernetes.default.svc:443
  - source_labels: [__meta_kubernetes_node_name]
    regex: (.+)
    target_label: __metrics_path__
    replacement: /api/v1/nodes/${1}/proxy/metrics

# cAdvisor指标 (容器资源使用)
- job_name: 'kubernetes-cadvisor'
  kubernetes_sd_configs:
  - role: node
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_node_label_(.+)
  - target_label: __address__
    replacement: kubernetes.default.svc:443
  - source_labels: [__meta_kubernetes_node_name]
    regex: (.+)
    target_label: __metrics_path__
    replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
EOF
```

---

## 4. 实战部署 (轻量)

**资源需求：**
- OpenCost: ~200MB内存
- Kubecost(轻量版): ~500MB内存
- 总内存占用: < 1GB

### 4.1 Kubecost/OpenCost部署

#### 4.1.1 OpenCost架构介绍

```
+================================================================================+
|                        OpenCost 架构                                            |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   OpenCost UI     |  Web界面展示成本数据                                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   OpenCost Server |  成本计算引擎                                            |
|  +---------+---------+                                                         |
|            |                                                                   |
|            +------------------+------------------+                               |
|            |                  |                  |                               |
|            v                  v                  v                               |
|  +----------------+ +----------------+ +----------------+                      |
|  | Prometheus     | | Pricing API    | | K8s API      |                      |
|  | (资源使用数据) | | (云厂商定价)   | | (元数据)     |                      |
|  +----------------+ +----------------+ +----------------+                      |
|                                                                                |
|  成本计算模型:                                                                 |
|  成本 = 资源使用量 × 资源单价 + 固定成本(如节点成本)                            |
|                                                                                |
+================================================================================+
```

#### 4.1.2 OpenCost Helm离线安装

```bash
# 添加OpenCost仓库
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

# 下载Chart
helm pull opencost/opencost --version 1.28.0

# 解压
mkdir -p opencost && tar -xzf opencost-1.28.0.tgz -C opencost --strip-components=1
```

```yaml
# opencost-values.yaml
# 轻量级OpenCost配置
opencost:
  exporter:
    image:
      registry: ghcr.io
      repository: opencost/opencost
      tag: latest
    
    # 资源配置 (轻量)
    resources:
      requests:
        cpu: "100m"  # CPU请求
        memory: "128Mi"  # 内存请求
      limits:
        cpu: "500m"
        memory: "256Mi"
    
    # Prometheus配置
    config:
      name: opencost
      # 使用现有Prometheus
      prometheus:
        internal:
          enabled: true
          namespaceName: monitoring
          serviceName: prometheus-server
          port: 9090
    
    # 自定义定价 (离线环境)
    customPricing:
      enabled: true
      provider: custom
      costModel:
        CPU: 0.05        # 每CPU核心每小时成本
        RAM: 0.01        # 每GB内存每小时成本
        storage: 0.0001  # 每GB存储每小时成本
        GPU: 1.0         # 每GPU每小时成本
        spotCPU: 0.02    # 竞价CPU价格
        spotRAM: 0.005   # 竞价内存价格
  
  ui:
    enabled: true
    image:
      registry: ghcr.io
      repository: opencost/opencost-ui
      tag: latest
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
      limits:
        cpu: "200m"
        memory: "128Mi"
  
  # 数据持久化
  persistence:
    enabled: true
    size: 5Gi
```

```bash
# 安装OpenCost
helm install opencost opencost/opencost \
  -f opencost-values.yaml \
  -n finops \
  --create-namespace

# 查看状态
kubectl get pods -n finops
kubectl get svc -n finops

# 端口转发访问UI
kubectl port-forward -n finops service/opencost 9090:9090
# 访问 http://localhost:9090
```

#### 4.1.3 成本数据收集配置

```yaml
# opencost-configmap.yaml
# OpenCost详细配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: opencost-config
  namespace: finops
data:
  # 分摊配置
  allocation:
    # 默认分摊标签
    defaultLabel: "namespace"
    # 支持的分摊维度
    dimensions:
    - namespace
    - deployment
    - service
    - pod
    - label:app
    - label:team
    - label:project
    - label:environment
  
  # 成本模型配置
  costModel:
    # 是否包含空闲成本
    idle: true
    # 是否包含开销成本
    overhead: true
    # 是否包含系统成本
    system: true
  
  # 数据保留
  retention:
    daily: 30d
    hourly: 7d
```

#### 4.1.4 与Prometheus集成

```yaml
# opencost-servicemonitor.yaml
# 让Prometheus抓取OpenCost指标
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor  # Prometheus服务监控
metadata:
  name: opencost-metrics
  namespace: finops
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: opencost
  endpoints:
  - port: http
    interval: 30s
    path: /metrics
```

```bash
# 验证指标
kubectl port-forward -n finops svc/opencost 9003:9003
curl http://localhost:9003/metrics | grep opencost
```

### 4.2 成本分摊策略

#### 4.2.1 按Namespace分摊

```yaml
# namespace-cost-labels.yaml
# 为Namespace添加成本标签
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha-prod
  labels:
    # 基础标签
    team: team-alpha
    environment: production
    cost-center: cc-12345
    project: ecommerce
    # FinOps专用标签
    finops/owner: "alice@company.com"
    finops/budget: "5000"
    finops/alert-threshold: "80"
```

```bash
# 查看各Namespace成本
kubectl exec -it -n finops deployment/opencost -- \
  curl "http://localhost:9003/allocation?window=7d&aggregate=namespace" | jq .
```

#### 4.2.2 按Label分摊

```yaml
# deployment-with-cost-labels.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: team-alpha-prod
  labels:
    app: payment-service
    # 成本分摊标签
    cost-team: team-alpha  # 成本归属团队
    cost-project: ecommerce
    cost-center: cc-12345
    cost-environment: production
    cost-owner: alice@company.com
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment-service
  template:
    metadata:
      labels:
        app: payment-service
        # Pod级别成本标签
        cost-team: team-alpha
        cost-project: ecommerce
        cost-center: cc-12345
    spec:
      containers:
      - name: payment
        image: payment-service:v1.0
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

```bash
# 按标签查询成本
kubectl exec -it -n finops deployment/opencost -- \
  curl "http://localhost:9003/allocation?window=7d&aggregate=label:cost-team" | jq .
```

#### 4.2.3 按团队/项目分摊

```bash
# cost-report-script.sh
#!/bin/bash
# 生成团队成本报告

NAMESPACES=$(kubectl get ns -l cost-team -o jsonpath='{.items[*].metadata.name}')

echo "=== 团队成本报告 ($(date)) ==="
echo ""

for ns in $NAMESPACES; do
  TEAM=$(kubectl get ns $ns -o jsonpath='{.metadata.labels.cost-team}')
  PROJECT=$(kubectl get ns $ns -o jsonpath='{.metadata.labels.cost-project}')
  CENTER=$(kubectl get ns $ns -o jsonpath='{.metadata.labels.cost-center}')
  
  # 获取Namespace资源使用
  CPU=$(kubectl top namespace $ns --no-headers 2>/dev/null | awk '{print $2}' || echo "N/A")
  MEM=$(kubectl top namespace $ns --no-headers 2>/dev/null | awk '{print $3}' || echo "N/A")
  
  echo "Namespace: $ns"
  echo "  Team: $TEAM"
  echo "  Project: $PROJECT"
  echo "  Cost Center: $CENTER"
  echo "  CPU Usage: $CPU"
  echo "  Memory Usage: $MEM"
  echo ""
done
```

#### 4.2.4 成本报告生成

```yaml
# cost-report-cronjob.yaml
apiVersion: batch/v1
kind: CronJob  # 定时任务
metadata:
  name: weekly-cost-report
  namespace: finops
spec:
  schedule: "0 9 * * 1"  # 每周一上午9点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report-generator
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "Generating cost report..."
              # 调用OpenCost API生成报告
              curl -s "http://opencost.finops.svc:9003/allocation?window=7d&aggregate=namespace" > /tmp/cost-report.json
              
              # 格式化报告
              echo "=== Weekly Cost Report ===" > /tmp/report.txt
              echo "Generated: $(date)" >> /tmp/report.txt
              echo "" >> /tmp/report.txt
              
              # 发送报告 (可以集成邮件/Slack)
              cat /tmp/report.txt
              
              # 保存到PVC
              cp /tmp/cost-report.json /reports/cost-report-$(date +%Y%m%d).json
            volumeMounts:
            - name: reports
              mountPath: /reports
          volumes:
          - name: reports
            persistentVolumeClaim:
              claimName: cost-reports-pvc
          restartPolicy: OnFailure
```

### 4.3 资源优化实践

#### 4.3.1 资源请求优化 (Right-sizing)

```yaml
# rightsizing-analysis.yaml
# 用于分析资源使用并建议优化
apiVersion: v1
kind: ConfigMap
metadata:
  name: rightsizing-rules
  namespace: finops
data:
  analysis.sh: |
    #!/bin/bash
    echo "=== Resource Right-sizing Analysis ==="
    
    # 获取所有Deployment
    kubectl get deployments --all-namespaces -o json | jq -r '
      .items[] | 
      select(.spec.template.spec.containers[0].resources.requests != null) |
      "\(.metadata.namespace)/\(.metadata.name) \(.spec.template.spec.containers[0].resources.requests)"
    '
    
    echo ""
    echo "=== Pods with High Resource Waste ==="
    
    # 分析实际使用vs请求
    kubectl top pods --all-namespaces --containers | awk '
    NR>1 {
      namespace=$1
      pod=$2
      container=$3
      cpu=$4
      mem=$5
      
      # 提取CPU数值 (去掉m后缀)
      gsub(/m/, "", cpu)
      
      # 如果CPU使用<10m，标记为低利用率
      if (cpu < 10) {
        print "LOW_CPU: " namespace "/" pod "/" container " CPU:" cpu "m"
      }
    }'
```

```bash
# 执行分析
kubectl create configmap rightsizing-rules --from-file=analysis.sh -n finops --dry-run=client -o yaml | kubectl apply -f -
```

**Right-sizing建议规则：**

| 场景 | 当前配置 | 建议配置 | 预期节省 |
|------|----------|----------|----------|
| CPU使用<10% | 500m | 100m | 80% |
| 内存使用<20% | 1Gi | 256Mi | 75% |
| 请求=限制 | 灵活配置 | 请求<限制 | 提高调度效率 |
| 无资源配置 | 无 | 设置合理请求 | 避免饥饿 |

#### 4.3.2 闲置Pod识别

```yaml
# idle-resource-detector.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: idle-resource-detector
  namespace: finops
spec:
  schedule: "0 2 * * *"  # 每天凌晨2点
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: finops-sa
          containers:
          - name: detector
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "=== Idle Resource Detection ==="
              
              # 获取7天前的Pod列表 (需要配合metrics-server历史数据或Prometheus)
              # 这里演示基于当前状态的检测
              
              echo "Checking for pods with 0 restarts and old age..."
              kubectl get pods --all-namespaces -o json | jq -r '
                .items[] |
                select(.status.containerStatuses != null) |
                select(.status.containerStatuses[0].restartCount == 0) |
                select(.status.startTime != null) |
                select((now - (.status.startTime | fromdateiso8601)) > 2592000) |
                "\(.metadata.namespace)/\(.metadata.name) Age: \(.status.startTime)"
              '
              
              echo ""
              echo "Checking for unused PVCs..."
              kubectl get pvc --all-namespaces -o json | jq -r '
                .items[] |
                select(.status.phase == "Bound") |
                select(.metadata.annotations["pv.kubernetes.io/bind-completed"] != null) |
                "\(.metadata.namespace)/\(.metadata.name)"
              '
          restartPolicy: OnFailure
```

#### 4.3.3 自动扩缩容策略

```yaml
# hpa-cost-optimized.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler  # HPA水平自动扩缩容
metadata:
  name: cost-optimized-hpa
  namespace: team-alpha-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-service
  minReplicas: 2      # 最小副本数 (保证高可用)
  maxReplicas: 20     # 最大副本数 (成本控制)
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70   # 目标CPU利用率
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80   # 目标内存利用率
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # 缩容冷却期5分钟
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 4
        periodSeconds: 15
      selectPolicy: Max
```

#### 4.3.4 存储成本优化

```yaml
# storage-cost-optimization.yaml
# 存储类成本优化配置
apiVersion: storage.k8s.io/v1
kind: StorageClass  # 存储类，定义存储类型
metadata:
  name: standard-ssd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer  # 延迟绑定，等待Pod调度
parameters:
  type: ssd
  # 成本标签
  cost-tier: standard
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cold-hdd
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: hdd
  # 低成本存储
  cost-tier: economy
allowVolumeExpansion: true
```

```bash
# 存储清理脚本
#!/bin/bash
echo "=== Storage Cost Optimization ==="

# 1. 查找未使用的PV
kubectl get pv | grep Released

# 2. 查找大容量PVC
echo "Large PVCs (>100Gi):"
kubectl get pvc --all-namespaces -o json | jq -r '
  .items[] |
  select(.spec.resources.requests.storage | test("[0-9]+[GT]i")) |
  "\(.metadata.namespace)/\(.metadata.name): \(.spec.resources.requests.storage)"
'

# 3. 查找无状态应用的PVC (可能可以删除)
echo "PVCs from Deployments (consider if needed):"
kubectl get pvc --all-namespaces -o json | jq -r '
  .items[] |
  select(.metadata.ownerReferences == null) |
  "\(.metadata.namespace)/\(.metadata.name)"
'
```

### 4.4 成本告警与治理

#### 4.4.1 成本阈值告警

```yaml
# cost-alerts-prometheus.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule  # Prometheus告警规则
metadata:
  name: cost-alerts
  namespace: monitoring
spec:
  groups:
  - name: cost
    interval: 1h
    rules:
    # Namespace成本告警
    - alert: HighNamespaceCost  # 命名空间成本过高
      expr: |
        sum by (namespace) (
          container_memory_working_set_bytes{container!=""} / 1024 / 1024 / 1024 * 0.01 +
          rate(container_cpu_usage_seconds_total{container!=""}[1h]) * 0.05
        ) > 100
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "High cost detected in namespace {{ $labels.namespace }}"
        description: "Estimated hourly cost is ${{ $value }}"
        
    # 资源利用率低告警
    - alert: LowResourceUtilization
      expr: |
        (
          container_memory_working_set_bytes{container!=""} /
          kube_pod_container_resource_requests{resource="memory",container!=""}
        ) < 0.2
      for: 7d
      labels:
        severity: info
      annotations:
        summary: "Low memory utilization in {{ $labels.namespace }}/{{ $labels.pod }}"
        description: "Memory utilization is below 20% for 7 days"
        
    # 闲置Pod告警
    - alert: IdlePodDetected
      expr: |
        rate(container_cpu_usage_seconds_total{container!=""}[1h]) == 0
        and
        time() - kube_pod_start_time > 604800
      for: 1h
      labels:
        severity: info
      annotations:
        summary: "Potentially idle pod {{ $labels.pod }}"
        description: "Pod has 0 CPU usage for 1 hour and is older than 7 days"
```

#### 4.4.2 预算管理

```yaml
# budget-crd.yaml
# 自定义预算资源
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition  # CRD自定义资源定义
metadata:
  name: budgets.finops.example.com
spec:
  group: finops.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              amount:
                type: number
                description: Budget amount in USD
              period:
                type: string
                enum: [daily, weekly, monthly]
              alertThresholds:
                type: array
                items:
                  type: number
              scope:
                type: object
                properties:
                  namespaces:
                    type: array
                    items:
                      type: string
                  labels:
                    type: object
                    additionalProperties:
                      type: string
---
# example-budget.yaml
apiVersion: finops.example.com/v1
kind: Budget
metadata:
  name: team-alpha-monthly
  namespace: finops
spec:
  amount: 5000
  period: monthly
  alertThresholds: [50, 80, 100]
  scope:
    namespaces:
    - team-alpha-prod
    - team-alpha-dev
    labels:
      team: team-alpha
```

#### 4.4.3 成本异常检测

```python
# cost-anomaly-detector.py
#!/usr/bin/env python3
"""
成本异常检测脚本
使用简单统计方法检测异常成本波动
"""

import json
import requests
import statistics
from datetime import datetime, timedelta

def get_cost_data(window="7d"):
    """从OpenCost获取成本数据"""
    url = f"http://opencost.finops.svc:9003/allocation?window={window}&aggregate=namespace"
    try:
        response = requests.get(url)
        return response.json()
    except Exception as e:
        print(f"Error fetching cost data: {e}")
        return {}

def detect_anomalies(data, threshold=2.0):
    """使用Z-score检测异常"""
    anomalies = []
    
    for namespace, metrics in data.get('data', {}).items():
        costs = []
        for window, values in metrics.items():
            if 'totalCost' in values:
                costs.append(values['totalCost'])
        
        if len(costs) < 3:
            continue
            
        mean = statistics.mean(costs)
        std = statistics.stdev(costs)
        
        if std == 0:
            continue
            
        for i, cost in enumerate(costs):
            z_score = abs(cost - mean) / std
            if z_score > threshold:
                anomalies.append({
                    'namespace': namespace,
                    'cost': cost,
                    'mean': mean,
                    'z_score': z_score,
                    'severity': 'high' if z_score > 3 else 'medium'
                })
    
    return anomalies

def main():
    print("=== Cost Anomaly Detection ===")
    
    # 获取历史数据
    data = get_cost_data("14d")
    
    # 检测异常
    anomalies = detect_anomalies(data)
    
    if anomalies:
        print(f"\nDetected {len(anomalies)} anomalies:")
        for a in anomalies:
            print(f"  [{a['severity'].upper()}] {a['namespace']}: "
                  f"${a['cost']:.2f} (avg: ${a['mean']:.2f}, z-score: {a['z_score']:.2f})")
    else:
        print("\nNo anomalies detected.")

if __name__ == "__main__":
    main()
```

#### 4.4.4 成本优化建议

```yaml
# cost-optimization-recommendations.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cost-recommendations
  namespace: finops
data:
  recommendations.json: |
    {
      "rules": [
        {
          "id": "rightsizing-cpu",
          "name": "CPU Right-sizing",
          "description": "Reduce CPU requests for pods with low utilization",
          "condition": "cpu_utilization < 20% for 7 days",
          "action": "Reduce CPU request by 50%",
          "potential_savings": "30-50%"
        },
        {
          "id": "rightsizing-memory",
          "name": "Memory Right-sizing",
          "description": "Reduce memory requests for pods with low utilization",
          "condition": "memory_utilization < 30% for 7 days",
          "action": "Reduce memory request by 40%",
          "potential_savings": "20-40%"
        },
        {
          "id": "delete-idle-pods",
          "name": "Remove Idle Pods",
          "description": "Delete pods with no activity for extended period",
          "condition": "cpu_usage == 0 for 7 days AND age > 30 days",
          "action": "Review and delete if not needed",
          "potential_savings": "100% of pod cost"
        },
        {
          "id": "spot-instances",
          "name": "Use Spot Instances",
          "description": "Migrate fault-tolerant workloads to spot instances",
          "condition": "workload is fault-tolerant",
          "action": "Add spot toleration and node selector",
          "potential_savings": "60-90%"
        },
        {
          "id": "storage-cleanup",
          "name": "Clean Up Storage",
          "description": "Remove unused PVCs and old snapshots",
          "condition": "PVC not mounted for 30 days",
          "action": "Delete PVC after confirmation",
          "potential_savings": "Variable"
        }
      ]
    }
```

---

## 5. 生产级实践

### 5.1 FinOps团队组织

```
+================================================================================+
|                    FinOps 团队组织结构                                          |
+================================================================================+
|                                                                                |
|  FinOps卓越中心 (FinOps COE)                                                    |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | 战略与治理        |  | 成本优化          |  | 工具与平台        |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | - 预算规划        |  | - 资源优化        |  | - 成本工具        |          |
|  | - 策略制定        |  | - 定价优化        |  | - 自动化          |          |
|  | - 报告与沟通      |  | - 异常处理        |  | - 数据集成        |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
|  嵌入式FinOps角色                                                               |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | 工程团队          |  | 产品团队          |  | 运维团队          |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | - 资源效率        |  | - 功能成本分析    |  | - 容量规划        |          |
|  | - 代码优化        |  | - ROI评估         |  | - 预留规划        |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
+================================================================================+
```

### 5.2 成本优化流程

```
+----------------------------------------------------------+
|                持续成本优化流程                            |
+----------------------------------------------------------+
|                                                          |
|  +-------------------+                                   |
|  | 1. 监控与发现     |                                   |
|  | - 成本仪表盘      |                                   |
|  | - 异常检测        |                                   |
|  | - 利用率分析      |                                   |
|  +---------+---------+                                   |
|            |                                             |
|            v                                             |
|  +-------------------+                                   |
|  | 2. 分析与评估     |                                   |
|  | - 根因分析        |                                   |
|  | - 影响评估        |                                   |
|  | - 优先级排序      |                                   |
|  +---------+---------+                                   |
|            |                                             |
|            v                                             |
|  +-------------------+                                   |
|  | 3. 优化执行       |                                   |
|  | - Right-sizing    |                                   |
|  | - 架构优化        |                                   |
|  | - 自动化治理      |                                   |
|  +---------+---------+                                   |
|            |                                             |
|            v                                             |
|  +-------------------+                                   |
|  | 4. 验证与报告     |                                   |
|  | - 效果验证        |                                   |
|  | - 节省报告        |                                   |
|  | - 经验分享        |                                   |
|  +-------------------+                                   |
|                                                          |
|  循环周期: 每周审查, 每月深度优化, 每季度战略评估         |
|                                                          |
+----------------------------------------------------------+
```

### 5.3 成本与性能平衡

| 场景 | 成本优先策略 | 性能优先策略 | 平衡策略 |
|------|--------------|--------------|----------|
| **开发环境** | Spot实例, 低配置 | N/A | 自动启停 |
| **测试环境** | 按需启动, 共享资源 | 与生产一致 | 定时扩缩容 |
| **生产环境** | 预留实例, 自动扩缩 | 高可用, 低延迟 | 分层架构 |
| **批处理** | Spot实例, 离线运行 | 并行处理 | 弹性资源池 |

### 5.4 成本报告自动化

```yaml
# automated-cost-reporting.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: monthly-cost-report
  namespace: finops
spec:
  schedule: "0 9 1 * *"  # 每月1日上午9点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report-generator
            image: finops-report-generator:latest
            env:
            - name: OPENCOST_URL
              value: "http://opencost.finops.svc:9003"
            - name: REPORT_RECIPIENTS
              value: "finance@company.com,platform@company.com"
            command:
            - /bin/sh
            - -c
            - |
              # 生成月度报告
              python3 /app/generate_report.py \
                --window "30d" \
                --format pdf,excel \
                --output /reports/monthly-cost-report-$(date +%Y%m).pdf
              
              # 发送邮件
              python3 /app/send_email.py \
                --to "$REPORT_RECIPIENTS" \
                --subject "Monthly Cloud Cost Report - $(date +%B %Y)" \
                --attachment /reports/monthly-cost-report-$(date +%Y%m).pdf
              
              # 上传到对象存储
              aws s3 cp /reports/monthly-cost-report-$(date +%Y%m).pdf \
                s3://cost-reports/monthly/
          volumes:
          - name: reports
            emptyDir: {}
          restartPolicy: OnFailure
```

---

## 6. 故障排查案例

### 案例1: OpenCost成本数据不准确

**现象：**
OpenCost显示的成本与预期不符，某些Namespace成本为0。

**排查过程：**
```bash
# 1. 检查OpenCost Pod状态
kubectl get pods -n finops -l app.kubernetes.io/name=opencost

# 2. 查看OpenCost日志
kubectl logs -n finops deployment/opencost -c opencost

# 3. 检查Prometheus连接
curl http://opencost.finops.svc:9003/metrics

# 4. 验证Prometheus指标
kubectl port-forward -n monitoring svc/prometheus-server 9090:9090
curl 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total'

# 5. 检查cAdvisor指标
curl 'http://localhost:9090/api/v1/query?query=container_memory_working_set_bytes'
```

**根因：**
Prometheus缺少cAdvisor指标，导致无法计算容器资源使用。

**解决方案：**
```yaml
# prometheus-scrape-config.yaml
# 添加cAdvisor scrape配置
- job_name: 'kubernetes-cadvisor'
  kubernetes_sd_configs:
  - role: node
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    insecure_skip_verify: true
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  - source_labels: [__meta_kubernetes_node_name]
    target_label: instance
  - target_label: __address__
    replacement: kubernetes.default.svc:443
  - source_labels: [__meta_kubernetes_node_name]
    regex: (.+)
    target_label: __metrics_path__
    replacement: /api/v1/nodes/${1}/proxy/metrics/cadvisor
```

### 案例2: 成本分摊标签不一致

**现象：**
同一团队的多个Namespace成本无法正确汇总。

**排查过程：**
```bash
# 1. 检查各Namespace标签
kubectl get namespaces --show-labels

# 2. 发现标签不一致
# team-alpha-prod: team=alpha
# team-alpha-dev: cost-team=team-alpha
# team-alpha-staging: team=team-alpha

# 3. 检查Pod标签传播
kubectl get pods -n team-alpha-prod --show-labels
kubectl get pods -n team-alpha-dev --show-labels
```

**根因：**
标签命名不统一，有的用`team`，有的用`cost-team`。

**解决方案：**
```yaml
# standardize-labels-policy.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: standardize-cost-labels
spec:
  rules:
  - name: sync-team-label
    match:
      resources:
        kinds:
        - Namespace
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            cost-team: "{{request.object.metadata.labels.team || request.object.metadata.labels.\"cost-team\"}}"
            
  - name: propagate-to-pods
    match:
      resources:
        kinds:
        - Pod
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            cost-team: "{{request.namespaceObject.metadata.labels.\"cost-team\" || request.namespaceObject.metadata.labels.team}}"
```

### 案例3: 预算告警误报

**现象：**
预算告警频繁触发，但实际成本并未超标。

**排查过程：**
```bash
# 1. 检查告警规则
kubectl get prometheusrules -n monitoring cost-alerts -o yaml

# 2. 检查Prometheus查询结果
curl 'http://prometheus.monitoring.svc:9090/api/v1/query?query=container_memory_working_set_bytes'

# 3. 发现指标包含系统Pod
# 系统Pod(如kube-system)不应计入团队成本

# 4. 检查OpenCost配置
kubectl get configmap -n finops opencost -o yaml
```

**根因：**
成本计算包含了系统Namespace，导致团队成本被高估。

**解决方案：**
```yaml
# opencost-exclude-namespaces.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: opencost-config
  namespace: finops
data:
  # 排除系统Namespace
  excluded_namespaces: |
    kube-system
    kube-public
    kube-node-lease
    ingress-nginx
    monitoring
    finops
    calico-system
    tigera-operator
```

---

## 7. 高频面试题

### Q1: 什么是FinOps？它的核心价值是什么？

**答案要点：**
- FinOps是云财务管理实践，通过数据驱动决策实现云支出最大价值
- 核心价值：成本可见性、资源优化、团队协作、预算控制
- 生命周期：Inform(告知) → Optimize(优化) → Operate(运营)
- 不是简单的省钱，而是实现成本与价值的平衡

### Q2: Kubernetes中如何实现成本分摊？

**答案要点：**
- **标签策略**：使用统一标签(cost-team, cost-project, cost-center)
- **Namespace分摊**：按Namespace汇总资源使用
- **实际使用计量**：基于Prometheus/cAdvisor数据计算
- **分摊工具**：OpenCost/Kubecost提供自动分摊
- **分摊模型**：平均分摊、按配额分摊、按使用分摊、混合模型

### Q3: 如何识别和优化Kubernetes中的资源浪费？

**答案要点：**
- **识别方法**：
  - 监控CPU/内存利用率，低于20%持续7天视为低利用率
  - 检查无流量Pod、未使用PVC、闲置LoadBalancer
  - 使用VPA分析资源使用模式
- **优化方法**：
  - Right-sizing：调整requests和limits
  - 自动扩缩容：HPA/VPA动态调整
  - 资源配额：限制Namespace资源上限
  - 定期清理：删除测试环境和临时资源

### Q4: Spot实例在K8s中如何使用？有什么注意事项？

**答案要点：**
- **使用方法**：
  - 添加Spot节点池，设置taint
  - 工作负载添加toleration和nodeSelector
  - 使用Pod Disruption Budget保证最小可用副本
- **注意事项**：
  - 仅用于容错工作负载(批处理、无状态应用)
  - 设置优雅终止处理(termination handler)
  - 监控Spot中断率，准备回退策略
  - 结合Cluster Autoscaler自动补充节点

### Q5: 如何建立有效的成本告警机制？

**答案要点：**
- **多层告警**：
  - 预算阈值告警(50%, 80%, 100%)
  - 异常检测告警(成本突增)
  - 资源利用率告警(低利用率识别)
- **告警策略**：
  - 区分紧急程度(info, warning, critical)
  - 设置告警冷却期避免轰炸
  - 关联成本影响评估
- **自动化响应**：
  - 自动资源清理
  - 自动扩缩容
  - 自动通知相关团队

---

## 8. 生产环境建议

### 8.1 FinOps成熟度模型

| 成熟度 | 特征 | 关键能力 |
|--------|------|----------|
| **Crawl** | 基础可见性 | 成本展示(Showback)，基础标签 |
| **Walk** | 主动优化 | 分摊计费(Chargeback)，优化建议 |
| **Run** | 自动化治理 | 自动优化，预算执行，异常检测 |
| **Fly** | 预测与规划 | 成本预测，容量规划，战略采购 |

### 8.2 成本优化检查清单

```
+----------------------------------------------------------+
|                成本优化检查清单                            |
+----------------------------------------------------------+
|                                                          |
|  日常检查 (Daily)                                         |
|  [ ] 检查成本仪表盘异常                                   |
|  [ ] 查看闲置资源报告                                     |
|  [ ] 确认自动扩缩容正常工作                               |
|                                                          |
|  每周审查 (Weekly)                                        |
|  [ ] 团队成本报告审查                                     |
|  [ ] 资源利用率分析                                       |
|  [ ] 优化建议执行                                         |
|                                                          |
|  每月优化 (Monthly)                                       |
|  [ ] 预留实例规划审查                                     |
|  [ ] 存储成本分析                                         |
|  [ ] 标签策略合规检查                                     |
|  [ ] 成本优化效果评估                                     |
|                                                          |
|  每季度规划 (Quarterly)                                   |
|  [ ] 预算规划与调整                                       |
|  [ ] 长期成本趋势分析                                     |
|  [ ] FinOps流程改进                                       |
|  [ ] 团队培训与分享                                       |
|                                                          |
+----------------------------------------------------------+
```

### 8.3 与前面模块的关联

| 模块 | 关联内容 |
|------|----------|
| 模块06 | Prometheus是成本数据的基础来源 |
| 模块07 | Loki日志可用于成本审计追踪 |
| 模块09 | OpenTelemetry增强成本可观测性 |
| 模块12 | ArgoCD部署的成本优化配置 |
| 模块17 | 多租户成本分摊是平台工程核心能力 |

### 8.4 CKA/CKS相关考点

| 考点 | 内容 | 模块关联 |
|------|------|----------|
| **ResourceQuota** | 资源配额配置 | 模块17 |
| **LimitRange** | 默认资源限制 | 模块17 |
| **HPA** | 自动扩缩容 | 本节4.3.3 |
| **Labels** | 标签用于成本分摊 | 本节4.2 |
| **Monitoring** | 资源监控与告警 | 本节4.4 |

### 8.5 关键成本指标(KPIs)

| KPI | 计算公式 | 目标值 |
|-----|----------|--------|
| **单位成本** | 总成本/业务指标 | 持续降低 |
| **资源利用率** | 实际使用/请求 | 60-80% |
| **分摊覆盖率** | 已标签资源/总资源 | >95% |
| **优化节省** | 优化前成本-优化后成本 | >20% |
| **预算偏差** | |实际-预算|/预算 | <10% |

---

**参考资源：**
- [FinOps Foundation](https://www.finops.org/)
- [OpenCost官方文档](https://www.opencost.io/docs/)
- [Kubecost文档](https://docs.kubecost.com/)
- [CNCF FinOps白皮书](https://www.cncf.io/reports/finops-kubernetes/)
