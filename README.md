# 云原生技术栈实战课程

> 一套完整的云原生技术栈实战课程，覆盖从基础设施到生产交付的全链路实践，新增故障排查、网络原理、内核机制、架构设计、面试案例五大深度模块。
> 
> **适配环境**: 6节点离线K8s集群 (3 Master 2C2G + 2 Worker 4C8G)  
> **K8s版本**: v1.28.15  
> **Harbor**: 192.168.1.61:80 (HTTP)  
> **总模块数**: 35个核心模块 (00-34) + 附录 + 全链路综合实战 + 3套微服务Demo

---

## 📚 课程模块总览

### 基础架构层

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 00 | [基础设施准备](./00-基础设施准备.md) | StorageClass、Gitea、Nexus、离线Helm、CSI存储 | ⭐⭐ |
| 01 | [K8s环境准备](./01-K8s环境准备.md) | 内核优化、containerd、kubelet/kubeadm、Windows容器 | ⭐⭐ |
| 02 | [Harbor私有仓库](./02-Harbor私有仓库.md) | Harbor部署、镜像签名、漏洞扫描、多架构构建 | ⭐⭐⭐ |
| 03 | [容器运行时containerd](./03-容器运行时containerd.md) | containerd配置、镜像管理、nerdctl | ⭐⭐ |
| 04 | [K8s集群初始化](./04-K8s集群初始化.md) | kubeadm、etcd备份、证书轮换、Velero灾备 | ⭐⭐⭐ |
| 15 | [基础设施即代码(IaC)](./15-基础设施即代码IaC.md) | Terraform、Ansible、VMware Workstation/vSphere | ⭐⭐⭐ |

### 网络与可观测性层

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 05 | [网络插件Calico](./05-网络插件Calico.md) | BGP/IPIP/VXLAN、高级策略、CoreDNS排查、eBPF/Cilium深入 | ⭐⭐⭐ |
| 06 | [Prometheus与Grafana监控](./06-Prometheus与Grafana监控.md) | Thanos长期存储、SLO实践、告警路由、KEDA事件伸缩 | ⭐⭐⭐⭐ |
| 07 | [Loki日志系统](./07-Loki日志系统.md) | Promtail、日志告警、Trace-Log关联 | ⭐⭐⭐ |
| 09 | [OpenTelemetry与可观测性](./09-OpenTelemetry与可观测性.md) | OTel Collector、采样策略、三支柱关联、性能分析 | ⭐⭐⭐⭐ |

### 流量管理与服务网格

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 08 | [Ingress与Istio服务网格](./08-Ingress与Istio服务网格.md) | Ingress、Istio、ExternalDNS、API Gateway选型 | ⭐⭐⭐⭐ |

### 中间件与数据层

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 10 | [Kafka消息队列KRaft](./10-Kafka消息队列KRaft.md) | Strimzi、KRaft模式、事件驱动选型 | ⭐⭐⭐ |
| 11 | [Nacos服务注册发现](./11-Nacos服务注册发现.md) | Nacos集群、配置中心、Spring Cloud集成 | ⭐⭐⭐ |

### 交付与运维层

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 12 | [ArgoCD应用交付](./12-ArgoCD应用交付.md) | GitOps、Secrets管理、Argo Rollouts、PR晋升 | ⭐⭐⭐⭐ |
| 13 | [Tekton流水线](./13-Tekton流水线.md) | Pipeline as Code、DevSecOps、多架构CI | ⭐⭐⭐⭐ |
| 16 | [云原生安全与合规](./16-云原生安全与合规.md) | 镜像安全、Kyverno、合规框架、安全分层 | ⭐⭐⭐⭐ |

### 综合实战

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 14 | [全链路综合实战](./14-全链路综合实战.md) | 电商微服务、混沌工程、容量压测、弹性伸缩 | ⭐⭐⭐⭐⭐ |

### 前沿实践层 (2024-2025)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 17 | [平台工程与多租户](./17-平台工程与多租户.md) | IDP、Namespace as a Service、Backstage、RBAC | ⭐⭐⭐⭐ |
| 18 | [FinOps成本优化](./18-FinOps成本优化.md) | OpenCost、成本分摊、资源优化、预算治理 | ⭐⭐⭐⭐ |
| 19 | [AI Native与AIOps](./19-AI-Native与AIOps.md) | K8s+AI、KServe、智能运维、AIOps入门 | ⭐⭐⭐⭐ |

### 数据层 (2025新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 20 | [数据库Operator实战](./20-数据库Operator实战.md) | MySQL/PostgreSQL/Redis Operator、备份恢复 | ⭐⭐⭐⭐ |

### 云厂商实战层 (2025新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 21 | [主流云厂商产品实战](./21-主流云厂商产品实战.md) | AWS/Azure/阿里云/腾讯云/华为云、价格对比、跨云迁移 | ⭐⭐⭐ |

### LLM时代AIOps层 (2025新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 22 | [LLM时代的AIOps实战](./22-LLM时代的AIOps实战.md) | RAG知识库、Multi-Agent协作、私有化LLM、安全合规 | ⭐⭐⭐⭐ |

### 高级调度层 (2025新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 23 | [K8s高级调度机制实战](./23-K8s高级调度机制实战.md) | Volcano/Gang Scheduling/Queue/GPU调度 | ⭐⭐⭐⭐ |

### 谷歌云大模型运维层 (2026新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 24 | [谷歌云大模型运维全栈技术](./24-谷歌云大模型运维全栈技术.md) | Vertex AI/Gemini/Cloud Run/GKE推理部署、Agent运维架构、LLM成本治理 | ⭐⭐⭐⭐ |

### 自研大模型交付层 (2026新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 25 | [自研大模型应用交付](./25-自研大模型应用交付.md) | GKE GPU推理服务、Token吞吐量HPA、Agent金丝雀发布、多租户隔离、可观测性体系 | ⭐⭐⭐⭐ |

### 国内AI平台对标层 (2026新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 26 | [国内AI应用交付平台对标与选型](./26-国内AI应用交付平台对标与选型.md) | 百度千帆/阿里百炼/字节火山/华为盘古/智谱AI六大平台对标、私有化vs公有云选型、成本对比、多平台统一接入 | ⭐⭐⭐ |

### 云厂商平台运维层 (2026新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 27 | [AWS与GCP平台级运维实战](./27-AWS与GCP平台级运维实战.md) | IAM治理、VPC网络架构、成本优化、CloudWatch/Cloud Monitoring监控告警、CloudTrail审计、多账号组织、故障自动修复 | ⭐⭐⭐ |

### AI应用入职预备层 (2026新增)

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 28 | [AI应用公司入职预备知识](./28-AI应用公司入职预备知识.md) | 公司业务架构全景、入职第一周Checklist、OCR/大模型/文档Agent/语音外呼运维实战、故障处理流程、数据安全合规 | ⭐⭐⭐ |

### 故障排查与原理层

| 模块 | 标题 | 核心内容 | 难度 |
|------|------|---------|------|
| 29 | [K8S故障排查与根因分析](./29-K8S故障排查与根因分析.md) | 分层诊断模型、Pod生命周期故障分类、日志聚合、排障脚本库 | ⭐⭐⭐⭐ |
| 30 | [中间件故障排查](./30-中间件故障排查.md) | ES/Kafka/MySQL/Nginx/Redis五件套诊断、连接池超时机制 | ⭐⭐⭐⭐ |
| 31 | [Linux系统故障排查](./31-Linux系统故障排查.md) | CPU瓶颈、内存泄漏/OOM、磁盘/文件系统、进程诊断 | ⭐⭐⭐⭐ |
| 32 | [网络协议深度解析](./32-网络协议深度解析.md) | TCP三次握手/四次挥手、滑动窗口/拥塞控制、TIME_WAIT优化 | ⭐⭐⭐⭐ |
| 33 | [计算机基础与内核](./33-计算机基础与内核.md) | 进程调度/状态转换、CFS调度器、内存管理 | ⭐⭐⭐⭐ |
| 34 | [运维架构设计原理](./34-运维架构设计原理.md) | 容器vs虚拟机、K8S设计决策、高可用架构选型 | ⭐⭐⭐ |

### 面试参考

| 文档 | 说明 |
|------|------|
| [附录-K8S生产环境故障分类与面试案例详解](./附录-K8S生产环境故障分类与面试案例详解.md) | 25类故障分类 + STAR-R面试模板 + 完整案例拆解 |

### 微服务Demo

| Demo | 路径 | 技术栈 | 内存占用 | 适用场景 |
|------|------|--------|---------|---------|
| Demo-A | [mall-demo/demo-a-springboot](./mall-demo/demo-a-springboot) | Spring Boot 3.2 | ~1.5GB | 完整课程演示 |
| Demo-B | [mall-demo/demo-b-golang](./mall-demo/demo-b-golang) | Go 1.22 | ~300MB | 资源极限环境 |
| Demo-C | [mall-demo/demo-c-hybrid](./mall-demo/demo-c-hybrid) | Go+Spring混合 | ~550MB | 生产架构参考 |

### 参考资料

| 文档 | 说明 |
|------|------|
| [术语中英对照表](./glossary.md) | 400+云原生术语中英对照，含代码注释速查 |

---

## 🎯 学习路径建议

### 路径一：基础运维工程师 (4-6周)
```
00-基础设施准备 → 01-K8s环境准备 → 02-Harbor → 03-containerd
→ 04-K8s集群初始化 → 05-Calico → 06-Prometheus监控 → 07-Loki
→ 31-Linux故障排查 → 32-网络协议 → 33-内核基础
```

### 路径二：云原生开发工程师 (6-8周)
```
基础层 → 08-Ingress-Istio → 10-Kafka → 11-Nacos
→ 09-OpenTelemetry → 13-Tekton → 12-ArgoCD
→ 29-K8S故障排查 → 30-中间件故障排查
```

### 路径三：平台架构师 (10-12周)
```
完整基础层 → 全部中间件 → 全部交付层 → 15-IaC → 16-安全合规 → 14-全链路实战
→ 17-平台工程 → 18-FinOps → 19-AI Native → 34-运维架构设计
```

### 路径四：云原生专家 (14-16周)
```
全部35个模块 + 3套Demo深度实践 + 附录面试案例 + 生产环境落地
```

### 路径五：多云架构师 (14-16周)
```
核心模块(00-19) + 21-云厂商实战 + 24-谷歌云 + 26-国内AI平台对标 + 27-AWS/GCP运维
+ 28-入职预备 → 跨云迁移实战
```

### 路径六：AI运维专家 (16-18周)
```
核心模块(00-19) + 22-LLM AIOps深度实践 + 24-谷歌云大模型 + 25-自研大模型交付
+ 26-国内AI平台对标 + Multi-Agent系统开发
```

### 路径七：调度与资源管理专家 (8-10周)
```
04-K8s初始化 → 05-Calico → 17-平台工程 → 18-FinOps → 23-高级调度 → 20-数据库Operator
```

### 路径八：故障排查与SRE (6-8周)
```
29-K8S故障排查 → 30-中间件故障排查 → 31-Linux故障排查 → 32-网络协议
→ 33-内核基础 → 34-架构设计 → 附录-面试案例
```

---

## 🔧 环境要求

### 实际硬件配置
| 节点类型 | 数量 | CPU | 内存 | 磁盘 | 用途 |
|---------|------|-----|------|------|------|
| Master | 3 | 2核 | 2GB | 50GB | 控制平面 + etcd |
| Harbor | 1 | 2核 | 2GB | 100GB | 镜像仓库（独立） |
| Worker-1 | 1 | 4核 | 8GB | 100GB | 工作负载 |
| Worker-2 | 1 | 4核 | 8GB | 100GB | 工作负载 |

> **总可用内存**: Master 6GB + Worker 16GB = **22GB**（Harbor独立不计入）

### 软件版本
- **OS**: CentOS 7.9 / Rocky Linux 8.4
- **K8s**: v1.28.15
- **Containerd**: 1.7.x
- **Helm**: 3.12+

### 网络规划
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12
- **Harbor**: 192.168.1.61:80
- **Gitea**: 192.168.1.61:3000

---

## ⚠️ 错峰部署指南

> **核心原则**: 受限于总内存22GB，**不可能同时运行全部组件**。请按学习进度错峰部署，学完一个模块后清理再进入下一个。

### 资源预算总览

```
总可用: 22GB (3×2G Master + 2×8G Worker)
├── K8s系统组件:    ~2GB   (常驻，不可卸载)
├── Calico/Cilium:  ~1GB   (常驻，网络插件二选一)
├── 基础监控:       ~2GB   (常驻，Prometheus+Grafana)
├── 动态区域:       ~15GB  (按学习模块切换)
└── 系统保留:       ~2GB
```

### 互斥组件（不可同时部署）

| 组别 | 方案A | 方案B | 说明 |
|------|-------|-------|------|
| **网络插件** | Calico (iptables) | Cilium (eBPF) | 二选一，不可共存 |
| **服务网格** | Istio Sidecar模式 | Istio Ambient Mesh | 二选一，可切换 |
| **南北流量** | Ingress-Nginx | Gateway API | Gateway API仅CRD，可与Ingress共存 |

### 模块部署顺序与资源预估

```
第1-2周: 基础层（常驻 ~5GB）
├── 00-基础设施准备    →   0GB (一次性配置)
├── 01-K8s环境准备    →   0GB (一次性配置)
├── 02-Harbor         →   0GB (独立节点)
├── 03-containerd     →   0GB (一次性配置)
├── 04-K8s初始化      →   0GB (常驻系统组件)
└── 05-Calico         →   1GB (DaemonSet，常驻)
    常驻总计: ~5GB ✅

第3周: 可观测性（常驻 ~3GB）
├── 06-Prometheus     →   2GB (Worker-1)
├── 07-Loki           →   1GB (Worker-2，按需启停)
└── 09-OTel Collector →  256MB (Worker-1，常驻)
    累计: ~8GB ✅

第4周: 中间件（错峰 ~4GB）
├── 10-Kafka          →   2GB (Worker-2)
└── 11-Nacos+MySQL    →   2GB (Worker-2)
    ⚠️ 学完后删除Deployment，保留PVC数据
    释放后回到: ~8GB ✅

第5周: 服务网格（集中 ~2GB）
├── 08-Istio          →   2GB (Worker-1+Worker-2)
    ⚠️ 专门1周学习，学完后卸载Istio释放资源
    释放后回到: ~8GB ✅

第6周: CI/CD（错峰 ~2GB）
├── 13-Tekton         →   1GB (Worker-2)
└── 12-ArgoCD         →   1GB (Worker-2)
    ⚠️ 学完后删除，释放资源
    释放后回到: ~8GB ✅

第7周: 安全与IaC（轻量 ~1GB）
├── 16-安全合规        →   512MB (Falco按需)
└── 15-IaC            →   0GB (Terraform本地运行)
    累计: ~9GB ✅

第8周: 前沿实践（错峰 ~2GB）
├── 17-平台工程        →   512MB (Backstage按需)
├── 18-FinOps         →   512MB (OpenCost)
└── 19-AI Native      →   1GB (Volcano/Knative按需)
    累计: ~10GB ✅

第9-10周: 全链路实战（峰值 ~8GB）
└── 14-全链路实战      →   按需启动所有组件
    ⚠️ 峰值需要: ~15GB，需要停掉非必要组件

第11-12周: 故障排查（无额外负载）
├── 29-K8S故障排查    →   0GB (理论+实战脚本)
├── 30-中间件排查      →   0GB (诊断脚本)
├── 31-Linux排查      →   0GB (诊断脚本)
├── 32-网络协议        →   0GB (理论)
├── 33-内核基础        →   0GB (理论)
└── 34-架构设计        →   0GB (理论)
    ⚠️ 故障排查模块以理论+本地诊断脚本为主，不占用集群资源
```

### DaemonSet组件注意事项

以下组件以DaemonSet形式运行，会占用**每个节点**的资源：

| 组件 | 每节点内存 | 3Master总计 | 建议 |
|------|-----------|------------|------|
| Calico Node | ~200MB | 600MB | ✅ 可接受 |
| Cilium Agent | ~500MB | 1.5GB | ⚠️ Master偏紧 |
| Tetragon | ~200MB | 600MB | ⚠️ 建议只在Worker部署 |
| Ambient ztunnel | ~500MB | 1.5GB | ⚠️ 建议只在Worker部署 |

**建议**: DaemonSet类组件通过 `tolerations` 和 `nodeSelector` 限制只部署在Worker节点：

```yaml
# 示例: Cilium Agent只部署在Worker
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
nodeSelector:
  node-role.kubernetes.io/worker: ""
```

### 一键清理脚本

学完一个模块后，使用清理脚本释放资源：

```bash
# 停止指定模块的所有Deployment/StatefulSet（保留PVC数据）
kubectl delete deploy,statefulset -n <namespace> --all

# 或者使用更精细的清理
kubectl scale deploy -n monitoring prometheus --replicas=0
kubectl scale deploy -n monitoring loki --replicas=0

# 查看当前资源使用
kubectl top nodes
```

### 资源监控命令

```bash
# 实时监控节点资源
watch -n 5 'kubectl top nodes'

# 查看各命名空间资源占用
kubectl top pods -A --sort-by=memory | head -20

# 查看Pod分布
kubectl get pods -A -o wide --sort-by='.spec.nodeName'
```

---

## 📦 核心特性

### ✅ 全离线适配
- 所有模块支持离线环境部署
- 详细的镜像预推送清单
- Helm Chart离线安装指南
- 私有仓库配置完整方案

### ✅ 生产级实践
- Thanos长期存储方案
- SLO与错误预算实践
- 证书自动轮换
- etcd备份与Velero灾备

### ✅ 安全合规
- 镜像签名(Cosign)与漏洞扫描(Trivy)
- RBAC精细化权限控制
- Secret加密管理(Sealed Secrets)
- Falco运行时安全监控
- CIS基准合规检查

### ✅ 可观测性三支柱
- **Metrics**: Prometheus + Thanos + Grafana
- **Logs**: Loki + Promtail
- **Traces**: OpenTelemetry + Tempo + Jaeger
- **关联**: TraceID贯穿三支柱统一查询

### ✅ GitOps与DevSecOps
- ArgoCD多集群管理
- Argo Rollouts渐进式交付
- Tekton Pipeline as Code
- 安全门禁与SBOM生成

### ✅ 故障排查体系 (2026新增)
- **40+诊断脚本**: 覆盖K8s/中间件/Linux/网络/内核五大领域
- **统一运行器**: `run-all.sh` 一键诊断，`--module` 分模块运行
- **自动修复链**: 磁盘满/FD耗尽/服务失败/僵尸进程/conntrack/inotify
- **告警处置**: 分级/确认/自动修复/复盘/企业微信通知完整闭环
- **面试案例**: 25类故障STAR-R模板 + 完整拆解

### ✅ 2024-2025前沿实践
- **平台工程**: IDP、多租户、Backstage门户
- **FinOps**: OpenCost、成本治理、预算管理
- **AI Native**: K8s+AI、KServe、AIOps智能运维

### ✅ 2025-2026 LLM时代AIOps
- **RAG知识库**: 向量检索增强生成，运维知识问答 (模块22)
- **Multi-Agent**: 多Agent协作，复杂任务自动化 (模块22)
- **LLM运维助手**: 告警分析、日志解读、命令生成 (模块19)
- **轻量异常检测**: Z-Score/IQR/移动平均，无GPU实现 (模块19)

### ✅ 2026技术趋势增量
- **eBPF与Cilium**: 替代iptables/Calico，统一网络/安全/可观测数据面 (模块05)
- **Sidecarless服务网格**: Ambient Mesh/Kmesh，资源节省80% (模块08)
- **Gateway API**: 替代Ingress，多团队原生支持 (模块08)
- **AI调度(Volcano)**: Agent编排、跨集群AI任务调度 (模块19)
- **Serverless融合**: Knative伸缩至零，低频服务成本优化 (模块19)

---

## 📋 CKA/CKS考点覆盖

| 考试 | 覆盖模块 | 核心考点 |
|------|---------|---------|
| **CKA** | 01, 04, 05, 06, 07, 08, 29, 31, 32 | 集群安装、网络、存储、故障排查、Linux排查 |
| **CKS** | 02, 04, 08, 09, 16, 29 | 镜像安全、RBAC、NetworkPolicy、审计日志、Falco、故障排查 |

---

## 📖 使用指南

### 1. 前置准备
每个模块都包含**离线前置准备**章节，请按顺序执行：
1. 镜像预推送到Harbor
2. Helm Chart下载
3. 二进制文件准备
4. 环境检查

### 2. 按模块学习
建议按模块顺序学习，每个模块包含：
- 架构图与核心概念
- 离线前置准备
- 实战部署步骤
- 验证与测试
- 故障排查案例
- CKA/CKS考点
- 高频面试题

### 3. 故障排查脚本
`troubleshoot-scripts/` 目录提供完整的诊断脚本体系：

```bash
cd troubleshoot-scripts

# 运行全部诊断（只读安全）
bash run-all.sh

# 按模块运行
bash run-all.sh --module os         # 系统诊断 (31-linux)
bash run-all.sh --module network    # 网络诊断 (32-network)
bash run-all.sh --module kernel     # 内核诊断 (33-kernel)
bash run-all.sh --module k8s        # K8S诊断 (29-k8s)
bash run-all.sh --module middleware # 中间件诊断 (30-middleware)
bash run-all.sh --module daily      # 日常巡检 (36-daily)

# 运行单个脚本
bash run-all.sh --script check-cpu

# 操作类模块（需传参，有副作用）
bash run-all.sh --module deploy     # ⚠️ 版本发布
bash run-all.sh --module alert      # 告警处置
```

### 4. 快速开始

```bash
# 1. 克隆课程仓库(在Gitea上)
git clone http://192.168.1.61:3000/demo/cloud-native-course.git
cd cloud-native-course

# 2. 按顺序执行模块
# 从 00-基础设施准备.md 开始
```

---

## 📚 参考资源

- [Kubernetes官方文档](https://kubernetes.io/docs/)
- [OpenTelemetry官方文档](https://opentelemetry.io/docs/)
- [Istio官方文档](https://istio.io/latest/docs/)
- [Prometheus官方文档](https://prometheus.io/docs/)
- [ArgoCD官方文档](https://argo-cd.readthedocs.io/)

---

## 🤝 贡献指南

欢迎提交Issue和PR来改进课程内容：
1. 发现错误或不清晰的地方
2. 补充更多故障排查案例
3. 增加新的生产实践场景
4. 优化离线部署流程

---

## 📝 更新日志

### v5.0 (2026-07) - 故障排查与原理层完整版
- ✅ 新增模块29: K8S故障排查与根因分析 (分层诊断模型/故障分类/排障脚本库)
- ✅ 新增模块30: 中间件故障排查 (ES/Kafka/MySQL/Nginx/Redis五件套)
- ✅ 新增模块31: Linux系统故障排查 (CPU/内存/磁盘/进程诊断)
- ✅ 新增模块32: 网络协议深度解析 (TCP/UDP/握手挥手/拥塞控制)
- ✅ 新增模块33: 计算机基础与内核 (进程调度/内存管理/CFS)
- ✅ 新增模块34: 运维架构设计原理 (容器vs虚拟机/K8S设计决策)
- ✅ 新增附录: K8S生产环境故障分类与面试案例详解 (25类故障+STAR-R模板)
- ✅ 新增 troubleshoot-scripts/ 诊断脚本体系 (40+脚本/统一运行器/自动修复)
- ✅ README补全模块29-34及附录，修正计数和过期引用
- ✅ 新增学习路径八: 故障排查与SRE

### v4.2 (2025-01) - 新增LLM时代AIOps模块
- ✅ 新增模块22: LLM时代的AIOps实战 (RAG知识库/Multi-Agent/私有化LLM)
- ✅ 新增模块23: K8s高级调度机制实战 (Volcano/Gang Scheduling/GPU调度)
- ✅ 增强模块19: 新增LLM运维助手、轻量异常检测、AI Agent实战
- ✅ 新增学习路径六: AI运维专家
- ✅ 所有AI相关内容无需GPU，使用云端LLM API即可实现
- ✅ 调度机制演示全部使用CPU Pod，无需GPU硬件

### v4.1 (2025-01) - 新增云厂商实战模块
- ✅ 新增模块21: 主流云厂商产品实战 (AWS/Azure/阿里云/腾讯云/华为云)
- ✅ 包含完整价格对比表（季度更新机制）
- ✅ 跨云迁移策略与多云管理工具

### v4.0 (2025-01) - 企业实践覆盖度提升至95%
- ✅ 新增模块20: 数据库Operator实战 (MySQL/PostgreSQL/Redis)
- ✅ 模块00新增: CSI存储驱动实战 (Longhorn离线部署)
- ✅ 模块01新增: Windows容器支持概述
- ✅ 模块02新增: 多架构镜像构建 (docker buildx)
- ✅ 模块05新增: Calico高级网络策略 + CoreDNS故障排查
- ✅ 模块08新增: ExternalDNS自动DNS + API Gateway选型
- ✅ 模块09新增: 持续性能分析 (Pyroscope/Parca)
- ✅ 模块10新增: 事件驱动技术选型 (Kafka/NATS/RabbitMQ/CloudEvents)
- ✅ 模块12新增: GitOps PR晋升工作流
- ✅ 模块13新增: 多架构CI流水线
- ✅ 模块14新增: 混沌工程中止条件 + Cluster Autoscaler概念
- ✅ 模块15增强: VMware Workstation完整操作指南 (基础镜像制作/Terraform生命周期管理/快速复刻)
- ✅ 模块16新增: Kyverno准入控制 + 行业合规框架 + 安全扫描分层

### v3.1 (2025-01) - 2026技术趋势增量
- ✅ 模块05新增: eBPF与Cilium趋势章节 (Cilium部署/Hubble/Tetragon)
- ✅ 模块08新增: Sidecarless服务网格 (Ambient Mesh/Kmesh)
- ✅ 模块08新增: Gateway API实战 (替代Ingress方案)
- ✅ 模块19新增: Volcano AI调度 + Knative Serverless融合

### v3.0 (2025-01) - 生产实践完整版
- ✅ 新增模块17: 平台工程与多租户 (2024趋势)
- ✅ 新增模块18: FinOps成本优化 (2024趋势)
- ✅ 新增模块19: AI Native与AIOps (2025趋势)
- ✅ 新增mall-demo: 3套微服务Demo (Spring/Go/混合)
- ✅ 新增GitLab CI配置和DevSecOps完整流程
- ✅ 新增SonarQube、SBOM、Trivy安全扫描

### v2.0 (2025-01)
- ✅ 新增模块15: 基础设施即代码(IaC)
- ✅ 新增模块16: 云原生安全与合规
- ✅ 深度增强模块02: Harbor镜像签名与漏洞扫描
- ✅ 深度增强模块04: etcd备份、证书轮换、Velero灾备
- ✅ 深度增强模块06: Thanos长期存储、SLO实践、告警路由
- ✅ 深度增强模块09: 采样策略、三支柱关联、成本估算
- ✅ 深度增强模块12: Secrets管理、Argo Rollouts、多集群
- ✅ 深度增强模块13: Pipeline as Code、DevSecOps、多环境推广
- ✅ 深度增强模块14: 混沌工程、容量压测、FinOps

### v1.0 (2024-12)
- 🎉 初始版本发布
- 14个核心模块
- 全离线环境适配

---

> **提示**: 本课程设计为在离线环境中完整运行，所有外部依赖都已通过Harbor镜像仓库和Gitea代码仓库本地化。
