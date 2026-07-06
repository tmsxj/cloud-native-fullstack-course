# 云原生术语中英对照表

> 本文档收录课程中所有英文术语的中文释义，供学习时参考。
> 
> **使用约定**: 每个术语在课程文件中首次出现时标注中文释义，后续不再重复。

---

## 1. Kubernetes 核心概念

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Pod** | Pod（容器组） | K8s最小调度单元，包含一个或多个容器 |
| **Node** | 节点 | 运行Pod的工作机器（物理机/虚拟机） |
| **Cluster** | 集群 | 多个Node组成的K8s集群 |
| **Namespace** | 命名空间 | 集群内的逻辑隔离单元 |
| **Deployment** | 部署 | 管理无状态应用的控制器，支持滚动更新 |
| **StatefulSet** | 有状态副本集 | 管理有状态应用（如数据库），保证Pod顺序和标识 |
| **DaemonSet** | 守护进程集 | 确保每个（或指定）Node上运行一个Pod副本 |
| **ReplicaSet** | 副本集 | 确保Pod副本数维持在期望值 |
| **Service** | 服务 | 为一组Pod提供稳定的网络访问入口 |
| **Ingress** | 入口 | HTTP/HTTPS七层路由规则，外部流量入口 |
| **ConfigMap** | 配置映射 | 存储非敏感配置数据，以环境变量或卷方式注入Pod |
| **Secret** | 密钥 | 存储敏感数据（密码、Token），Base64编码 |
| **PVC** | 持久卷声明 | 用户对存储的请求，类似"存储订单" |
| **PV** | 持久卷 | 实际的存储资源，类似"存储商品" |
| **StorageClass** | 存储类 | 动态存储配置模板，自动创建PV |
| **Volume** | 卷 | Pod内的存储目录，可挂载多种后端 |
| **HPA** | 水平Pod自动伸缩 | 根据CPU/内存等指标自动调整Pod副本数 |
| **VPA** | 垂直Pod自动伸缩 | 自动调整Pod的CPU/内存请求值 |
| **CronJob** | 定时任务 | 按Cron表达式定时创建Job |
| **Job** | 任务 | 一次性任务，运行完成即退出 |
| **Label** | 标签 | 键值对，用于资源分组和筛选 |
| **Annotation** | 注解 | 键值对，用于存储元数据（不可用于筛选） |
| **Taint** | 污点 | 标记Node，排斥不容忍该污点的Pod |
| **Toleration** | 容忍 | 允许Pod调度到有对应Taint的Node |
| **NodeSelector** | 节点选择器 | 通过Label将Pod调度到指定Node |
| **Affinity** | 亲和性 | Pod/Node级别的调度偏好（软/硬约束） |
| **Liveness Probe** | 存活探针 | 检测容器是否存活，失败则重启 |
| **Readiness Probe** | 就绪探针 | 检测容器是否就绪，失败则从Service摘除 |
| **Startup Probe** | 启动探针 | 检测容器是否启动完成，用于慢启动应用 |
| **RBAC** | 基于角色的访问控制 | K8s权限管理机制（Role + RoleBinding） |
| **API Server** | API服务器 | K8s控制面核心组件，接收所有API请求 |
| **etcd** | etcd分布式存储 | 存储集群所有数据的键值数据库 |
| **Scheduler** | 调度器 | 决定Pod运行在哪个Node |
| **Controller Manager** | 控制器管理器 | 运行各种控制器（Deployment、Node等） |
| **kubelet** | kubelet节点代理 | Node上的代理，负责Pod生命周期管理 |
| **kube-proxy** | kube-proxy网络代理 | 维护节点网络规则，实现Service路由 |
| **kubectl** | kubectl命令行工具 | K8s集群管理命令行客户端 |
| **kubeadm** | kubeadm集群初始化工具 | K8s集群快速初始化和管理工具 |

---

## 2. 网络相关术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **CNI** | 容器网络接口 | Container Network Interface，K8s网络插件标准 |
| **Calico** | Calico网络插件 | 基于BGP的高性能网络策略插件 |
| **Cilium** | Cilium网络插件 | 基于eBPF的新一代网络/安全/可观测插件 |
| **BGP** | 边界网关协议 | Border Gateway Protocol，用于路由学习和传播 |
| **VXLAN** | 虚拟扩展局域网 | Virtual Extensible LAN，网络Overlay封装协议 |
| **IPIP** | IP-in-IP隧道 | IP封装在IP中的隧道协议 |
| **eBPF** | 扩展的伯克利包过滤器 | Extended BPF，内核级可编程技术 |
| **NetworkPolicy** | 网络策略 | K8s原生网络隔离策略 |
| **Service Mesh** | 服务网格 | 微服务间通信的基础设施层（如Istio） |
| **Sidecar** | 边车容器 | 与主容器共享Pod的辅助容器（如Envoy代理） |
| **mTLS** | 双向TLS认证 | Mutual TLS，服务间双向证书认证 |
| **Gateway API** | 网关API | K8s新一代流量管理API标准 |
| **DNS** | 域名系统 | Domain Name System，域名解析服务 |
| **CoreDNS** | CoreDNS | K8s集群内置的DNS服务 |
| **NAT** | 网络地址转换 | Network Address Translation |
| **CIDR** | 无类别域间路由 | Classless Inter-Domain Routing，IP地址段表示法 |
| **TCP** | 传输控制协议 | Transmission Control Protocol，可靠传输协议 |
| **UDP** | 用户数据报协议 | User Datagram Protocol，无连接传输协议 |
| **HTTP/HTTPS** | 超文本传输协议 | Hypertext Transfer Protocol，Web通信协议 |
| **TLS/SSL** | 传输层安全协议 | Transport Layer Security，加密通信协议 |
| **Ambient Mesh** | 无边车网格 | Istio新一代架构，无需Sidecar代理 |

---

## 3. 存储相关术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **CSI** | 容器存储接口 | Container Storage Interface，存储插件标准 |
| **local-path** | 本地路径存储 | 使用节点本地磁盘的简单存储 |
| **Longhorn** | Longhorn分布式存储 | 轻量级K8s分布式块存储方案 |
| **Rook-Ceph** | Rook-Ceph存储 | 基于Ceph的企业级K8s存储编排 |
| **Snapshot** | 快照 | 存储卷的某一时刻的只读副本 |
| **Clone** | 克隆 | 从现有卷创建完全相同的副本 |
| **PV Reclaim Policy** | PV回收策略 | PV被释放后的处理方式（Retain/Delete/Recycle） |
| **StorageClass QoS** | 存储服务质量 | 存储性能等级（如SSD/HDD） |
| **VolumeSnapshotClass** | 卷快照类 | 定义快照的存储后端和参数 |
| **StorageClass Provisioner** | 存储类供应器 | 动态创建PV的后端驱动（如local-path） |
| **RWX** | 读写多挂载 | ReadWriteMany，多个Pod可同时读写 |
| **RWO** | 读写单挂载 | ReadWriteOnce，只能一个Pod挂载读写 |
| **ROX** | 只读多挂载 | ReadOnlyMany，多个Pod只读挂载 |

---

## 4. 容器与运行时

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **containerd** | containerd容器运行时 | CNCF标准的容器运行时 |
| **Docker** | Docker容器引擎 | 最流行的容器构建和运行平台 |
| **Image** | 镜像 | 容器的只读模板，包含应用和依赖 |
| **Container** | 容器 | 镜像的运行实例 |
| **Registry** | 镜像仓库 | 存储和分发Docker镜像的服务 |
| **Harbor** | Harbor镜像仓库 | 企业级Docker镜像仓库（VMware开源） |
| **Dockerfile** | Docker构建文件 | 定义镜像构建步骤的文本文件 |
| **OCI** | 开放容器倡议 | Open Container Initiative，容器标准组织 |
| **CRI** | 容器运行时接口 | Container Runtime Interface，K8s与运行时的接口 |
| **Sandbox** | 沙箱 | 容器隔离运行环境 |
| **OverlayFS** | 叠加文件系统 | 联合挂载的分层文件系统，Docker镜像基础 |
| **nerdctl** | nerdctl容器CLI | containerd的Docker兼容命令行工具 |
| **Buildkit** | BuildKit构建引擎 | Docker/容器镜像的高级构建引擎 |
| **Multi-arch** | 多架构 | 同一镜像支持多种CPU架构（amd64/arm64） |
| **Docker Compose** | Docker编排工具 | 定义和运行多容器应用的工具 |

---

## 5. 可观测性术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Observability** | 可观测性 | 通过外部信号推断系统内部状态的能力 |
| **Metrics** | 指标 | 可聚合的数值数据（如CPU使用率、请求数） |
| **Logs** | 日志 | 离散的事件记录 |
| **Traces** | 链路追踪 | 请求在分布式系统中的完整路径 |
| **Prometheus** | Prometheus监控 | CNCF毕业项目，时序数据库+告警+查询 |
| **Grafana** | Grafana可视化 | 开源监控数据可视化面板 |
| **Loki** | Loki日志系统 | Grafana Labs的轻量级日志聚合系统 |
| **Tempo** | Tempo链路存储 | Grafana Labs的链路追踪后端 |
| **Jaeger** | Jaeger链路追踪 | CNCF链路追踪系统（Uber开源） |
| **Alert** | 告警 | 当指标满足条件时触发的通知 |
| **SLO** | 服务等级目标 | Service Level Objective，可靠性目标（如99.9%） |
| **SLI** | 服务等级指标 | Service Level Indicator，衡量SLO的具体指标 |
| **SLA** | 服务等级协议 | Service Level Agreement，与客户签订的正式协议 |
| **Error Budget** | 错误预算 | SLO允许的故障时间（如99.9%即月43.2分钟） |
| **RED Method** | RED方法 | Rate（请求率）、Errors（错误率）、Duration（延迟） |
| **USE Method** | USE方法 | Utilization（使用率）、Saturation（饱和度）、Errors（错误） |
| **Thanos** | Thanos长期存储 | Prometheus高可用和长期存储方案 |
| **OpenTelemetry** | 开放遥测 | CNCF统一的可观测性数据采集标准（OTel） |
| **Span** | 跨度 | 链路追踪中的单个操作单元 |
| **Trace** | 追踪 | 完整的请求链路，由多个Span组成 |
| **Sampling** | 采样 | 按策略采集部分数据（如1%概率采样） |
| **Profiling** | 性能分析 | 持续采集CPU/内存热点，定位性能瓶颈 |
| **PromQL** | Prometheus查询语言 | Prometheus的时序数据查询语言 |
| **Alertmanager** | 告警管理器 | Prometheus生态的告警路由和分组组件 |
| **RetentionPolicy** | 数据保留策略 | 时序数据的自动清理和保留周期 |
| **Cardinality** | 基数 | 指标标签组合的唯一值数量，过高会导致性能问题 |

---

## 6. CI/CD与交付

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **CI** | 持续集成 | Continuous Integration，代码提交后自动构建和测试 |
| **CD** | 持续交付/部署 | Continuous Delivery/Deployment，自动发布到各环境 |
| **GitOps** | Git运维 | 以Git为唯一事实来源的运维模式 |
| **ArgoCD** | ArgoCD交付工具 | CNCF项目，基于GitOps的K8s应用交付 |
| **Tekton** | Tekton流水线 | CNCF项目，K8s原生的CI/CD框架 |
| **Pipeline** | 流水线 | 自动化的构建-测试-部署流程 |
| **Pipeline as Code** | 流水线即代码 | 用YAML定义流水线，版本化管理 |
| **Helm** | Helm包管理器 | K8s应用包管理工具（类似apt/yum） |
| **Chart** | Helm图表 | Helm的应用打包格式 |
| **Kustomize** | Kustomize配置管理 | K8s原生配置覆盖工具，无需模板 |
| **Overlay** | 覆盖层 | Kustomize中基于基础配置的差异化配置 |
| **Canary** | 金丝雀发布 | 灰度发布策略，逐步放量到小比例用户 |
| **Blue-Green** | 蓝绿部署 | 两套环境切换的零停机发布策略 |
| **Rollback** | 回滚 | 将应用恢复到之前的版本 |
| **DevSecOps** | 安全开发运维 | 将安全集成到CI/CD流程中 |
| **SAST** | 静态应用安全测试 | Static Application Security Testing，扫描源代码漏洞 |
| **SCA** | 软件成分分析 | Software Composition Analysis，扫描依赖漏洞 |
| **DAST** | 动态应用安全测试 | Dynamic Application Security Testing，运行时漏洞扫描 |
| **SBOM** | 软件物料清单 | Software Bill of Materials，依赖组件清单 |
| **SonarQube** | SonarQube代码质量 | 开源代码质量和安全扫描平台 |
| **Trivy** | Trivy安全扫描 | Aqua开源的容器镜像/文件系统漏洞扫描器 |
| **GitLab CI** | GitLab持续集成 | GitLab内置的CI/CD流水线功能 |
| **Artifact** | 制品 | CI/CD流程中构建产生的产物（镜像/包/JAR） |
| **Release** | 发布 | 软件版本的正式发布动作 |
| **Environment** | 环境 | 部署的隔离空间（dev/staging/prod） |

---

## 7. 安全与合规

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **RBAC** | 基于角色的访问控制 | Role-Based Access Control |
| **IAM** | 身份与访问管理 | Identity and Access Management |
| **OIDC** | OpenID连接 | OpenID Connect，基于OAuth 2.0的身份认证协议 |
| **JWT** | JSON Web令牌 | JSON Web Token，紧凑的令牌格式 |
| **Falco** | Falco运行时安全 | CNCF项目，基于规则的容器运行时安全监控 |
| **Tetragon** | Tetragon可观测安全 | Cilium的eBPF运行时安全和可观测工具 |
| **Cosign** | Cosign镜像签名 | SigStore项目的容器镜像签名工具 |
| **Sealed Secrets** | 加密封装密钥 | Bitnami的K8s Secret加密方案 |
| **Kyverno** | Kyverno策略引擎 | K8s原生策略管理工具（类似OPA） |
| **OPA** | 开放策略代理 | Open Policy Agent，通用策略引擎 |
| **CIS Benchmark** | CIS安全基准 | Center for Internet Security的安全检查标准 |
| **SOC2** | SOC2合规 | Service Organization Control 2，安全合规框架 |
| **GDPR** | 通用数据保护条例 | General Data Protection Regulation，欧盟数据保护法 |
| **PCI-DSS** | 支付卡行业数据安全标准 | Payment Card Industry Data Security Standard |
| **Admission Controller** | 准入控制器 | K8s API请求拦截器（验证/变更） |
| **NetworkPolicy** | 网络策略 | K8s原生网络隔离策略 |
| **Pod Security** | Pod安全标准 | K8s Pod安全策略（Privileged/Baseline/Restricted） |
| **mTLS** | 双向TLS | Mutual TLS，服务间双向证书认证 |

---

## 8. 基础设施即代码

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **IaC** | 基础设施即代码 | Infrastructure as Code，用代码管理基础设施 |
| **Terraform** | Terraform编排工具 | HashiCorp的多云基础设施编排工具 |
| **HCL** | HashiCorp配置语言 | HashiCorp Configuration Language，Terraform专用语言 |
| **Provider** | 提供者 | Terraform中管理特定云厂商的插件 |
| **State** | 状态文件 | 记录已创建资源的元数据（.tfstate） |
| **Ansible** | Ansible自动化 | Red Hat的配置管理和自动化工具 |
| **Playbook** | 剧本 | Ansible的任务编排文件（YAML格式） |
| **Inventory** | 主机清单 | Ansible管理的主机列表 |
| **Pulumi** | Pulumi编排工具 | 用编程语言（Python/Go）管理基础设施 |
| **Crossplane** | Crossplane多云控制 | 基于K8s的多云资源管理平台 |
| **cloud-init** | 云初始化 | Linux虚拟机首次启动时的自动配置工具 |

---

## 9. 服务网格与流量管理

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Istio** | Istio服务网格 | CNCF毕业项目，最流行的服务网格 |
| **Envoy** | Envoy代理 | Lyft开源的高性能L4/L7代理 |
| **VirtualService** | 虚拟服务 | Istio流量路由规则 |
| **DestinationRule** | 目标规则 | Istio负载均衡和连接池配置 |
| **Gateway** | 网关 | Istio入口/出口流量管理 |
| **ExternalDNS** | 外部DNS | 自动同步K8s资源到DNS记录 |
| **cert-manager** | 证书管理器 | K8s自动TLS证书签发和续期 |
| **APISIX** | APISIX网关 | Apache开源的高性能API网关 |
| **Kong** | Kong网关 | 开源API网关和企业级平台 |
| **Rate Limiting** | 速率限制 | 限制单位时间内的请求数量 |
| **Circuit Breaker** | 熔断器 | 自动切断故障服务的调用，防止雪崩 |
| **Retry** | 重试 | 请求失败后自动重试的机制 |
| **Timeout** | 超时 | 请求等待响应的最大时间限制 |
| **Health Check** | 健康检查 | 定期检测服务是否正常可用 |

---

## 10. 消息队列与数据

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Kafka** | Kafka消息队列 | Apache高吞吐量分布式消息队列 |
| **KRaft** | KRaft共识协议 | Kafka内置的共识协议（替代ZooKeeper） |
| **NATS** | NATS消息系统 | 高性能轻量级消息系统 |
| **RabbitMQ** | RabbitMQ消息队列 | Erlang实现的消息队列，支持多种协议 |
| **CloudEvents** | 云事件标准 | CNCF事件数据描述标准 |
| **Strimzi** | Strimzi Kafka Operator | 在K8s上部署和管理Apache Kafka |
| **Topic** | 主题 | 消息的逻辑分类通道 |
| **Partition** | 分区 | Topic的物理分片，提高并行度 |
| **Consumer Group** | 消费者组 | 一组消费者共同消费Topic |
| **Offset** | 偏移量 | 消费者在分区中的消费位置 |

---

## 11. 平台工程与FinOps

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **IDP** | 内部开发者平台 | Internal Developer Platform，自助服务平台 |
| **Backstage** | Backstage开发者门户 | Spotify开源的开发者门户框架 |
| **Namespace as a Service** | 命名空间即服务 | 自助申请和管理命名空间 |
| **ResourceQuota** | 资源配额 | 命名空间级别的资源使用上限 |
| **LimitRange** | 限制范围 | Pod/容器的默认和最大资源限制 |
| **FinOps** | 云财务运营 | 云成本优化和管理实践 |
| **OpenCost** | OpenCost成本监控 | K8s成本监控和分摊工具 |
| **Chargeback** | 成本分摊 | 将云成本分摊到各团队/项目 |
| **Showback** | 成本展示 | 向各团队展示其资源使用成本 |
| **Knative** | Knative Serverless | K8s上的Serverless计算平台 |
| **Golden Signal** | 黄金信号 | Google提出的四个核心监控指标（延迟/流量/错误/饱和度） |
| **On-call** | 值班 | 运维人员轮班处理告警和故障 |
| **Runbook** | 运维手册 | 标准化的故障处理操作文档 |
| **SRE** | 站点可靠性工程 | Site Reliability Engineering，Google提出的运维方法论 |
| **Toil** | 苦力活 | 重复性、无创造性的运维工作（应自动化消除） |

---

## 12. AI与AIOps

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **KServe** | KServe推理服务 | K8s上的ML模型推理服务框架 |
| **GPU** | 图形处理器 | Graphics Processing Unit，AI训练/推理加速 |
| **Volcano** | Volcano调度器 | K8s高性能计算/AI任务调度器 |
| **AIOps** | 智能运维 | Artificial Intelligence for IT Operations |
| **Inference** | 推理 | 使用训练好的模型进行预测 |
| **Model Serving** | 模型服务 | 将ML模型部署为在线服务 |
| **LLM** | 大语言模型 | Large Language Model，如GPT、DeepSeek |
| **RAG** | 检索增强生成 | Retrieval-Augmented Generation，结合知识库的LLM应用 |
| **Agent** | 智能体 | 可自主规划、执行、反思的AI系统 |
| **Prompt** | 提示词 | 发送给LLM的指令和上下文 |
| **Embedding** | 向量嵌入 | 将文本转换为向量表示 |
| **Vector DB** | 向量数据库 | 存储和检索向量嵌入的数据库（如Milvus、Chroma） |
| **Token** | 词元 | LLM处理的最小文本单元 |
| **Temperature** | 温度参数 | 控制LLM输出随机性的参数 |
| **Multi-Agent** | 多智能体 | 多个Agent协作完成复杂任务 |
| **ReAct** | 推理行动循环 | Reasoning + Acting，Agent的经典架构 |
| **Ollama** | Ollama推理框架 | 轻量级本地LLM运行工具 |
| **vLLM** | vLLM推理引擎 | 高性能LLM推理服务 |
| **Chroma** | Chroma向量库 | 轻量级向量数据库 |
| **Milvus** | Milvus向量库 | 企业级向量数据库 |

---

## 13. 调度相关术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Gang Scheduling** | 协同调度 | 多个Pod必须同时调度成功，否则全部等待 |
| **PodGroup** | Pod组 | Volcano中多个Pod作为一个调度单元 |
| **Queue** | 资源队列 | Volcano中按权重分配资源配额 |
| **Preemption** | 抢占 | 高优先级任务抢占低优先级任务的资源 |
| **PriorityClass** | 优先级类 | 定义Pod的调度优先级 |
| **NUMA** | 非统一内存访问 | Non-Uniform Memory Access，CPU与内存的亲和性 |
| **NVLink** | NVLink互联 | NVIDIA GPU间高速互联技术 |
| **MIG** | 多实例GPU | Multi-Instance GPU，A100/H100硬件级GPU分割 |
| **Time-slicing** | 时间片共享 | 多个Pod轮流使用同一GPU |
| **Topology Awareness** | 拓扑感知 | 调度时考虑GPU/CPU/网络的物理拓扑 |
| **Scheduler Framework** | 调度器框架 | K8s可扩展的调度器插件架构 |
| **Filter** | 过滤 | 调度阶段：排除不满足条件的Node |
| **Score** | 打分 | 调度阶段：对候选Node打分排序 |
| **Bind** | 绑定 | 调度阶段：将Pod绑定到目标Node |
| **Yunikorn** | Yunikorn调度器 | Apache的K8s资源调度器 |
| **Kueue** | Kueue队列管理 | K8s原生的批处理任务队列管理 |
| **Descheduler** | 反调度器 | 定期重新平衡Pod分布，优化资源利用率 |
| **cgroup** | 控制组 | Linux内核的资源隔离和限制机制 |
| **Namespace Quota** | 命名空间配额 | 限制命名空间级别的资源总量 |
| **Pod Overhead** | Pod开销 | Pod沙箱本身占用的额外系统资源 |
| **Taint-based Eviction** | 基于污点的驱逐 | Node异常时自动驱逐不容忍污点的Pod |
| **PDB** | Pod中断预算 | Pod Disruption Budget，限制自愿中断时的最大不可用Pod数 |

---

## 14. 云厂商术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **AWS** | 亚马逊云服务 | Amazon Web Services |
| **Azure** | 微软云 | Microsoft Azure |
| **EC2** | 弹性计算云 | Elastic Compute Cloud（AWS虚拟机） |
| **ECS** | 弹性计算服务 | Elastic Compute Service（阿里云/华为云虚拟机） |
| **CVM** | 云虚拟机 | Cloud Virtual Machine（腾讯云虚拟机） |
| **S3** | 简单存储服务 | Simple Storage Service（AWS对象存储） |
| **OSS** | 对象存储服务 | Object Storage Service（阿里云） |
| **COS** | 对象存储 | Cloud Object Storage（腾讯云） |
| **OBS** | 对象存储 | Object Bucket Service（华为云） |
| **VPC** | 虚拟私有云 | Virtual Private Cloud |
| **ALB** | 应用负载均衡 | Application Load Balancer |
| **SLB** | 服务器负载均衡 | Server Load Balancer（阿里云） |
| **CLB** | 负载均衡 | Cloud Load Balancer（腾讯云） |
| **RDS** | 关系数据库服务 | Relational Database Service |
| **EBS** | 弹性块存储 | Elastic Block Store（AWS块存储） |
| **IAM** | 身份与访问管理 | Identity and Access Management |
| **CloudWatch** | 云监控（AWS） | AWS监控和告警服务 |
| **EKS** | 弹性K8s服务 | Elastic Kubernetes Service（AWS） |
| **ACK** | 容器K8s服务 | Alibaba Cloud Kubernetes（阿里云） |
| **TKE** | 腾讯K8s引擎 | Tencent Kubernetes Engine（腾讯云） |
| **CCE** | 云容器引擎 | Cloud Container Engine（华为云） |

---

## 15. 故障排查术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **OOM** | 内存溢出 | Out of Memory，Pod因超出内存限制被内核杀死 |
| **OOMKilled** | OOM被终止 | K8s事件类型，表示Pod因OOM被终止 |
| **CrashLoopBackOff** | 崩溃循环回退 | Pod反复启动失败后的K8s状态 |
| **ImagePullBackOff** | 镜像拉取回退 | 镜像拉取失败后的K8s状态，持续重试 |
| **Pending** | 等待中 | Pod等待调度或资源分配的状态 |
| **Terminating** | 终止中 | Pod正在被删除，等待优雅关闭完成 |
| **Root Cause** | 根因 | 故障的根本原因，区别于表象 |
| **Postmortem** | 故障复盘 | 故障后系统性分析原因和改进措施的流程 |
| **Runbook** | 运维操作手册 | 标准化的故障处理操作步骤文档 |
| **MTTR** | 平均恢复时间 | Mean Time To Recovery，故障恢复速度指标 |
| **MTBF** | 平均故障间隔 | Mean Time Between Failures，系统稳定性的指标 |
| **STAR-R** | 面试结构法 | Situation/Task/Action/Result/Reflection 案例回答法 |
| **Triage** | 告警分级 | 对告警按严重程度分类处理的流程 |
| **Escalation** | 告警升级 | 低级别告警在规定时间内未处理则升级到更高优先级 |
| **Conntrack** | 连接跟踪 | Linux内核的网络连接状态跟踪表 |
| **FD** | 文件描述符 | File Descriptor，进程打开的文件/网络连接句柄 |
| **Inotify** | Inode通知 | Linux内核的文件系统事件监控机制 |
| **SIGTERM** | 终止信号 | 优雅关闭信号，K8s删除Pod时首先发送 |
| **SIGKILL** | 强制终止信号 | 强制杀死进程的信号，无法被捕获处理 |
| **Graceful Shutdown** | 优雅关闭 | 应用在收到终止信号后完成存量请求再退出 |

---

## 16. 网络协议深度术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **SYN** | 同步标志 | TCP三次握手中请求建立连接的标志位 |
| **ACK** | 确认标志 | TCP确认收到数据的标志位 |
| **FIN** | 结束标志 | TCP四次挥手中请求断开连接的标志位 |
| **RST** | 重置标志 | TCP异常终止连接的标志位 |
| **MSS** | 最大分段大小 | Maximum Segment Size，TCP单个数据段的最大载荷 |
| **MTU** | 最大传输单元 | Maximum Transmission Unit，链路层最大数据包大小 |
| **CWND** | 拥塞窗口 | Congestion Window，TCP发送方可发送的最大数据量 |
| **RWND** | 接收窗口 | Receive Window，接收方通告的可接收数据量 |
| **Slow Start** | 慢启动 | TCP拥塞控制初始阶段，CWND指数增长 |
| **Congestion Avoidance** | 拥塞避免 | TCP拥塞控制主要阶段，CWND线性增长 |
| **Fast Retransmit** | 快速重传 | 收到3个重复ACK后不等待超时直接重传 |
| **Fast Recovery** | 快速恢复 | 快速重传后不回到慢启动，而是继续拥塞避免 |
| **TIME_WAIT** | 时间等待状态 | TCP连接关闭后的等待状态（2MSL），防止旧包干扰 |
| **CLOSE_WAIT** | 关闭等待状态 | 收到对端FIN但本端未关闭的连接状态 |
| **Ephemeral Port** | 临时端口 | 客户端发起连接时使用的动态端口范围 |
| **Backlog** | 半连接队列 | TCP SYN队列，存储未完成三次握手的连接 |
| **Keepalive** | 保活机制 | TCP定期发送探测包检测连接是否存活 |

---

## 17. 内核与操作系统术语

| 英文 | 中文 | 简要说明 |
|------|------|----------|
| **Kernel** | 内核 | 操作系统的核心组件，管理系统资源 |
| **User Space** | 用户空间 | 内核以外的应用程序运行空间 |
| **System Call** | 系统调用 | 用户空间程序请求内核服务的接口 |
| **Process** | 进程 | 正在运行的程序实例 |
| **Thread** | 线程 | 进程内的执行单元 |
| **Scheduler** | 调度器 | 内核中决定进程/线程运行的组件 |
| **CFS** | 完全公平调度器 | Completely Fair Scheduler，Linux默认进程调度器 |
| **Preemption** | 抢占 | 高优先级任务中断低优先级任务的执行 |
| **Context Switch** | 上下文切换 | CPU从一个进程/线程切换到另一个的开销 |
| **Load Average** | 平均负载 | 系统在1/5/15分钟内的平均运行队列长度 |
| **Page Fault** | 缺页异常 | 进程访问未映射到物理内存的虚拟地址时触发 |
| **Swap** | 交换分区 | 将内存数据换出到磁盘的机制 |
| **Page Cache** | 页缓存 | 内核缓存文件系统数据的区域 |
| **Buffer Cache** | 缓冲区缓存 | 内核缓存块设备数据的区域 |
| **Slab** | Slab分配器 | 内核对象内存分配的高效机制 |
| **NUMA** | 非统一内存访问 | Non-Uniform Memory Access，多CPU内存架构 |
| **HugePages** | 大页内存 | 使用大尺寸内存页（2MB/1GB）减少TLB miss |
| **Cgroups** | 控制组 | Control Groups，Linux资源隔离和限制机制 |
| **Namespaces** | 命名空间 | Linux进程隔离机制，容器技术基础 |

---

## 18. 其他常用缩写

| 英文 | 全称 | 中文 |
|------|------|------|
| **API** | Application Programming Interface | 应用程序编程接口 |
| **REST** | Representational State Transfer | 表述性状态转移（Web API风格） |
| **gRPC** | gRPC远程过程调用 | Google的高性能RPC框架 |
| **YAML** | YAML Ain't Markup Language | YAML数据序列化格式 |
| **JSON** | JavaScript Object Notation | JavaScript对象表示法 |
| **TLS** | Transport Layer Security | 传输层安全协议 |
| **SSH** | Secure Shell | 安全远程登录协议 |
| **HTTP** | Hypertext Transfer Protocol | 超文本传输协议 |
| **HTTPS** | HTTP Secure | 加密的HTTP |
| **TCP** | Transmission Control Protocol | 传输控制协议 |
| **UDP** | User Datagram Protocol | 用户数据报协议 |
| **IP** | Internet Protocol | 互联网协议 |
| **DNS** | Domain Name System | 域名系统 |
| **NTP** | Network Time Protocol | 网络时间协议 |
| **CPU** | Central Processing Unit | 中央处理器 |
| **RAM** | Random Access Memory | 随机存取存储器 |
| **SSD** | Solid State Drive | 固态硬盘 |
| **HDD** | Hard Disk Drive | 机械硬盘 |
| **LVM** | Logical Volume Manager | 逻辑卷管理器 |
| **PITR** | Point-in-Time Recovery | 时间点恢复 |
| **HA** | High Availability | 高可用 |
| **DR** | Disaster Recovery | 灾难恢复 |
| **MTTR** | Mean Time To Recovery | 平均恢复时间 |
| **MTBF** | Mean Time Between Failures | 平均故障间隔时间 |
| **QPS** | Queries Per Second | 每秒查询数 |
| **TPS** | Transactions Per Second | 每秒事务数 |
| **RPS** | Requests Per Second | 每秒请求数 |
| **RPM** | Requests Per Minute | 每分钟请求数 |
| **SLA** | Service Level Agreement | 服务等级协议 |
| **SLO** | Service Level Objective | 服务等级目标 |
| **SLI** | Service Level Indicator | 服务等级指标 |
| **Apdex** | Application Performance Index | 应用性能满意度指数 |
