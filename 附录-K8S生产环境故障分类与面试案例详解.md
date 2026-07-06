# K8S生产环境故障分类与面试案例详解

> 本文档系统梳理Kubernetes生产环境中常见的故障类型，按责任边界分为开发侧、运维侧、共同处理三类，并提供完整的面试案例拆解模板。
>
> **关联模块**: 本文档是 [模块29-K8S故障排查与根因分析](./29-K8S故障排查与根因分析.md) 的实战延伸——模块29侧重分层诊断模型和排查方法论，本文档侧重面试场景下的案例拆解和STAR-R表达。
> 故障排查脚本库见 [troubleshoot-scripts/](./troubleshoot-scripts/)。

---

## 一、故障分类总览

```
┌─────────────────────────────────────────────────────────────┐
│                    K8S生产环境故障分类                        │
├─────────────────┬─────────────────┬─────────────────────────┤
│    开发侧故障    │    运维侧故障    │    开发运维共同处理      │
├─────────────────┼─────────────────┼─────────────────────────┤
│ • 应用代码缺陷   │ • 基础设施问题   │ • 资源配置协作          │
│ • 服务治理缺失   │ • 集群组件故障   │ • 发布流程协作          │
│ • 配置管理不当   │ • 网络存储异常   │ • 监控告警协作          │
│ • 资源使用不当   │ • 安全证书问题   │ • 容量规划协作          │
└─────────────────┴─────────────────┴─────────────────────────┘
```

> **与模块29的关系**: 模块29 1.3节"故障分类与责任边界"定义了分类框架，本文档将每类展开为可面试的完整案例。

---

## 二、开发侧故障（8类）

### 2.1 应用内存泄漏导致Pod OOM重启

**故障现象**
- Pod频繁重启，`kubectl describe pod`显示`OOMKilled`
- 监控显示内存曲线持续上升，无回落
- 日常流量下运行数天后触发，压测时加速暴露

**排查路径**
```bash
# 1. 确认OOM事件
kubectl describe pod <pod-name> | grep -A5 "Last State"

# 2. 查看内存使用趋势
kubectl top pod <pod-name> --containers

# 3. 进入容器分析堆内存（Java示例）
kubectl exec -it <pod-name> -- jmap -histo:live 1 | head -20

# 4. 生成堆转储文件
kubectl exec -it <pod-name> -- jmap -dump:live,format=b,file=/tmp/heap.hprof 1
```

**根因分析**
- 业务迭代中引入循环引用（如事件监听器未注销）
- 缓存未设置过期策略，无限增长
- 大对象创建后未释放，GC无法回收

**修复方案**
- **短期**：临时调大Pod内存limit，争取修复时间
- **长期**：
  - 代码审查，修复循环引用
  - 添加缓存过期策略（LRU/TTL）
  - 引入内存分析工具（pprof/arthas）到CI流程

**经验沉淀**
- 压测环节增加内存泄漏检测（持续运行24小时以上）
- 生产环境配置内存使用率告警（>80%触发）

---

### 2.2 数据库/中间件连接池耗尽引发接口超时

**故障现象**
- 接口响应时间突然升高，大量请求超时
- 应用日志出现`connection pool exhausted`或`timeout waiting for connection`
- 数据库连接数监控达到上限

**排查路径**
```bash
# 1. 查看应用连接池状态（如果有actuator端点）
curl http://<pod-ip>:8080/actuator/metrics/jdbc.connections.active

# 2. 查看数据库连接数
# MySQL
mysql -e "SHOW PROCESSLIST;" | wc -l

# 3. 分析线程dump，查看等待连接的线程
kubectl exec -it <pod-name> -- jstack 1 | grep -A10 "waiting for connection"
```

**根因分析**
- 连接池配置过小（如max_connections=10），无法应对流量高峰
- 连接泄漏：代码获取连接后未在finally块中释放
- 慢查询占用连接时间过长，导致连接池被占满

**修复方案**
- **短期**：临时调大连接池大小，重启Pod释放被占连接
- **长期**：
  - 设置合理的连接池大小（公式：连接数 = (核心数 * 2) + 有效磁盘数）
  - 添加连接泄漏检测（HikariCP的leakDetectionThreshold）
  - 优化慢查询，添加查询超时控制

**经验沉淀**
- 连接池配置纳入代码审查清单
- 生产环境监控连接池使用率（>80%告警）

---

### 2.3 配置热更新不生效，需重启容器才能加载新配置

**故障现象**
- 修改ConfigMap后，应用仍使用旧配置
- 手动重启Pod后配置生效
- 不符合云原生"配置热更新"期望

**排查路径**
```bash
# 1. 确认ConfigMap已更新
kubectl get configmap <cm-name> -o yaml

# 2. 查看Pod内配置文件是否同步
kubectl exec -it <pod-name> -- cat /etc/config/app.conf

# 3. 检查应用是否监听配置变更
# 查看应用日志是否有"config reload"相关输出
kubectl logs <pod-name> | grep -i config
```

**根因分析**
- 应用未实现配置热加载机制（如监听文件变更事件）
- 配置读取仅在启动时执行一次，后续不再刷新
- 使用了缓存配置对象，未提供刷新接口

**修复方案**
- **短期**：修改ConfigMap后滚动重启Deployment
- **长期**：
  - 引入配置中心（Apollo/Nacos）支持热更新
  - 或实现文件监听机制（使用fsnotify库）
  - 添加配置刷新API，供运维手动触发

**经验沉淀**
- 技术选型时评估配置热更新能力
- 文档明确标注哪些配置支持热更新，哪些需要重启

---

### 2.4 健康检查接口逻辑错误，返回200但实际服务异常

**故障现象**
- Pod状态为Running且Ready，但业务请求返回错误
- 健康检查接口始终返回200，无法反映真实服务状态
- 流量持续打入异常Pod，导致业务受损

**排查路径**
```bash
# 1. 检查健康检查端点实现
curl http://<pod-ip>:8080/actuator/health

# 2. 对比健康检查和业务接口状态
curl http://<pod-ip>:8080/actuator/health
curl http://<pod-ip>:8080/api/health  # 业务健康检查

# 3. 查看健康检查详细指标
curl http://<pod-ip>:8080/actuator/health | jq .
```

**根因分析**
- 健康检查仅检查应用是否启动，未检查依赖服务（数据库、缓存）
- 健康检查逻辑过于简单，仅返回固定字符串"OK"
- 依赖服务故障时，健康检查未降级处理

**修复方案**
- **立即**：修复健康检查逻辑，增加依赖服务检查
- **长期**：
  - 实现分层健康检查：/health（存活）、/ready（就绪）、/live（存活）
  - 依赖服务故障时，健康检查返回503，触发Pod摘除
  - 添加健康检查缓存，避免频繁检查依赖服务

**经验沉淀**
- 健康检查纳入代码审查必检项
- 混沌工程定期演练依赖故障场景

---

### 2.5 本地缓存数据与集群状态不同步

**故障现象**
- 多Pod实例间数据不一致
- 用户请求打到不同Pod返回不同结果
- 缓存更新后部分Pod仍使用旧数据

**排查路径**
```bash
# 1. 查看各Pod缓存状态
for pod in $(kubectl get pods -l app=myapp -o name); do
  kubectl exec $pod -- curl -s localhost:8080/cache/status
done

# 2. 检查缓存同步机制日志
kubectl logs -l app=myapp | grep -i cache
```

**根因分析**
- 使用本地缓存（如Caffeine、Guava Cache）存储共享数据
- 缓存更新仅发生在当前Pod，未同步到其他Pod
- 缺乏缓存失效广播机制

**修复方案**
- **短期**：降级为无缓存或缩短缓存过期时间
- **长期**：
  - 共享数据使用分布式缓存（Redis/Memcached）
  - 本地缓存仅存储Pod私有数据
  - 引入缓存同步机制（如Redis Pub/Sub通知失效）

**经验沉淀**
- 代码审查时区分本地缓存和分布式缓存使用场景
- 缓存使用文档化，明确数据一致性要求

---

### 2.6 代码未处理依赖服务异常，直接导致容器崩溃

**故障现象**
- 依赖服务（如Redis、MySQL）短暂故障后，应用Pod大量重启
- 应用日志显示panic或unhandled exception
- 缺乏降级能力，级联故障扩散

**排查路径**
```bash
# 1. 查看Pod重启原因
kubectl describe pod <pod-name> | grep -A10 "Events"

# 2. 查看应用崩溃日志
kubectl logs <pod-name> --previous

# 3. 分析堆栈跟踪
kubectl logs <pod-name> --previous | grep -A20 "Exception\|panic"
```

**根因分析**
- 代码未对依赖服务调用添加try-catch或错误处理
- 依赖服务超时未设置，导致线程阻塞累积
- 缺乏熔断降级机制，故障直接向上传播

**修复方案**
- **立即**：添加异常处理，避免未捕获异常导致进程退出
- **长期**：
  - 引入熔断器（Hystrix/Resilience4j/Sentinel）
  - 设置合理的超时和重试策略
  - 实现降级逻辑（如缓存兜底、默认值返回）

**经验沉淀**
- 依赖服务调用必须包装在熔断器内
- 混沌工程定期演练依赖故障场景

---

### 2.7 Go goroutine泄漏导致Pod CPU持续高位

**故障现象**
- Pod CPU使用率持续高位，接近limit
- 但业务QPS并未显著增长
- `kubectl top pod`显示CPU使用率高，内存正常

**排查路径**
```bash
# 1. 查看goroutine数量
kubectl exec -it <pod-name> -- curl -s localhost:8080/debug/pprof/goroutine | head

# 2. 获取goroutine profile
go tool pprof http://<pod-ip>:8080/debug/pprof/goroutine

# 3. 在pprof中查看goroutine堆栈
(pprof) top
(pprof) list <function-name>
```

**根因分析**
- goroutine创建后未正确退出（如channel阻塞、死循环）
- 每个请求创建新goroutine处理，但未限制并发数
- 后台任务（如定时任务）goroutine泄漏

**修复方案**
- **短期**：重启Pod释放goroutine
- **长期**：
  - 使用context控制goroutine生命周期
  - 添加goroutine数量监控和告警
  - 使用worker pool模式限制并发goroutine数

**经验沉淀**
- Go应用监控goroutine数量指标
- 代码审查关注goroutine创建和退出逻辑

---

### 2.8 优雅关闭未实现，Pod缩容时正在处理的请求直接中断

**故障现象**
- 滚动更新或缩容时，部分请求失败（connection reset）
- 用户感知到请求中断或超时
- 监控显示更新期间错误率上升

**排查路径**
```bash
# 1. 查看Pod终止过程
kubectl describe pod <pod-name> | grep -A5 "Terminating"

# 2. 检查应用是否处理SIGTERM
kubectl logs <pod-name> | grep -i "shutdown\|sigterm\|graceful"

# 3. 查看terminationGracePeriodSeconds设置
kubectl get pod <pod-name> -o yaml | grep terminationGracePeriodSeconds
```

**根因分析**
- 应用未监听SIGTERM信号，收到后直接退出
- 未实现优雅关闭逻辑（停止接收新请求、等待存量请求完成）
- terminationGracePeriodSeconds设置过短，存量请求未完成就被强制终止

**修复方案**
- **立即**：调大terminationGracePeriodSeconds争取时间
- **长期**：
  - 实现SIGTERM信号处理，执行优雅关闭
  - 关闭HTTP server前等待存量请求完成
  - 设置合理的terminationGracePeriodSeconds（30-60秒）

**代码示例（Go）**
```go
func main() {
    srv := &http.Server{Addr: ":8080", Handler: handler}
    
    go func() {
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatalf("listen: %s\n", err)
        }
    }()
    
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    log.Println("Shutting down server...")
    
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Fatal("Server forced to shutdown:", err)
    }
    log.Println("Server exiting")
}
```

**经验沉淀**
- 所有服务必须实现优雅关闭
- 滚动更新期间监控错误率，确保零中断

---

## 三、运维侧故障（11类）

### 3.1 节点CPU/内存资源争抢，Pod调度失败处于Pending状态

**故障现象**
- 新创建的Pod一直处于Pending状态
- `kubectl describe pod`显示`Insufficient cpu`或`Insufficient memory`
- 节点资源使用率接近100%

**排查路径**
```bash
# 1. 查看Pod调度事件
kubectl describe pod <pod-name> | grep -A10 "Events"

# 2. 查看节点资源使用情况
kubectl top nodes

# 3. 查看节点资源分配情况
kubectl describe node <node-name> | grep -A5 "Allocated resources"

# 4. 查看节点上运行的Pod资源占用
kubectl top pods --all-namespaces --sort-by=cpu | head -20
```

**根因分析**
- 节点资源被系统进程（kubelet、docker、监控agent）占用过多
- Pod资源limit设置过大，导致节点可容纳Pod数减少
- 缺乏资源配额管理，某个Namespace占用过多资源

**修复方案**
- **短期**：扩容节点或清理低优先级Pod
- **长期**：
  - 设置节点预留资源（kubelet --system-reserved）
  - 配置ResourceQuota限制Namespace资源使用
  - 启用Cluster Autoscaler自动扩缩容

**经验沉淀**
- 节点资源预留纳入集群规划标准
- 监控节点资源分配率（Allocated/Allocable）

---

### 3.2 网络插件bug导致跨节点容器通信中断

**故障现象**
- 同节点Pod通信正常，跨节点Pod通信失败
- 服务间调用出现间歇性超时
- 网络插件（Calico/Flannel/Cilium）Pod异常

**排查路径**
```bash
# 1. 检查网络插件Pod状态
kubectl get pods -n kube-system | grep -E "calico|flannel|cilium"

# 2. 测试跨节点连通性
# 在Node A的Pod中
kubectl exec -it <pod-a> -- ping <pod-b-ip>

# 3. 检查网络插件日志
kubectl logs -n kube-system <network-plugin-pod>

# 4. 检查节点路由表
kubectl exec -it <network-plugin-pod> -n kube-system -- ip route
```

**根因分析**
- 网络插件版本存在已知bug
- 节点间网络策略（NetworkPolicy）配置错误
- 底层网络（VPC/SDN）路由配置问题

**修复方案**
- **短期**：重启网络插件Pod或回滚版本
- **长期**：
  - 升级网络插件到稳定版本
  - 定期验证跨节点网络连通性
  - 配置网络监控（如Node Exporter网络指标）

**经验沉淀**
- 网络插件升级前在测试环境充分验证
- 建立网络连通性基线测试

---

### 3.3 存储卷挂载异常，PVC一直处于Pending状态

**故障现象**
- PVC创建后一直处于Pending状态
- Pod无法启动，事件显示`unbound immediate PersistentVolumeClaims`
- 有状态应用无法部署

**排查路径**
```bash
# 1. 查看PVC状态
kubectl get pvc

# 2. 查看PVC事件
kubectl describe pvc <pvc-name>

# 3. 查看StorageClass
kubectl get storageclass

# 4. 查看Provisioner日志（如NFS/CSI driver）
kubectl logs -n kube-system <csi-pod>
```

**根因分析**
- StorageClass配置错误或无可用StorageClass
- 底层存储（NFS/Ceph/云盘）容量不足
- CSI driver未正确部署或权限不足
- PVC请求的存储大小超过StorageClass限制

**修复方案**
- **短期**：手动创建PV绑定PVC，或调整PVC大小
- **长期**：
  - 检查并修复StorageClass配置
  - 扩容底层存储或清理无用数据
  - 配置PVC告警，提前发现存储容量问题

**经验沉淀**
- 存储容量纳入容量规划
- 定期清理无用PVC和PV

---

### 3.4 节点内核参数冲突，容器启动后立即退出

**故障现象**
- Pod启动后立即退出，状态为CrashLoopBackOff
- 日志无明确错误信息或显示权限相关错误
- 同一镜像在某些节点正常，某些节点异常

**排查路径**
```bash
# 1. 查看Pod事件
kubectl describe pod <pod-name>

# 2. 对比正常和异常节点的内核参数
kubectl exec -it <pod-on-normal-node> -- sysctl -a | grep <param>
kubectl exec -it <pod-on-abnormal-node> -- sysctl -a | grep <param>

# 3. 检查节点系统日志
journalctl -u kubelet | grep -i error
```

**根因分析**
- 节点内核参数不一致（如vm.max_map_count、fs.file-max）
- SELinux/AppArmor策略限制
- 节点系统版本差异导致行为不一致

**修复方案**
- **短期**：将Pod调度到正常节点，或手动调整节点内核参数
- **长期**：
  - 使用DaemonSet统一配置节点内核参数
  - 节点初始化脚本标准化
  - 节点镜像版本统一

**经验沉淀**
- 节点配置纳入基础设施即代码管理
- 新节点加入集群前进行配置基线检查

---

### 3.5 监控指标采集漏传，无法定位资源瓶颈

**故障现象**
- Grafana面板显示"No data"
- 告警规则无法触发，故障发现延迟
- Prometheus targets页面显示部分target为DOWN

**排查路径**
```bash
# 1. 检查Prometheus targets状态
kubectl port-forward svc/prometheus 9090:9090
curl localhost:9090/api/v1/targets | jq .

# 2. 检查ServiceMonitor/PodMonitor配置
kubectl get servicemonitor -A

# 3. 检查指标端点可访问性
kubectl exec -it <pod-name> -- curl -s localhost:8080/metrics

# 4. 检查Prometheus抓取日志
kubectl logs <prometheus-pod> | grep -i error
```

**根因分析**
- ServiceMonitor标签选择器配置错误，未匹配到目标Pod
- 指标端点未暴露或被防火墙阻挡
- Prometheus relabel配置错误，丢弃了关键指标
- 指标采集频率设置过高，导致采样丢失

**修复方案**
- **立即**：修复ServiceMonitor配置，重启Prometheus
- **长期**：
  - 建立指标采集基线检查流程
  - 配置Prometheus自身监控告警
  - 指标命名和标签规范化

**经验沉淀**
- 新服务上线时检查指标采集完整性
- 定期进行监控覆盖度审计

---

### 3.6 镜像仓库权限配置错误，私有镜像拉取失败

**故障现象**
- Pod状态为ImagePullBackOff
- 事件显示`Failed to pull image`或`unauthorized`
- 公有镜像可拉取，私有镜像失败

**排查路径**
```bash
# 1. 查看Pod事件
kubectl describe pod <pod-name> | grep -A5 "Failed to pull image"

# 2. 检查imagePullSecrets配置
kubectl get pod <pod-name> -o yaml | grep -A10 imagePullSecrets

# 3. 检查Secret内容
kubectl get secret <secret-name> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d

# 4. 手动测试镜像拉取
docker login <registry>
docker pull <image>
```

**根因分析**
- imagePullSecrets未配置或配置错误
- Secret中的仓库地址或凭据过期
- ServiceAccount未绑定imagePullSecrets
- 网络策略阻挡了仓库访问

**修复方案**
- **立即**：更新Secret凭据，或检查网络连通性
- **长期**：
  - 使用vault或外部密钥管理服务同步凭据
  - 配置镜像仓库访问监控
  - 定期轮换仓库凭据

**经验沉淀**
- 镜像仓库凭据纳入密钥管理流程
- 私有镜像拉取失败纳入告警

---

### 3.7 etcd集群健康度下降导致API Server响应变慢

**故障现象**
- kubectl命令执行缓慢或超时
- API Server日志显示`etcdserver: request timed out`
- 集群整体响应变慢，Pod调度延迟

**排查路径**
```bash
# 1. 检查etcd集群健康状态
kubectl exec -it <etcd-pod> -n kube-system -- etcdctl endpoint health

# 2. 检查etcd节点状态
kubectl exec -it <etcd-pod> -n kube-system -- etcdctl member list

# 3. 查看etcd日志
kubectl logs -n kube-system <etcd-pod>

# 4. 检查etcd磁盘性能
kubectl exec -it <etcd-pod> -n kube-system -- df -h
kubectl exec -it <etcd-pod> -n kube-system -- iostat -x 1
```

**根因分析**
- etcd磁盘I/O性能不足（etcd对磁盘延迟敏感）
- etcd数据量过大，defrag未执行
- etcd节点间网络延迟高
- etcd集群节点故障或脑裂

**修复方案**
- **紧急**：重启etcd Pod，或临时扩容etcd资源
- **长期**：
  - 使用SSD磁盘部署etcd
  - 定期执行etcd defrag和快照备份
  - 监控etcd磁盘延迟（wal_fsync_duration）
  - 配置etcd集群高可用（3节点或5节点）

**经验沉淀**
- etcd磁盘性能纳入集群规划核心指标
- 定期etcd健康检查和备份

---

### 3.8 集群证书过期，所有节点与API Server通信中断

**故障现象**
- kubectl命令无法执行，显示证书错误
- 节点状态变为NotReady
- kubelet日志显示证书验证失败

**排查路径**
```bash
# 1. 检查证书过期时间
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates

# 2. 查看kubelet证书状态
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -noout -dates

# 3. 检查证书管理器日志
kubectl logs -n kube-system <cert-manager-pod>
```

**根因分析**
- Kubernetes组件证书（1年有效期）未及时轮换
- kubeadm集群未配置自动证书轮换
- 系统时间错误导致证书验证失败

**修复方案**
- **紧急**：使用kubeadm alpha certs renew命令手动续期
- **长期**：
  - 配置kubeadm自动证书轮换
  - 部署cert-manager管理应用证书
  - 设置证书过期告警（提前30天）

**经验沉淀**
- 证书过期时间纳入监控
- 建立证书轮换SOP

---

### 3.9 CoreDNS解析延迟/失败，服务间调用间歇性超时

**故障现象**
- 服务间调用出现间歇性超时
- DNS解析时间变长或失败
- CoreDNS Pod CPU或内存使用率高

**排查路径**
```bash
# 1. 测试DNS解析
kubectl run -it --rm debug --image=busybox:1.28 --restart=Never -- nslookup kubernetes.default

# 2. 查看CoreDNS Pod状态
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 3. 查看CoreDNS日志
kubectl logs -n kube-system <coredns-pod>

# 4. 检查CoreDNS配置
kubectl get configmap coredns -n kube-system -o yaml
```

**根因分析**
- CoreDNS副本数不足，无法应对查询压力
- CoreDNS缓存配置不当
- 上游DNS服务器不稳定
- 节点conntrack表满，导致DNS包丢失

**修复方案**
- **短期**：扩容CoreDNS副本数
- **长期**：
  - 根据集群规模配置CoreDNS副本数（公式：副本数 = max(2, ceil(节点数/10))）
  - 启用CoreDNS缓存插件
  - 监控conntrack使用情况
  - 配置NodeLocal DNSCache

**经验沉淀**
- CoreDNS性能纳入集群容量规划
- 定期进行DNS压力测试

---

### 3.10 Ingress控制器配置热更新导致流量瞬间中断

**故障现象**
- 更新Ingress配置后，部分请求失败（502/503）
- 流量中断持续数秒
- Nginx/Traefik reload期间新连接被拒绝

**排查路径**
```bash
# 1. 查看Ingress控制器日志
kubectl logs -n ingress-nginx <ingress-controller-pod>

# 2. 检查Nginx配置重载时间
kubectl exec -it <ingress-controller-pod> -n ingress-nginx -- nginx -T | wc -l

# 3. 监控reload期间的连接数
kubectl exec -it <ingress-controller-pod> -n ingress-nginx -- curl localhost:10254/metrics | grep nginx_reload
```

**根因分析**
- Nginx reload采用fork-exec模式，新旧进程切换期间连接处理中断
- Ingress配置过多，reload耗时过长
- 缺乏优雅关闭配置，旧进程直接退出

**修复方案**
- **短期**：减少Ingress配置变更频率，使用批量更新
- **长期**：
  - 使用Nginx Plus或OpenResty的动态配置能力
  - 或切换到支持热更新的Ingress控制器（如Traefik 2.x）
  - 配置优雅关闭超时时间

**经验沉淀**
- Ingress配置变更纳入发布窗口管理
- 监控Ingress reload频率和耗时

---

### 3.11 大规模集群Service Endpoint同步延迟

**故障现象**
- 集群节点数超过50时，新就绪Pod未及时加入Endpoint
- 流量间歇性503，无明显配置错误日志
- Service后端Pod健康但无法接收流量

**排查路径**
```bash
# 1. 检查Endpoint状态
kubectl get endpoints <service-name>

# 2. 对比Pod IP和Endpoint列表
kubectl get pods -l app=<app-name> -o wide
kubectl get endpoints <service-name> -o yaml

# 3. 查看Endpoint Controller日志
kubectl logs -n kube-system <endpoint-controller-pod>

# 4. 检查EndpointSlice（K8S 1.21+）
kubectl get endpointslices -l kubernetes.io/service-name=<service-name>
```

**根因分析**
- Endpoint Controller在处理大规模Endpoint列表时出现延迟
- 默认`--endpoint-sync-period`（5秒）在高频变更场景下不足
- Endpoint列表过长，API Server响应变慢

**修复方案**
- **短期**：调大Endpoint Controller的`--endpoint-sync-period`
- **长期**：
  - 升级到K8S 1.21+，使用EndpointSlice替代Endpoint（性能更好）
  - 拆分大型Service，减少单个Service的Endpoint数量
  - 使用Headless Service直接访问Pod IP，绕过Endpoint

**经验沉淀**
- 集群规模超过50节点时，Service设计要考虑Endpoint规模
- 监控Endpoint同步延迟指标

---

## 四、开发运维共同处理故障（7类）

### 4.1 容器资源限制配置不合理，开发申请值与实际需求偏差大，运维未结合监控调整

**故障现象**
- Pod频繁OOM重启或CPU限流
- 资源利用率监控显示实际使用远低于limit
- 成本浪费或稳定性问题并存

**排查路径**
```bash
# 1. 查看Pod资源使用历史
kubectl top pod <pod-name> --containers

# 2. 查看资源限制配置
kubectl get pod <pod-name> -o yaml | grep -A10 resources

# 3. 分析Prometheus历史数据
# 查询CPU使用率
rate(container_cpu_usage_seconds_total{pod="<pod-name>"}[5m])

# 查询内存使用率
container_memory_working_set_bytes{pod="<pod-name>"}
```

**根因分析**
- 开发按峰值流量申请资源，但日常流量远低于峰值
- 运维未根据实际监控数据调整资源限制
- 缺乏资源使用基线，无法判断合理值

**修复方案**
- **协作流程**：
  1. 开发提供资源需求预估（基于压测数据）
  2. 运维配置初始资源限制
  3. 生产运行后根据监控数据调整
  4. 建立资源使用基线，定期review
- **工具支撑**：
  - 使用VPA（Vertical Pod Autoscaler）自动调整资源请求
  - 使用Goldilocks分析资源使用建议

**经验沉淀**
- 资源限制配置纳入发布检查清单
- 每月进行资源使用review，优化配置

---

### 4.2 镜像构建冗余依赖，镜像体积过大，开发打包未优化，运维未做镜像校验

**故障现象**
- 镜像拉取时间过长，Pod启动延迟
- 镜像仓库存储成本过高
- 镜像包含不必要的依赖，安全风险增加

**排查路径**
```bash
# 1. 查看镜像大小
docker images | grep <image-name>

# 2. 分析镜像层
docker history <image-name>

# 3. 使用dive工具分析镜像
dive <image-name>

# 4. 检查镜像内容
docker run --rm -it <image-name> sh
```

**根因分析**
- Dockerfile包含不必要的构建依赖（如编译工具、缓存文件）
- 未使用多阶段构建，构建产物和源码混在一起
- 基础镜像选择不当（如使用完整版而非alpine/slim版）
- 运维未建立镜像大小基线和检查机制

**修复方案**
- **开发侧**：
  - 使用多阶段构建，只复制必要产物
  - 清理构建缓存（`rm -rf /var/cache/apt/*`）
  - 选择轻量级基础镜像
- **运维侧**：
  - 建立镜像大小基线（如<500MB）
  - CI流程集成镜像扫描（Trivy/Snyk）
  - 定期清理旧镜像

**经验沉淀**
- 镜像大小纳入CI检查
- 建立镜像构建最佳实践文档

---

### 4.3 存活探针参数不匹配，开发定义检测接口，运维配置超时时间过短导致误重启

**故障现象**
- Pod频繁重启，但业务实际正常
- 监控显示重启次数高，但业务指标无异常
- 探针配置调整后重启停止

**排查路径**
```bash
# 1. 查看Pod重启事件
kubectl describe pod <pod-name> | grep -A5 "Events"

# 2. 查看探针配置
kubectl get pod <pod-name> -o yaml | grep -A20 livenessProbe

# 3. 手动测试探针接口
curl -w "@curl-format.txt" -o /dev/null -s http://<pod-ip>:8080/health

# 4. 对比探针超时和接口实际响应时间
```

**根因分析**
- 开发未提供探针接口的SLA（预期响应时间）
- 运维配置的`timeoutSeconds`小于接口实际响应时间
- `failureThreshold`设置过小，偶发超时即触发重启
- 探针接口未优化，执行耗时操作（如数据库查询）

**修复方案**
- **协作流程**：
  1. 开发文档化探针接口的SLA
  2. 运维根据SLA配置探针参数
  3. 探针接口应轻量，避免耗时操作
- **参数建议**：
  - `timeoutSeconds` >= 接口P99响应时间
  - `periodSeconds` * `failureThreshold` >= 30秒（避免误杀）

**经验沉淀**
- 探针配置纳入发布检查清单
- 监控探针失败率，及时发现配置问题

---

### 4.4 服务端口绑定冲突，开发设置端口与运维主机端口预留规则冲突

**故障现象**
- Pod启动失败，显示端口已被占用
- HostNetwork模式下端口冲突
- NodePort Service端口与节点服务冲突

**排查路径**
```bash
# 1. 查看Pod事件
kubectl describe pod <pod-name> | grep -i port

# 2. 检查节点端口占用
netstat -tlnp | grep <port>

# 3. 检查NodePort范围
kubectl get svc <service-name> -o yaml | grep nodePort

# 4. 检查kube-apiserver配置的NodePort范围
grep service-node-port-range /etc/kubernetes/manifests/kube-apiserver.yaml
```

**根因分析**
- 开发使用HostNetwork模式，端口与节点系统服务冲突
- NodePort Service端口与运维预留端口（如22、53）冲突
- 缺乏端口分配规范，各部门随意使用

**修复方案**
- **协作流程**：
  1. 建立端口分配规范文档
  2. HostNetwork模式需提前申请端口
  3. NodePort范围避开系统预留端口
- **技术方案**：
  - 优先使用ClusterIP + Ingress，避免NodePort
  - 使用LoadBalancer Service替代NodePort

**经验沉淀**
- 端口分配纳入变更管理流程
- 建立端口使用台账

---

### 4.5 配置中心参数格式错误，开发提交配置与运维环境变量解析规则不兼容

**故障现象**
- 应用启动失败，显示配置解析错误
- 配置值被截断或格式错乱
- 环境变量注入后值与预期不符

**排查路径**
```bash
# 1. 查看Pod环境变量
kubectl exec -it <pod-name> -- env | grep <config-name>

# 2. 查看ConfigMap内容
kubectl get configmap <cm-name> -o yaml

# 3. 对比配置值在ConfigMap和容器内的差异
kubectl exec -it <pod-name> -- cat /etc/config/<file>

# 4. 检查应用配置解析日志
kubectl logs <pod-name> | grep -i config
```

**根因分析**
- 配置值包含特殊字符（如换行、引号），未正确转义
- 开发使用YAML多行字符串（`|`或`>`），运维解析逻辑不兼容
- 环境变量名大小写敏感问题
- 配置值长度超过环境变量限制

**修复方案**
- **协作流程**：
  1. 建立配置格式规范文档
  2. 配置提交前进行格式校验
  3. 敏感配置使用Secret而非ConfigMap
- **技术方案**：
  - 使用配置模板引擎（如Helm values）
  - CI流程集成配置格式检查

**经验沉淀**
- 配置变更纳入代码审查
- 建立配置格式检查工具

---

### 4.6 Helm Chart版本管理混乱，回滚时配置丢失

**故障现象**
- Helm升级后应用异常，回滚后问题仍存在
- 回滚后配置与预期不符，部分配置丢失
- 多环境（dev/test/prod）配置差异大，难以同步

**排查路径**
```bash
# 1. 查看Helm发布历史
helm history <release-name>

# 2. 对比不同版本的values
helm get values <release-name> --revision <rev>

# 3. 查看实际部署的manifest
helm get manifest <release-name>

# 4. 检查ConfigMap/Secret是否被覆盖
kubectl get configmap -l app.kubernetes.io/managed-by=Helm
```

**根因分析**
- Helm upgrade时未使用`-f values.yaml`，导致默认配置覆盖自定义配置
- 回滚时只回滚了镜像版本，未回滚配置
- 多环境values文件管理混乱，未使用git版本控制

**修复方案**
- **协作流程**：
  1. 所有配置变更通过values文件管理
  2. values文件纳入git版本控制
  3. 升级前备份当前values
- **技术方案**：
  - 使用helm-diff插件预览变更
  - 使用Helmfile管理多环境配置
  - 配置CI流程自动检查配置差异

**经验沉淀**
- Helm操作纳入变更管理流程
- 定期进行配置基线检查

---

### 4.7 多环境ConfigMap/Secret差异未收敛，生产环境引用了测试配置

**故障现象**
- 生产环境出现测试数据或测试配置
- 数据库连接串指向测试环境
- 功能开关状态与环境不匹配

**排查路径**
```bash
# 1. 对比多环境ConfigMap
kubectl get configmap <cm-name> -n prod -o yaml > prod.yaml
kubectl get configmap <cm-name> -n test -o yaml > test.yaml
diff prod.yaml test.yaml

# 2. 检查环境标识
kubectl get pods -n prod -o yaml | grep -i env

# 3. 检查配置引用关系
kubectl get pods -n prod -o yaml | grep -A5 configMapKeyRef
```

**根因分析**
- 多环境配置未使用统一模板，手动维护导致差异
- 配置复制时未修改环境相关参数
- 缺乏配置差异检测机制
- 环境标识（如namespace、label）使用不规范

**修复方案**
- **协作流程**：
  1. 使用Kustomize或Helm管理多环境配置
  2. 建立环境标识规范（如namespace命名规则）
  3. 配置变更前进行差异对比
- **技术方案**：
  - CI流程集成配置差异检测
  - 使用OPA/Gatekeeper阻止跨环境配置引用
  - 配置环境隔离策略

**经验沉淀**
- 多环境配置纳入基础设施即代码管理
- 定期进行配置一致性检查

---

## 五、面试案例完整模板

### 5.1 案例回答结构（STAR-R法）

```
Situation（背景）
├── 系统架构：[描述你运维的系统架构，如微服务数、节点数、核心组件]
├── 业务规模：[日活用户数、QPS、数据量等量化指标]
└── 故障影响：[故障范围、受影响用户数、业务损失]

Task（任务）
├── 你的角色：[SRE工程师/K8S平台工程师/运维负责人]
└── 核心目标：[恢复服务 / 定位根因 / 建立预防机制]

Action（行动）
├── 排查步骤：[从现象到根因的排查链路，用具体命令说明]
├── 关键决策：[应急方案的选择理由、权衡考虑]
└── 协作过程：[与开发/运维/业务的沟通方式]

Result（结果）
├── 故障恢复：[恢复时间、恢复方式]
├── 业务影响：[量化指标的变化，如订单成功率从xx%恢复到xx%]
└── 数据指标：[具体数字，体现你的贡献]

Reflection（反思）
├── 根本原因：[技术根因 + 流程根因]
├── 改进措施：[短期止血 + 长期预防，分条列出]
└── 经验沉淀：[形成的规范/SOP/自动化工具]
```

### 5.2 开发侧经典案例：应用内存泄漏导致Pod OOM重启

**Situation**
- 系统架构：微服务架构，Java Spring Boot应用，部署在K8S集群
- 业务规模：日活用户50万，核心交易服务
- 故障影响：交易服务Pod每2-3天重启一次，用户下单失败

**Task**
- 我的角色：SRE工程师，负责故障排查和恢复
- 核心目标：定位内存泄漏根因，彻底修复问题

**Action**
1. **现象确认**：通过`kubectl describe pod`确认OOMKilled事件，监控显示内存持续增长
2. **初步排查**：进入容器执行`jmap -histo`，发现某业务对象实例数异常增长
3. **深入分析**：生成堆转储文件，使用MAT工具分析，定位到订单缓存未设置过期策略
4. **协作修复**：与开发团队确认，该缓存用于订单状态查询，但业务迭代后未添加TTL
5. **临时止血**：调大Pod内存limit，争取修复时间

**Result**
- 故障恢复：开发修复代码，添加缓存TTL后，内存使用稳定
- 业务影响：故障期间订单成功率从99.9%下降到97%，修复后恢复
- 数据指标：Pod内存使用从4GB稳定在1.5GB，不再重启

**Reflection**
- 根本原因：业务迭代引入缓存，但未考虑过期策略，属于设计缺陷
- 改进措施：
  - 压测环节增加内存泄漏检测（24小时持续运行）
  - 代码审查增加缓存使用检查点
  - 生产环境配置内存使用率告警
- 经验沉淀：缓存必须设置过期策略，这是生产环境铁律

---

### 5.3 运维侧经典案例：大规模集群Service Endpoint同步延迟

**Situation**
- 系统架构：K8S集群50+节点，微服务200+，使用Service做服务发现
- 业务规模：日调用量10亿次，P99延迟要求<100ms
- 故障影响：发布新版本时，流量间歇性503，持续10-30秒

**Task**
- 我的角色：K8S平台工程师
- 核心目标：定位503根因，消除发布期间的流量异常

**Action**
1. **现象确认**：发布期间监控显示503错误率上升，但Pod状态正常
2. **初步排查**：检查Service Endpoint，发现新Pod Ready后未立即加入Endpoint列表
3. **深入分析**：
   - 查看Endpoint Controller日志，发现relist操作耗时增加
   - 分析发现集群规模（50+节点）导致Endpoint列表过长
   - 默认`--endpoint-sync-period`（5秒）在高频变更场景下不足
4. **根因定位**：Endpoint Controller同步延迟，新Pod Ready后需等待下一次同步才能接收流量
5. **修复实施**：
   - 短期：调大Endpoint Controller的`--endpoint-sync-period`到10秒
   - 长期：升级到K8S 1.21+，启用EndpointSlice替代Endpoint

**Result**
- 故障恢复：调整后发布期间503错误消失
- 业务影响：发布期间的P99延迟从200ms恢复到80ms
- 数据指标：Endpoint同步延迟从5-10秒降低到1-2秒

**Reflection**
- 根本原因：集群规模增长后，默认的Endpoint同步机制性能不足，属于K8S机制性问题
- 改进措施：
  - 集群规模超过50节点时，评估Endpoint性能
  - 升级到EndpointSlice，提升性能
  - 发布流程增加灰度观察期，确保Endpoint同步完成后再全量引流
- 经验沉淀：集群规模增长时，需要重新评估核心组件的性能瓶颈

---

### 5.4 共同处理经典案例：资源限制配置与突发流量不匹配

**Situation**
- 系统架构：电商大促系统，Java微服务，K8S部署
- 业务规模：日常QPS 1000，大促峰值QPS 10000
- 故障影响：大促开始10分钟后，核心服务Pod频繁重启，订单成功率下降

**Task**
- 我的角色：SRE工程师，协调开发和运维团队
- 核心目标：快速恢复服务，并建立大促资源保障机制

**Action**
1. **现象确认**：监控显示Pod CPU使用率达到limit（2核），触发限流，随后OOM重启
2. **初步排查**：
   - 检查资源限制：开发按日常峰值（QPS 1000）申请了2核CPU、4GB内存
   - 检查实际流量：大促峰值QPS 10000，是日常的10倍
3. **协作分析**：
   - 开发：按日常峰值申请资源，未考虑大促场景
   - 运维：按常规阈值设置limit，未对齐大促需求
4. **紧急处理**：
   - 临时调大资源limit（CPU 4核，内存8GB）
   - 启用HPA自动扩容
5. **长期改进**：
   - 建立大促资源评估流程
   - 开发提供各场景资源需求文档
   - 运维根据场景配置资源限制

**Result**
- 故障恢复：资源调整后服务稳定，订单成功率恢复到99.5%
- 业务影响：大促前30分钟订单成功率下降到85%，调整后恢复
- 数据指标：大促期间Pod CPU使用率稳定在70%，无重启

**Reflection**
- 根本原因：资源限制配置缺乏场景化考虑，开发和运维对大促需求的理解不一致
- 改进措施：
  - 建立资源需求评审机制，开发提供场景化资源需求
  - 运维根据场景配置资源限制，而非固定阈值
  - 大促前进行全链路压测，验证资源配置
  - 建立容量规划流程，定期review资源使用
- 经验沉淀：资源限制不是一次性的配置，需要随着业务场景持续优化

---

## 六、面试高频问题与回答要点

### 6.1 如何排查Pod一直处于Pending状态？

**回答要点**
1. `kubectl describe pod`查看Events，定位具体原因
2. 常见原因及排查：
   - `Insufficient cpu/memory`：节点资源不足，扩容或清理
   - `PersistentVolumeClaim not bound`：PVC未绑定，检查StorageClass
   - `no nodes available to schedule pods`：节点选择器或亲和性配置错误
   - `Failed to pull image`：镜像拉取失败，检查镜像名和权限
3. 使用`kubectl get events --field-selector reason=FailedScheduling`查看调度事件

### 6.2 如何排查Pod频繁重启？

**回答要点**
1. `kubectl describe pod`查看Last State和Restart Count
2. 常见原因：
   - OOMKilled：内存不足，调大limit或排查内存泄漏
   - Error/Exit Code非0：应用崩溃，查看日志定位
   - Liveness探针失败：检查探针配置和应用健康状态
3. `kubectl logs --previous`查看上一次运行的日志
4. 使用`kubectl debug`启动调试容器深入排查

### 6.3 如何排查服务间调用超时？

**回答要点**
1. 分层排查：
   - DNS层：`nslookup`检查服务名解析
   - 网络层：`ping`/`telnet`检查连通性
   - 应用层：检查应用日志和指标
2. 常见原因：
   - CoreDNS解析延迟
   - 网络策略（NetworkPolicy）阻挡
   - 服务端资源不足，处理缓慢
   - 客户端超时设置过短
3. 使用`kubectl exec`进入客户端Pod，手动测试服务端点

### 6.4 如何排查Ingress访问异常？

**回答要点**
1. 分层排查：
   - 客户端到Ingress：检查域名解析、证书
   - Ingress到Service：检查Ingress配置、Backend状态
   - Service到Pod：检查Endpoint、Pod状态
2. 查看Ingress控制器日志：`kubectl logs -n ingress-nginx <pod>`
3. 使用`kubectl ingress-nginx`插件检查配置
4. 常见原因：
   - Ingress规则配置错误
   - Service名称或端口不匹配
   - 后端Pod未就绪
   - 证书过期或配置错误

### 6.5 如何设计高可用的K8S集群？

**回答要点**
1. **控制平面高可用**：
   - API Server：多实例+负载均衡
   - etcd：3节点或5节点集群
   - Controller Manager/Scheduler：主备模式
2. **工作节点高可用**：
   - 多可用区部署
   - 配置Pod反亲和性，避免单点故障
   - 启用Cluster Autoscaler自动扩缩容
3. **网络高可用**：
   - 多副本CoreDNS
   - 配置NodeLocal DNSCache
   - 网络插件多副本部署
4. **存储高可用**：
   - 使用分布式存储（Ceph/Rook）
   - 配置存储多副本
5. **备份与恢复**：
   - 定期etcd备份
   - 资源配置GitOps管理

---

## 七、故障排查工具箱

### 7.1 必备命令速查

```bash
# Pod状态诊断
kubectl get pod <pod> -o yaml                    # 查看完整配置
kubectl describe pod <pod>                       # 查看事件和状态
kubectl logs <pod> --previous                    # 查看上次运行日志
kubectl logs <pod> -c <container>                # 查看指定容器日志
kubectl exec -it <pod> -- /bin/sh                # 进入容器

# 资源使用
kubectl top node                                 # 节点资源使用
kubectl top pod --all-namespaces                 # Pod资源使用
kubectl describe node <node>                     # 节点详细信息

# 网络诊断
kubectl get svc,endpoints                        # 查看服务和端点
kubectl run -it --rm debug --image=busybox --restart=Never -- /bin/sh  # 启动调试Pod
kubectl port-forward svc/<svc> 8080:80           # 端口转发

# 存储诊断
kubectl get pvc,pv                               # 查看存储卷
kubectl describe pvc <pvc>                       # 查看PVC事件

# 配置诊断
kubectl get configmap,secret                     # 查看配置
kubectl get events --sort-by=.lastTimestamp      # 查看事件
```

### 7.2 推荐工具

| 工具 | 用途 | 安装 |
|------|------|------|
| stern | 多Pod日志聚合 | `brew install stern` |
| k9s | 交互式K8S管理 | `brew install k9s` |
| kube-ps1 | 命令行显示当前context | `brew install kube-ps1` |
| kubectx/kubens | 快速切换context/namespace | `brew install kubectx` |
| dive | 镜像分析 | `brew install dive` |
| kubespy | 实时观察K8S资源变化 | `brew install kubespy` |

### 7.3 本课程诊断脚本库

课程提供完整的故障排查脚本体系，位于 `troubleshoot-scripts/`：

```bash
cd troubleshoot-scripts
bash run-all.sh                         # 一键运行全部诊断
bash run-all.sh --module k8s            # K8S诊断 (对应模块29)
bash run-all.sh --module middleware     # 中间件诊断 (对应模块30)
bash run-all.sh --module os             # Linux系统诊断 (对应模块31)
bash run-all.sh --module network        # 网络诊断 (对应模块32)
bash run-all.sh --module kernel         # 内核诊断 (对应模块33)
```

---

## 八、总结

### 故障处理黄金法则

1. **先恢复，后排查**：业务优先，先止血再根因分析
2. **分层定位**：从现象到根因，逐层深入
3. **日志为王**：保留现场，收集完整日志
4. **协作透明**：开发运维信息共享，避免各自为战
5. **复盘沉淀**：每次故障都是改进机会，形成SOP

### 面试回答技巧

1. **结构化表达**：使用STAR-R法，逻辑清晰
2. **数据支撑**：用具体数字说明影响（如"订单成功率从99.9%下降到97%"）
3. **体现协作**：强调跨团队沟通和协作能力
4. **反思深度**：不仅说"怎么修"，更要说"为什么发生"和"如何预防"
5. **技术细节**：适当展示具体命令和配置，体现实操能力

### 学习路径建议

| 步骤 | 内容 | 关联模块 |
|------|------|----------|
| 1 | 掌握K8S分层诊断模型 | 模块29 |
| 2 | 熟悉中间件五件套诊断 | 模块30 |
| 3 | 理解Linux系统故障机制 | 模块31 |
| 4 | 深挖网络协议原理 | 模块32 |
| 5 | 吃透内核调度与内存 | 模块33 |
| 6 | 融会贯通架构设计 | 模块34 |
| 7 | 用STAR-R法练习表达 | 本文档第五、六章 |

---

*本文档持续更新，建议结合实际工作经验补充更多案例。*
