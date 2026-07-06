# 模块19：AI Native与AIOps

---

## 1. 概述与架构图

### 1.1 AI Native应用特点

AI Native(AI原生)应用是指从设计之初就深度集成AI能力的应用程序，与传统的AI增强应用不同，AI Native将AI作为核心架构组件。

**AI Native应用特征：**

| 特征 | 说明 | 示例 |
|------|------|------|
| **模型即服务** | 模型通过API提供服务 | OpenAI API, HuggingFace |
| **持续学习** | 模型在线更新和迭代 | 推荐系统, 风控模型 |
| **多模态交互** | 支持文本、语音、图像等多种输入 | 智能客服, 数字人 |
| **智能决策** | 自主决策和优化 | 自动驾驶, 智能调度 |
| **弹性伸缩** | 根据推理负载自动扩缩 | LLM推理服务 |

### 1.2 K8s+AI工作负载管理

```
+================================================================================+
|                    Kubernetes AI工作负载管理架构                                |
+================================================================================+
|                                                                                |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   训练工作负载     |    |   推理服务         |    |   数据处理         |      |
|  +---------+---------+    +---------+---------+    +---------+---------+      |
|            |                       |                       |                   |
|            v                       v                       v                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | - PyTorchJob      |    | - KServe          |    | - Spark Operator  |      |
|  | - TFJob           |    | - Seldon Core     |    | - Argo Workflows  |      |
|  | - MPIJob          |    | - Triton Server   |    | - Kubeflow Pipelines|    |
|  +---------+---------+    +---------+---------+    +---------+---------+      |
|            |                       |                       |                   |
|            +-----------------------+-----------------------+                   |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                         GPU资源管理层                                    |    |
|  |  +-------------+  +-------------+  +-------------+  +-------------+   |    |
|  |  | GPU Operator|  | Device Plugin|  | MIG Manager |  | Scheduler   |   |    |
|  |  +-------------+  +-------------+  +-------------+  +-------------+   |    |
|  +=======================================================================+    |
|                                    |                                           |
|                                    v                                           |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |  GPU Nodes        |    |  CPU Nodes        |    |  Storage (PV)     |      |
|  |  (NVIDIA/A100)    |    |  (推理/控制面)     |    |  (模型/数据)      |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
+================================================================================+
```

### 1.3 AIOps概念与价值

AIOps (Artificial Intelligence for IT Operations，智能运维) 是将AI技术应用于IT运维的实践，通过机器学习分析运维数据，实现智能监控、故障预测和自动化修复。

**AIOps核心价值：**

| 价值 | 说明 | 效果 |
|------|------|------|
| **智能告警** | 自动降噪，关联根因 | 减少90%无效告警 |
| **异常检测** | 自动识别指标异常 | 提前发现问题 |
| **根因分析** | 快速定位故障原因 | 缩短MTTR 70% |
| **容量预测** | 预测资源需求 | 避免容量不足 |
| **自动化修复** | 自动执行修复操作 | 减少人工干预 |

### 1.4 智能运维架构图

```
+================================================================================+
|                        AIOps 智能运维架构                                       |
+================================================================================+
|                                                                                |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   数据采集层       |    |   智能分析层       |    |   决策执行层       |      |
|  +---------+---------+    +---------+---------+    +---------+---------+      |
|            |                       |                       |                   |
|            v                       v                       v                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | - Metrics         |    | - 异常检测         |    | - 告警通知         |      |
|  | - Logs            | -->| - 根因分析         |--> | - 自动修复         |      |
|  | - Traces          |    | - 趋势预测         |    | - 弹性伸缩         |      |
|  | - Events          |    | - 关联分析         |    | - 资源优化         |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  数据源:                                                                       |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | Prometheus        |    | Loki/ELK          |    | Jaeger/Tempo      |      |
|  | (指标)            |    | (日志)            |    | (链路)            |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  AI/ML能力:                                                                    |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | 时序预测          |    | 异常检测          |    | 自然语言处理      |      |
|  | (Prophet/ARIMA)   |    | (Isolation Forest)|    | (日志分析)        |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
+================================================================================+
```

---

## 2. 核心概念

### 2.1 GPU资源管理

```
+----------------------------------------------------------+
|                GPU 资源管理模型                            |
+----------------------------------------------------------+
|                                                          |
|  GPU共享策略                                              |
|  +--------------------------------------------------+   |
|  |                                                  |   |
|  |  1. 物理隔离 (整卡分配)                           |   |
|  |     Pod A -> GPU0                                |   |
|  |     Pod B -> GPU1                                |   |
|  |     优点: 性能隔离好                             |   |
|  |     缺点: 利用率低                               |   |
|  |                                                  |   |
|  |  2. MIG (Multi-Instance GPU)                     |   |
|  |     A100 -> 7个独立GPU实例                        |   |
|  |     优点: 硬件级隔离                             |   |
|  |     缺点: 仅支持A100/H100                        |   |
|  |                                                  |   |
|  |  3. Time-slicing (时间片共享)                     |   |
|  |     多个Pod轮流使用GPU                           |   |
|  |     优点: 高利用率                               |   |
|  |     缺点: 上下文切换开销                         |   |
|  |                                                  |   |
|  +--------------------------------------------------+   |
|                                                          |
+----------------------------------------------------------+
```

**GPU资源类型：**

| 资源类型 | 说明 | 适用场景 |
|----------|------|----------|
| `nvidia.com/gpu` | 整卡GPU(独占) | 训练任务 |
| `nvidia.com/mig-3g.20gb` | MIG实例(多实例GPU) | 推理服务 |
| `nvidia.com/gpu.shared` | 共享GPU | 轻量推理 |

### 2.2 AI工作负载调度

```
+----------------------------------------------------------+
|                AI工作负载调度策略                          |
+----------------------------------------------------------+
|                                                          |
|  训练任务调度                                             |
|  +--------------------------------------------------+   |
|  |  - Gang Scheduling( gang 调度): 同时调度所有Worker |   |
|  |  - 避免部分分配导致资源死锁                        |   |
|  |  - 使用Volcano/Yunikorn(高级调度器)               |   |
|  +--------------------------------------------------+   |
|                                                          |
|  推理服务调度                                             |
|  +--------------------------------------------------+   |
|  |  - 负载均衡: 均匀分布到GPU节点                     |   |
|  |  - 亲和性: 同一模型副本调度到不同节点              |   |
|  |  - 优先级: 区分在线/离线推理                       |   |
|  +--------------------------------------------------+   |
|                                                          |
|  批处理任务调度                                           |
|  +--------------------------------------------------+   |
|  |  - 队列管理: 按优先级和资源需求排队                |   |
|  |  - 抢占机制: 高优先级任务抢占低优先级              |   |
|  |  - 资源回收: 任务完成后立即释放资源                |   |
|  +--------------------------------------------------+   |
|                                                          |
+----------------------------------------------------------+
```

### 2.3 模型服务 (Model Serving)

| 服务框架 | 特点 | 适用场景 |
|----------|------|----------|
| **KServe** | K8s原生，支持多种运行时 | 企业级模型服务(推理) |
| **Seldon Core** | 丰富的部署策略 | A/B测试，金丝雀 |
| **NVIDIA Triton** | 高性能推理 | GPU推理优化 |
| **TensorFlow Serving** | TF模型专用 | TensorFlow模型 |
| **TorchServe** | PyTorch专用 | PyTorch模型 |
| **vLLM** | LLM专用优化(高吞吐推理) | 大语言模型推理 |

### 2.4 智能告警/根因分析

```
+----------------------------------------------------------+
|                智能告警降噪流程                            |
+----------------------------------------------------------+
|                                                          |
|  原始告警 (1000条/天)                                     |
|  +--------------------------------------------------+   |
|  |  1. 去重合并                                       |   |
|  |     相同问题多次告警合并为一条                     |   |
|  |     1000 -> 300                                  |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  +--------------------------------------------------+   |
|  |  2. 优先级排序                                     |   |
|  |     基于影响面和紧急程度排序                       |   |
|  |     300 -> 150                                   |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  +--------------------------------------------------+   |
|  |  3. 关联分析                                       |   |
|  |     识别告警间的因果关系                           |   |
|  |     150 -> 30 (根因告警)                         |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  +--------------------------------------------------+   |
|  |  4. 智能通知                                       |   |
|  |     只通知根因，抑制衍生告警                       |   |
|  |     最终: 30条有效告警                           |   |
|  +--------------------------------------------------+   |
|                                                          |
|  降噪效果: 97%  (1000 -> 30)                             |
|                                                          |
+----------------------------------------------------------+
```

---

## 3. 离线前置准备

### 3.1 GPU Operator镜像 (概念介绍)

**注意：** 您的环境无GPU，以下为概念性介绍，供学习参考。

```bash
# GPU Operator相关镜像清单 (概念性)
# 如需实际部署，需要NVIDIA GPU硬件支持

cat > gpu-operator-images.txt << 'EOF'
# GPU Operator核心组件
nvcr.io/nvidia/gpu-operator:v23.9.0
nvcr.io/nvidia/driver:535.104.05
nvcr.io/nvidia/container-toolkit:v1.14.0
nvcr.io/nvidia/device-plugin:v0.14.0
nvcr.io/nvidia/dcgm-exporter:3.2.0

# CUDA基础镜像
nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04
nvcr.io/nvidia/cuda:12.2.0-runtime-ubuntu22.04
nvcr.io/nvidia/cuda:12.2.0-devel-ubuntu22.04

# 深度学习框架
nvcr.io/nvidia/pytorch:23.08-py3
nvcr.io/nvidia/tensorflow:23.08-tf2-py3
EOF
```

### 3.2 KServe/OpenVINO镜像

```bash
# 创建镜像清单文件
mkdir -p /opt/ai-images
cd /opt/ai-images

# ==================== KServe 相关镜像 ====================
cat > kserve-images.txt << 'EOF'
kserve/kserve-controller:v0.11.0
kserve/agent:v0.11.0
kserve/storage-initializer:v0.11.0
kserve/sklearnserver:v0.11.0
kserve/xgbserver:v0.11.0
kserve/pmmlserver:v0.11.0
kserve/lgbserver:v0.11.0
kserve/paddleserver:v0.11.0
custom-model-server:latest
EOF

# ==================== OpenVINO 相关镜像 ====================
cat > openvino-images.txt << 'EOF'
openvino/model_server:latest
openvino/workbench:latest
EOF

# ==================== 推理优化镜像 ====================
cat > inference-images.txt << 'EOF'
vllm/vllm-openai:latest
huggingface/text-embeddings-inference:latest
EOF

# ==================== AIOps相关镜像 ====================
cat > aiops-images.txt << 'EOF'
grafana/otel-lgtm:latest
prometheus/alertmanager:latest
EOF
```

---

## 4. 实战部署 (轻量/概念演示)

**资源需求：**
- KServe (轻量CPU版): ~300MB内存
- 模型服务示例: ~200MB内存
- 总内存占用: < 1GB (CPU模式)

### 4.1 K8s GPU管理 (概念)

#### 4.1.1 GPU Operator架构

```
+================================================================================+
|                        GPU Operator 架构                                        |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   GPU Operator    |  统一管理GPU驱动和工具                                   |
|  +---------+---------+                                                         |
|            |                                                                   |
|            +------------------+------------------+------------------+          |
|            |                  |                  |                  |          |
|            v                  v                  v                  v          |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|  | Node Driver    | | Container      | | Device Plugin  | | DCGM Exporter  |  |
|  | (驱动安装)     | | Toolkit        | | (资源暴露)     | | (监控)         |  |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|                                                                                |
|  部署流程:                                                                     |
|  1. Operator部署 -> 2. 驱动安装 -> 3. Device Plugin注册 -> 4. GPU可调度      |
|                                                                                |
+================================================================================+
```

#### 4.1.2 GPU共享策略 (MIG/Time-slicing)

```yaml
# mig-config.yaml
# MIG配置示例 (需要A100/H100 GPU)
apiVersion: nvidia.com/v1
kind: ClusterPolicy  # GPU集群策略
metadata:
  name: cluster-policy
spec:
  mig:
    strategy: mixed  # MIG策略: mixed/single/none
  migManager:
    enabled: true
    config:
      name: mig-config
---
# mig-profiles.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: mig-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    mig-configs:
      all-disabled:
        - devices: all
          mig-enabled: false
      all-1g.5gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "1g.5gb": 7  # 每个A100分成7个1g.5gb实例
      all-2g.10gb:
        - devices: all
          mig-enabled: true
          mig-devices:
            "2g.10gb": 3
            "1g.5gb": 1
```

```yaml
# time-slicing-config.yaml
# GPU时间片共享配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config  # GPU时间片共享配置
  namespace: gpu-operator
data:
  any: |-
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        resources:
        - name: nvidia.com/gpu
          replicas: 4  # 一个GPU分成4个共享单元
```

#### 4.1.3 GPU监控指标

```yaml
# gpu-metrics-service-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor  # GPU监控采集
metadata:
  name: nvidia-dcgm-exporter
  namespace: monitoring
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: nvidia-dcgm-exporter
  endpoints:
  - port: gpu-metrics
    interval: 30s
    scrapeTimeout: 10s
    metricRelabelings:
    - sourceLabels: [__name__]
      regex: 'DCGM_.*'
      action: keep
```

**关键GPU指标：**

| 指标 | 说明 | 告警阈值 |
|------|------|----------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU利用率 | <20%持续1小时 |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | 显存带宽利用率 | 视场景 |
| `DCGM_FI_DEV_FB_USED` | 显存使用 | >90% |
| `DCGM_FI_DEV_GPU_TEMP` | GPU温度 | >85°C |
| `DCGM_FI_DEV_POWER_USAGE` | 功耗 | 视规格 |

### 4.2 AI工作负载调度 (轻量CPU版)

#### 4.2.1 KServe架构介绍

```
+================================================================================+
|                        KServe 架构                                              |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   InferenceService|  CRD定义模型服务                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   Predictor       |    |   Explainer       |    |   Transformer     |      |
|  |   (推理服务)      |    |   (可解释性)      |    |   (预处理)        |      |
|  +---------+---------+    +-------------------+    +-------------------+      |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   Knative         |    |   Istio           |    |   Storage         |      |
|  |   (Serverless)    |    |   (流量管理)      |    |   (模型存储)      |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  支持的Runtime:                                                                |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | Triton            |  | MLServer          |  | PMML              |          |
|  | TensorFlow        |  | PyTorch           |  | XGBoost           |          |
|  | SKLearn           |  | LightGBM          |  | Custom            |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
+================================================================================+
```

#### 4.2.2 轻量模型服务部署 (使用CPU)

```yaml
# sklearn-iris-inferenceservice.yaml
# 轻量级Scikit-learn模型服务 (CPU模式)
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService  # KServe推理服务CRD
metadata:
  name: iris-classifier
  namespace: ai-services
  annotations:
    # 使用CPU推理
    serving.kserve.io/deploymentMode: RawDeployment  # 直接部署模式
spec:
  predictor:
    sklearn:
      protocolVersion: v1
      storageUri: "gs://kfserving-examples/models/sklearn/1.0/model"  # 模型存储路径
      # 或者使用PVC
      # storageUri: "pvc://model-pvc/model"
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
    # 副本配置
    minReplicas: 1
    maxReplicas: 3
```

```yaml
# custom-model-service.yaml
# 自定义模型服务 (CPU模式)
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: custom-ml-service
  namespace: ai-services
spec:
  predictor:
    containers:
    - name: predictor
      image: custom-model-server:latest
      args:
      - --model_name=custom-model
      - --model_dir=/mnt/models
      env:
      - name: STORAGE_URI
        value: "pvc://model-storage/custom-model"
      resources:
        requests:
          cpu: "200m"
          memory: "512Mi"
        limits:
          cpu: "1000m"
          memory: "1Gi"
      ports:
      - containerPort: 8080
        protocol: TCP
```

```bash
# 安装KServe (轻量版)
# 1. 安装Cert Manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 2. 安装KServe (CPU模式，不安装Istio)
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve.yaml

# 3. 安装KServe Runtime
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.11.0/kserve-runtimes.yaml

# 4. 部署模型服务
kubectl apply -f sklearn-iris-inferenceservice.yaml

# 5. 查看状态
kubectl get inferenceservices -n ai-services

# 6. 测试推理 (端口转发)
kubectl port-forward -n ai-services svc/iris-classifier-predictor 8080:80
curl -v http://localhost:8080/v1/models/iris-classifier:predict \
  -H "Content-Type: application/json" \
  -d '{"instances": [[6.2, 3.4, 5.4, 2.3]]}'
```

#### 4.2.3 自动扩缩容 (KEDA)

```yaml
# keda-scaledobject.yaml
# 基于推理请求的自动扩缩容
apiVersion: keda.sh/v1alpha1
kind: ScaledObject  # KEDA弹性伸缩对象
metadata:
  name: ml-service-scaler
  namespace: ai-services
spec:
  scaleTargetRef:
    name: iris-classifier-predictor
  minReplicaCount: 1  # 最小副本数
  maxReplicaCount: 10  # 最大副本数
  triggers:
  # 基于HTTP请求率
  - type: metrics-api
    metadata:
      targetValue: "100"
      url: "http://prometheus.monitoring.svc:9090/api/v1/query"
      valueLocation: "data.result.0.value.1"
      query: |
        sum(rate(http_requests_total{service="iris-classifier"}[1m]))
  
  # 基于队列深度 (如果使用消息队列)
  - type: kafka
    metadata:
      bootstrapServers: kafka:9092
      consumerGroup: ml-inference-group
      topic: inference-requests
      lagThreshold: "100"
  
  # 基于自定义指标 (GPU利用率)
  # - type: prometheus
  #   metadata:
  #     serverAddress: http://prometheus.monitoring.svc:9090
  #     metricName: dcgm_gpu_utilization
  #     threshold: '70'
  #     query: avg(DCGM_FI_DEV_GPU_UTIL)
```

#### 4.2.4 A/B测试与金丝雀发布

```yaml
# canary-inferenceservice.yaml
# 金丝雀发布配置
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: recommendation-model
  namespace: ai-services
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    canaryTrafficPercent: 20  # 金丝雀: 20%流量到新版本
    model:
      modelFormat:
        name: sklearn
      protocolVersion: v1
      storageUri: "pvc://models/recommendation/v2"  # 新版本模型路径
      resources:
        requests:
          cpu: "200m"
          memory: "512Mi"
```

```yaml
# ab-test-inferenceservice.yaml
# A/B测试配置
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  namespace: ai-services
spec:
  predictor:
    # 模型A (基线)
    model:
      modelFormat:
        name: xgboost
      protocolVersion: v1
      storageUri: "pvc://models/fraud/v1"
      resources:
        requests:
          cpu: "300m"
          memory: "1Gi"
    
    # 模型B (实验)
    canary:
      modelFormat:
        name: xgboost
      protocolVersion: v1
      storageUri: "pvc://models/fraud/v2-experiment"
      resources:
        requests:
          cpu: "300m"
          memory: "1Gi"
    canaryTrafficPercent: 30  # 30%流量到实验版本
```

### 4.3 可观测性AI增强 (概念)

#### 4.3.1 日志异常检测 (概念)

```python
# log-anomaly-detection.py
"""
日志异常检测概念演示
使用简单的统计方法检测日志异常模式
"""

import re
from collections import Counter
import statistics

class LogAnomalyDetector:
    def __init__(self):
        self.pattern_baseline = {}
        self.error_keywords = ['error', 'exception', 'failed', 'fatal', 'panic']
        
    def extract_pattern(self, log_line):
        """提取日志模式，将变量替换为占位符"""
        # 替换时间戳
        pattern = re.sub(r'\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}', '<TIMESTAMP>', log_line)
        # 替换IP地址
        pattern = re.sub(r'\d+\.\d+\.\d+\.\d+', '<IP>', pattern)
        # 替换数字
        pattern = re.sub(r'\d+', '<NUM>', pattern)
        # 替换UUID
        pattern = re.sub(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<UUID>', pattern)
        return pattern
    
    def train_baseline(self, log_lines):
        """训练基线模型"""
        patterns = [self.extract_pattern(line) for line in log_lines]
        self.pattern_baseline = Counter(patterns)
        print(f"Trained baseline with {len(self.pattern_baseline)} unique patterns")
        
    def detect_anomaly(self, log_line):
        """检测单条日志是否异常"""
        pattern = self.extract_pattern(log_line)
        
        # 1. 新模式检测
        is_new_pattern = pattern not in self.pattern_baseline
        
        # 2. 错误关键词检测
        has_error = any(kw in log_line.lower() for kw in self.error_keywords)
        
        # 3. 频率异常检测
        frequency = self.pattern_baseline.get(pattern, 0)
        is_rare = frequency < 5  # 出现次数少于5次视为罕见
        
        anomaly_score = 0
        reasons = []
        
        if is_new_pattern:
            anomaly_score += 0.4
            reasons.append("New pattern")
        if has_error:
            anomaly_score += 0.5
            reasons.append("Contains error keywords")
        if is_rare:
            anomaly_score += 0.1
            reasons.append("Rare pattern")
            
        return {
            'is_anomaly': anomaly_score > 0.5,
            'score': anomaly_score,
            'reasons': reasons,
            'pattern': pattern
        }

# 使用示例
detector = LogAnomalyDetector()

# 训练数据 (正常日志)
normal_logs = [
    "2024-01-15 10:30:00 INFO Request processed successfully",
    "2024-01-15 10:31:00 DEBUG Connection established to 192.168.1.100",
    "2024-01-15 10:32:00 INFO User 12345 logged in",
]

detector.train_baseline(normal_logs)

# 检测异常
test_logs = [
    "2024-01-15 11:00:00 ERROR NullPointerException in PaymentService",  # 异常
    "2024-01-15 11:01:00 INFO Request processed successfully",  # 正常
]

for log in test_logs:
    result = detector.detect_anomaly(log)
    print(f"Log: {log[:50]}...")
    print(f"Anomaly: {result['is_anomaly']}, Score: {result['score']:.2f}")
    print(f"Reasons: {result['reasons']}")
    print()
```

#### 4.3.2 指标预测 (概念)

```python
# metric-forecasting.py
"""
指标预测概念演示
使用简单移动平均和线性趋势进行预测
"""

import statistics
from datetime import datetime, timedelta

class SimpleMetricForecaster:
    def __init__(self, window_size=7):
        self.window_size = window_size
        
    def moving_average(self, values):
        """计算移动平均"""
        if len(values) < self.window_size:
            return statistics.mean(values)
        return statistics.mean(values[-self.window_size:])
    
    def linear_trend(self, values):
        """计算线性趋势"""
        if len(values) < 2:
            return 0
        
        n = len(values)
        x_mean = (n - 1) / 2
        y_mean = statistics.mean(values)
        
        numerator = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(values))
        denominator = sum((i - x_mean) ** 2 for i in range(n))
        
        if denominator == 0:
            return 0
        return numerator / denominator
    
    def forecast(self, historical_values, periods=7):
        """预测未来值"""
        if not historical_values:
            return []
        
        ma = self.moving_average(historical_values)
        trend = self.linear_trend(historical_values)
        
        forecasts = []
        for i in range(1, periods + 1):
            # 移动平均 + 趋势
            forecast = ma + (trend * i)
            forecasts.append(max(0, forecast))  # 确保非负
            
        return forecasts
    
    def detect_anomaly(self, current_value, historical_values, threshold=2.0):
        """基于预测检测异常"""
        if len(historical_values) < 3:
            return False, 0
            
        mean = statistics.mean(historical_values)
        stdev = statistics.stdev(historical_values) if len(historical_values) > 1 else 0
        
        if stdev == 0:
            return current_value != mean, 0
            
        z_score = abs(current_value - mean) / stdev
        is_anomaly = z_score > threshold
        
        return is_anomaly, z_score

# 使用示例
forecaster = SimpleMetricForecaster(window_size=7)

# 模拟CPU使用率数据 (过去14天)
cpu_usage_history = [45, 48, 52, 50, 55, 60, 58, 62, 65, 63, 68, 70, 72, 75]

# 预测未来7天
forecast = forecaster.forecast(cpu_usage_history, periods=7)
print("CPU Usage Forecast (next 7 days):")
for i, val in enumerate(forecast, 1):
    print(f"  Day +{i}: {val:.1f}%")

# 检测当前值是否异常
current = 95  # 突然飙升
is_anomaly, z_score = forecaster.detect_anomaly(current, cpu_usage_history)
print(f"\nCurrent: {current}%")
print(f"Anomaly detected: {is_anomaly}, Z-score: {z_score:.2f}")
```

#### 4.3.3 智能告警降噪 (概念)

```yaml
# intelligent-alerting-rules.yaml
# 智能告警规则配置
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule  # 智能告警规则
metadata:
  name: intelligent-alerts
  namespace: monitoring
spec:
  groups:
  - name: intelligent-alerting
    interval: 30s
    rules:
    # 基础告警 (原始)
    - alert: HighCPURaw  # CPU高告警(原始)
      expr: |
        100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 2m
      labels:
        severity: info
        type: raw
      annotations:
        summary: "High CPU on {{ $labels.instance }}"
        
    # 智能告警 (带上下文)
    - alert: HighCPUIntelligent
      expr: |
        (
          100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        ) and on(instance) (
          # 排除已知维护窗口
          hour() < 2 or hour() > 4
        ) and on(instance) (
          # 排除低负载实例
          node_load1 > 5
        )
      for: 5m
      labels:
        severity: warning
        type: intelligent
      annotations:
        summary: "High CPU on {{ $labels.instance }}"
        description: "CPU > 80% for 5m, not in maintenance window, high load"
        
    # 关联告警 (多个指标同时异常)
    - alert: ResourceExhaustion
      expr: |
        (
          100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        ) and on(instance) (
          (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
        ) and on(instance) (
          (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.05
        )
      for: 2m
      labels:
        severity: critical
        type: correlated
      annotations:
        summary: "Resource exhaustion on {{ $labels.instance }}"
        description: "CPU, Memory, and Disk all critical"
```

### 4.4 AIOps实践入门

#### 4.4.1 根因分析流程

```
+----------------------------------------------------------+
|                自动化根因分析流程                          |
+----------------------------------------------------------+
|                                                          |
|  1. 告警接收                                              |
|  +--------------------------------------------------+   |
|  |  - 接收Prometheus告警                              |   |
|  |  - 解析告警元数据                                  |   |
|  |  - 获取告警上下文                                  |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  2. 数据收集                                              |
|  +--------------------------------------------------+   |
|  |  - 查询相关指标 (前后30分钟)                       |   |
|  |  - 收集相关日志                                    |   |
|  |  - 获取事件信息 (部署、配置变更)                   |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  3. 关联分析                                              |
|  +--------------------------------------------------+   |
|  |  - 时间关联: 告警与事件的时序关系                  |   |
|  |  - 拓扑关联: 服务依赖关系                          |   |
|  |  - 模式匹配: 历史相似故障                          |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  4. 根因推断                                              |
|  +--------------------------------------------------+   |
|  |  - 评分排序可能原因                                |   |
|  |  - 生成根因假设                                    |   |
|  |  - 置信度评估                                      |   |
|  +--------------------------------------------------+   |
|            |                                             |
|            v                                             |
|  5. 结果输出                                              |
|  +--------------------------------------------------+   |
|  |  - 根因报告                                        |   |
|  |  - 修复建议                                        |   |
|  |  - 通知相关人员                                    |   |
|  +--------------------------------------------------+   |
|                                                          |
+----------------------------------------------------------+
```

#### 4.4.2 故障预测概念

```python
# failure-prediction-concept.py
"""
故障预测概念演示
基于趋势分析预测潜在故障
"""

import statistics
from datetime import datetime, timedelta

class FailurePredictor:
    def __init__(self):
        self.thresholds = {
            'disk_full_days': 7,      # 磁盘将在7天内满
            'memory_pressure': 0.9,    # 内存压力阈值
            'cpu_saturation': 0.85,    # CPU饱和阈值
        }
    
    def predict_disk_full(self, usage_history, capacity):
        """预测磁盘何时会满"""
        if len(usage_history) < 3:
            return None
        
        # 计算增长趋势
        growth_rates = []
        for i in range(1, len(usage_history)):
            rate = (usage_history[i] - usage_history[i-1]) / usage_history[i-1]
            growth_rates.append(rate)
        
        avg_growth = statistics.mean(growth_rates)
        current_usage = usage_history[-1]
        
        if avg_growth <= 0:
            return None
        
        # 预测达到100%的时间
        remaining = 100 - current_usage
        days_to_full = remaining / (avg_growth * 100)
        
        return {
            'predicted_full_date': datetime.now() + timedelta(days=days_to_full),
            'days_remaining': days_to_full,
            'risk_level': 'high' if days_to_full < 7 else 'medium' if days_to_full < 30 else 'low'
        }
    
    def predict_resource_exhaustion(self, metrics_history, resource_type):
        """预测资源耗尽"""
        if len(metrics_history) < 7:
            return None
        
        # 计算7天趋势
        recent = metrics_history[-7:]
        trend = statistics.mean(recent) - statistics.mean(metrics_history[:-7])
        
        threshold = self.thresholds.get(f'{resource_type}_saturation', 0.8)
        current = metrics_history[-1]
        
        if trend <= 0:
            return {'risk': 'stable', 'predicted_date': None}
        
        # 简单线性预测
        days_to_threshold = (threshold * 100 - current) / (trend * 100 / 7)
        
        return {
            'risk': 'high' if days_to_threshold < 3 else 'medium' if days_to_threshold < 14 else 'low',
            'predicted_date': datetime.now() + timedelta(days=days_to_threshold) if days_to_threshold > 0 else None,
            'current_utilization': current,
            'trend': 'increasing' if trend > 0 else 'decreasing'
        }

# 使用示例
predictor = FailurePredictor()

# 磁盘使用率历史 (百分比)
disk_usage = [65, 67, 70, 72, 75, 78, 82, 85]
prediction = predictor.predict_disk_full(disk_usage, 100)
print("Disk Full Prediction:")
print(f"  Predicted full date: {prediction['predicted_full_date']}")
print(f"  Days remaining: {prediction['days_remaining']:.1f}")
print(f"  Risk level: {prediction['risk_level']}")

# CPU使用率历史
cpu_usage = [40, 42, 45, 48, 52, 55, 60, 65]
exhaustion = predictor.predict_resource_exhaustion(cpu_usage, 'cpu')
print("\nCPU Exhaustion Prediction:")
print(f"  Risk: {exhaustion['risk']}")
print(f"  Current: {exhaustion['current_utilization']:.1f}%")
print(f"  Trend: {exhaustion['trend']}")
```

#### 4.4.3 自动化修复 (概念)

```yaml
# auto-remediation-workflow.yaml
# 自动化修复工作流 (使用Argo Workflows)
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: auto-remediation
  namespace: aiops
spec:
  entrypoint: remediation-flow
  templates:
  - name: remediation-flow
    steps:
    - - name: analyze-alert
        template: analyze-alert
    - - name: decide-action
        template: decide-action
    - - name: execute-remediation
        template: execute-remediation
        when: "{{steps.decide-action.outputs.parameters.action}} != none"
    - - name: verify-fix
        template: verify-fix
        when: "{{steps.decide-action.outputs.parameters.action}} != none"
        
  - name: analyze-alert
    script:
      image: bitnami/kubectl:latest
      command: [bash]
      source: |
        # 分析告警内容
        ALERT="{{workflow.parameters.alert}}"
        echo "Analyzing alert: $ALERT"
        
        # 查询相关指标
        kubectl exec -it prometheus-pod -- curl \
          "http://localhost:9090/api/v1/query?query=up"
        
        echo "Analysis complete" > /tmp/result.txt
      
  - name: decide-action
    script:
      image: python:3.9-alpine
      command: [python3]
      source: |
        import json
        
        # 决策逻辑
        alert_type = "{{workflow.parameters.alert_type}}"
        severity = "{{workflow.parameters.severity}}"
        
        actions = {
            'PodCrashLoopBackOff': 'restart-pod',
            'HighMemoryUsage': 'scale-up',
            'DiskFull': 'cleanup-logs',
            'ServiceDown': 'check-dependencies'
        }
        
        action = actions.get(alert_type, 'none')
        
        # 输出决策结果
        with open('/tmp/action.txt', 'w') as f:
            f.write(action)
    outputs:
      parameters:
      - name: action
        valueFrom:
          path: /tmp/action.txt
          
  - name: execute-remediation
    script:
      image: bitnami/kubectl:latest
      command: [bash]
      source: |
        ACTION="{{steps.decide-action.outputs.parameters.action}}"
        NAMESPACE="{{workflow.parameters.namespace}}"
        RESOURCE="{{workflow.parameters.resource}}"
        
        case $ACTION in
          restart-pod)
            kubectl delete pod $RESOURCE -n $NAMESPACE
            ;;
          scale-up)
            kubectl scale deployment $RESOURCE --replicas=5 -n $NAMESPACE
            ;;
          cleanup-logs)
            kubectl exec -it $RESOURCE -n $NAMESPACE -- find /var/log -name "*.log" -mtime +7 -delete
            ;;
          *)
            echo "No action taken"
            ;;
        esac
```

---

## 5. 生产级实践

### 5.1 AI平台架构设计

```
+================================================================================+
|                    企业级AI平台架构                                             |
+================================================================================+
|                                                                                |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |   模型开发层       |    |   模型服务层       |    |   运维管理层       |      |
|  +---------+---------+    +---------+---------+    +---------+---------+      |
|            |                       |                       |                   |
|            v                       v                       v                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | - JupyterHub      |    | - KServe          |    | - MLflow          |      |
|  | - Kubeflow        |    | - Model Registry  |    | - Prometheus      |      |
|  | - Ray             |    | - Feature Store   |    | - ArgoCD          |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  数据层:                                                                       |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | 数据湖 (S3/HDFS)  |    | 特征存储 (Feast)  |    | 模型存储 (MinIO)  |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
|  计算层:                                                                       |
|  +-------------------+    +-------------------+    +-------------------+      |
|  | GPU训练集群       |    | CPU推理集群       |    | 弹性资源池        |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
+================================================================================+
```

### 5.2 MLOps与DevOps融合

| 阶段 | DevOps | MLOps | 融合实践 |
|------|--------|-------|----------|
| **开发** | 代码版本控制 | 实验跟踪 | Git + MLflow |
| **构建** | 镜像构建 | 模型训练 | Tekton + Kubeflow |
| **测试** | 单元测试 | 模型验证 | 集成模型测试 |
| **部署** | 应用部署 | 模型发布 | ArgoCD + KServe |
| **监控** | 应用监控 | 模型监控 | 统一可观测性 |

### 5.3 模型版本管理

```yaml
# model-versioning-example.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: recommendation-service
  namespace: ai-services
  annotations:
    # 模型版本信息
    model-version: "v2.3.1"
    model-git-commit: "abc123"
    model-training-date: "2024-01-15"
    model-framework: "xgboost"
    model-metrics: "auc:0.92,accuracy:0.89"
spec:
  predictor:
    model:
      modelFormat:
        name: xgboost
      storageUri: "s3://models/recommendation/v2.3.1"
      # 模型版本标签
      runtime: kserve-mlserver
---
# model-rollout.yaml
# 模型版本滚动更新
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: recommendation-service
  namespace: ai-services
spec:
  predictor:
    # 新版本
    model:
      modelFormat:
        name: xgboost
      storageUri: "s3://models/recommendation/v2.4.0"
    # 金丝雀发布
    canaryTrafficPercent: 10
```

### 5.4 AI成本优化

| 优化策略 | 说明 | 节省 |
|----------|------|------|
| **训练优化** | 使用混合精度、分布式训练 | 30-50%时间 |
| **推理优化** | 模型量化、批处理、缓存 | 50-70%成本 |
| **资源共享** | GPU共享、多模型服务 | 40-60%GPU |
| **弹性伸缩** | 按需启动训练集群 | 70-90%空闲成本 |
| **Spot实例** | 容错训练任务使用Spot | 60-90%计算成本 |

---

## 6. 故障排查案例

### 案例1: 模型服务推理延迟高

**现象：**
KServe模型服务响应时间超过5秒，用户体验差。

**排查过程：**
```bash
# 1. 检查Pod资源使用
kubectl top pod -l serving.kserve.io/inferenceservice=iris-classifier -n ai-services

# 2. 查看Pod日志
kubectl logs -l serving.kserve.io/inferenceservice=iris-classifier -n ai-services

# 3. 检查模型加载时间
kubectl logs -l serving.kserve.io/inferenceservice=iris-classifier -n ai-services | grep "load"

# 4. 测试直接访问Pod
kubectl exec -it <pod-name> -n ai-services -- curl localhost:8080/v1/models/iris-classifier

# 5. 检查HPA状态
kubectl get hpa -n ai-services
```

**根因：**
模型文件存储在远程S3，每次Pod启动都需要下载，且未配置资源限制导致CPU争用。

**解决方案：**
```yaml
# optimized-inferenceservice.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: iris-classifier
  namespace: ai-services
spec:
  predictor:
    sklearn:
      protocolVersion: v1
      storageUri: "pvc://model-cache/iris-model"  # 使用本地PVC缓存
      resources:
        requests:
          cpu: "500m"      # 增加CPU请求
          memory: "512Mi"
        limits:
          cpu: "2000m"     # 提高CPU限制
          memory: "1Gi"
    minReplicas: 2         # 保持最小副本
    containerConcurrency: 10  # 限制并发
```

### 案例2: GPU Pod无法调度

**现象：**
GPU训练任务Pod一直处于Pending状态。

**排查过程：**
```bash
# 1. 查看Pod事件
kubectl describe pod gpu-training-job -n ai-services
# 输出: 0/3 nodes are available: 3 Insufficient nvidia.com/gpu

# 2. 检查GPU节点
kubectl get nodes -l nvidia.com/gpu.present=true

# 3. 检查GPU资源分配
kubectl describe node <gpu-node>
# 查看Allocated resources部分

# 4. 检查GPU Operator状态
kubectl get pods -n gpu-operator

# 5. 检查Device Plugin日志
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

**根因：**
GPU节点上的Device Plugin未正常运行，导致GPU资源未上报到Kubernetes。

**解决方案：**
```bash
# 重启Device Plugin
kubectl rollout restart daemonset nvidia-device-plugin-daemonset -n gpu-operator

# 验证GPU资源
kubectl get node <gpu-node> -o yaml | grep nvidia.com/gpu

# 检查GPU驱动
kubectl exec -it -n gpu-operator <driver-pod> -- nvidia-smi
```

### 案例3: A/B测试结果不准确

**现象：**
模型A/B测试显示新版本效果更好，但上线后效果下降。

**排查过程：**
```bash
# 1. 检查流量分配
kubectl get inferenceservice fraud-detection -n ai-services -o yaml

# 2. 查看各版本指标
kubectl port-forward -n ai-services svc/fraud-detection-predictor 8080:80

# 3. 检查模型版本
kubectl get pods -l serving.kserve.io/inferenceservice=fraud-detection -n ai-services \
  -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'

# 4. 查看KServe Controller日志
kubectl logs -n kserve deployment/kserve-controller-manager
```

**根因：**
流量分配不均匀，部分用户被固定路由到特定版本，导致样本偏差。

**解决方案：**
```yaml
# fair-ab-test.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: fraud-detection
  namespace: ai-services
  annotations:
    # 使用会话保持确保用户体验一致
    serving.kserve.io/enable-sticky-session: "true"
spec:
  predictor:
    model:
      modelFormat:
        name: xgboost
      storageUri: "pvc://models/fraud/v1"
    canary:
      modelFormat:
        name: xgboost
      storageUri: "pvc://models/fraud/v2"
    canaryTrafficPercent: 30
    # 确保随机分配
    logger:
      mode: all
      url: http://message-logger.ai-services.svc.cluster.local
```

---

## 7. 高频面试题

### Q1: 如何在Kubernetes中管理GPU资源？

**答案要点：**
- 使用GPU Operator统一管理GPU驱动和工具
- Device Plugin将GPU资源暴露给Kubernetes调度器
- 支持多种GPU共享策略：整卡分配、MIG、Time-slicing
- 使用DCGM Exporter监控GPU利用率、显存、温度等指标
- 调度策略：节点亲和性、Pod亲和性/反亲和性

### Q2: KServe与传统模型服务有什么区别？

**答案要点：**
- KServe是K8s原生的Serverless模型推理平台
- 支持多种模型框架：TensorFlow、PyTorch、SKLearn、XGBoost等
- 内置自动扩缩容、A/B测试、金丝雀发布
- 标准化推理协议，简化客户端调用
- 支持GPU和CPU推理，可配置资源限制
- 与Istio/Knative集成，提供流量管理能力

### Q3: 什么是AIOps？它如何解决传统运维的痛点？

**答案要点：**
- AIOps是将AI技术应用于IT运维的实践
- 解决痛点：
  - 告警风暴：智能降噪，减少90%无效告警
  - 故障定位慢：自动根因分析，缩短MTTR
  - 容量规划难：基于趋势预测资源需求
  - 重复工作多：自动化修复常见问题
- 核心技术：异常检测、关联分析、预测模型、NLP

### Q4: 如何设计一个高可用的AI推理服务？

**答案要点：**
- **多副本部署**：minReplicas >= 2，跨可用区分布
- **自动扩缩容**：HPA/KEDA基于请求量/延迟自动调整
- **健康检查**：配置liveness和readiness探针
- **优雅终止**：处理完当前请求后再停止Pod
- **模型缓存**：使用PVC缓存模型文件，避免重复下载
- **熔断降级**：配置超时和重试策略
- **监控告警**：监控推理延迟、错误率、资源使用

### Q5: MLOps与DevOps有什么区别？如何融合？

**答案要点：**
- **区别**：
  - DevOps关注代码和应用的CI/CD
  - MLOps额外关注模型、数据、实验的生命周期
  - 模型需要版本管理、性能监控、持续训练
- **融合实践**：
  - 统一Git工作流，代码和模型配置一起管理
  - 使用ArgoCD等工具部署模型服务
  - 统一监控平台，应用和模型指标一起展示
  - 自动化流水线包含模型测试和验证

---

## 8. 生产环境建议

### 8.1 AI平台成熟度模型

| 成熟度 | 特征 | 关键能力 |
|--------|------|----------|
| **Level 1** | 手动管理 | 手工部署模型，无版本控制 |
| **Level 2** | 半自动化 | 基础CI/CD，简单模型服务 |
| **Level 3** | 自动化 | 完整MLOps流程，A/B测试 |
| **Level 4** | 智能化 | 自动优化，智能监控，AIOps |
| **Level 5** | 自治化 | 自学习系统，自动决策 |

### 8.2 AI服务性能优化检查清单

```
+----------------------------------------------------------+
|                AI服务性能优化检查清单                      |
+----------------------------------------------------------+
|                                                          |
|  模型优化                                                 |
|  [ ] 使用模型量化 (INT8/FP16)                            |
|  [ ] 启用批处理推理                                      |
|  [ ] 配置推理缓存                                        |
|  [ ] 使用专用推理引擎 (TensorRT/ONNX Runtime)            |
|                                                          |
|  资源优化                                                 |
|  [ ] 配置合理的资源请求/限制                             |
|  [ ] 使用GPU共享提高利用率                               |
|  [ ] 配置自动扩缩容策略                                  |
|  [ ] 模型文件使用本地缓存                                |
|                                                          |
|  服务优化                                                 |
|  [ ] 配置连接池和超时                                    |
|  [ ] 启用HTTP/2和压缩                                    |
|  [ ] 配置健康检查和优雅终止                              |
|  [ ] 使用服务网格进行流量管理                            |
|                                                          |
+----------------------------------------------------------+
```

### 8.3 与前面模块的关联

| 模块 | 关联内容 |
|------|----------|
| 模块06 | Prometheus监控AI服务指标 |
| 模块08 | Istio服务网格管理AI流量 |
| 模块12 | ArgoCD部署模型服务 |
| 模块13 | Tekton构建ML流水线 |
| 模块17 | 多租户隔离AI资源 |
| 模块18 | FinOps优化AI成本 |

### 8.4 CKA/CKS相关考点

| 考点 | 内容 | 模块关联 |
|------|------|----------|
| **ResourceQuota** | 限制GPU资源配额 | 模块17 |
| **NodeSelector** | GPU节点调度 | 本节4.1 |
| **Taints/Tolerations** | GPU节点专用 | 本节4.1 |
| **HPA** | 推理服务自动扩缩容 | 本节4.2.3 |
| **Monitoring** | GPU和AI服务监控 | 本节4.1.3 |

### 8.5 无GPU环境的替代方案

由于您的环境无GPU，以下是CPU环境的AI实践建议：

| 场景 | GPU方案 | CPU替代方案 |
|------|---------|-------------|
| **模型训练** | GPU集群 | 使用小规模数据在CPU上训练，或使用云GPU |
| **模型推理** | GPU推理 | 使用轻量模型，模型量化，批处理优化 |
| **LLM服务** | vLLM + GPU | 使用较小模型，或CPU优化的推理引擎 |
| **实验开发** | Jupyter + GPU | 使用CPU版Jupyter，小规模数据实验 |

---

## 9. 2026技术趋势 — AI调度与Volcano

> 📌 **2026技术趋势 (KubeCon EU 2026)**
>
> Kubernetes调度正在经历从"作业调度"到"智能体编排"的范式转变。Volcano作为CNCF毕业项目，已成为AI/ML和批处理工作负载调度的事实标准。2026年，随着AI Agent的爆发式增长，调度层面面临全新的挑战和机遇。

### 9.1 趋势概述

**从"作业调度"到"智能体编排"的范式转变：**

| 阶段 | 时间 | 调度对象 | 典型场景 |
|------|------|----------|----------|
| Pod调度 | 2015-2019 | 单个Pod | Web服务、微服务 |
| 批处理调度 | 2019-2023 | PodGroup | 大数据、AI训练 |
| AI推理调度 | 2023-2025 | 模型服务 | LLM推理、推荐 |
| Agent编排 | 2025-2026 | Agent DAG | Multi-Agent协作 |

**Volcano项目进展：**
- 2019年：华为开源，进入CNCF Sandbox
- 2021年：晋升为CNCF Incubating
- 2025年：通过CNCF毕业投票，成为毕业项目
- 2026年：AgentCube子项目孵化，支持AI Agent编排

### 9.2 K8s原生调度 vs Volcano对比

| 维度 | K8s Scheduler | Volcano |
|------|--------------|---------|
| **调度粒度** | Pod | PodGroup ( Gang Scheduling ) |
| **批处理** | 不支持 | Queue管理 |
| **GPU调度** | 基础 (Device Plugin) | 拓扑感知/共享/NUMA |
| **多集群** | 不支持 | Volcano-Global |
| **AI工作负载** | 不支持 | Kthena (LLM推理调度) |
| **Agent编排** | 不支持 | AgentCube (Multi-Agent DAG) |
| **公平调度** | 不支持 | 权重/配额/抢占 |
| **队列管理** | 不支持 | Queue + Capability |
| **拓扑感知** | 基础 | GPU/NIC/存储拓扑 |
| **插件扩展** | Scheduler Framework | 自定义Scheduler Plugin |

```
+================================================================================+
|              K8s原生调度 vs Volcano 调度对比                                      |
+================================================================================+
|                                                                                |
|  K8s原生调度器                                                                   |
|  +----------------------------------------------------------+                 |
|  |  Pod A ──→ 调度到Node1                                    |                 |
|  |  Pod B ──→ 调度到Node2  (可能永远等不到资源)               |                 |
|  |  Pod C ──→ Pending... (死锁风险)                          |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
|  Volcano调度器 (Gang Scheduling)                                               |
|  +----------------------------------------------------------+                 |
|  |  PodGroup {A, B, C} ──→ 全部调度到Node1+Node2             |                 |
|  |  要么全部成功，要么全部等待 (避免部分分配)                  |                 |
|  |  Queue: training-queue (权重: 80)                         |                 |
|  |  Queue: inference-queue (权重: 20)                        |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
+================================================================================+
```

### 9.3 Volcano核心组件

```
+================================================================================+
|                        Volcano 架构                                             |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   vcctl CLI       |  命令行管理工具                                          |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+       |
|  |   Admission       |    |   Volcano         |    |   Volcano         |       |
|  |   Controller      |    |   Scheduler       |    |   Controller      |       |
|  |   (资源校验)      |    |   (核心调度)      |    |   (生命周期管理)   |       |
|  +---------+---------+    +---------+---------+    +---------+---------+       |
|            |                       |                       |                   |
|            +-----------------------+-----------------------+                   |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                      Volcano CRDs                                      |    |
|  |  +-------------+  +-------------+  +-------------+  +-------------+  |    |
|  |  | Queue       |  | PodGroup    |  | VolcanoJob  |  | VCJob       |  |    |
|  |  | (资源队列)  |  | (Pod组)     |  | (批处理)    |  | (MPI/Spark) |  |    |
|  |  +-------------+  +-------------+  +-------------+  +-------------+  |    |
|  +=======================================================================+    |
|                                                                                |
+================================================================================+
```

**核心组件说明：**

| 组件 | 功能 | 资源需求 |
|------|------|----------|
| **Volcano Scheduler** | 核心调度引擎，支持多种调度算法 | ~200MB内存 |
| **Volcano Controller** | 管理CRD生命周期 (Job/Queue/PodGroup) | ~150MB内存 |
| **Admission Controller** | 资源配额校验，PodGroup合法性检查 | ~50MB内存 |
| **vcctl CLI** | 命令行管理Queue、Job、PodGroup | 无 (客户端工具) |

### 9.4 Volcano轻量部署

**资源需求 (轻量模式)：**
- Volcano Scheduler: 200MB内存, 0.5 CPU
- Volcano Controller: 150MB内存, 0.3 CPU
- 总计: ~350MB内存 (无GPU依赖)

#### 9.4.1 Helm离线安装

```bash
# ==================== 离线镜像清单 ====================
cat > volcano-images.txt << 'EOF'
volcanosh/vc-scheduler:v1.10.0
volcanosh/vc-controller-manager:v1.10.0
volcanosh/vc-webhook-manager:v1.10.0
EOF

# 拉取并导入镜像 (离线环境)
for image in $(cat volcano-images.txt); do
  docker pull $image
  docker save $image -o $(echo $image | tr '/' '-' | tr ':' '-').tar
done

# 导入到K8s节点
for tar in *.tar; do
  docker load -i $tar
done

# ==================== Helm安装 ====================
# 下载Chart (离线环境提前下载)
helm repo add volcano-sh https://volcano-sh.github.io/charts
helm pull volcano-sh/volcano --version 1.10.0

# 安装Volcano (轻量模式)
helm install volcano ./volcano-1.10.0.tgz \
  --namespace volcano-system \
  --create-namespace \
  --set scheduler.replicas=1 \
  --set controllerManager.replicas=1 \
  --set admission.replicas=1 \
  --set basic.image_registry="" \
  --set basic.image_tag="v1.10.0"

# 验证安装
kubectl get pods -n volcano-system
kubectl get crd | grep volcano
```

#### 9.4.2 Queue配置

```yaml
# volcano-queue.yaml
# 定义资源队列
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: training-queue
spec:
  weight: 80  # 训练队列权重80%
  capability:
    cpu: "8"
    memory: "32Gi"
  reclaimable: true  # 允许资源回收
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: inference-queue
spec:
  weight: 20  # 推理队列权重20%
  capability:
    cpu: "4"
    memory: "16Gi"
  reclaimable: true
---
apiVersion: scheduling.volcano.sh/v1beta1
kind: Queue
metadata:
  name: mall-demo-queue
spec:
  weight: 50  # 课程mall-demo项目队列
  capability:
    cpu: "4"
    memory: "8Gi"
  reclaimable: true
```

#### 9.4.3 PodGroup配置示例

```yaml
# volcano-podgroup.yaml
# PodGroup: 将多个Pod作为一个调度单元
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: ai-training-group
  namespace: ai-services
spec:
  minMember: 3  # 最少需要3个Pod同时就绪
  queue: training-queue
  priorityClassName: high-priority
  minResources:  # 最少资源需求 (Gang Scheduling判断)
    cpu: "4"
    memory: "16Gi"
---
# PodGroup中的Pod需要关联PodGroup
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-0
  namespace: ai-services
  labels:
    scheduling.volcano.sh/group-name: ai-training-group  # 关联PodGroup
spec:
  schedulerName: volcano  # 使用Volcano调度器
  containers:
  - name: worker
    image: pytorch/pytorch:2.0.1-cpu-py311
    command: ["python", "train.py"]
    resources:
      requests:
        cpu: "2"
        memory: "8Gi"
      limits:
        cpu: "2"
        memory: "8Gi"
---
apiVersion: v1
kind: Pod
metadata:
  name: training-worker-1
  namespace: ai-services
  labels:
    scheduling.volcano.sh/group-name: ai-training-group
spec:
  schedulerName: volcano
  containers:
  - name: worker
    image: pytorch/pytorch:2.0.1-cpu-py311
    command: ["python", "train.py"]
    resources:
      requests:
        cpu: "2"
        memory: "8Gi"
      limits:
        cpu: "2"
        memory: "8Gi"
```

#### 9.4.4 与现有K8s调度器共存

```
+================================================================================+
|              Volcano与K8s原生调度器共存架构                                       |
+================================================================================+
|                                                                                |
|  +-------------------+    +-------------------+                                 |
|  |   K8s Scheduler   |    |   Volcano         |                                 |
|  |   (默认调度器)     |    |   Scheduler       |                                 |
|  +---------+---------+    +---------+---------+                                 |
|            |                       |                                           |
|            v                       v                                           |
|  +-------------------+    +-------------------+                                 |
|  | schedulerName:     |    | schedulerName:     |                                |
|  | "default-scheduler"|    | "volcano"          |                                |
|  +---------+---------+    +---------+---------+                                 |
|            |                       |                                           |
|            v                       v                                           |
|  +-------------------+    +-------------------+                                 |
|  | 普通微服务         |    | AI训练/批处理      |                                 |
|  | mall-demo服务      |    | PodGroup任务       |                                 |
|  | 监控组件           |    | 推理服务           |                                 |
|  +-------------------+    +-------------------+                                 |
|                                                                                |
|  共存规则:                                                                     |
|  - 不指定schedulerName → 使用K8s默认调度器                                      |
|  - 指定schedulerName: volcano → 使用Volcano调度器                               |
|  - 两种调度器共享集群资源池                                                     |
|  - Volcano通过Queue管理资源配额                                                 |
|                                                                                |
+================================================================================+
```

### 9.5 AI Agent调度 (AgentCube概念)

> 📌 **2026技术趋势**
>
> 随着AI Agent的爆发式增长，传统的Pod级别调度已无法满足需求。AgentCube是Volcano社区正在孵化的子项目，专门解决Multi-Agent系统的编排和调度问题。

**Agent工作负载特点：**

| 特点 | 说明 | 调度挑战 |
|------|------|----------|
| **DAG依赖** | Agent之间存在有向无环图依赖 | 需要拓扑排序调度 |
| **动态伸缩** | Agent数量随任务动态变化 | 传统PodGroup固定数量 |
| **异构资源** | 不同Agent需要不同资源 (CPU/GPU/内存) | 多维度资源匹配 |
| **长时运行** | Agent可能运行数小时甚至数天 | 需要抢占和恢复机制 |
| **交互通信** | Agent之间需要低延迟通信 | 网络拓扑感知 |

**Agent编排需求 vs K8s原生调度：**

```
+================================================================================+
|              AI Agent编排需求 vs K8s原生调度                                     |
+================================================================================+
|                                                                                |
|  典型Multi-Agent工作流:                                                         |
|                                                                                |
|  +----------+     +----------+     +----------+                                |
|  | Planner  |────>| Research |────>| Writer   |                                |
|  | Agent    |     | Agent    |     | Agent    |                                |
|  +----------+     +----------+     +----------+                                |
|       |                 |                 |                                    |
|       v                 v                 v                                    |
|  +----------+     +----------+     +----------+                                |
|  | Code     |     | Data     |     | Review   |                                |
|  | Agent    |     | Agent    |     | Agent    |                                |
|  +----------+     +----------+     +----------+                                |
|                                                                                |
|  K8s原生调度:                                                                   |
|  [ ] 不支持DAG依赖关系                                                         |
|  [ ] 不支持Agent间亲和性                                                       |
|  [ ] 无Agent级别的资源隔离                                                      |
|                                                                                |
|  AgentCube (概念):                                                             |
|  [x] AgentGroup CRD (类似PodGroup)                                             |
|  [x] AgentDAG CRD (定义Agent依赖)                                              |
|  [x] Agent亲和性调度 (同节点/同AZ)                                             |
|  [x] Agent通信优化 (共享内存/本地网络)                                          |
|                                                                                |
+================================================================================+
```

**概念演示 (不需要GPU)：**

```yaml
# agentcube-demo.yaml
# Multi-Agent编排概念演示 (CPU模式)
apiVersion: scheduling.volcano.sh/v1beta1
kind: PodGroup
metadata:
  name: mall-recommendation-agents
  namespace: ai-services
spec:
  minMember: 3
  queue: mall-demo-queue
  minResources:
    cpu: "2"
    memory: "4Gi"
---
# Agent 1: 用户行为分析Agent
apiVersion: v1
kind: Pod
metadata:
  name: behavior-analysis-agent
  namespace: ai-services
  labels:
    scheduling.volcano.sh/group-name: mall-recommendation-agents
    agent-type: analysis
spec:
  schedulerName: volcano
  containers:
  - name: agent
    image: python:3.11-slim
    command: ["python", "-c"]
    args:
    - |
      import json, time
      print("Agent 1: Analyzing user behavior...")
      time.sleep(5)
      result = {"users_analyzed": 1000, "patterns_found": 42}
      print(json.dumps(result))
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
---
# Agent 2: 商品推荐Agent
apiVersion: v1
kind: Pod
metadata:
  name: product-recommendation-agent
  namespace: ai-services
  labels:
    scheduling.volcano.sh/group-name: mall-recommendation-agents
    agent-type: recommendation
spec:
  schedulerName: volcano
  containers:
  - name: agent
    image: python:3.11-slim
    command: ["python", "-c"]
    args:
    - |
      import json, time
      print("Agent 2: Generating product recommendations...")
      time.sleep(3)
      result = {"recommendations": ["SKU-001", "SKU-002", "SKU-003"]}
      print(json.dumps(result))
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
---
# Agent 3: 结果聚合Agent
apiVersion: v1
kind: Pod
metadata:
  name: result-aggregation-agent
  namespace: ai-services
  labels:
    scheduling.volcano.sh/group-name: mall-recommendation-agents
    agent-type: aggregation
spec:
  schedulerName: volcano
  containers:
  - name: agent
    image: python:3.11-slim
    command: ["python", "-c"]
    args:
    - |
      import json, time
      print("Agent 3: Aggregating results...")
      time.sleep(2)
      result = {"final_score": 0.92, "confidence": "high"}
      print(json.dumps(result))
    resources:
      requests:
        cpu: "500m"
        memory: "512Mi"
```

### 9.6 跨集群AI编排 (Karmada + Volcano)

> 📌 **2026技术趋势**
>
> 当单个K8s集群资源不足以支撑大规模AI训练时，跨集群编排成为必然选择。Karmada作为CNCF毕业的多集群项目，与Volcano Global协同实现跨集群AI任务编排。

```
+================================================================================+
|              Karmada + Volcano 跨集群AI编排架构                                   |
+================================================================================+
|                                                                                |
|  +=======================================================================+    |
|  |                        Karmada Control Plane                            |    |
|  |  +-------------------+    +-------------------+    +-------------------+ |    |
|  |  | Karmada           |    | Karmada           |    | Volcano           | |    |
|  |  | Scheduler         |    | Controller        |    | Global            | |    |
|  |  | (集群选择)        |    | (资源分发)        |    | (跨集群调度)      | |    |
|  |  +-------------------+    +-------------------+    +-------------------+ |    |
|  +=======================================================================+    |
|            |                       |                       |                   |
|            +-----------------------+-----------------------+                   |
|            |                       |                       |                   |
|            v                       v                       v                   |
|  +-------------------+    +-------------------+    +-------------------+       |
|  | Cluster A         |    | Cluster B         |    | Cluster C         |       |
|  | (GPU训练集群)     |    | (CPU推理集群)     |    | (弹性资源池)      |       |
|  | +------+ +------+ |    | +------+ +------+ |    | +------+ +------+ |       |
|  | |Volc. | |Volc. | |    | |Volc. | |Volc. | |    | |Volc. | |Volc. | |       |
|  | |Sched.| |Contr.| |    | |Sched.| |Contr.| |    | |Sched.| |Contr.| |       |
|  | +------+ +------+ |    | +------+ +------+ |    | +------+ +------+ |       |
|  | GPU: 8x A100      |    | CPU: 64核         |    | CPU: 32核         |       |
|  | 训练Worker: 4     |    | 推理副本: 8       |    | 弹性伸缩: 0-16    |       |
|  +-------------------+    +-------------------+    +-------------------+       |
|                                                                                |
|  任务拆分策略:                                                                   |
|  1. 训练任务 → Cluster A (GPU密集)                                             |
|  2. 推理服务 → Cluster B (CPU密集)                                             |
|  3. 数据预处理 → Cluster C (弹性伸缩)                                           |
|  4. 跨集群数据同步 → Karmada PropagationPolicy                                  |
|                                                                                |
+================================================================================+
```

**跨集群AI任务拆分示例：**

```yaml
# karmada-volcano-multi-cluster.yaml
# 跨集群AI训练任务 (概念演示)
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: ai-training-propagation
spec:
  resourceSelectors:
  - apiVersion: scheduling.volcano.sh/v1beta1
    kind: Queue
    name: training-queue
  - apiVersion: scheduling.volcano.sh/v1beta1
    kind: PodGroup
    name: cross-cluster-training
  placement:
    clusterAffinity:
      clusterNames:
      - gpu-cluster-a    # 训练任务只在GPU集群
      - gpu-cluster-b    # 多GPU集群分担
    replicaScheduling:
      replicaDivisionPreference: Weighted
      replicaSchedulingType: Divided
      weightPreference:
        staticWeightList:
        - targetCluster:
            clusterNames:
            - gpu-cluster-a
          weight: 60
        - targetCluster:
            clusterNames:
            - gpu-cluster-b
          weight: 40
```

**资源需求 (跨集群模式)：**
- Karmada Control Plane: ~500MB内存 (管理节点)
- 每个成员集群Volcano: ~350MB内存
- 网络要求: 集群间低延迟网络 (推荐 <10ms)

---

## 10. 2026技术趋势 — Serverless与微服务融合

> 📌 **2026技术趋势**
>
> Serverless不再是FaaS (Function-as-a-Service) 的专属概念，正在与微服务深度融合。Knative Serving让任意容器化应用具备"伸缩至零"的能力，为低频服务 (如通知、报表) 提供极致弹性。2026年，Serverless微服务已成为云原生架构的标配模式。

### 10.1 趋势概述

**Serverless与微服务融合的驱动力：**

| 驱动力 | 说明 | 影响 |
|--------|------|------|
| **成本优化** | 低频服务持续占用资源浪费严重 | 伸缩至零节省60-80%资源 |
| **弹性需求** | 业务峰值/低谷差异巨大 | 自动伸缩应对突发流量 |
| **运维简化** | 无需关心副本数和扩缩策略 | 平台自动管理 |
| **绿色计算** | 减少空闲资源降低碳排放 | ESG合规要求 |

**典型低频服务场景：**

| 服务 | 调用频率 | 传统部署问题 | Serverless优势 |
|------|----------|-------------|----------------|
| **邮件通知** | 每天几十次 | 3副本24h运行，利用率<1% | 伸缩至零，按需启动 |
| **报表生成** | 每周/月一次 | 空闲时浪费8核16G | 需要时启动，完成后缩零 |
| **数据导出** | 用户触发 | 固定副本无法应对突发 | 自动扩缩，冷启动1-3秒 |
| **优惠券发放** | 营销活动期间 | 平时浪费，活动时不够 | 弹性伸缩，成本最优 |

### 10.2 传统微服务 vs Serverless对比

| 维度 | 传统Deployment | Knative Serving |
|------|---------------|----------------|
| **弹性** | HPA (最少1副本) | 伸缩至零 (0副本) |
| **冷启动** | 无 | 1-3秒 (CPU模式) |
| **适用场景** | 高频服务 (订单/支付) | 低频/突发服务 (通知/报表) |
| **资源效率** | 持续占用 | 按需使用 |
| **成本** | 固定 (24h运行) | 可变 (按实际使用) |
| **编程模型** | 完整应用 (Spring Boot) | Function / 完整应用均可 |
| **流量管理** | Ingress / Service | 自动路由 + 流量分流 |
| **版本管理** | 手动Rollout | 自动流量切换 |
| **可观测性** | 需要额外配置 | 内置指标采集 |

```
+================================================================================+
|              传统微服务 vs Serverless (Knative) 资源利用对比                      |
+================================================================================+
|                                                                                |
|  传统 Deployment (notification-service, 3副本 x 24h)                           |
|  +----------------------------------------------------------+                 |
|  |  CPU使用率                                                 |                 |
|  |  100% |                                                    |                 |
|  |   80% |                                                    |                 |
|  |   60% |                                                    |                 |
|  |   40% |                                                    |                 |
|  |   20% |  ██                                              |                 |
|  |    0% |__██______________________________________________ |                 |
|  |       00  02  04  06  08  10  12  14  16  18  20  22  24 |                 |
|  |       ← 实际使用仅2% →  ← 98%资源浪费 →                   |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
|  Knative Serving (notification-service, 伸缩至零)                               |
|  +----------------------------------------------------------+                 |
|  |  CPU使用率                                                 |                 |
|  |  100% |  ██  ██                                           |                 |
|  |   80% |  ██  ██                                           |                 |
|  |   60% |  ██  ██                                           |                 |
|  |   40% |  ██  ██                                           |                 |
|  |   20% |  ██  ██                                           |                 |
|  |    0% |__██  ██__________________________________________ |                 |
|  |       08  09  12  14  18  20                               |                 |
|  |       ← 按需启动 →  ← 0副本空闲 →                          |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
|  资源节省: ~80% (低频服务场景)                                                  |
|                                                                                |
+================================================================================+
```

### 10.3 Knative Serving架构

```
+================================================================================+
|                        Knative Serving 架构                                     |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   用户请求         |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Ingress/Gateway |  (Istio/Contour)                                       |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Activator       |  请求缓冲 (缩零时接收请求，唤醒Pod)                     |
|  +---------+---------+                                                         |
|            |  (缩零状态: 缓冲请求)                                              |
|            |  (运行状态: 直接转发)                                              |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Queue-Proxy     |  Sidecar: 指标采集 + 请求排队 + 并发控制                |
|  |   (每个Pod内)     |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   User Container  |  业务容器 (Spring Boot / Function)                      |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Autoscaler      |  基于并发数/RTB自动伸缩 (含缩零决策)                   |
|  +-------------------+                                                         |
|                                                                                |
|  核心CRD:                                                                      |
|  +-------------------+  +-------------------+  +-------------------+          |
|  | Service           |  | Configuration     |  | Revision          |          |
|  | (路由+配置)       |  | (模板+环境变量)   |  | (不可变版本快照)  |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|  +-------------------+  +-------------------+                                 |
|  | Route             |  | PodAutoscaler     |                                 |
|  | (流量分发)        |  | (伸缩配置)        |                                 |
|  +-------------------+  +-------------------+                                 |
|                                                                                |
+================================================================================+
```

**伸缩至零时序图：**

```
+================================================================================+
|                        Knative 伸缩至零时序                                      |
+================================================================================+
|                                                                                |
|  请求1 (缩零状态)                                                               |
|  +----------------------------------------------------------+                 |
|  |  Client  Activator  Autoscaler  Deployment  Pod           |                 |
|  |    |-------->|          |           |          |          |                 |
|  |    |  HTTP   |          |           |          |          |                 |
|  |    |  Req    |          |           |          |          |                 |
|  |    |         |--------->|           |          |          |                 |
|  |    |         | 需要扩容 |           |          |          |                 |
|  |    |         |--------->|--------->|          |          |                 |
|  |    |         |         | 创建Pod   |          |          |                 |
|  |    |         |         |           |--------->|          |                 |
|  |    |         |         |           |          | 启动中   |                 |
|  |    |         |         |           |          | (冷启动) |                 |
|  |    |         |         |           |<---------|          |                 |
|  |    |         |         |           | Pod Ready|          |                 |
|  |    |<--------|         |           |          |          |                 |
|  |    | 转发请求|         |           |          |          |                 |
|  |    |-------->|------------------------->|------>|          |                 |
|  |    |         |         |           |          | 处理请求 |                 |
|  |<---|---------|<-------------------------|<------|          |                 |
|  |    |  响应   |         |           |          |          |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
|  请求2 (运行状态, 直接转发)                                                     |
|  +----------------------------------------------------------+                 |
|  |  Client  Activator  Queue-Proxy  Pod                      |                 |
|  |    |---------------------->|------->|                     |                 |
|  |    |  直接转发 (绕过Activator)       |                     |                 |
|  |<---|<----------------------|<-------|                     |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
|  空闲超时 (默认60秒无请求)                                                      |
|  +----------------------------------------------------------+                 |
|  |  Autoscaler  Deployment  Pod                             |                 |
|  |     |--------->|          |                               |                 |
|  |     | 缩容至0  |          |                               |                 |
|  |     |         |--------->|                               |                 |
|  |     |         | 删除Pod  |                               |                 |
|  |     |         |          X                               |                 |
|  +----------------------------------------------------------+                 |
|                                                                                |
+================================================================================+
```

### 10.4 Knative轻量部署

**资源需求 (轻量模式)：**
- Knative Serving Core: ~400MB内存
- Activator: ~200MB内存
- Queue-Proxy (每Pod): ~20MB内存
- 总计: ~600MB内存 (无Istio依赖，使用Contour)

#### 10.4.1 Helm离线安装

```bash
# ==================== 离线镜像清单 ====================
cat > knative-images.txt << 'EOF'
# Knative Serving Core
gcr.io/knative-releases/knative.dev/serving/cmd/activator:v1.14.0
gcr.io/knative-releases/knative.dev/serving/cmd/autoscaler:v1.14.0
gcr.io/knative-releases/knative.dev/serving/cmd/controller:v1.14.0
gcr.io/knative-releases/knative.dev/serving/cmd/webhook:v1.14.0
gcr.io/knative-releases/knative.dev/serving/cmd/domain-mapping:v1.14.0
gcr.io/knative-releases/knative.dev/serving/cmd/domain-mapping-webhook:v1.14.0

# Queue-Proxy
gcr.io/knative-releases/knative.dev/serving/cmd/queue:v1.14.0

# 网络层 (Contour, 替代Istio)
ghcr.io/projectcontour/contour:v1.30.0
ghcr.io/projectcontour/contour-crd:v1.30.0
EOF

# 拉取并导入镜像 (离线环境)
for image in $(cat knative-images.txt); do
  docker pull $image
  docker save $image -o $(echo $image | tr '/' '-' | tr ':' '-').tar
done

# 导入到K8s节点
for tar in *.tar; do
  docker load -i $tar
done

# ==================== 安装Contour (替代Istio, 更轻量) ====================
# 下载Contour CRD
kubectl apply -f https://github.com/projectcontour/contour/releases/download/v1.30.0/contour.yaml

# 配置Knative使用Contour
kubectl patch configmap/config-network \
  -n knative-serving \
  --type merge \
  -p '{"data":{"ingress.class":"contour.ingress.networking.knative.dev"}}'

# ==================== 安装Knative Serving ====================
# 下载Chart (离线环境提前下载)
helm repo add knative https://knative.github.io/charts
helm pull knative/serving --version 1.14.0

# 安装Knative Serving (轻量模式)
helm install knative-serving ./serving-1.14.0.tgz \
  --namespace knative-serving \
  --create-namespace \
  --set activator.replicas=1 \
  --set autoscaler.replicas=1 \
  --set controller.replicas=1 \
  --set webhook.replicas=1

# 验证安装
kubectl get pods -n knative-serving
kubectl get ksvc -A
```

#### 10.4.2 Eventing组件 (可选)

```bash
# ==================== Knative Eventing (可选) ====================
cat > knative-eventing-images.txt << 'EOF'
gcr.io/knative-releases/knative.dev/eventing/cmd/eventing-controller:v1.14.0
gcr.io/knative-releases/knative.dev/eventing/cmd/imc-controller:v1.14.0
gcr.io/knative-releases/knative.dev/eventing/cmd/mtpingress:v1.14.0
gcr.io/knative-releases/knative.dev/eventing/cmd/broker:v1.14.0
gcr.io/knative-releases/knative.dev/eventing/cmd/mt-broker-filter:v1.14.0
gcr.io/knative-releases/knative.dev/eventing/cmd/mt-broker-ingress:v1.14.0
EOF

# 安装Eventing (如需事件驱动)
helm pull knative/eventing --version 1.14.0
helm install knative-eventing ./eventing-1.14.0.tgz \
  --namespace knative-eventing \
  --create-namespace
```

### 10.5 Spring Cloud Function适配

> 📌 **2026技术趋势**
>
> Spring Cloud Function + Knative 实现了Java函数式编程与Serverless的完美结合。开发者可以使用熟悉的Spring Boot开发模型，同时获得Knative的自动伸缩能力。

#### 10.5.1 Function编程模型

```java
// EmailNotificationFunction.java
// Spring Cloud Function - 邮件通知函数
package com.mall.notification;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import java.util.function.Function;

@Configuration
public class EmailNotificationFunction {

    /**
     * 邮件通知函数
     * 输入: 订单事件JSON
     * 输出: 发送结果JSON
     */
    @Bean
    public Function<OrderEvent, NotificationResult> sendEmail() {
        return orderEvent -> {
            // 1. 构建邮件内容
            String subject = String.format("订单确认: %s", orderEvent.getOrderNo());
            String body = String.format(
                "尊敬的%s，您的订单%s已确认，金额: %.2f元",
                orderEvent.getUserName(),
                orderEvent.getOrderNo(),
                orderEvent.getAmount()
            );

            // 2. 发送邮件 (实际项目中调用邮件服务)
            System.out.println("Sending email: " + subject);
            System.out.println("To: " + orderEvent.getEmail());
            System.out.println("Body: " + body);

            // 3. 返回结果
            NotificationResult result = new NotificationResult();
            result.setSuccess(true);
            result.setMessageId("msg-" + System.currentTimeMillis());
            result.setChannel("EMAIL");
            return result;
        };
    }
}

// 数据模型
class OrderEvent {
    private String orderNo;
    private String userName;
    private String email;
    private Double amount;
    // getters & setters ...
}

class NotificationResult {
    private boolean success;
    private String messageId;
    private String channel;
    // getters & setters ...
}
```

```yaml
# application.yml
# Spring Cloud Function 配置
spring:
  cloud:
    function:
      definition: sendEmail  # 函数名
    stream:
      bindings:
        sendEmail-in-0:
          destination: order-events  # Kafka Topic
          group: notification-group
        sendEmail-out-0:
          destination: notification-results
      kafka:
        binder:
          brokers: kafka:9092
```

#### 10.5.2 与Knative集成

```yaml
# knative-notification-service.yaml
# 将Spring Cloud Function部署到Knative Serving
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: notification-service
  namespace: mall-demo
spec:
  template:
    metadata:
      annotations:
        # 伸缩至零配置
        autoscaling.knative.dev/min-scale: "0"       # 最小0副本 (缩零)
        autoscaling.knative.dev/max-scale: "5"        # 最大5副本
        autoscaling.knative.dev/scale-to-zero-pod-retention-period: "60s"  # 60秒无流量缩零
        autoscaling.knative.dev/target: "1"          # 每个Pod处理1个并发请求
    spec:
      containers:
      - image: mall-notification:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_CLOUD_FUNCTION_DEFINITION
          value: "sendEmail"
        - name: KAFKA_BOOTSTRAP_SERVERS
          value: "kafka:9092"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
        # 冷启动优化
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 2
```

#### 10.5.3 电商通知服务示例 (Kafka事件驱动)

```
+================================================================================+
|              Knative + Kafka 事件驱动通知服务架构                                 |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   订单服务         |  mall-demo order-service                                |
|  |   (Deployment)    |  高频服务, 保持运行                                      |
|  +---------+---------+                                                         |
|            |                                                                   |
|            | 1. 发布订单事件                                                    |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Kafka           |                                                         |
|  |   Topic:          |                                                         |
|  |   order-events    |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            | 2. KafkaSource触发                                                |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Knative         |  事件触发 → 自动唤醒Pod                                  |
|  |   Service         |  notification-service (Knative)                         |
|  |   (伸缩至零)      |  处理完成后自动缩零                                      |
|  +---------+---------+                                                         |
|            |                                                                   |
|            | 3. 发送通知                                                       |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+       |
|  |   邮件服务         |    |   短信服务         |    |   App推送          |       |
|  |   (SMTP)          |    |   (SMS API)       |    |   (FCM/APNs)       |       |
|  +-------------------+    +-------------------+    +-------------------+       |
|                                                                                |
|  优势:                                                                         |
|  - 无订单时不占用资源 (缩零)                                                   |
|  - 大促期间自动扩容 (Knative Autoscaler)                                       |
|  - 事件驱动, 解耦订单与通知                                                    |
|  - 成本节省约80% (相比3副本24h运行)                                            |
|                                                                                |
+================================================================================+
```

```yaml
# knative-kafka-source.yaml
# Kafka事件源 → 触发Knative Service
apiVersion: sources.knative.dev/v1beta1
kind: KafkaSource
metadata:
  name: order-event-source
  namespace: mall-demo
spec:
  consumerGroup: knative-notification
  bootstrapServers:
  - kafka:9092
  topics:
  - order-events
  sink:
    ref:
      apiVersion: serving.knative.dev/v1
      kind: Service
      name: notification-service
```

### 10.6 与课程微服务Demo集成

> 将mall-demo项目的notification-service迁移到Knative，验证伸缩至零能力。

#### 10.6.1 notification-service迁移到Knative

```bash
# ==================== 步骤1: 构建镜像 ====================
cd mall-demo/notification-service

# 构建Spring Boot应用 (包含Spring Cloud Function)
mvn clean package -DskipTests

# 构建Docker镜像
docker build -t mall-notification:latest .

# 导出镜像 (离线环境)
docker save mall-notification:latest -o mall-notification.tar

# ==================== 步骤2: 部署到Knative ====================
# 应用Knative Service配置
kubectl apply -f knative-notification-service.yaml

# 查看Service状态
kubectl get ksvc notification-service -n mall-demo

# 查看URL
kubectl get ksvc notification-service -n mall-demo \
  -o jsonpath='{.status.url}'
```

#### 10.6.2 伸缩至零验证

```bash
# ==================== 伸缩至零验证 ====================

# 1. 发送请求, 确认服务正常
curl -X POST http://notification-service.mall-demo.example.com \
  -H "Content-Type: application/json" \
  -d '{
    "orderNo": "ORD-2026-001",
    "userName": "张三",
    "email": "zhangsan@example.com",
    "amount": 299.99
  }'

# 2. 查看Pod (应该有1个Pod在运行)
kubectl get pods -n mall-demo -l serving.knative.dev/service=notification-service

# 3. 等待60秒 (scale-to-zero-pod-retention-period)
sleep 60

# 4. 再次查看Pod (应该缩零, 0个Pod)
kubectl get pods -n mall-demo -l serving.knative.dev/service=notification-service
# 预期输出: No resources found.

# 5. 确认Revision仍然存在 (配置保留)
kubectl get revisions -n mall-demo

# 6. 再次发送请求 (触发冷启动)
time curl -X POST http://notification-service.mall-demo.example.com \
  -H "Content-Type: application/json" \
  -d '{
    "orderNo": "ORD-2026-002",
    "userName": "李四",
    "email": "lisi@example.com",
    "amount": 159.50
  }'
# 预期: 冷启动耗时1-3秒 (CPU模式)
```

#### 10.6.3 冷启动测试

```bash
# ==================== 冷启动测试脚本 ====================
cat > cold-start-test.sh << 'SCRIPT'
#!/bin/bash
echo "=== Knative Cold Start Test ==="
echo ""

# 确保服务已缩零
echo "Step 1: Waiting for scale to zero..."
while true; do
  PODS=$(kubectl get pods -n mall-demo \
    -l serving.knative.dev/service=notification-service 2>/dev/null | grep -c "Running" || true)
  if [ "$PODS" -eq 0 ]; then
    echo "  Service scaled to zero. OK"
    break
  fi
  echo "  Waiting... ($PODS pods running)"
  sleep 5
done

# 测试冷启动延迟
echo ""
echo "Step 2: Measuring cold start latency..."
START_TIME=$(date +%s%N)

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://notification-service.mall-demo.example.com \
  -H "Content-Type: application/json" \
  -d '{"orderNo":"TEST-001","userName":"Test","email":"test@test.com","amount":99.99}')

END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo "  HTTP Status: $RESPONSE"
echo "  Cold Start Latency: ${ELAPSED_MS}ms"
echo ""

if [ "$ELAPSED_MS" -lt 3000 ]; then
  echo "  Result: PASS (cold start < 3s)"
elif [ "$ELAPSED_MS" -lt 5000 ]; then
  echo "  Result: ACCEPTABLE (cold start < 5s)"
else
  echo "  Result: NEED OPTIMIZATION (cold start >= 5s)"
fi
SCRIPT

chmod +x cold-start-test.sh
./cold-start-test.sh
```

#### 10.6.4 成本对比

| 维度 | 传统Deployment (3副本) | Knative Serving (缩零) | 节省 |
|------|----------------------|----------------------|------|
| **CPU请求** | 600m x 3 = 1800m | 200m x 0.5 (平均) = 100m | 94% |
| **内存请求** | 512Mi x 3 = 1536Mi | 256Mi x 0.5 (平均) = 128Mi | 92% |
| **月运行成本** | ~$45 (估算) | ~$5 (估算) | 89% |
| **适用服务** | order-service, user-service | notification-service, report-service |
| **响应延迟** | <50ms (无冷启动) | 1-3s (冷启动), <50ms (热) | - |

**冷启动优化建议：**

| 优化手段 | 效果 | 适用场景 |
|----------|------|----------|
| 减小镜像体积 | 冷启动减少30-50% | 所有场景 |
| JVM预热 (CDS/AppCDS) | 冷启动减少40-60% | Java应用 |
| GraalVM Native Image | 冷启动减少80-90% | 无反射场景 |
| 保持最小副本1 | 无冷启动 | 可接受少量浪费 |
| KEDA + Knative | 事件驱动预扩容 | 可预测流量 |

### 10.7 面试题补充

#### Q6: Volcano与K8s原生调度器有什么区别？什么场景需要用Volcano？

**答案要点：**
- **调度粒度**：K8s调度器以Pod为单位，Volcano以PodGroup为单位，支持Gang Scheduling
- **适用场景**：
  - AI训练：需要多个Worker同时启动，避免部分分配导致死锁
  - 大数据：Spark/Flink批处理任务需要队列管理和公平调度
  - AI Agent：Multi-Agent编排需要DAG依赖调度
- **资源管理**：Volcano支持Queue、权重配额、抢占机制
- **共存**：两种调度器可以共存，通过`schedulerName`字段区分
- **2026趋势**：Volcano已CNCF毕业，AgentCube子项目支持AI Agent编排

#### Q7: Knative Serving如何实现"伸缩至零"？对业务有什么影响？

**答案要点：**
- **实现机制**：Autoscaler监控并发数和请求速率，超过配置的空闲时间后缩容至0
- **冷启动流程**：请求到达Activator → 缓冲请求 → 触发Autoscaler扩容 → Pod就绪后转发
- **冷启动时间**：CPU模式1-3秒，GPU模式可能更长
- **业务影响**：
  - 低频服务 (通知/报表) 适合，节省80%+资源
  - 高频服务 (订单/支付) 不适合，冷启动影响用户体验
- **优化手段**：镜像瘦身、JVM预热 (CDS)、GraalVM Native Image、KEDA预扩容

#### Q8: 如何选择传统Deployment和Knative Serving部署微服务？

**答案要点：**
- **选择Deployment**：
  - 高频服务，需要低延迟响应 (订单、支付、用户服务)
  - 需要长连接 (WebSocket、gRPC流式)
  - 有状态服务或需要本地缓存
- **选择Knative Serving**：
  - 低频服务，可接受冷启动 (通知、报表、数据导出)
  - 突发性流量 (优惠券发放、秒杀通知)
  - 开发测试环境，按需使用节省成本
- **混合架构**：核心链路用Deployment，边缘服务用Knative，通过同一个Ingress访问

---

**参考资源：**
- [KServe官方文档](https://kserve.github.io/website/)
- [Kubeflow文档](https://www.kubeflow.org/docs/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [AIOps实践指南](https://www.gartner.com/en/documents/3984175)
- [MLOps社区](https://mlops.community/)
- [Volcano官方文档](https://volcano.sh/docs/)
- [Knative官方文档](https://knative.dev/docs/)
- [Karmada多集群](https://karmada.io/docs/)
- [Spring Cloud Function](https://spring.io/projects/spring-cloud-function)

---

## 11. LLM运维助手实战

> 📌 **2025-2026实践**
>
> 大语言模型(LLM)正在改变运维工作方式。本节介绍如何利用LLM API构建运维助手，实现智能告警分析、日志解读、命令生成等能力。**无需本地GPU，通过调用外部LLM API即可实现**。

### 11.1 LLM运维助手架构

```
+================================================================================+
|                        LLM运维助手架构                                           |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   运维事件         |  告警/日志/事件/问题                                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   上下文构建       |  收集相关指标、日志、拓扑信息                             |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Prompt工程       |  构建结构化提示词                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   LLM API调用      |  OpenAI/DeepSeek/通义千问/文心一言                        |
|  |   (无需本地GPU)    |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   结果解析         |  提取根因、建议、命令                                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   执行/通知        |  自动执行修复 或 通知运维人员                             |
|  +-------------------+                                                         |
|                                                                                |
+================================================================================+
```

### 11.2 支持的LLM API

| 提供商 | API | 特点 | 推荐场景 |
|--------|-----|------|----------|
| **OpenAI** | GPT-4o/GPT-4-turbo | 能力最强，英文优秀 | 复杂根因分析 |
| **DeepSeek** | DeepSeek-V3 | 国产，性价比高，中文友好 | 国内项目首选 |
| **通义千问** | qwen-max | 阿里云，中文优秀 | 阿里云生态 |
| **文心一言** | ERNIE-4.0 | 百度，中文优秀 | 百度生态 |
| **Claude** | claude-3-opus | 长上下文，代码能力强 | 日志分析 |

### 11.3 告警分析助手实现

```python
# llm-alert-analyzer.py
"""
LLM告警分析助手
通过调用LLM API分析告警根因，生成修复建议
无需本地GPU，仅需API访问权限
"""

import json
import requests
from datetime import datetime
from typing import Dict, List, Optional

class LLMAlertAnalyzer:
    """LLM告警分析器"""
    
    def __init__(self, api_provider: str = "deepseek", api_key: str = ""):
        """
        初始化LLM分析器
        
        Args:
            api_provider: API提供商 (deepseek/openai/qwen/wenxin)
            api_key: API密钥
        """
        self.api_provider = api_provider
        self.api_key = api_key
        self.api_endpoints = {
            "deepseek": "https://api.deepseek.com/v1/chat/completions",
            "openai": "https://api.openai.com/v1/chat/completions",
            "qwen": "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation",
        }
        self.model_map = {
            "deepseek": "deepseek-chat",
            "openai": "gpt-4o-mini",
            "qwen": "qwen-max",
        }
    
    def build_alert_prompt(self, alert: Dict, context: Dict) -> str:
        """
        构建告警分析的Prompt
        
        Args:
            alert: 告警信息
            context: 上下文信息 (指标、日志、拓扑)
        
        Returns:
            结构化的Prompt字符串
        """
        prompt = f"""你是一个Kubernetes运维专家。请分析以下告警，给出根因分析和修复建议。

## 告警信息
- 告警名称: {alert.get('name', 'N/A')}
- 告警级别: {alert.get('severity', 'N/A')}
- 告警时间: {alert.get('starts_at', 'N/A')}
- 告警标签: {json.dumps(alert.get('labels', {}), ensure_ascii=False)}
- 告警描述: {alert.get('annotations', {}).get('summary', 'N/A')}

## 上下文信息
### 相关指标 (过去10分钟)
{json.dumps(context.get('metrics', {}), ensure_ascii=False, indent=2)}

### 相关日志 (最近50条)
{chr(10).join(context.get('logs', [])[:50])}

### 最近的部署事件
{json.dumps(context.get('events', []), ensure_ascii=False, indent=2)}

### 服务拓扑关系
{json.dumps(context.get('topology', {}), ensure_ascii=False, indent=2)}

## 请输出以下内容 (JSON格式):
1. root_cause: 根因分析 (一句话)
2. confidence: 置信度 (high/medium/low)
3. impact: 影响范围
4. suggested_actions: 建议操作列表 (每个操作包含action和command)
5. prevention: 预防措施

请只输出JSON，不要输出其他内容。
"""
        return prompt
    
    def call_llm_api(self, prompt: str) -> str:
        """
        调用LLM API
        
        Args:
            prompt: 提示词
        
        Returns:
            LLM响应内容
        """
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}"
        }
        
        payload = {
            "model": self.model_map.get(self.api_provider, "deepseek-chat"),
            "messages": [
                {"role": "system", "content": "你是一个Kubernetes运维专家，擅长故障诊断和根因分析。"},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.3,  # 较低温度，保证输出稳定
            "max_tokens": 2000
        }
        
        try:
            response = requests.post(
                self.api_endpoints[self.api_provider],
                headers=headers,
                json=payload,
                timeout=30
            )
            response.raise_for_status()
            
            if self.api_provider in ["deepseek", "openai"]:
                return response.json()["choices"][0]["message"]["content"]
            elif self.api_provider == "qwen":
                return response.json()["output"]["text"]
            
        except Exception as e:
            return json.dumps({"error": str(e)})
    
    def analyze_alert(self, alert: Dict, context: Dict) -> Dict:
        """
        分析告警并返回结果
        
        Args:
            alert: 告警信息
            context: 上下文信息
        
        Returns:
            分析结果字典
        """
        # 1. 构建Prompt
        prompt = self.build_alert_prompt(alert, context)
        
        # 2. 调用LLM API
        llm_response = self.call_llm_api(prompt)
        
        # 3. 解析结果
        try:
            # 尝试提取JSON
            if "```json" in llm_response:
                json_str = llm_response.split("```json")[1].split("```")[0].strip()
            elif "```" in llm_response:
                json_str = llm_response.split("```")[1].split("```")[0].strip()
            else:
                json_str = llm_response
            
            result = json.loads(json_str)
        except json.JSONDecodeError:
            result = {
                "root_cause": "无法解析LLM响应",
                "raw_response": llm_response
            }
        
        # 4. 添加元数据
        result["analyzed_at"] = datetime.now().isoformat()
        result["alert_name"] = alert.get("name")
        result["api_provider"] = self.api_provider
        
        return result


# ==================== 使用示例 ====================
if __name__ == "__main__":
    # 初始化分析器
    analyzer = LLMAlertAnalyzer(
        api_provider="deepseek",  # 或 "openai", "qwen"
        api_key="your-api-key-here"
    )
    
    # 模拟告警
    alert = {
        "name": "PodCrashLoopBackOff",
        "severity": "critical",
        "starts_at": "2026-01-15T10:30:00Z",
        "labels": {
            "namespace": "mall-demo",
            "pod": "order-service-5d4f8b9c-x7k2m",
            "container": "order-service"
        },
        "annotations": {
            "summary": "Pod order-service-5d4f8b9c-x7k2m is in CrashLoopBackOff"
        }
    }
    
    # 模拟上下文
    context = {
        "metrics": {
            "cpu_usage": "85%",
            "memory_usage": "92%",
            "restart_count": 5
        },
        "logs": [
            "2026-01-15 10:29:55 ERROR OutOfMemoryError: Java heap space",
            "2026-01-15 10:29:55 INFO Attempting to recover...",
            "2026-01-15 10:30:00 ERROR Application shutdown initiated"
        ],
        "events": [
            {"type": "Warning", "reason": "BackOff", "message": "Container failed"}
        ],
        "topology": {
            "service": "order-service",
            "dependencies": ["mysql", "redis", "kafka"]
        }
    }
    
    # 分析告警
    result = analyzer.analyze_alert(alert, context)
    print(json.dumps(result, ensure_ascii=False, indent=2))
```

### 11.4 日志解读助手

```python
# llm-log-interpreter.py
"""
LLM日志解读助手
帮助运维人员快速理解复杂日志，定位问题
"""

import json
import requests
from typing import List, Dict

class LLMLogInterpreter:
    """LLM日志解读器"""
    
    def __init__(self, api_provider: str = "deepseek", api_key: str = ""):
        self.api_provider = api_provider
        self.api_key = api_key
        # 复用LLMAlertAnalyzer的API配置
        from llm_alert_analyzer import LLMAlertAnalyzer
        self.llm = LLMAlertAnalyzer(api_provider, api_key)
    
    def interpret_error_log(self, log_lines: List[str], context: str = "") -> Dict:
        """
        解读错误日志
        
        Args:
            log_lines: 日志行列表
            context: 额外上下文 (如服务名、环境等)
        
        Returns:
            解读结果
        """
        prompt = f"""请解读以下错误日志，帮助运维人员快速定位问题。

## 日志内容
```
{chr(10).join(log_lines)}
```

## 上下文
{context}

## 请输出 (JSON格式):
1. error_type: 错误类型 (如 OutOfMemory, NetworkError, DatabaseError 等)
2. root_cause: 根因 (一句话)
3. affected_component: 受影响组件
4. severity: 严重程度 (critical/high/medium/low)
5. suggested_fix: 建议修复方案
6. related_docs: 相关文档链接建议 (如官方文档关键词)

只输出JSON。
"""
        response = self.llm.call_llm_api(prompt)
        
        try:
            if "```json" in response:
                json_str = response.split("```json")[1].split("```")[0].strip()
            else:
                json_str = response
            return json.loads(json_str)
        except:
            return {"raw_response": response}
    
    def generate_kubectl_command(self, task_description: str) -> str:
        """
        根据自然语言描述生成kubectl命令
        
        Args:
            task_description: 任务描述
        
        Returns:
            kubectl命令
        """
        prompt = f"""根据以下任务描述，生成对应的kubectl命令。

任务: {task_description}

要求:
1. 只输出命令，不要解释
2. 使用最佳实践
3. 如果需要多个命令，用 && 连接

命令:"""
        
        response = self.llm.call_llm_api(prompt)
        # 提取命令 (去除markdown代码块标记)
        command = response.strip()
        if command.startswith("```"):
            command = command.split("```")[1].strip()
            if command.startswith("bash") or command.startswith("sh"):
                command = command[4:].strip()
        return command


# ==================== 使用示例 ====================
if __name__ == "__main__":
    interpreter = LLMLogInterpreter(
        api_provider="deepseek",
        api_key="your-api-key"
    )
    
    # 示例1: 解读Java错误日志
    java_error_logs = [
        "2026-01-15 10:30:00.123 ERROR [http-nio-8080-exec-1] c.m.o.s.OrderService - Failed to process order",
        "java.sql.SQLException: Connection refused",
        "\tat com.mysql.jdbc.Connection.<init>(Connection.java:234)",
        "\tat com.mall.order.service.OrderService.process(OrderService.java:156)",
        "Caused by: java.net.ConnectException: Connection refused (Connection refused)",
        "\tat java.net.PlainSocketImpl.socketConnect(Native Method)"
    ]
    
    result = interpreter.interpret_error_log(
        java_error_logs,
        context="服务: order-service, 命名空间: mall-demo"
    )
    print("日志解读结果:")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    
    # 示例2: 生成kubectl命令
    task = "查看mall-demo命名空间下所有Pod的资源使用情况"
    command = interpreter.generate_kubectl_command(task)
    print(f"\n生成的命令: {command}")
```

### 11.5 K8s部署 (作为API服务)

```yaml
# llm-ops-assistant.yaml
# LLM运维助手K8s部署配置
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-ops-assistant
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llm-ops-assistant
  template:
    metadata:
      labels:
        app: llm-ops-assistant
    spec:
      containers:
      - name: assistant
        image: python:3.11-slim
        command: ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
        workingDir: /app
        env:
        - name: LLM_API_PROVIDER
          value: "deepseek"  # 或 openai, qwen
        - name: LLM_API_KEY
          valueFrom:
            secretKeyRef:
              name: llm-api-secret
              key: api-key
        - name: PROMETHEUS_URL
          value: "http://prometheus.monitoring.svc:9090"
        - name: LOKI_URL
          value: "http://loki.monitoring.svc:3100"
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
        volumeMounts:
        - name: app-code
          mountPath: /app
      volumes:
      - name: app-code
        configMap:
          name: llm-ops-assistant-code
---
apiVersion: v1
kind: Secret
metadata:
  name: llm-api-secret
  namespace: aiops
type: Opaque
stringData:
  api-key: "your-api-key-here"  # 替换为实际API密钥
---
apiVersion: v1
kind: Service
metadata:
  name: llm-ops-assistant
  namespace: aiops
spec:
  selector:
    app: llm-ops-assistant
  ports:
  - port: 80
    targetPort: 8080
```

### 11.6 与Alertmanager集成

```yaml
# alertmanager-llm-receiver.yaml
# Alertmanager配置 - 将告警发送到LLM分析
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      resolve_timeout: 5m
    
    route:
      receiver: 'llm-analysis'
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
      # 严重告警发送到LLM分析
      - match:
          severity: critical
        receiver: 'llm-analysis'
      # 普通告警发送到默认
      - match:
          severity: warning
        receiver: 'default'
    
    receivers:
    - name: 'llm-analysis'
      webhook_configs:
      - url: 'http://llm-ops-assistant.aiops.svc/alerts'
        send_resolved: true
    
    - name: 'default'
      webhook_configs:
      - url: 'http://notification-service.monitoring.svc/alerts'
```

---

## 12. 轻量异常检测实战

> 📌 **无GPU方案**
>
> 使用基于统计和规则的轻量异常检测算法，无需GPU和深度学习框架，纯Python实现，适合在K8s中作为CronJob运行。

### 12.1 异常检测算法对比

| 算法 | 类型 | 资源需求 | 适用场景 | 准确率 |
|------|------|----------|----------|--------|
| **Z-Score** | 统计 | 极低 | 单指标异常 | 中 |
| **IQR** | 统计 | 极低 | 单指标异常 | 中 |
| **移动平均+标准差** | 统计 | 低 | 时序数据 | 中高 |
| **Isolation Forest** | ML | 低 | 多指标异常 | 高 |
| **DBSCAN聚类** | ML | 低 | 多维数据 | 中高 |
| **LSTM/Transformer** | 深度学习 | 高 (需GPU) | 复杂时序 | 最高 |

**推荐方案**: Z-Score + IQR + 移动平均组合，无需GPU，准确率可达80%+。

### 12.2 轻量异常检测实现

```python
# lightweight-anomaly-detector.py
"""
轻量级异常检测器
基于统计方法，无需GPU和深度学习框架
"""

import json
import statistics
import requests
from datetime import datetime, timedelta
from typing import List, Dict, Tuple, Optional
from dataclasses import dataclass
import math

@dataclass
class AnomalyResult:
    """异常检测结果"""
    is_anomaly: bool
    score: float
    algorithm: str
    reason: str
    timestamp: str
    value: float
    threshold: float


class LightweightAnomalyDetector:
    """轻量级异常检测器"""
    
    def __init__(self):
        self.algorithms = {
            'zscore': self._detect_zscore,
            'iqr': self._detect_iqr,
            'moving_avg': self._detect_moving_avg,
            'combined': self._detect_combined
        }
    
    # ==================== Z-Score算法 ====================
    def _detect_zscore(
        self, 
        value: float, 
        history: List[float], 
        threshold: float = 3.0
    ) -> AnomalyResult:
        """
        Z-Score异常检测
        
        Args:
            value: 当前值
            history: 历史值列表
            threshold: Z分数阈值 (默认3.0, 覆盖99.7%正态分布)
        
        Returns:
            检测结果
        """
        if len(history) < 3:
            return AnomalyResult(
                is_anomaly=False, score=0, algorithm='zscore',
                reason='Insufficient history', timestamp=datetime.now().isoformat(),
                value=value, threshold=threshold
            )
        
        mean = statistics.mean(history)
        stdev = statistics.stdev(history)
        
        if stdev == 0:
            z_score = 0 if value == mean else float('inf')
        else:
            z_score = abs(value - mean) / stdev
        
        return AnomalyResult(
            is_anomaly=z_score > threshold,
            score=z_score,
            algorithm='zscore',
            reason=f"Z-score: {z_score:.2f} > {threshold}",
            timestamp=datetime.now().isoformat(),
            value=value,
            threshold=threshold
        )
    
    # ==================== IQR算法 ====================
    def _detect_iqr(
        self, 
        value: float, 
        history: List[float], 
        k: float = 1.5
    ) -> AnomalyResult:
        """
        IQR (四分位距) 异常检测
        
        Args:
            value: 当前值
            history: 历史值列表
            k: IQR倍数 (默认1.5, 3.0为极端异常)
        
        Returns:
            检测结果
        """
        if len(history) < 4:
            return AnomalyResult(
                is_anomaly=False, score=0, algorithm='iqr',
                reason='Insufficient history', timestamp=datetime.now().isoformat(),
                value=value, threshold=k
            )
        
        sorted_history = sorted(history)
        n = len(sorted_history)
        
        # 计算四分位数
        q1_idx = n // 4
        q3_idx = 3 * n // 4
        q1 = sorted_history[q1_idx]
        q3 = sorted_history[q3_idx]
        iqr = q3 - q1
        
        lower_bound = q1 - k * iqr
        upper_bound = q3 + k * iqr
        
        is_anomaly = value < lower_bound or value > upper_bound
        
        # 计算异常程度
        if value > upper_bound:
            score = (value - upper_bound) / iqr if iqr > 0 else 0
        elif value < lower_bound:
            score = (lower_bound - value) / iqr if iqr > 0 else 0
        else:
            score = 0
        
        return AnomalyResult(
            is_anomaly=is_anomaly,
            score=score,
            algorithm='iqr',
            reason=f"Value: {value:.2f}, Bounds: [{lower_bound:.2f}, {upper_bound:.2f}]",
            timestamp=datetime.now().isoformat(),
            value=value,
            threshold=k
        )
    
    # ==================== 移动平均+标准差 ====================
    def _detect_moving_avg(
        self, 
        value: float, 
        history: List[float], 
        window: int = 7,
        threshold: float = 2.0
    ) -> AnomalyResult:
        """
        移动平均 + 标准差异常检测
        
        Args:
            value: 当前值
            history: 历史值列表
            window: 移动窗口大小
            threshold: 标准差倍数
        
        Returns:
            检测结果
        """
        if len(history) < window:
            return AnomalyResult(
                is_anomaly=False, score=0, algorithm='moving_avg',
                reason='Insufficient history', timestamp=datetime.now().isoformat(),
                value=value, threshold=threshold
            )
        
        recent = history[-window:]
        mean = statistics.mean(recent)
        stdev = statistics.stdev(recent) if len(recent) > 1 else 0
        
        if stdev == 0:
            deviation = 0 if value == mean else float('inf')
        else:
            deviation = abs(value - mean) / stdev
        
        return AnomalyResult(
            is_anomaly=deviation > threshold,
            score=deviation,
            algorithm='moving_avg',
            reason=f"Deviation: {deviation:.2f}σ from MA{window}",
            timestamp=datetime.now().isoformat(),
            value=value,
            threshold=threshold
        )
    
    # ==================== 组合算法 ====================
    def _detect_combined(
        self, 
        value: float, 
        history: List[float]
    ) -> AnomalyResult:
        """
        组合多种算法投票
        
        Args:
            value: 当前值
            history: 历史值列表
        
        Returns:
            组合检测结果
        """
        results = [
            self._detect_zscore(value, history, threshold=3.0),
            self._detect_iqr(value, history, k=1.5),
            self._detect_moving_avg(value, history, window=7, threshold=2.0)
        ]
        
        # 投票: 2/3算法认为异常则判定异常
        anomaly_votes = sum(1 for r in results if r.is_anomaly)
        avg_score = statistics.mean([r.score for r in results])
        
        return AnomalyResult(
            is_anomaly=anomaly_votes >= 2,
            score=avg_score,
            algorithm='combined',
            reason=f"Votes: {anomaly_votes}/3, Avg Score: {avg_score:.2f}",
            timestamp=datetime.now().isoformat(),
            value=value,
            threshold=2  # 投票阈值
        )
    
    def detect(
        self, 
        value: float, 
        history: List[float], 
        algorithm: str = 'combined'
    ) -> AnomalyResult:
        """
        执行异常检测
        
        Args:
            value: 当前值
            history: 历史值列表
            algorithm: 算法名称
        
        Returns:
            检测结果
        """
        if algorithm not in self.algorithms:
            algorithm = 'combined'
        
        return self.algorithms[algorithm](value, history)


# ==================== Prometheus指标采集 ====================
class PrometheusAnomalyScanner:
    """Prometheus指标异常扫描器"""
    
    def __init__(self, prometheus_url: str):
        self.prometheus_url = prometheus_url
        self.detector = LightweightAnomalyDetector()
    
    def query_metric(self, query: str, hours: int = 24) -> List[float]:
        """
        查询Prometheus指标历史数据
        
        Args:
            query: PromQL查询
            hours: 历史时长 (小时)
        
        Returns:
            指标值列表
        """
        end = datetime.now()
        start = end - timedelta(hours=hours)
        
        url = f"{self.prometheus_url}/api/v1/query_range"
        params = {
            'query': query,
            'start': start.timestamp(),
            'end': end.timestamp(),
            'step': '1h'  # 每小时一个点
        }
        
        try:
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            data = response.json()
            
            if data['status'] == 'success':
                values = data['data']['result'][0]['values']
                return [float(v[1]) for v in values]
        except Exception as e:
            print(f"Query error: {e}")
        
        return []
    
    def scan_metrics(self, metrics_config: Dict) -> List[Dict]:
        """
        扫描多个指标的异常
        
        Args:
            metrics_config: 指标配置 {name: query}
        
        Returns:
            异常结果列表
        """
        anomalies = []
        
        for name, query in metrics_config.items():
            history = self.query_metric(query)
            
            if len(history) < 3:
                continue
            
            current = history[-1]
            past = history[:-1]
            
            result = self.detector.detect(current, past, algorithm='combined')
            
            if result.is_anomaly:
                anomalies.append({
                    'metric': name,
                    'current_value': current,
                    'score': result.score,
                    'reason': result.reason,
                    'timestamp': result.timestamp
                })
        
        return anomalies


# ==================== 使用示例 ====================
if __name__ == "__main__":
    # 示例1: 单值检测
    detector = LightweightAnomalyDetector()
    
    # 模拟CPU使用率历史 (正常波动)
    cpu_history = [45, 48, 52, 50, 55, 60, 58, 62, 65, 63, 68, 70, 72, 75]
    current_cpu = 95  # 突然飙升
    
    result = detector.detect(current_cpu, cpu_history, algorithm='combined')
    print(f"CPU异常检测: {result.is_anomaly}, Score: {result.score:.2f}")
    print(f"原因: {result.reason}")
    
    # 示例2: Prometheus扫描
    scanner = PrometheusAnomalyScanner("http://prometheus:9090")
    
    metrics_to_scan = {
        'cpu_usage': '100 - avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100',
        'memory_usage': '(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100',
        'pod_restart_rate': 'sum(rate(kube_pod_container_status_restarts_total[1h]))'
    }
    
    anomalies = scanner.scan_metrics(metrics_to_scan)
    print(f"\n发现 {len(anomalies)} 个异常指标:")
    for a in anomalies:
        print(f"  - {a['metric']}: {a['current_value']:.2f} (Score: {a['score']:.2f})")
```

### 12.3 K8s CronJob部署

```yaml
# anomaly-detection-cronjob.yaml
# 异常检测CronJob - 每5分钟扫描一次
apiVersion: batch/v1
kind: CronJob
metadata:
  name: anomaly-detector
  namespace: aiops
spec:
  schedule: "*/5 * * * *"  # 每5分钟
  concurrencyPolicy: Forbid  # 禁止并发
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: detector
            image: python:3.11-slim
            command: ["python", "/app/detector.py"]
            env:
            - name: PROMETHEUS_URL
              value: "http://prometheus.monitoring.svc:9090"
            - name: ALERT_WEBHOOK
              value: "http://alertmanager.monitoring.svc:9093/api/v1/alerts"
            volumeMounts:
            - name: detector-code
              mountPath: /app
            resources:
              requests:
                cpu: "100m"
                memory: "128Mi"
              limits:
                cpu: "500m"
                memory: "256Mi"
          volumes:
          - name: detector-code
            configMap:
              name: anomaly-detector-code
          restartPolicy: OnFailure
```

---

## 13. AI Agent运维助手

> 📌 **2025-2026趋势**
>
> AI Agent (智能体) 是LLM应用的新范式。与传统的"一问一答"不同，Agent可以自主规划、执行、反思，完成复杂的运维任务。本节介绍轻量级AI Agent的实现。

### 13.1 Agent vs 传统LLM应用

| 维度 | 传统LLM应用 | AI Agent |
|------|------------|----------|
| **交互模式** | 一问一答 | 多轮自主交互 |
| **执行能力** | 仅生成文本 | 可调用工具执行操作 |
| **规划能力** | 无 | 自主分解任务、规划步骤 |
| **反思能力** | 无 | 执行后检查结果、调整策略 |
| **记忆** | 无/短期 | 长期记忆 + 工作记忆 |
| **适用场景** | 简单问答 | 复杂任务编排 |

### 13.2 ReAct Agent实现

```python
# react-agent.py
"""
ReAct (Reasoning + Acting) Agent实现
Agent可以推理、执行工具、观察结果、调整策略
"""

import json
import re
from typing import List, Dict, Callable, Any
from dataclasses import dataclass
from llm_alert_analyzer import LLMAlertAnalyzer

@dataclass
class Tool:
    """工具定义"""
    name: str
    description: str
    func: Callable
    parameters: Dict  # 参数schema


class ReActAgent:
    """ReAct Agent实现"""
    
    def __init__(self, llm: LLMAlertAnalyzer, tools: List[Tool], max_iterations: int = 5):
        """
        初始化Agent
        
        Args:
            llm: LLM实例
            tools: 可用工具列表
            max_iterations: 最大迭代次数
        """
        self.llm = llm
        self.tools = {t.name: t for t in tools}
        self.max_iterations = max_iterations
        self.memory: List[Dict] = []  # 工作记忆
    
    def build_system_prompt(self) -> str:
        """构建系统提示"""
        tools_desc = "\n".join([
            f"- {name}: {tool.description}"
            for name, tool in self.tools.items()
        ])
        
        return f"""你是一个Kubernetes运维Agent。你可以使用以下工具:

{tools_desc}

使用以下格式思考和行动:

Thought: 思考下一步应该做什么
Action: 工具名称
Action Input: 工具输入 (JSON格式)
Observation: 工具返回结果
... (重复 Thought/Action/Observation 直到完成任务)
Thought: 我现在知道最终答案了
Final Answer: 最终答案

开始!
"""
    
    def parse_action(self, response: str) -> Tuple[Optional[str], Optional[Dict]]:
        """
        解析LLM响应中的Action
        
        Args:
            response: LLM响应
        
        Returns:
            (action_name, action_input) 或 (None, None)
        """
        # 匹配 Action: xxx
        action_match = re.search(r'Action:\s*(\w+)', response)
        if not action_match:
            return None, None
        
        action = action_match.group(1)
        
        # 匹配 Action Input: {...}
        input_match = re.search(r'Action Input:\s*(\{.*?\})', response, re.DOTALL)
        if input_match:
            try:
                action_input = json.loads(input_match.group(1))
            except:
                action_input = {}
        else:
            action_input = {}
        
        return action, action_input
    
    def execute_tool(self, action: str, action_input: Dict) -> str:
        """
        执行工具
        
        Args:
            action: 工具名称
            action_input: 工具输入
        
        Returns:
            工具执行结果
        """
        if action not in self.tools:
            return f"Error: Unknown tool '{action}'"
        
        try:
            result = self.tools[action].func(**action_input)
            return json.dumps(result, ensure_ascii=False)
        except Exception as e:
            return f"Error: {str(e)}"
    
    def run(self, task: str) -> str:
        """
        执行任务
        
        Args:
            task: 任务描述
        
        Returns:
            最终结果
        """
        # 初始化对话
        messages = [
            {"role": "system", "content": self.build_system_prompt()},
            {"role": "user", "content": task}
        ]
        
        for i in range(self.max_iterations):
            # 1. 调用LLM思考
            response = self.llm.call_llm_api(messages[-1]["content"])
            
            # 2. 记录思考过程
            self.memory.append({
                "iteration": i,
                "thought": response
            })
            
            # 3. 检查是否完成
            if "Final Answer:" in response:
                final_answer = response.split("Final Answer:")[-1].strip()
                return final_answer
            
            # 4. 解析并执行Action
            action, action_input = self.parse_action(response)
            
            if action:
                observation = self.execute_tool(action, action_input)
                
                # 5. 将Observation添加到对话
                messages.append({
                    "role": "assistant",
                    "content": response
                })
                messages.append({
                    "role": "user",
                    "content": f"Observation: {observation}"
                })
            else:
                # 没有Action，继续思考
                messages.append({
                    "role": "assistant",
                    "content": response
                })
        
        return "达到最大迭代次数，任务未完成"


# ==================== 定义运维工具 ====================
def kubectl_tool(command: str) -> Dict:
    """执行kubectl命令"""
    import subprocess
    try:
        result = subprocess.run(
            f"kubectl {command}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "error": result.stderr
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


def prometheus_tool(query: str) -> Dict:
    """查询Prometheus指标"""
    import requests
    try:
        response = requests.get(
            f"http://prometheus:9090/api/v1/query",
            params={"query": query},
            timeout=10
        )
        return response.json()
    except Exception as e:
        return {"error": str(e)}


def log_tool(namespace: str, pod: str, lines: int = 100) -> Dict:
    """获取Pod日志"""
    import subprocess
    try:
        result = subprocess.run(
            f"kubectl logs {pod} -n {namespace} --tail={lines}",
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        return {
            "success": result.returncode == 0,
            "logs": result.stdout.split("\n")
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


# ==================== 使用示例 ====================
if __name__ == "__main__":
    # 初始化LLM
    llm = LLMAlertAnalyzer(
        api_provider="deepseek",
        api_key="your-api-key"
    )
    
    # 定义工具
    tools = [
        Tool(
            name="kubectl",
            description="执行kubectl命令，如: get pods, describe pod, logs等",
            func=kubectl_tool,
            parameters={"command": "kubectl命令 (不含kubectl前缀)"}
        ),
        Tool(
            name="prometheus",
            description="查询Prometheus指标，返回时序数据",
            func=prometheus_tool,
            parameters={"query": "PromQL查询语句"}
        ),
        Tool(
            name="logs",
            description="获取Pod日志",
            func=log_tool,
            parameters={"namespace": "命名空间", "pod": "Pod名称", "lines": "日志行数"}
        )
    ]
    
    # 创建Agent
    agent = ReActAgent(llm, tools, max_iterations=5)
    
    # 执行任务
    task = "mall-demo命名空间的order-service服务响应变慢，请帮我诊断原因"
    result = agent.run(task)
    print(f"最终结果: {result}")
```

### 13.3 K8s部署

```yaml
# ai-agent-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-ops-agent
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-ops-agent
  template:
    metadata:
      labels:
        app: ai-ops-agent
    spec:
      serviceAccountName: ai-ops-agent  # 需要RBAC权限
      containers:
      - name: agent
        image: python:3.11-slim
        command: ["python", "/app/agent_server.py"]
        env:
        - name: LLM_API_PROVIDER
          value: "deepseek"
        - name: LLM_API_KEY
          valueFrom:
            secretKeyRef:
              name: llm-api-secret
              key: api-key
        volumeMounts:
        - name: agent-code
          mountPath: /app
        resources:
          requests:
            cpu: "300m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
      volumes:
      - name: agent-code
        configMap:
          name: ai-agent-code
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ai-ops-agent
rules:
- apiGroups: [""]
  resources: ["pods", "services", "events", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ai-ops-agent
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ai-ops-agent
subjects:
- kind: ServiceAccount
  name: ai-ops-agent
  namespace: aiops
```

---

## 14. 模块总结

### 14.1 本章新增内容回顾

| 章节 | 内容 | 资源需求 |
|------|------|----------|
| **11. LLM运维助手** | 告警分析、日志解读、命令生成 | 无GPU，仅需API |
| **12. 轻量异常检测** | Z-Score/IQR/移动平均算法 | 无GPU，纯CPU |
| **13. AI Agent** | ReAct Agent自主运维 | 无GPU，仅需API |

### 14.2 与模块22的关系

本模块(19)介绍了AI在运维中的**基础应用**，模块22将深入介绍**LLM时代的AIOps**，包括：

- RAG (检索增强生成) 知识库
- Multi-Agent协作系统
- LLM微调与私有化部署
- AI运维安全与合规

### 14.3 面试题补充

#### Q9: 如何在无GPU环境下实现AI运维能力？

**答案要点：**
- **LLM API调用**: 使用外部LLM服务(DeepSeek/OpenAI)，无需本地GPU
- **轻量算法**: Z-Score、IQR、移动平均等统计方法，纯CPU运行
- **规则引擎**: 基于专家规则的告警降噪和根因推断
- **混合方案**: 简单任务用规则/统计，复杂任务调用LLM API
- **成本优化**: 仅在需要时调用LLM，日常监控用统计方法

#### Q10: AI Agent与传统自动化脚本有什么区别？

**答案要点：**
- **自主性**: Agent可以自主规划和决策，脚本按固定流程执行
- **适应性**: Agent可以根据执行结果调整策略，脚本无法调整
- **交互性**: Agent可以与人类对话澄清需求，脚本无交互
- **学习能力**: Agent可以从历史案例学习，脚本无学习能力
- **适用场景**: 
  - 脚本: 已知问题、固定流程 (如重启服务)
  - Agent: 未知问题、需要推理 (如诊断复杂故障)

---

**参考资源 (新增):**
- [DeepSeek API文档](https://platform.deepseek.com/docs)
- [OpenAI API文档](https://platform.openai.com/docs)
- [LangChain文档](https://python.langchain.com/docs/)
- [ReAct论文](https://arxiv.org/abs/2210.03629)
- [AIOps最佳实践](https://www.gartner.com/en/documents/3984175)
