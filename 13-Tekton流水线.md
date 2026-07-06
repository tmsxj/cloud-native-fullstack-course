# 模块13：Tekton流水线

---

## 1. 概述与架构图

### 1.1 CI/CD 完整链路

```
+================================================================+
|                    CI/CD 完整链路 (Tekton + ArgoCD)              |
+================================================================+
|                                                                 |
|  开发者         CI (Tekton)              CD (ArgoCD)    K8s     |
|                                                                 |
|  git push      +----------+            +----------+   +------+  |
| --------->     | Git Clone|            |  Watch   |   | App  |  |
|                +----+-----+            |  Git     |   | Sync |  |
|                     |                  +----+-----+   +--+---+  |
|                +----+-----+               |             |       |
|                | Unit     |               |             |       |
|                | Test     |               |             |       |
|                +----+-----+               |             |       |
|                     |                  +----+-----+       |       |
|                +----+-----+            |  Auto    |       |       |
|                | Build    |            |  Sync    |------>|       |
|                | Image    |            +----------+       |       |
|                +----+-----+                               |       |
|                     |                                     |       |
|                +----+-----+                               |       |
|                | Push to  |                               |       |
|                | Harbor   |                               |       |
|                +----+-----+                               |       |
|                     |                                     |       |
|                +----+-----+                               |       |
|                | Update   |  git commit                   |       |
|                | Helm     |--------------> Git Repo       |       |
|                | values   |                               |       |
|                +----------+                               |       |
+================================================================+
```

### 1.2 Tekton 架构

```
+================================================================+
|                    Tekton 架构                                  |
+================================================================+
|                                                                 |
|  +------------------+                                           |
|  | Tekton Triggers  |  <-- 接收 Git Webhook 事件               |
|  | (EventListener)  |                                           |
|  +--------+---------+                                           |
|           |                                                      |
|           | 触发 TriggerBinding + TriggerTemplate               |
|           v                                                      |
|  +--------+---------+                                           |
|  | PipelineRun       |  <-- 创建 PipelineRun 实例               |
|  +--------+---------+                                           |
|           |                                                      |
|           v                                                      |
|  +--------+---------+                                           |
|  | Pipeline          |  <-- 定义任务编排顺序                     |
|  | +------+ +------+|                                           |
|  | |Task 1| |Task 2||                                           |
|  | |Clone | |Test  ||                                           |
|  | +------+ +------+|                                           |
|  | +------+ +------+|                                           |
|  | |Task 3| |Task 4||                                           |
|  | |Build | |Push  ||                                           |
|  | +------+ +------+|                                           |
|  | +------+         |                                           |
|  | |Task 5|         |                                           |
|  | |Update|         |                                           |
|  | +------+         |                                           |
|  +------------------+                                           |
|           |                                                      |
|           v                                                      |
|  +--------+---------+                                           |
|  | TaskRun           |  <-- 执行具体的 Task（Pod）               |
|  | (每个 Task 一个 Pod)|                                        |
|  +------------------+                                           |
+================================================================+
```

### 1.3 Workspace（工作空间） 类型

```
+================================================================+
|                    Tekton Workspace 类型                        |
+================================================================+
|                                                                 |
|  +------------------+  +------------------+  +------------------+|
|  | emptyDir         |  | configMap        |  | secret           ||
|  | 临时目录          |  | 配置文件          |  | 敏感信息          ||
|  | (Task 间共享)     |  | (只读)           |  | (只读)           ||
|  +------------------+  +------------------+  +------------------+|
|                                                                 |
|  +------------------+  +------------------+  +------------------+|
|  | pvc              |  | volumeClaimTemplate| | persistentVolume ||
|  | 持久化存储        |  | 动态创建 PVC      |  | Claim (PVC)      ||
|  | (跨 TaskRun)     |  |                  |  |                  ||
|  +------------------+  +------------------+  +------------------+|
+================================================================+
```

---

## 2. 理论基础

### 2.1 Tekton 核心概念

| 概念 | 说明 |
|------|------|
| Task | 最小执行单元，定义一组步骤（Steps），每个 Step 是一个容器 |
| Pipeline（流水线） | 任务编排，定义多个 Task 的执行顺序和依赖关系 |
| TaskRun | Task 的执行实例，创建一个 Pod 执行 Task |
| PipelineRun | Pipeline 的执行实例，创建多个 TaskRun |
| Workspace | Task 间共享数据的空间（源码、构建产物等） |
| PipelineResource | 已废弃（v1 中移除），被 Workspace 和 Workspaces 替代 |
| Trigger | 事件驱动，接收外部事件（Git Webhook（回调钩子））并创建 PipelineRun（流水线执行实例） |
| TriggerBinding（触发参数绑定） | 从事件中提取参数（如 commit SHA、分支名） |
| TriggerTemplate（触发模板） | 定义 PipelineRun 的模板，使用 Binding 提取的参数 |
| EventListener（事件监听器） | 接收 HTTP 事件的服务（Service + Pod） |
| Condition | 条件判断，控制 Task 是否执行 |

### 2.2 Tekton vs Jenkins vs GitLab CI

| 特性 | Tekton | Jenkins | GitLab CI |
|------|--------|---------|-----------|
| 运行环境 | K8s 原生（Pod） | 独立服务器/Agent | K8s Runner |
| 定义方式 | YAML CRD（自定义资源定义） | Groovy/Jenkinsfile | .gitlab-ci.yml |
| 扩展性 | Task Catalog + Catalog | 插件生态 | 内置 |
| 多集群 | 原生支持 | 需配置 | 需配置 |
| 缓存 | PVC/Workspace | Workspace | Cache |
| 并发 | 原生 K8s 调度 | Executor 插件 | Runner 并发 |
| UI | Dashboard（基础） | 功能丰富 | 功能丰富 |
| 学习曲线 | 中等 | 高 | 低 |
| CNCF（云原生计算基金会） | 毕业项目 | - | - |
| 与 ArgoCD 集成 | 天然互补 | 需配置 | 需配置 |

### 2.3 CI/CD 流水线设计原则

| 原则 | 说明 |
|------|------|
| 快速反馈 | 单元测试阶段应快速完成（< 5 分钟），尽早发现问题 |
| 幂等性 | Pipeline 可以安全地重复执行，不会产生副作用 |
| 并行化 | 独立的 Task 并行执行，缩短总耗时 |
| 缓存复用 | Maven/Gradle 依赖、Docker Layer 缓存，避免重复下载 |
| 失败快速 | 任何步骤失败立即终止，不浪费后续资源 |
| 安全隔离 | CI 使用专用 ServiceAccount（服务账户），限制权限 |
| 可观测 | 每个步骤的日志、耗时、状态可追踪 |

---

## 3. 部署实战

### 3.1 离线安装 Tekton

> **前置条件：** 已完成 [第10节 离线前置准备](#10-离线前置准备) 中的镜像预推送和YAML文件准备。

```bash
# ========== 步骤1：在有外网的服务器上下载 Tekton YAML ==========
# 下载 Tekton Operator
curl -sL https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml -o tekton-operator.yaml

# 下载 Tekton Dashboard
curl -sL https://storage.googleapis.com/tekton-releases/dashboard/latest/latest-release.yaml -o tekton-dashboard.yaml

# ========== 步骤2：修改 YAML 中的镜像地址，指向 Harbor ==========
# 将所有 gcr.io/tekton-releases/* 镜像替换为 Harbor 地址
# 使用 sed 批量替换（在有外网的服务器上执行）：
sed -i 's|gcr.io/tekton-releases|192.168.1.61/tekton-releases|g' tekton-operator.yaml
sed -i 's|gcr.io/tekton-releases|192.168.1.61/tekton-releases|g' tekton-dashboard.yaml
# 如果 YAML 中有 ghcr.io 或其他镜像源，也需替换
sed -i 's|ghcr.io/tektoncd|192.168.1.61/tektoncd|g' tekton-operator.yaml
sed -i 's|ghcr.io/tektoncd|192.168.1.61/tektoncd|g' tekton-dashboard.yaml
# 替换 quay.io 镜像
sed -i 's|quay.io/|192.168.1.61/quay/|g' tekton-operator.yaml
sed -i 's|quay.io/|192.168.1.61/quay/|g' tekton-dashboard.yaml
# 替换 registry.k8s.io 镜像
sed -i 's|registry.k8s.io/|192.168.1.61/k8s/|g' tekton-operator.yaml
sed -i 's|registry.k8s.io/|192.168.1.61/k8s/|g' tekton-dashboard.yaml

# ========== 步骤3：镜像预推送到 Harbor ==========
# 提取 YAML 中所有镜像地址并逐一拉取、打标签、推送
# 示例（在有外网的服务器上执行）：
# docker pull gcr.io/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.0
# docker tag gcr.io/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.0 192.168.1.61/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.0
# docker push 192.168.1.61/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.0
# 完整镜像清单见第10节

# ========== 步骤4：传输 YAML 到 Master 节点 ==========
# scp tekton-operator.yaml tekton-dashboard.yaml root@192.168.1.54:/root/

# ========== 步骤5：在 Master 节点离线安装 ==========
# 安装 Tekton Operator
kubectl apply -f /root/tekton-operator.yaml

# 验证 Operator
kubectl get pods -n tekton-operator-system
# 预期：tekton-operator-xxx Running

# 创建 TektonConfig（启用所有组件，含资源优化配置）
cat <<'EOF' | kubectl apply -f -
apiVersion: operator.tekton.dev/v1alpha1  # Tekton API 版本
kind: TektonConfig  # Tekton 全局配置
metadata:
  name: config
spec:
  profile: all  # 安装所有组件
  targetNamespace: tekton-pipelines  # 目标命名空间
  addon:
    params:
    - name: clusterTask
      value: "true"
  pipeline:
    await-sidecar-readiness: true
    disable-affinity-assistant: true  # 禁用亲和性助手
    keep-pod-on-cancel: false
    metrics.taskrun.duration-type: histogram
    options:
      disabled: false
    # 资源优化：降低 Controller 和 Webhook 的资源需求（适配 2C4G Master）
    controller-resources:
      requests:
        cpu: 100m  # CPU 100m
        memory: 200Mi  # 内存 200Mi
      limits:
        cpu: 500m  # CPU 500m
        memory: 512Mi  # 内存 512Mi
    webhook-resources:
      requests:
        cpu: 50m  # CPU 50m
        memory: 100Mi  # 内存 100Mi
      limits:
        cpu: 200m  # CPU 200m
        memory: 256Mi  # 内存 256Mi
  trigger:
    enable-api-fields: beta  # 启用 Beta API 字段
  dashboard:
    readonly: false
EOF

# 验证安装
kubectl get pods -n tekton-pipelines
# 预期：tekton-pipelines-controller-xxx, tekton-pipelines-webhook-xxx Running

# ========== 步骤6：离线安装 Tekton CLI (tkn) ==========
# 在有外网的服务器上下载：
# curl -sL https://github.com/tektoncd/cli/releases/download/v0.37.0/tkn_0.37.0_Linux_x86_64.tar.gz -o tkn.tar.gz
# 传输到 Master 节点后安装：
# tar xzf tkn.tar.gz -C /usr/local/bin tkn
# tkn version

# ========== 步骤7：离线安装 Tekton Dashboard ==========
kubectl apply -f /root/tekton-dashboard.yaml

# 暴露 Dashboard
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc tekton-dashboard -n tekton-pipelines -p '{"spec":{"ports":[{"port":9097,"targetPort":9097,"nodePort":32097}]}}'

# 访问 Dashboard：http://<任意Worker节点IP>:32097
```

### 3.2 创建 CI Pipeline

```bash
# 创建 Pipeline Workspace PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: PersistentVolumeClaim  # PVC 持久卷声明
metadata:
  name: ci-workspace
  namespace: tekton-pipelines
spec:
  accessModes:
  - ReadWriteOnce  # 单节点读写
  storageClassName: local-path  # 存储类名称
  resources:
    requests:
      storage: 10Gi
---
# Maven 缓存 PVC
apiVersion: v1  # API 版本
kind: PersistentVolumeClaim  # PVC 持久卷声明
metadata:
  name: maven-cache
  namespace: tekton-pipelines
spec:
  accessModes:
  - ReadWriteOnce  # 单节点读写
  storageClassName: local-path  # 存储类名称
  resources:
    requests:
      storage: 20Gi
---
# Kaniko 构建缓存 PVC（用于 Kaniko --cache 模式，可选）
apiVersion: v1  # API 版本
kind: PersistentVolumeClaim  # PVC 持久卷声明
metadata:
  name: kaniko-cache
  namespace: tekton-pipelines
spec:
  accessModes:
  - ReadWriteOnce  # 单节点读写
  storageClassName: local-path  # 存储类名称
  resources:
    requests:
      storage: 20Gi
EOF
```

#### 3.2.1 Maven/Gradle 依赖缓存优化

```yaml
# 增强版 Maven Task，支持多层级缓存
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: maven-build-cached
  namespace: tekton-pipelines
spec:
  description: Maven build with optimized caching strategy
  params:
  - name: context-dir
    type: string
    default: "."
  - name: maven-args
    type: string
    default: "clean package -DskipTests=false"
  - name: incremental-build
    type: string
    default: "true"
  workspaces:
  - name: source
  - name: maven-cache
    description: Maven dependency cache (PVC)
  - name: build-cache
    description: Build output cache (PVC)
  - name: maven-settings
    mountPath: /root/.m2  # Maven 配置挂载路径
  steps:
  - name: prepare-cache
    image: 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -e
      
      # 创建缓存目录结构
      mkdir -p $(workspaces.maven-cache.path)/.m2/repository
      mkdir -p $(workspaces.build-cache.path)/target
      
      # 恢复之前的构建缓存（增量构建）
      if [ "$(params.incremental-build)" = "true" ] && [ -d "$(workspaces.build-cache.path)/target" ]; then
        echo "Restoring build cache..."
        cp -r $(workspaces.build-cache.path)/target/* $(workspaces.source.path)/$(params.context-dir)/target/ 2>/dev/null || true
      fi
      
      echo "Cache preparation completed"
  
  - name: maven-build
    image: 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -e
      
      cd "$(workspaces.source.path)/$(params.context-dir)"
      
      # 使用缓存目录
      MAVEN_OPTS="-Dmaven.repo.local=$(workspaces.maven-cache.path)/.m2/repository"
      
      # 离线模式（如果依赖已缓存）
      if [ -f "$(workspaces.maven-cache.path)/.m2/repository/.completed" ]; then
        echo "Using offline mode (dependencies cached)"
        MAVEN_OPTS="$MAVEN_OPTS -o"
      fi
      
      # 执行构建
      mvn $(params.maven-args) \
        -s /root/.m2/settings.xml \
        $MAVEN_OPTS \
        -Dmaven.artifact.threads=10 \
        -T 4 \
        -B
      
      echo "Build completed successfully!"
    resources:
      requests:
        cpu: "1"
        memory: 2Gi  # 内存 2Gi
      limits:
        cpu: "4"
        memory: 4Gi  # 内存 4Gi
  
  - name: save-cache
    image: 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      
      # 保存构建输出到缓存
      if [ "$(params.incremental-build)" = "true" ]; then
        echo "Saving build cache..."
        mkdir -p $(workspaces.build-cache.path)/target
        cp -r $(workspaces.source.path)/$(params.context-dir)/target/* $(workspaces.build-cache.path)/target/ 2>/dev/null || true
      fi
      
      # 标记依赖缓存完成
      touch $(workspaces.maven-cache.path)/.m2/repository/.completed
      
      echo "Cache saved successfully!"
```

```yaml
# Gradle 缓存 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: gradle-build-cached
  namespace: tekton-pipelines
spec:
  params:
  - name: context-dir
    type: string
    default: "."
  - name: gradle-args
    type: string
    default: "build"
  workspaces:
  - name: source
  - name: gradle-cache
    description: Gradle dependency cache (PVC)
  steps:
  - name: gradle-build
    image: 192.168.1.61/tekton/gradle:8.5-jdk17  # 镜像地址(Harbor)
    env:
    - name: GRADLE_USER_HOME
      value: "$(workspaces.gradle-cache.path)"
    - name: GRADLE_OPTS
      value: "-Dorg.gradle.daemon=false -Dorg.gradle.parallel=true -Dorg.gradle.workers.max=4"
    script: |
      #!/bin/bash
      set -e
      
      cd "$(workspaces.source.path)/$(params.context-dir)"
      
      # 配置 Gradle 使用缓存
      mkdir -p gradle
      cat > gradle.properties <<EOF
      org.gradle.caching=true
      org.gradle.configureondemand=true
      org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=512m
      EOF
      
      # 执行构建
      gradle $(params.gradle-args) --build-cache --configure-on-demand
      
      echo "Gradle build completed!"
    resources:
      requests:
        cpu: "1"
        memory: 2Gi  # 内存 2Gi
      limits:
        cpu: "4"
        memory: 4Gi  # 内存 4Gi
```

#### 3.2.2 Kaniko（无守护进程镜像构建） 层缓存优化

```yaml
# 带缓存优化的 Kaniko Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: kaniko-build-cached
  namespace: tekton-pipelines
spec:
  description: Build with Kaniko using layer caching
  params:
  - name: image
    type: string
  - name: dockerfile
    type: string
    default: Dockerfile
  - name: context
    type: string
    default: "."
  - name: cache-repo
    type: string
    default: "192.168.1.61/cache/kaniko"
  - name: cache-ttl
    type: string
    default: "24h"
  workspaces:
  - name: source
  - name: dockerconfig
    mountPath: /kaniko/.docker  # Docker 配置挂载路径
  steps:
  - name: build-with-cache
    image: 192.168.1.61/tekton/kaniko-project/executor:latest  # 镜像地址(Harbor)
    args:
    - --dockerfile=$(params.dockerfile)
    - --context=$(workspaces.source.path)/$(params.context)
    - --destination=$(params.image)
    - --cache=true
    - --cache-repo=$(params.cache-repo)
    - --cache-ttl=$(params.cache-ttl)
    - --snapshot-mode=redo
    - --use-new-run
    - --skip-tls-verify
    resources:
      requests:
        cpu: "1"
        memory: 2Gi  # 内存 2Gi
      limits:
        cpu: "4"
        memory: 8Gi  # 内存 8Gi
```

```dockerfile
# 多阶段构建优化示例 Dockerfile
# 注意：将此 Dockerfile 用于 Kaniko 构建以获得最佳缓存效果
# Dockerfile.optimized

# 阶段1：依赖缓存层
FROM 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17 AS dependencies
WORKDIR /app
COPY pom.xml .
# 单独下载依赖，利用缓存层
RUN mvn dependency:go-offline -B

# 阶段2：构建
FROM 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
# 从依赖阶段复制缓存
COPY --from=dependencies /root/.m2 /root/.m2
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests -B

# 阶段3：运行时
FROM 192.168.1.61/tekton/eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

#### 3.2.3 增量构建策略

```yaml
# 增量构建 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: incremental-build-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  - name: build-cache
  - name: git-history
    description: Git history cache for incremental detection
  
  tasks:
  - name: git-clone-smart
    taskRef:
      name: git-clone-incremental
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    - name: depth
      value: "10"  # 浅克隆，但保留一些历史用于增量检测
    workspaces:
    - name: output
      workspace: source
    - name: history
      workspace: git-history
  
  - name: detect-changes
    runAfter:  # 依赖任务: 
    - git-clone-smart
    taskRef:
      name: change-detector
    params:
    - name: base-ref
      value: "HEAD~1"
    workspaces:
    - name: source
      workspace: source
  
  - name: conditional-build
    runAfter:  # 依赖任务: 
    - detect-changes
    when:
    - input: "$(tasks.detect-changes.results.changed)"
      operator: in  # 条件判断: 包含
      values: ["true"]
    taskRef:
      name: maven-build-cached
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
    - name: build-cache
      workspace: build-cache
```

```yaml
# 变更检测 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: change-detector
  namespace: tekton-pipelines
spec:
  params:
  - name: base-ref
    type: string
    default: "HEAD~1"
  - name: watch-paths
    type: string
    default: "src/ pom.xml Dockerfile"
  results:
  - name: changed
    description: Whether watched paths have changed
  - name: changed-files
    description: List of changed files
  workspaces:
  - name: source
  steps:
  - name: detect
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      cd $(workspaces.source.path)
      
      # 获取变更的文件列表
      CHANGED_FILES=$(git diff --name-only $(params.base-ref) HEAD || echo "")
      echo "Changed files: $CHANGED_FILES"
      
      # 检查是否有关注的文件变更
      WATCHED_CHANGED="false"
      for path in $(params.watch-paths); do
        if echo "$CHANGED_FILES" | grep -q "^$path"; then
          WATCHED_CHANGED="true"
          break
        fi
      done
      
      echo -n "$WATCHED_CHANGED" > $(results.changed.path)
      echo -n "$CHANGED_FILES" > $(results.changed-files.path)
      
      if [ "$WATCHED_CHANGED" = "true" ]; then
        echo "Watched paths have changed, build required."
      else
        echo "No changes in watched paths, skipping build."
      fi
```

```yaml
# 智能 Git Clone Task（支持增量更新）
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: git-clone-incremental
  namespace: tekton-pipelines
spec:
  params:
  - name: url
    type: string
  - name: revision
    type: string
  - name: depth
    type: string
    default: "10"
  workspaces:
  - name: output
  - name: history
  steps:
  - name: clone
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      # 检查是否有历史缓存
      if [ -d "$(workspaces.history.path)/.git" ]; then
        echo "Using cached git history..."
        cp -r $(workspaces.history.path)/.git $(workspaces.output.path)/
        cd $(workspaces.output.path)
        git remote update
        git checkout $(params.revision)
      else
        echo "Fresh clone..."
        git clone --depth $(params.depth) $(params.url) $(workspaces.output.path)
        cd $(workspaces.output.path)
        git checkout $(params.revision)
      fi
      
      # 保存历史供下次使用
      rm -rf $(workspaces.history.path)/.git
      cp -r $(workspaces.output.path)/.git $(workspaces.history.path)/
      
      echo "Clone completed!"
```

### 3.3 创建 Kaniko Build Task（替代 Docker-in-Docker）

> **说明：** 本集群使用 containerd 作为容器运行时，不支持 Docker-in-Docker 模式。
> 因此使用 Kaniko 在用户空间构建镜像，无需 Docker Daemon，无需特权模式。

```bash
# Kaniko Build + Push Task（替代原 docker-build-push）
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: kaniko-build-push
  namespace: tekton-pipelines
spec:
  description: Build container image using Kaniko and push to Harbor (no Docker daemon required)
  params:
  - name: image
    description: Full image name including registry (e.g. 192.168.1.61/tekton/app:tag)
    type: string
  - name: dockerfile
    description: Path to Dockerfile
    type: string
    default: Dockerfile
  - name: context
    description: Build context path
    type: string
    default: .
  - name: build-args
    description: Docker build arguments (comma-separated key=value pairs)
    type: string
    default: ""
  - name: extra-args
    description: Extra Kaniko arguments (e.g. --skip-tls-verify for HTTP registry)
    type: string
    default: "--skip-tls-verify"
  workspaces:
  - name: source
    description: Source code workspace
  - name: dockerconfig
    description: Docker config for registry auth (mounted to /kaniko/.docker)
    mountPath: /kaniko/.docker  # Docker 配置挂载路径
  steps:
  - name: build-and-push
    image: 192.168.1.61/tekton/kaniko-project/executor:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -ex

      # Build arguments
      BUILD_ARGS=""
      if [ -n "$(params.build-args)" ]; then
        for arg in $(params.build-args | tr ',' '\n'); do
          BUILD_ARGS="$BUILD_ARGS --build-arg $arg"
        done
      fi

      # Build and push image using Kaniko
      /kaniko/executor \
        --dockerfile="$(workspaces.source.path)/$(params.dockerfile)" \
        --context="dir://$(workspaces.source.path)/$(params.context)" \
        --destination="$(params.image)" \
        $(params.extra-args) \
        $BUILD_ARGS

      echo "Image built and pushed successfully: $(params.image)"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 512Mi  # 内存 512Mi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
EOF
```

### 3.4 创建完整 CI Pipeline

```bash
# 完整的 CI Pipeline
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: java-ci-pipeline
  namespace: tekton-pipelines
spec:
  description: CI Pipeline for Java Spring Boot applications
  params:
  - name: git-url
    description: Git repository URL
    type: string
  - name: git-revision
    description: Git revision (branch/tag/SHA)
    type: string
    default: main
  - name: app-name
    description: Application name
    type: string
  - name: image-registry
    description: Container image registry
    type: string
    default: 192.168.1.61:80
  - name: image-tag
    description: Container image tag
    type: string
    default: ""
  - name: helm-values-path
    description: Path to Helm values file in Git repo
    type: string
    default: helm/values.yaml
  - name: helm-values-repo
    description: Git repo containing Helm values
    type: string
    default: ""
  workspaces:
  - name: source
    description: Source code workspace
  - name: maven-cache
    description: Maven dependency cache
  - name: kaniko-cache
    description: Kaniko build cache
  - name: dockerconfig
    description: Docker registry credentials

  tasks:
  # Task 1: Git Clone
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    - name: subdirectory
      value: ""
    - name: deleteExisting
      value: "true"
    workspaces:
    - name: output
      workspace: source

  # Task 2: Unit Test
  - name: unit-test
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-test
    params:
    - name: context-dir
      value: "."
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
    - name: maven-settings
      configMap:
        name: maven-settings

  # Task 3: Build Image
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "$(params.image-registry)/$(params.app-name):$(params.image-tag)"
    - name: dockerfile
      value: Dockerfile
    - name: context
      value: "."
    workspaces:
    - name: source
      workspace: source
    - name: dockerconfig
      workspace: dockerconfig

  # Task 4: Update Helm Values
  - name: update-helm-values
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: update-helm-values
    params:
    - name: app-name
      value: $(params.app-name)
    - name: image-tag
      value: $(params.image-tag)
    - name: image-registry
      value: $(params.image-registry)
    - name: helm-values-repo
      value: $(params.helm-values-repo)
    - name: helm-values-path
      value: $(params.helm-values-path)
    - name: git-revision
      value: $(params.git-revision)
    workspaces:
    - name: source
      workspace: source

  finally:  # 最终执行(无论成功失败)
  # Cleanup: Notify build result
  - name: notify
    when:
    - input: "$(tasks.status)"
      operator: in  # 条件判断: 包含
      values: ["Failed", "Succeeded"]
    taskRef:
      name: send-notification
    params:
    - name: status
      value: "$(tasks.status)"
    - name: app-name
      value: $(params.app-name)
    - name: image-tag
      value: $(params.image-tag)
EOF
```

### 3.5 创建 Maven Test Task（离线构建）

> **离线构建说明：** 本集群无外网，Maven 构建依赖 Nexus 私服（192.168.1.61:8081）。
> 需要预先在 Nexus（Maven 私服） 中代理 Maven Central 仓库，并通过 ConfigMap（配置映射） 挂载 settings.xml。

```bash
# 创建 Maven settings.xml ConfigMap（指向 Nexus 私服）
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: maven-settings
  namespace: tekton-pipelines
data:
  settings.xml: |
    <?xml version="1.0" encoding="UTF-8"?>
    <settings xmlns="http://maven.apache.org/SETTINGS/1.2.0"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.2.0 https://maven.apache.org/xsd/settings-1.2.0.xsd">
      <mirrors>
        <mirror>
          <id>nexus-mirror</id>
          <name>Nexus Maven Mirror</name>
          <url>http://192.168.1.61:8081/repository/maven-public/</url>
          <mirrorOf>*</mirrorOf>
        </mirror>
      </mirrors>
      <servers>
        <server>
          <id>nexus-releases</id>
          <username>admin</username>
          <password>admin123</password>
        </server>
        <server>
          <id>nexus-snapshots</id>
          <username>admin</username>
          <password>admin123</password>
        </server>
      </servers>
      <profiles>
        <profile>
          <id>nexus</id>
          <repositories>
            <repository>
              <id>nexus-releases</id>
              <url>http://192.168.1.61:8081/repository/maven-releases/</url>
              <releases><enabled>true</enabled></releases>
              <snapshots><enabled>false</enabled></snapshots>
            </repository>
            <repository>
              <id>nexus-snapshots</id>
              <url>http://192.168.1.61:8081/repository/maven-snapshots/</url>
              <releases><enabled>false</enabled></releases>
              <snapshots><enabled>true</enabled></snapshots>
            </repository>
          </repositories>
        </profile>
      </profiles>
      <activeProfiles>
        <activeProfile>nexus</activeProfile>
      </activeProfiles>
    </settings>
EOF

# Maven Test Task（使用 Nexus 私服 + PVC 缓存）
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: maven-test
  namespace: tekton-pipelines
spec:
  description: Run Maven unit tests with Nexus private repository
  params:
  - name: context-dir
    description: Context directory within source
    type: string
    default: "."
  - name: maven-args
    description: Maven arguments
    type: string
    default: "clean test -DskipTests=false -Dmaven.test.failure.ignore=false"
  workspaces:
  - name: source
    description: Source code workspace
  - name: maven-cache
    description: Maven dependency cache (PVC)
  - name: maven-settings
    description: Maven settings.xml ConfigMap (contains Nexus mirror config)
    mountPath: /root/.m2  # Maven 配置挂载路径
    readOnly: true
  steps:
  - name: maven-test
    image: 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -ex

      cd "$(workspaces.source.path)/$(params.context-dir)"

      # 使用 Nexus 私服 + PVC 缓存运行测试
      mvn $(params.maven-args) \
        -s /root/.m2/settings.xml \
        -Dmaven.repo.local=$(workspaces.maven-cache.path)/.m2/repository \
        -B

      echo "Unit tests completed successfully!"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
EOF
```

### 3.6 创建 Update Helm（K8s 包管理器） Values Task

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: update-helm-values
  namespace: tekton-pipelines
spec:
  description: Update Helm values with new image tag and commit to Git
  params:
  - name: app-name
    type: string
  - name: image-tag
    type: string
  - name: image-registry
    type: string
  - name: helm-values-repo
    type: string
  - name: helm-values-path
    type: string
  - name: git-revision
    type: string
  workspaces:
  - name: source
    description: Source workspace
  steps:
  - name: update-values
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -ex

      # Clone the Helm values repo
      git clone "$(params.helm-values-repo)" /tmp/helm-values
      cd /tmp/helm-values

      # Configure git
      git config user.email "tekton@ci.local"
      git config user.name "Tekton CI"

      # Update image tag in values file
      VALUES_FILE="$(params.helm-values-path)"
      if [ ! -f "$VALUES_FILE" ]; then
        echo "Error: Values file $VALUES_FILE not found"
        exit 1
      fi

      # Update image tag using sed
      sed -i "s|tag:.*|tag: $(params.image-tag)|g" "$VALUES_FILE"

      # Also update image repository if needed
      sed -i "s|repository:.*|repository: $(params.image-registry)/$(params.app-name)|g" "$VALUES_FILE"

      # Show diff
      git diff "$VALUES_FILE"

      # Commit and push
      git add "$VALUES_FILE"
      git commit -m "ci: update $(params.app-name) image to $(params.image-tag)

      Pipeline: java-ci-pipeline
      Branch: $(params.git-revision)
      Image: $(params.image-registry)/$(params.app-name):$(params.image-tag)"

      git push origin main

      echo "Helm values updated successfully!"
      echo "New image: $(params.image-registry)/$(params.app-name):$(params.image-tag)"
EOF
```

### 3.7 创建 Send Notification Task

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: send-notification
  namespace: tekton-pipelines
spec:
  description: Send build notification
  params:
  - name: status
    type: string
  - name: app-name
    type: string
  - name: image-tag
    type: string
  steps:
  - name: notify
    image: 192.168.1.61/tekton/curlimages/curl:8.0  # 镜像地址(Harbor)
    script: |
      #!/bin/bash

      STATUS="$(params.status)"
      APP="$(params.app-name)"
      TAG="$(params.image-tag)"

      if [ "$STATUS" = "Succeeded" ]; then
        MESSAGE="Build SUCCEEDED for ${APP}:${TAG}"
        COLOR="#36a64f"
      else
        MESSAGE="Build FAILED for ${APP}:${TAG}"
        COLOR="#ff0000"
      fi

      echo "$MESSAGE"

      # Slack notification (if configured)
      # curl -X POST "$SLACK_WEBHOOK_URL" \
      #   -H "Content-Type: application/json" \
      #   -d "{\"text\":\"$MESSAGE\",\"attachments\":[{\"color\":\"$COLOR\",\"text\":\"Pipeline: java-ci-pipeline\\nApp: $APP\\nTag: $TAG\\nStatus: $STATUS\"}]}"

      # DingTalk notification (if configured)
      # curl -X POST "$DINGTALK_WEBHOOK_URL" \
      #   -H "Content-Type: application/json" \
      #   -d "{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"Build $STATUS\",\"text\":\"## Build $STATUS\\n- App: $APP\\n- Tag: $TAG\\n- Status: $STATUS\"}}"

      echo "Notification sent!"
EOF
```

### 3.8 配置 Git Webhook 触发

```bash
# 1. 创建 Docker Registry Secret
kubectl create secret docker-registry harbor-secret \
  --namespace tekton-pipelines \
  --docker-server=192.168.1.61:80 \
  --docker-username=admin \
  --docker-password=Harbor12345

# 2. 创建 Git Secret
kubectl create secret generic git-secret \
  --namespace tekton-pipelines \
  --from-file=ssh-key=~/.ssh/id_rsa \
  --type=kubernetes.io/ssh-auth

# 3. 创建 ServiceAccount
cat <<'EOF' | kubectl apply -f -
apiVersion: v1  # API 版本
kind: ServiceAccount  # 服务账户
metadata:
  name: tekton-ci-sa
  namespace: tekton-pipelines
secrets:
- name: harbor-secret
- name: git-secret
EOF

# 4. 创建 RBAC（Pipeline 需要创建 PipelineRun 的权限）
cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: Role  # 角色
metadata:
  name: tekton-pipeline-role
  namespace: tekton-pipelines
rules:
- apiGroups: ["tekton.dev"]
  resources: ["pipelineruns", "taskruns"]
  verbs: ["get", "list", "create", "update", "delete"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1  # RBAC API 版本
kind: RoleBinding  # 角色绑定
metadata:
  name: tekton-pipeline-rolebinding
  namespace: tekton-pipelines
subjects:
- kind: ServiceAccount
  name: tekton-ci-sa
  namespace: tekton-pipelines
roleRef:
  kind: Role  # 角色
  name: tekton-pipeline-role
  apiGroup: rbac.authorization.k8s.io
EOF

# 5. 创建 TriggerBinding
cat <<'EOF' | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: TriggerBinding  # 触发参数绑定
metadata:
  name: git-push-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-revision
    value: $(body.head_commit.id)  # Git 提交 SHA
  - name: git-url
    value: $(body.repository.clone_url)  # Git 仓库地址
  - name: git-branch
    value: $(body.ref)  # Git 分支引用
  - name: app-name
    value: $(body.repository.name)  # 仓库名称
  - name: image-tag
    value: $(body.head_commit.id[:8])  # 短 SHA(镜像标签)
EOF

# 6. 创建 TriggerTemplate
cat <<'EOF' | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: TriggerTemplate  # 触发模板
metadata:
  name: java-ci-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    description: Git repository URL
  - name: git-revision
    description: Git commit SHA
  - name: git-branch
    description: Git branch
  - name: app-name
    description: Application name
  - name: image-tag
    description: Image tag (short SHA)
  resourcetemplates:
  - apiVersion: tekton.dev/v1beta1
    kind: PipelineRun  # 流水线执行实例
    metadata:
      generateName: ci-$(tt.params.app-name)-  # 自动生成名称前缀
      labels:
        app: $(tt.params.app-name)
        branch: $(tt.params.git-branch)
    spec:
      pipelineRef:
        name: java-ci-pipeline
      params:
      - name: git-url
        value: $(tt.params.git-url)
      - name: git-revision
        value: $(tt.params.git-revision)
      - name: app-name
        value: $(tt.params.app-name)
      - name: image-tag
        value: $(tt.params.image-tag)
      - name: image-registry
        value: "192.168.1.61:80"
      - name: helm-values-repo
        value: "http://192.168.1.61:3000/demo/demo-manifests.git"
      - name: helm-values-path
        value: "helm/$(tt.params.app-name)/values.yaml"
      workspaces:
      - name: source
        persistentVolumeClaim:
          claimName: ci-workspace
      - name: maven-cache
        persistentVolumeClaim:
          claimName: maven-cache
      - name: kaniko-cache
        persistentVolumeClaim:
          claimName: kaniko-cache
      - name: dockerconfig
        secret:
          secretName: harbor-secret
      serviceAccountName: tekton-ci-sa  # CI 服务账户
EOF

# 7. 创建 EventListener
cat <<'EOF' | kubectl apply -f -
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: EventListener  # 事件监听器
metadata:
  name: git-webhook-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-ci-sa  # CI 服务账户
  triggers:
  - name: git-push-trigger
    bindings:
    - ref: git-push-binding
    template:
      ref: java-ci-template
  resources:
    kubernetesResource:
      spec:
        template:
          spec:
            serviceType: NodePort  # NodePort 类型服务
            ports:
            - port: 8080
              targetPort: 8080
              nodePort: 32090  # NodePort 端口
            containers:
            - name: event-listener
              resources:
                requests:
                  cpu: 100m  # CPU 100m
                  memory: 128Mi  # 内存 128Mi
                limits:
                  cpu: 500m  # CPU 500m
                  memory: 512Mi  # 内存 512Mi
EOF

# 8. 获取 EventListener URL
kubectl get svc -n tekton-pipelines el-git-webhook-listener
# Webhook URL: http://192.168.1.54:32090

# 9. 在 Git 仓库中配置 Webhook
# Gitea: 仓库 -> Settings -> Webhooks -> Add Webhook
#   Payload URL: http://192.168.1.54:32090
#   Content type: application/json
#   Events: Push events
```

### 3.9 手动触发 Pipeline

```bash
# 手动创建 PipelineRun
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: PipelineRun  # 流水线执行实例
metadata:
  generateName: ci-order-service-  # 自动生成名称前缀
  namespace: tekton-pipelines
  labels:
    app: order-service
    branch: main
spec:
  pipelineRef:
    name: java-ci-pipeline
  params:
  - name: git-url
    value: "http://192.168.1.61:3000/demo/order-service.git"
  - name: git-revision
    value: "main"
  - name: app-name
    value: "order-service"
  - name: image-tag
    value: "v1.0.0"
  - name: image-registry
    value: "192.168.1.61:80"
  - name: helm-values-repo
    value: "http://192.168.1.61:3000/demo/demo-manifests.git"
  - name: helm-values-path
    value: "helm/order-service/values.yaml"
  workspaces:
  - name: source
    persistentVolumeClaim:
      claimName: ci-workspace
  - name: maven-cache
    persistentVolumeClaim:
      claimName: maven-cache
  - name: kaniko-cache
    persistentVolumeClaim:
      claimName: kaniko-cache
  - name: dockerconfig
    secret:
      secretName: harbor-secret
  serviceAccountName: tekton-ci-sa  # CI 服务账户
EOF

# 查看 PipelineRun 状态
tkn pipelinerun list -n tekton-pipelines

# 查看 PipelineRun 详情
tkn pipelinerun describe <pipelinerun-name> -n tekton-pipelines

# 查看 PipelineRun 日志
tkn pipelinerun logs <pipelinerun-name> -f -n tekton-pipelines

# 实时跟踪
tkn pipelinerun logs <pipelinerun-name> -f --follow -n tekton-pipelines
```

### 3.10 CI -> CD 完整链路验证

```bash
# 完整链路：
# 1. 开发者推送代码到 Git
# git push origin main

# 2. Git Webhook 触发 Tekton Pipeline
# EventListener 接收事件 -> TriggerBinding 提取参数 -> TriggerTemplate 创建 PipelineRun

# 3. Tekton Pipeline 执行 CI
# git-clone -> unit-test -> build-image -> update-helm-values

# 4. ArgoCD 检测到 Helm values 变更
# ArgoCD 自动 Sync 新配置到 K8s

# 5. 验证链路
# 查看 PipelineRun
tkn pipelinerun list -n tekton-pipelines --label app=order-service

# 查看 ArgoCD Application 状态
argocd app get order-service

# 查看 Pod 状态
kubectl get pods -n demo -l app=order-service

# 查看应用日志
kubectl logs -f deploy/order-service -n demo
```

---

## 4. 配置详解 / 高级功能

### 4.1 Pipeline 条件执行

```bash
# 使用 when 条件控制 Task 执行
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: conditional-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: run-integration-test
    type: string
    default: "false"
  - name: skip-build
    type: string
    default: "false"
  tasks:
  - name: unit-test
    taskRef:
      name: maven-test
  - name: integration-test
    runAfter:  # 依赖任务: 
    - unit-test
    when:
    - input: "$(params.run-integration-test)"
      operator: in  # 条件判断: 包含
      values: ["true", "yes"]
    taskRef:
      name: integration-test
  - name: build-image
    when:
    - input: "$(params.skip-build)"
      operator: notin
      values: ["true", "yes"]
    taskRef:
      name: kaniko-build-push
EOF
```

### 4.2 Pipeline 结果传递

```bash
# Task 之间传递结果
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: result-pipeline
  namespace: tekton-pipelines
spec:
  tasks:
  - name: build
    taskRef:
      name: kaniko-build-push
  - name: deploy
    runAfter:  # 依赖任务: 
    - build
    params:
    - name: image-digest
      value: $(tasks.build.results.image-digest)
    taskRef:
      name: deploy-to-k8s
EOF
```

### 4.3 并行执行

```bash
# 并行执行多个 Task
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: parallel-pipeline
  namespace: tekton-pipelines
spec:
  tasks:
  # 并行执行：unit-test 和 lint 同时运行
  - name: unit-test
    taskRef:
      name: maven-test
  - name: lint
    taskRef:
      name: code-lint
  # 等待所有并行任务完成后执行 build
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    - lint
    taskRef:
      name: kaniko-build-push
EOF
```

### 4.5 GitLab CI与Tekton对比

> **GitLab CI** 是 GitLab 内置的 CI/CD 工具，与 Tekton 相比有不同的架构设计和适用场景。本节从多个维度对比两者，帮助选择适合的技术方案。

#### 架构对比图

```
+================================================================================+
|                    GitLab CI vs Tekton 架构对比                                 |
+================================================================================+
|                                                                                |
|  GitLab CI 架构                                                                 |
|  +------------------+     +------------------+     +------------------+       |
|  | GitLab Server    |---->| GitLab Runner    |---->| Executor         |       |
|  | (Web UI/API)     |     | (任务调度)        |     | (Shell/Docker/   |       |
|  +------------------+     +------------------+     |  K8s)            |       |
|         |                                              +------------------+   |
|         |                                                                     |
|         v                                                                     |
|  +------------------+                                                        |
|  | .gitlab-ci.yml   |  配置存储在代码仓库                                      |
|  +------------------+                                                        |
|                                                                                |
|  Tekton 架构                                                                   |
|  +------------------+     +------------------+     +------------------+       |
|  | Tekton Triggers  |---->| PipelineRun      |---->| TaskRun (Pod)    |       |
|  | (EventListener)  |     | (任务编排)        |     | (容器执行)        |       |
|  +------------------+     +------------------+     +------------------+       |
|         |                                                                     |
|         v                                                                     |
|  +------------------+     +------------------+                               |
|  | Pipeline YAML    |---->| Task YAML        |  配置存储在K8s CRD            |
|  +------------------+     +------------------+                               |
|                                                                                |
+================================================================================+
```

#### 适用场景对比表

| 对比维度 | GitLab CI | Tekton |
|----------|-----------|--------|
| **部署模式** | 中心化部署，需要GitLab Server | 分布式部署，K8s原生 |
| **配置位置** | 代码仓库中的.gitlab-ci.yml | K8s集群中的CRD资源 |
| **执行环境** | GitLab Runner (VM/容器/K8s) | K8s Pod (原生容器) |
| **扩展方式** | 插件市场、自定义Runner | Task Catalog、自定义Task |
| **多集群支持** | 需配置多个Runner | 原生支持多集群Pipeline |
| **与K8s集成** | 通过K8s Executor间接集成 | 原生CRD，深度集成 |
| **学习曲线** | 较低，YAML配置简单 | 中等，需理解K8s概念 |
| **UI功能** | 丰富，内置在GitLab中 | 基础，需Dashboard |
| **权限管理** | GitLab RBAC（基于角色的访问控制） | K8s RBAC |
| **适用场景** | 中小型项目、GitLab用户 | 云原生、K8s原生环境 |

#### 配置方式对比

**GitLab CI配置 (.gitlab-ci.yml):**
```yaml
# .gitlab-ci.yml 示例
stages:
  - build
  - test
  - deploy

variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"

cache:
  paths:
    - .m2/repository
    - target/

build:
  stage: build
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn clean package -DskipTests
  artifacts:
    paths:
      - target/*.jar

test:
  stage: test
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn test
  dependencies:
    - build

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - kubectl apply -f k8s/
  only:
    - main
```

**Tekton配置 (Pipeline YAML):**
```yaml
# Tekton Pipeline 示例
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: java-ci-pipeline
spec:
  workspaces:
  - name: source
  - name: maven-cache
  tasks:
  - name: git-clone
    taskRef:
      name: git-clone
    workspaces:
    - name: output
      workspace: source
  - name: maven-build
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-build
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
```

#### 资源消耗对比

| 资源类型 | GitLab CI | Tekton |
|----------|-----------|--------|
| **控制面** | GitLab Server (4C8G起步) | Tekton Controller (100m/200Mi) |
| **执行节点** | Runner节点 (长期运行) | 动态创建Pod (按需) |
| **存储** | 外部Artifact存储 | PVC/Workspace (K8s原生) |
| **网络** | 依赖GitLab网络 | K8s CNI原生支持 |
| **扩展性** | 垂直扩展Runner | 水平扩展K8s节点 |

#### 选择建议

**选择GitLab CI的场景:**
- 团队已使用GitLab作为代码仓库
- 需要开箱即用的CI/CD功能
- 项目规模较小，不需要复杂的编排
- 团队不熟悉K8s，希望快速上手

**选择Tekton的场景:**
- 已采用K8s作为基础设施
- 需要云原生、声明式的Pipeline管理
- 需要多集群、复杂的任务编排
- 需要与ArgoCD等GitOps（Git 驱动运维）工具集成

**混合方案:**
- 使用GitLab CI触发Tekton Pipeline
- GitLab CI负责代码管理和基础CI
- Tekton负责复杂的K8s原生部署

---

### 4.4 Pipeline as Code 实践

> **Pipeline as Code** 是将 Pipeline 定义存储在 Git 仓库中，实现版本管理、代码审查和自动同步的最佳实践。

#### 架构图：Pipeline as Code 工作流

```
+================================================================+
|                    Pipeline as Code 架构                        |
+================================================================+
|                                                                 |
|  Git 仓库                                                       |
|  +--------------------------------------------------------+    |
|  |  .tekton/                                               |    |
|  |    ├── pipeline.yaml      # Pipeline 定义               |    |
|  |    ├── tasks/             # 自定义 Task                 |    |
|  |    │   ├── build.yaml                                   |    |
|  |    │   └── test.yaml                                    |    |
|  |    └── triggers/          # Trigger 配置                |    |
|  |        ├── binding.yaml                                 |    |
|  |        └── template.yaml                                |    |
|  |  src/                                                   |    |
|  |    └── ...                                              |    |
|  +-------------------+-------------------------------------+    |
|                      |                                          |
|                      | git push                                 |
|                      v                                          |
|  +-------------------+------------------+                      |
|  | Tekton Triggers                     |                      |
|  | +--------------------------------+  |                      |
|  | | EventListener                  |  |                      |
|  | |  +-------------------------+   |  |                      |
|  | |  | Interceptor (CEL)       |   |  |                      |
|  | |  | 检查 .tekton/ 变更      |   |  |                      |
|  | |  +-------------------------+   |  |                      |
|  | +--------------------------------+  |                      |
|  +-------------------+------------------+                      |
|                      |                                          |
|                      | 触发 Pipeline 同步                       |
|                      v                                          |
|  +-------------------+------------------+                      |
|  | Tekton Operator / kubectl apply     |                      |
|  | 自动更新集群中的 Pipeline/Task      |                      |
|  +-------------------------------------+                      |
+================================================================+
```

#### 4.4.1 将 Pipeline 定义存储在 Git 仓库

```bash
# 项目目录结构
my-application/
├── .tekton/                    # Tekton 配置目录
│   ├── kustomization.yaml      # Kustomize 配置
│   ├── pipeline.yaml           # Pipeline 定义
│   ├── tasks/
│   │   ├── maven-build.yaml    # 自定义 Task
│   │   └── security-scan.yaml
│   └── triggers/
│       ├── eventlistener.yaml
│       ├── binding.yaml
│       └── template.yaml
├── src/                        # 应用源码
├── Dockerfile
└── pom.xml
```

```yaml
# .tekton/pipeline.yaml - 与应用代码同版本管理
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: app-ci-pipeline
  namespace: tekton-pipelines
  # 添加标签用于版本追踪
  labels:
    app: my-application
    version: "1.0.0"
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  tasks:
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    workspaces:
    - name: output
      workspace: source
  
  - name: build
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-build  # 引用同仓库的自定义 Task
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
```

#### 4.4.2 Tekton Triggers 监听 Git 事件自动运行

```yaml
# .tekton/triggers/eventlistener.yaml
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: EventListener  # 事件监听器
metadata:
  name: pipeline-as-code-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-ci-sa  # CI 服务账户
  triggers:
  - name: pipeline-sync-trigger
    interceptors:
    - ref:
        name: "cel"
      params:
      # 只监听 .tekton/ 目录的变更
      - name: "filter"
        value: "body.commits.exists(c, c.modified.exists(m, m.startsWith('.tekton/'))) || body.commits.exists(c, c.added.exists(m, m.startsWith('.tekton/')))"
    bindings:
    - ref: pipeline-sync-binding
    template:
      ref: pipeline-sync-template
  - name: app-build-trigger
    interceptors:
    - ref:
        name: "cel"
      params:
      # 监听 src/ 目录变更触发应用构建
      - name: "filter"
        value: "body.commits.exists(c, c.modified.exists(m, m.startsWith('src/'))) || body.ref == 'refs/heads/main'"
    bindings:
    - ref: git-push-binding
    template:
      ref: app-build-template
```

```yaml
# .tekton/triggers/binding.yaml
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: TriggerBinding  # 触发参数绑定
metadata:
  name: pipeline-sync-binding
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    value: $(body.repository.clone_url)  # Git 仓库地址
  - name: git-revision
    value: $(body.head_commit.id)  # Git 提交 SHA
  - name: changed-files
    value: $(body.commits[0].modified)
---
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: TriggerTemplate  # 触发模板
metadata:
  name: pipeline-sync-template
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
  - name: git-revision
  resourcetemplates:
  # 创建 TaskRun 来同步 Pipeline 定义
  - apiVersion: tekton.dev/v1beta1
    kind: TaskRun
    metadata:
      generateName: sync-pipeline-
    spec:
      taskRef:
        name: sync-pipeline-from-git
      params:
      - name: git-url
        value: $(tt.params.git-url)
      - name: git-revision
        value: $(tt.params.git-revision)
      workspaces:
      - name: source
        emptyDir: {}
```

```yaml
# Pipeline 同步 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: sync-pipeline-from-git
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  workspaces:
  - name: source
  steps:
  - name: clone-and-sync
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      # 克隆仓库
      git clone --depth 1 $(params.git-url) $(workspaces.source.path)/repo
      cd $(workspaces.source.path)/repo
      
      # 检查 .tekton 目录是否存在
      if [ ! -d ".tekton" ]; then
        echo "No .tekton directory found, skipping sync"
        exit 0
      fi
      
      # 应用所有 Tekton 资源
      echo "Syncing Tekton resources..."
      kubectl apply -f .tekton/pipeline.yaml 2>/dev/null || echo "pipeline.yaml not found"
      kubectl apply -f .tekton/tasks/ 2>/dev/null || echo "No tasks to sync"
      kubectl apply -f .tekton/triggers/ 2>/dev/null || echo "No triggers to sync"
      
      echo "Pipeline sync completed!"
    resources:
      requests:
        cpu: 100m  # CPU 100m
        memory: 128Mi  # 内存 128Mi
```

#### 4.4.3 多分支 Pipeline 策略

```yaml
# 多分支 Pipeline 配置
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: multi-branch-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: git-branch
    type: string
  - name: app-name
    type: string
  tasks:
  # 根据分支执行不同的任务
  - name: determine-pipeline-type
    taskRef:
      name: branch-analyzer
    params:
    - name: branch
      value: $(params.git-branch)
  
  # Feature 分支：只运行测试
  - name: feature-test
    runAfter:  # 依赖任务: 
    - determine-pipeline-type
    when:
    - input: "$(tasks.determine-pipeline-type.results.branch-type)"
      operator: in  # 条件判断: 包含
      values: ["feature"]
    taskRef:
      name: maven-test
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
  
  # Develop 分支：运行测试 + 构建镜像（不推送生产）
  - name: dev-build
    runAfter:  # 依赖任务: 
    - determine-pipeline-type
    when:
    - input: "$(tasks.determine-pipeline-type.results.branch-type)"
      operator: in  # 条件判断: 包含
      values: ["develop"]
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "192.168.1.61/dev/$(params.app-name):$(params.git-revision)"
  
  # Main/Release 分支：完整 CI/CD
  - name: prod-build
    runAfter:  # 依赖任务: 
    - determine-pipeline-type
    when:
    - input: "$(tasks.determine-pipeline-type.results.branch-type)"
      operator: in  # 条件判断: 包含
      values: ["main", "release"]
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "192.168.1.61/prod/$(params.app-name):$(params.git-revision)"
```

```yaml
# 分支分析 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: branch-analyzer
  namespace: tekton-pipelines
spec:
  params:
  - name: branch
    type: string
  results:
  - name: branch-type
    description: Type of branch (feature, develop, main, release, hotfix)
  steps:
  - name: analyze
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      BRANCH="$(params.branch)"
      
      # 从 refs/heads/xxx 提取分支名
      BRANCH_NAME=$(echo "$BRANCH" | sed 's|refs/heads/||')
      
      if echo "$BRANCH_NAME" | grep -qE "^feature/"; then
        echo -n "feature" > $(results.branch-type.path)
      elif echo "$BRANCH_NAME" | grep -qE "^develop$"; then
        echo -n "develop" > $(results.branch-type.path)
      elif echo "$BRANCH_NAME" | grep -qE "^main$|^master$"; then
        echo -n "main" > $(results.branch-type.path)
      elif echo "$BRANCH_NAME" | grep -qE "^release/"; then
        echo -n "release" > $(results.branch-type.path)
      elif echo "$BRANCH_NAME" | grep -qE "^hotfix/"; then
        echo -n "hotfix" > $(results.branch-type.path)
      else
        echo -n "unknown" > $(results.branch-type.path)
      fi
      
      echo "Branch type: $(cat $(results.branch-type.path))"
```

#### 4.4.4 Pipeline 版本管理与回滚

```bash
# 使用 Git 标签管理 Pipeline 版本
# 1. 为 Pipeline 创建版本标签
git tag -a pipeline-v1.0.0 -m "Pipeline version 1.0.0"
git push origin pipeline-v1.0.0

# 2. 在 PipelineRun 中指定特定版本
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: PipelineRun  # 流水线执行实例
metadata:
  name: build-with-specific-pipeline
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: app-ci-pipeline
    # 使用特定版本的 Pipeline
  params:
  - name: git-url
    value: "http://192.168.1.61:3000/demo/my-app.git"
  - name: git-revision
    value: "pipeline-v1.0.0"  # 使用 Pipeline 版本标签
EOF
```

```yaml
# Pipeline 版本回滚 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: pipeline-rollback
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: target-version
    type: string
    description: Git tag or commit SHA to rollback to
  steps:
  - name: rollback
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      APP="$(params.app-name)"
      VERSION="$(params.target-version)"
      
      echo "Rolling back Pipeline for $APP to version $VERSION"
      
      # 获取历史 PipelineRun
      echo "Recent PipelineRuns for $APP:"
      kubectl get pipelinerun -n tekton-pipelines -l app=$APP --sort-by=.metadata.creationTimestamp | tail -5
      
      # 回滚到指定版本（重新触发该版本的构建）
      # 实际实现取决于具体的 GitOps 策略
      echo "Rollback completed. Please verify the deployment."
```

```bash
# 使用 Kustomize 管理多环境 Pipeline 配置
# .tekton/overlays/dev/kustomization.yaml
# .tekton/overlays/prod/kustomization.yaml

# 目录结构：
# .tekton/
#   ├── base/
#   │   ├── kustomization.yaml
#   │   ├── pipeline.yaml
#   │   └── tasks/
#   ├── overlays/
#   │   ├── dev/
#   │   │   └── kustomization.yaml
#   │   └── prod/
#   │       └── kustomization.yaml

# 应用不同环境的 Pipeline
kubectl apply -k .tekton/overlays/dev/   # 开发环境
kubectl apply -k .tekton/overlays/prod/  # 生产环境
```

---

## 5. 验证与测试

### 5.1 验证 Tekton 安装

```bash
# 检查 Tekton 组件
tkn version

# 列出所有 Pipeline
tkn pipeline list -n tekton-pipelines

# 列出所有 Task
tkn task list -n tekton-pipelines

# 列出所有 ClusterTask
tkn clustertask list

# 列出 Trigger
tkn triggerbinding list -n tekpton-pipelines
tkn triggertemplate list -n tekton-pipelines
tkn eventlistener list -n tekton-pipelines
```

### 5.2 验证 Pipeline 执行

```bash
# 手动触发 Pipeline
tkn pipeline start java-ci-pipeline \
  -p git-url="http://192.168.1.61:3000/demo/order-service.git" \
  -p git-revision="main" \
  -p app-name="order-service" \
  -p image-tag="v1.0.0" \
  -p image-registry="192.168.1.61:80" \
  -p helm-values-repo="http://192.168.1.61:3000/demo/demo-manifests.git" \
  -p helm-values-path="helm/order-service/values.yaml" \
  -w name=source,volumeClaimTemplateFile=pvc.yaml \
  -w name=maven-cache,claimName=maven-cache \
  -w name=kaniko-cache,claimName=kaniko-cache \
  -w name=dockerconfig,secret=harbor-secret \
  -s tekton-ci-sa \
  -n tekton-pipelines \
  --showlog

# 查看 PipelineRun 状态
tkn pipelinerun list -n tekton-pipelines

# 查看 TaskRun 状态
tkn taskrun list -n tekton-pipelines

# 查看日志
tkn pipelinerun logs -f -n tekton-pipelines <pipelinerun-name>
```

### 5.3 验证 Webhook 触发

```bash
# 模拟 Git Push Webhook
curl -X POST http://192.168.1.54:32090 \
  -H "Content-Type: application/json" \
  -H "X-Gitea-Event: push" \
  -d '{
    "ref": "refs/heads/main",
    "repository": {
      "clone_url": "http://192.168.1.61:3000/demo/order-service.git",
      "name": "order-service"
    },
    "head_commit": {
      "id": "abcdef1234567890abcdef1234567890abcdef12",
      "message": "feat: add new feature"
    }
  }'

# 检查是否创建了 PipelineRun
tkn pipelinerun list -n tekton-pipelines --label app=order-service
```

### 5.4 DevSecOps 安全集成

> **DevSecOps** 是将安全实践集成到 CI/CD 流水线中的方法论，实现"安全左移"，在开发早期发现并修复安全问题。

#### 架构图：DevSecOps 流水线

```
+================================================================+
|                    DevSecOps 流水线架构                         |
+================================================================+
|                                                                 |
|  源代码提交                                                      |
|       |                                                         |
|       v                                                         |
|  +----------------+    +----------------+    +----------------+|
|  | 代码质量扫描   |--->| 依赖漏洞扫描   |--->| 镜像安全扫描   ||
|  | SonarQube      |    | OWASP/SCA      |    | Trivy          ||
|  +----------------+    +----------------+    +----------------+|
|         |                      |                      |         |
|         v                      v                      v         |
|  +----------------+    +----------------+    +----------------+|
|  | 代码规范门禁   |    | 高危漏洞门禁   |    | 镜像合规门禁   ||
|  | (质量阈值)     |    | (CVE 阈值)     |    | (CIS 基准)     ||
|  +----------------+    +----------------+    +----------------+|
|         |                      |                      |         |
|         +----------------------+----------------------+         |
|                              |                                  |
|                              v                                  |
|  +----------------+    +----------------+    +----------------+|
|  | SBOM 生成      |--->| 签名镜像       |--->| 安全报告       ||
|  | CycloneDX      |    | Cosign         |    | 归档审计       ||
|  +----------------+    +----------------+    +----------------+|
|                                                                 |
+================================================================+
```

#### 5.4.1 镜像漏洞扫描(Trivy)集成到 Pipeline

```yaml
# Trivy 镜像扫描 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: trivy-image-scan
  namespace: tekton-pipelines
  labels:
    app.kubernetes.io/version: "0.1"
spec:
  description: Scan container image for vulnerabilities using Trivy
  params:
  - name: image
    description: Image to scan (format: registry/repo:tag)
    type: string
  - name: severity
    description: Severities to check (comma-separated)
    type: string
    default: "HIGH,CRITICAL"
  - name: exit-code
    description: Exit code when vulnerabilities are found
    type: string
    default: "1"
  - name: format
    description: Output format (table, json, sarif)
    type: string
    default: "json"
  - name: output-file
    description: Output file path
    type: string
    default: "/workspace/reports/trivy-report.json"
  workspaces:
  - name: reports
    description: Workspace to store scan reports
  steps:
  - name: scan-image
    image: 192.168.1.61/tekton/aquasec/trivy:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      mkdir -p $(dirname $(params.output-file))
      
      echo "Scanning image: $(params.image)"
      echo "Severity filter: $(params.severity)"
      
      # 离线环境：使用本地漏洞数据库
      # 需要预先将 trivy-db 推送到 Harbor 或本地存储
      if [ -d "/opt/trivy-db" ]; then
        export TRIVY_DB_REPOSITORY=/opt/trivy-db
      fi
      
      # 执行扫描
      trivy image \
        --severity $(params.severity) \
        --format $(params.format) \
        --output $(params.output-file) \
        --exit-code $(params.exit-code) \
        $(params.image) || SCAN_EXIT=$?
      
      # 生成摘要报告
      echo "=== Scan Summary ===" 
      trivy image \
        --severity $(params.severity) \
        --format table \
        $(params.image) 2>/dev/null || true
      
      if [ "${SCAN_EXIT:-0}" -ne 0 ]; then
        echo "Vulnerabilities found! Check $(params.output-file) for details."
        exit ${SCAN_EXIT}
      fi
      
      echo "Image scan completed successfully."
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 512Mi  # 内存 512Mi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
  - name: upload-report
    image: 192.168.1.61/tekton/curlimages/curl:8.0  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      # 可选：上传报告到安全平台或对象存储
      echo "Report saved to: $(params.output-file)"
      ls -la $(params.output-file)
```

```yaml
# 集成到 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: secure-ci-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  - name: image-registry
    type: string
    default: "192.168.1.61:80"
  workspaces:
  - name: source
  - name: maven-cache
  - name: security-reports
  
  tasks:
  # ... git-clone, unit-test, build-image ...
  
  - name: security-scan
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: trivy-image-scan
    params:
    - name: image
      value: "$(params.image-registry)/$(params.app-name):$(params.git-revision)"
    - name: severity
      value: "HIGH,CRITICAL"
    - name: exit-code
      value: "1"  # 发现高危漏洞时失败
    - name: format
      value: "sarif"  # 兼容 GitHub/GitLab 安全仪表板
    - name: output-file
      value: "/workspace/reports/trivy-$(params.app-name)-$(params.git-revision).sarif"
    workspaces:
    - name: reports
      workspace: security-reports
```

#### 5.4.2 代码质量检查(SonarQube)集成

```yaml
# SonarQube 扫描 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: sonarqube-scan
  namespace: tekton-pipelines
spec:
  params:
  - name: sonar-host-url
    description: SonarQube server URL
    type: string
    default: "http://192.168.1.61:9000"
  - name: sonar-project-key
    description: SonarQube project key
    type: string
  - name: sonar-project-name
    description: SonarQube project name
    type: string
    default: ""
  - name: sonar-quality-gate
    description: Wait for quality gate result
    type: string
    default: "true"
  - name: source-path
    description: Path to source code
    type: string
    default: "."
  workspaces:
  - name: source
    description: Source code workspace
  - name: sonar-token
    description: SonarQube token secret
  steps:
  - name: sonar-scan
    image: 192.168.1.61/tekton/sonarsource/sonar-scanner-cli:latest  # 镜像地址(Harbor)
    env:
    - name: SONAR_TOKEN
      valueFrom:
        secretKeyRef:
          name: $(workspaces.sonar-token.secretName)
          key: token
    script: |
      #!/bin/sh
      set -e
      
      cd $(workspaces.source.path)/$(params.source-path)
      
      # 生成 sonar-project.properties
      cat > sonar-project.properties <<EOF
      sonar.host.url=$(params.sonar-host-url)
      sonar.projectKey=$(params.sonar-project-key)
      sonar.projectName=$(params.sonar-project-name)
      sonar.sources=src
      sonar.java.binaries=target/classes
      sonar.junit.reportPaths=target/surefire-reports
      sonar.jacoco.reportPaths=target/jacoco.exec
      sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
      EOF
      
      echo "Starting SonarQube scan..."
      sonar-scanner \
        -Dsonar.qualitygate.wait=$(params.sonar-quality-gate) \
        -Dsonar.qualitygate.timeout=300
      
      echo "SonarQube scan completed."
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
```

```yaml
# 集成代码质量门禁的 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: code-quality-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  - name: sonar-token
  
  tasks:
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    workspaces:
    - name: output
      workspace: source
  
  - name: unit-test-with-coverage
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-test-coverage  # 带覆盖率报告的测试
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
  
  - name: sonarqube-analysis
    runAfter:  # 依赖任务: 
    - unit-test-with-coverage
    taskRef:
      name: sonarqube-scan
    params:
    - name: sonar-project-key
      value: "$(params.app-name)"
    - name: sonar-project-name
      value: "$(params.app-name)"
    - name: sonar-quality-gate
      value: "true"  # 启用质量门禁
    workspaces:
    - name: source
      workspace: source
    - name: sonar-token
      workspace: sonar-token
```

#### 5.4.3 安全门禁配置(高危漏洞阻止发布)

```yaml
# 安全门禁检查 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: security-gate-check
  namespace: tekton-pipelines
spec:
  params:
  - name: scan-report-path
    description: Path to security scan report
    type: string
  - name: max-critical-vulns
    description: Maximum allowed critical vulnerabilities
    type: string
    default: "0"
  - name: max-high-vulns
    description: Maximum allowed high vulnerabilities
    type: string
    default: "5"
  - name: block-on-license
    description: Block on license violations
    type: string
    default: "true"
  workspaces:
  - name: reports
    description: Workspace containing scan reports
  results:
  - name: gate-result
    description: Security gate result (PASS/FAIL)
  - name: critical-count
    description: Number of critical vulnerabilities
  - name: high-count
    description: Number of high vulnerabilities
  steps:
  - name: evaluate-gate
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      REPORT="$(workspaces.reports.path)/$(params.scan-report-path)"
      
      if [ ! -f "$REPORT" ]; then
        echo "ERROR: Scan report not found: $REPORT"
        exit 1
      fi
      
      # 解析 Trivy JSON 报告
      CRITICAL=$(grep -o '"Severity": "CRITICAL"' "$REPORT" | wc -l)
      HIGH=$(grep -o '"Severity": "HIGH"' "$REPORT" | wc -l)
      
      echo "Critical vulnerabilities: $CRITICAL"
      echo "High vulnerabilities: $HIGH"
      
      # 输出结果
      echo -n "$CRITICAL" > $(results.critical-count.path)
      echo -n "$HIGH" > $(results.high-count.path)
      
      # 门禁判断
      MAX_CRITICAL="$(params.max-critical-vulns)"
      MAX_HIGH="$(params.max-high-vulns)"
      
      if [ "$CRITICAL" -gt "$MAX_CRITICAL" ]; then
        echo "SECURITY GATE FAILED: Critical vulnerabilities ($CRITICAL) exceed threshold ($MAX_CRITICAL)"
        echo -n "FAIL" > $(results.gate-result.path)
        exit 1
      fi
      
      if [ "$HIGH" -gt "$MAX_HIGH" ]; then
        echo "SECURITY GATE FAILED: High vulnerabilities ($HIGH) exceed threshold ($MAX_HIGH)"
        echo -n "FAIL" > $(results.gate-result.path)
        exit 1
      fi
      
      echo "SECURITY GATE PASSED"
      echo -n "PASS" > $(results.gate-result.path)
```

```yaml
# 带安全门禁的 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: gated-security-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  - name: security-reports
  - name: dockerconfig
  
  tasks:
  # ... git-clone, unit-test ...
  
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
  
  - name: vulnerability-scan
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: trivy-image-scan
    params:
    - name: image
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
    - name: format
      value: "json"
    - name: output-file
      value: "/workspace/reports/scan-$(params.git-revision).json"
    workspaces:
    - name: reports
      workspace: security-reports
  
  - name: security-gate
    runAfter:  # 依赖任务: 
    - vulnerability-scan
    taskRef:
      name: security-gate-check
    params:
    - name: scan-report-path
      value: "scan-$(params.git-revision).json"
    - name: max-critical-vulns
      value: "0"  # 零容忍策略
    - name: max-high-vulns
      value: "3"
    workspaces:
    - name: reports
      workspace: security-reports
  
  # 只有通过安全门禁才推送镜像到生产仓库
  - name: promote-image
    runAfter:  # 依赖任务: 
    - security-gate
    when:
    - input: "$(tasks.security-gate.results.gate-result)"
      operator: in  # 条件判断: 包含
      values: ["PASS"]
    taskRef:
      name: crane-copy  # 使用 crane 复制镜像
    params:
    - name: source
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
    - name: destination
      value: "192.168.1.61/prod/$(params.app-name):$(params.git-revision)"
```

#### 5.4.4 SBOM(软件物料清单)生成

```yaml
# SBOM 生成 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: generate-sbom
  namespace: tekton-pipelines
spec:
  params:
  - name: image
    description: Image to generate SBOM for
    type: string
  - name: format
    description: SBOM format (cyclonedx, spdx-json)
    type: string
    default: "cyclonedx-json"
  - name: output-file
    description: Output file path
    type: string
    default: "/workspace/sbom/sbom.json"
  - name: app-name
    description: Application name
    type: string
  - name: app-version
    description: Application version
    type: string
  workspaces:
  - name: sbom
    description: Workspace to store SBOM
  steps:
  - name: generate-sbom
    image: 192.168.1.61/tekton/anchore/syft:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      mkdir -p $(dirname $(params.output-file))
      
      echo "Generating SBOM for image: $(params.image)"
      
      # 生成 SBOM
      syft $(params.image) \
        -o $(params.format)=$(params.output-file) \
        --scope all-layers
      
      echo "SBOM generated: $(params.output-file)"
      
      # 显示摘要
      echo "=== SBOM Summary ==="
      cat $(params.output-file) | grep -o '"name"' | wc -l
      echo "components found"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 512Mi  # 内存 512Mi
      limits:
        cpu: "1"
        memory: 1Gi  # 内存 1Gi
  
  - name: sign-sbom
    image: 192.168.1.61/tekton/cosign:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      # 使用 Cosign 签名 SBOM
      echo "Signing SBOM..."
      # cosign sign-blob --key env://COSIGN_PRIVATE_KEY $(params.output-file)
      echo "SBOM signed (placeholder)"
  
  - name: upload-sbom
    image: 192.168.1.61/tekton/curlimages/curl:8.0  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      # 上传 SBOM 到 Harbor 或依赖追踪系统
      SBOM_FILE="$(params.output-file)"
      
      # Harbor 2.8+ 支持 SBOM 附件
      # curl -X POST "http://192.168.1.61/api/v2.0/projects/$(params.app-name)/repositories/..."
      
      echo "SBOM uploaded for $(params.app-name):$(params.app-version)"
      echo "File: $SBOM_FILE"
      ls -la $SBOM_FILE
```

```yaml
# 完整 DevSecOps Pipeline 示例
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: devsecops-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  - name: app-version
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  - name: security-reports
  - name: sbom
  - name: dockerconfig
  - name: sonar-token
  
  tasks:
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    workspaces:
    - name: output
      workspace: source
  
  - name: code-quality
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: sonarqube-scan
    params:
    - name: sonar-project-key
      value: "$(params.app-name)"
    workspaces:
    - name: source
      workspace: source
    - name: sonar-token
      workspace: sonar-token
  
  - name: unit-test
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-test
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
  
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    - code-quality
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
  
  - name: vulnerability-scan
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: trivy-image-scan
    params:
    - name: image
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
    workspaces:
    - name: reports
      workspace: security-reports
  
  - name: security-gate
    runAfter:  # 依赖任务: 
    - vulnerability-scan
    taskRef:
      name: security-gate-check
    params:
    - name: max-critical-vulns
      value: "0"
    workspaces:
    - name: reports
      workspace: security-reports
  
  - name: generate-sbom
    runAfter:  # 依赖任务: 
    - security-gate
    taskRef:
      name: generate-sbom
    params:
    - name: image
      value: "192.168.1.61:80/$(params.app-name):$(params.git-revision)"
    - name: app-name
      value: "$(params.app-name)"
    - name: app-version
      value: "$(params.app-version)"
    workspaces:
    - name: sbom
      workspace: sbom
  
  finally:  # 最终执行(无论成功失败)
  - name: security-report
    taskRef:
      name: send-security-report
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: scan-status
      value: "$(tasks.security-gate.results.gate-result)"
```

### 5.5 DevSecOps安全流水线

> **DevSecOps** 是将安全实践集成到 CI/CD 流水线中的方法论，实现"安全左移"，在开发早期发现并修复安全问题。本节介绍如何在 Tekton 中构建完整的 DevSecOps 流水线。

#### 安全左移理念

```
+================================================================================+
|                         安全左移 (Shift Left Security)                          |
+================================================================================+
|                                                                                |
|  传统安全模型                    DevSecOps安全模型                              |
|  +----------------+             +----------------+                             |
|  | 开发           |             | 安全扫描       |                             |
|  | 开发           |             | 代码质量       |                             |
|  | 开发           |             | 依赖检查       |                             |
|  | 开发           |             | 密钥检测       |                             |
|  +--------+-------+             +--------+-------+                             |
|           |                              |                                     |
|           v                              v                                     |
|  +----------------+             +----------------+                             |
|  | 测试           |             | 构建           |                             |
|  | 测试           |             | 镜像扫描       |                             |
|  | 测试           |             | SBOM生成       |                             |
|  +--------+-------+             +--------+-------+                             |
|           |                              |                                     |
|           v                              v                                     |
|  +----------------+             +----------------+                             |
|  | 部署           |             | 部署           |                             |
|  | 安全扫描       |             | 准入控制       |                             |
|  | (太晚!)        |             | 签名验证       |                             |
|  +--------+-------+             +--------+-------+                             |
|           |                              |                                     |
|           v                              v                                     |
|  +----------------+             +----------------+                             |
|  | 生产           |             | 生产           |                             |
|  | 漏洞修复       |             | 运行时监控     |                             |
|  | (成本高!)      |             | 持续安全       |                             |
|  +----------------+             +----------------+                             |
|                                                                                |
+================================================================================+
```

**安全左移核心价值:**
- 早期发现漏洞，降低修复成本
- 自动化安全检测，减少人工审计
- 安全门禁阻断高风险发布
- 完整的审计追溯链

#### SAST(SonarQube)集成

**SonarQube扫描Task:**
```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: sonarqube-sast-scan
  namespace: tekton-pipelines
spec:
  description: SAST扫描 - 使用SonarQube进行代码安全分析
  params:
  - name: sonar-host-url
    description: SonarQube服务器地址
    type: string
    default: "http://192.168.1.61:9000"
  - name: sonar-project-key
    description: 项目唯一标识
    type: string
  - name: sonar-project-name
    description: 项目名称
    type: string
    default: ""
  - name: sonar-quality-gate
    description: 是否等待质量门禁结果
    type: string
    default: "true"
  - name: source-path
    description: 源码路径
    type: string
    default: "."
  - name: coverage-report-path
    description: 覆盖率报告路径
    type: string
    default: "target/site/jacoco/jacoco.xml"
  workspaces:
  - name: source
    description: 源码工作区
  - name: sonar-token
    description: SonarQube Token Secret
  results:
  - name: scan-status
    description: 扫描状态 (PASS/FAIL)
  - name: quality-gate-status
    description: 质量门禁状态
  steps:
  - name: sonar-scan
    image: 192.168.1.61/tekton/sonarsource/sonar-scanner-cli:5.0  # 镜像地址(Harbor)
    env:
    - name: SONAR_TOKEN
      valueFrom:
        secretKeyRef:
          name: $(workspaces.sonar-token.secretName)
          key: token
    script: |
      #!/bin/bash
      set -e
      
      cd $(workspaces.source.path)/$(params.source-path)
      
      PROJECT_NAME="$(params.sonar-project-name)"
      if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="$(params.sonar-project-key)"
      fi
      
      # 生成sonar-project.properties
      cat > sonar-project.properties <<EOF
      sonar.host.url=$(params.sonar-host-url)
      sonar.projectKey=$(params.sonar-project-key)
      sonar.projectName=${PROJECT_NAME}
      sonar.sources=src/main/java
      sonar.tests=src/test/java
      sonar.java.binaries=target/classes
      sonar.junit.reportPaths=target/surefire-reports
      sonar.coverage.jacoco.xmlReportPaths=$(params.coverage-report-path)
      sonar.exclusions=**/target/**,**/*.min.js
      sonar.sourceEncoding=UTF-8
      EOF
      
      echo "=== SonarQube配置 ==="
      cat sonar-project.properties
      
      echo "=== 开始SAST扫描 ==="
      sonar-scanner \
        -Dsonar.qualitygate.wait=$(params.sonar-quality-gate) \
        -Dsonar.qualitygate.timeout=300 \
        -Dsonar.log.level=INFO
      
      # 获取扫描结果
      if [ "$(params.sonar-quality-gate)" = "true" ]; then
        echo "质量门禁检查通过"
        echo -n "PASS" > $(results.scan-status.path)
        echo -n "PASSED" > $(results.quality-gate-status.path)
      else
        echo "扫描完成，未启用质量门禁"
        echo -n "COMPLETED" > $(results.scan-status.path)
        echo -n "UNKNOWN" > $(results.quality-gate-status.path)
      fi
      
      echo "SAST扫描完成"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
```

#### SCA(依赖扫描)集成

**Dependency Check Task (OWASP):**
```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: dependency-check-scan
  namespace: tekton-pipelines
spec:
  description: SCA扫描 - 检测依赖组件中的已知漏洞
  params:
  - name: project-name
    description: 项目名称
    type: string
  - name: scan-path
    description: 扫描路径
    type: string
    default: "."
  - name: output-format
    description: 输出格式 (JSON, XML, HTML, CSV, VULN)
    type: string
    default: "JSON"
  - name: fail-on-cvss
    description: CVSS分数阈值，超过则失败
    type: string
    default: "7"  # HIGH及以上
  - name: suppression-file
    description: 抑制文件路径（用于排除误报）
    type: string
    default: ""
  workspaces:
  - name: source
    description: 源码工作区
  - name: reports
    description: 报告输出工作区
  - name: dependency-check-db
    description: Dependency Check数据库缓存
  results:
  - name: vulnerability-count
    description: 发现的漏洞数量
  - name: scan-result
    description: 扫描结果 (PASS/FAIL)
  steps:
  - name: dependency-check
    image: 192.168.1.61/tekton/owasp/dependency-check:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -e
      
      mkdir -p $(workspaces.reports.path)/dependency-check
      
      SUPPRESSION_ARG=""
      if [ -n "$(params.suppression-file)" ] && [ -f "$(workspaces.source.path)/$(params.suppression-file)" ]; then
        SUPPRESSION_ARG="--suppression $(workspaces.source.path)/$(params.suppression-file)"
      fi
      
      echo "=== 开始依赖扫描 ==="
      echo "项目: $(params.project-name)"
      echo "路径: $(workspaces.source.path)/$(params.scan-path)"
      echo "CVSS阈值: $(params.fail-on-cvss)"
      
      # 离线环境配置
      if [ -d "$(workspaces.dependency-check-db.path)/data" ]; then
        echo "使用本地漏洞数据库"
        cp -r $(workspaces.dependency-check-db.path)/data /tmp/dependency-check-data
        DC_ARGS="--data /tmp/dependency-check-data"
      else
        DC_ARGS=""
      fi
      
      /usr/share/dependency-check/bin/dependency-check.sh \
        --project "$(params.project-name)" \
        --scan "$(workspaces.source.path)/$(params.scan-path)" \
        --format $(params.output-format) \
        --out $(workspaces.reports.path)/dependency-check \
        --failOnCVSS $(params.fail-on-cvss) \
        $SUPPRESSION_ARG \
        $DC_ARGS \
        --noupdate || SCAN_EXIT=$?
      
      # 解析结果
      if [ -f "$(workspaces.reports.path)/dependency-check/dependency-check-report.json" ]; then
        VULN_COUNT=$(cat $(workspaces.reports.path)/dependency-check/dependency-check-report.json | \
          jq '[.dependencies[].vulnerabilities? // empty | length] | add // 0')
        echo "发现漏洞数量: $VULN_COUNT"
        echo -n "$VULN_COUNT" > $(results.vulnerability-count.path)
      else
        echo -n "0" > $(results.vulnerability-count.path)
      fi
      
      if [ "${SCAN_EXIT:-0}" -eq 0 ]; then
        echo -n "PASS" > $(results.scan-result.path)
        echo "依赖扫描通过"
      else
        echo -n "FAIL" > $(results.scan-result.path)
        echo "发现高危依赖漏洞，请查看报告"
        exit 1
      fi
    resources:
      requests:
        cpu: "1"
        memory: 2Gi  # 内存 2Gi
      limits:
        cpu: "2"
        memory: 4Gi  # 内存 4Gi
```

#### 容器镜像安全扫描

**Trivy镜像扫描Task (增强版):**
```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: trivy-image-security-scan
  namespace: tekton-pipelines
spec:
  description: 容器镜像安全扫描 - 使用Trivy进行漏洞和配置检查
  params:
  - name: image
    description: 待扫描镜像
    type: string
  - name: severity
    description: 漏洞严重程度 (UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL)
    type: string
    default: "HIGH,CRITICAL"
  - name: scanners
    description: 扫描器类型 (vuln,config,secret,license)
    type: string
    default: "vuln,config,secret"
  - name: exit-code
    description: 发现漏洞时的退出码 (0=不失败, 1=失败)
    type: string
    default: "1"
  - name: ignore-unfixed
    description: 忽略未修复的漏洞
    type: string
    default: "false"
  - name: skip-files
    description: 跳过的文件路径
    type: string
    default: ""
  - name: skip-dirs
    description: 跳过的目录
    type: string
    default: "/var/lib/docker,/tmp"
  workspaces:
  - name: reports
    description: 报告输出工作区
  - name: trivy-db
    description: Trivy漏洞数据库缓存
  results:
  - name: critical-count
    description: 关键漏洞数量
  - name: high-count
    description: 高危漏洞数量
  - name: medium-count
    description: 中危漏洞数量
  - name: scan-status
    description: 扫描状态
  steps:
  - name: scan-image
    image: 192.168.1.61/tekton/aquasec/trivy:0.55  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -e
      
      mkdir -p $(workspaces.reports.path)/trivy
      
      # 离线环境配置
      if [ -d "$(workspaces.trivy-db.path)" ]; then
        echo "使用本地漏洞数据库"
        export TRIVY_CACHE_DIR=$(workspaces.trivy-db.path)
        DB_ARGS="--skip-db-update --skip-java-db-update"
      else
        DB_ARGS=""
      fi
      
      SKIP_FILES_ARG=""
      if [ -n "$(params.skip-files)" ]; then
        SKIP_FILES_ARG="--skip-files $(params.skip-files)"
      fi
      
      echo "=== 开始镜像安全扫描 ==="
      echo "镜像: $(params.image)"
      echo "扫描器: $(params.scanners)"
      echo "严重程度: $(params.severity)"
      
      # JSON格式报告
      trivy image \
        --scanners $(params.scanners) \
        --severity $(params.severity) \
        --format json \
        --output $(workspaces.reports.path)/trivy/scan-report.json \
        --exit-code 0 \
        --ignore-unfixed=$(params.ignore-unfixed) \
        --skip-dirs "$(params.skip-dirs)" \
        $SKIP_FILES_ARG \
        $DB_ARGS \
        $(params.image)
      
      # 生成表格摘要
      echo "=== 扫描摘要 ==="
      trivy image \
        --scanners $(params.scanners) \
        --severity $(params.severity) \
        --format table \
        --ignore-unfixed=$(params.ignore-unfixed) \
        $DB_ARGS \
        $(params.image) || true
      
      # 统计漏洞数量
      if [ -f "$(workspaces.reports.path)/trivy/scan-report.json" ]; then
        CRITICAL=$(cat $(workspaces.reports.path)/trivy/scan-report.json | \
          jq '[.Results[].Vulnerabilities? // empty | .[] | select(.Severity=="CRITICAL")] | length' || echo "0")
        HIGH=$(cat $(workspaces.reports.path)/trivy/scan-report.json | \
          jq '[.Results[].Vulnerabilities? // empty | .[] | select(.Severity=="HIGH")] | length' || echo "0")
        MEDIUM=$(cat $(workspaces.reports.path)/trivy/scan-report.json | \
          jq '[.Results[].Vulnerabilities? // empty | .[] | select(.Severity=="MEDIUM")] | length' || echo "0")
        
        echo -n "$CRITICAL" > $(results.critical-count.path)
        echo -n "$HIGH" > $(results.high-count.path)
        echo -n "$MEDIUM" > $(results.medium-count.path)
        
        echo "关键漏洞: $CRITICAL"
        echo "高危漏洞: $HIGH"
        echo "中危漏洞: $MEDIUM"
      else
        echo -n "0" > $(results.critical-count.path)
        echo -n "0" > $(results.high-count.path)
        echo -n "0" > $(results.medium-count.path)
      fi
      
      # 根据exit-code参数决定是否失败
      if [ "$(params.exit-code)" = "1" ]; then
        TOTAL=$((CRITICAL + HIGH))
        if [ "$TOTAL" -gt 0 ]; then
          echo "发现高危漏洞，扫描失败"
          echo -n "FAIL" > $(results.scan-status.path)
          exit 1
        fi
      fi
      
      echo -n "PASS" > $(results.scan-status.path)
      echo "镜像安全扫描完成"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 512Mi  # 内存 512Mi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
```

#### DAST动态测试

**DAST扫描Task (使用OWASP ZAP):**
```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: zap-dast-scan
  namespace: tekton-pipelines
spec:
  description: DAST动态测试 - 使用OWASP ZAP进行运行时安全测试
  params:
  - name: target-url
    description: 目标应用URL
    type: string
  - name: scan-type
    description: 扫描类型 (baseline, apis, full)
    type: string
    default: "baseline"
  - name: context-file
    description: ZAP上下文文件路径
    type: string
    default: ""
  - name: ajax-spider
    description: 启用AJAX Spider
    type: string
    default: "false"
  - name: active-scan
    description: 启用主动扫描
    type: string
    default: "false"
  - name: fail-on-risk
    description: 风险等级阈值 (0=INFO, 1=LOW, 2=MEDIUM, 3=HIGH)
    type: string
    default: "3"
  workspaces:
  - name: reports
    description: 报告输出工作区
  - name: zap-home
    description: ZAP主目录缓存
  results:
  - name: high-risk-count
    description: 高风险问题数量
  - name: scan-status
    description: 扫描状态
  steps:
  - name: zap-scan
    image: 192.168.1.61/tekton/owasp/zap2docker-stable:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      
      mkdir -p $(workspaces.reports.path)/zap
      
      # 配置ZAP Home
      export ZAP_HOME=$(workspaces.zap-home.path)
      mkdir -p $ZAP_HOME
      
      CONTEXT_ARG=""
      if [ -n "$(params.context-file)" ] && [ -f "$(workspaces.reports.path)/$(params.context-file)" ]; then
        CONTEXT_ARG="-c $(workspaces.reports.path)/$(params.context-file)"
      fi
      
      AJAX_ARG=""
      if [ "$(params.ajax-spider)" = "true" ]; then
        AJAX_ARG="-j"
      fi
      
      ACTIVE_ARG=""
      if [ "$(params.active-scan)" = "true" ]; then
        ACTIVE_ARG="-a"
      fi
      
      echo "=== 开始DAST扫描 ==="
      echo "目标: $(params.target-url)"
      echo "扫描类型: $(params.scan-type)"
      
      # 执行ZAP扫描
      zap-baseline.py \
        -t $(params.target-url) \
        -r $(workspaces.reports.path)/zap/zap-report.html \
        -w $(workspaces.reports.path)/zap/zap-report.md \
        -J $(workspaces.reports.path)/zap/zap-report.json \
        $CONTEXT_ARG \
        $AJAX_ARG \
        $ACTIVE_ARG \
        -l $(params.fail-on-risk) || SCAN_EXIT=$?
      
      # 解析结果
      if [ -f "$(workspaces.reports.path)/zap/zap-report.json" ]; then
        HIGH_RISKS=$(cat $(workspaces.reports.path)/zap/zap-report.json | \
          jq '[.site[0].alerts[] | select(.riskcode | tonumber >= $(params.fail-on-risk))] | length' || echo "0")
        echo -n "$HIGH_RISKS" > $(results.high-risk-count.path)
      else
        echo -n "0" > $(results.high-risk-count.path)
      fi
      
      # ZAP退出码说明: 0=PASS, 1=WARNINGS, 2=FAIL
      case "${SCAN_EXIT:-0}" in
        0)
          echo "DAST扫描通过，无风险"
          echo -n "PASS" > $(results.scan-status.path)
          ;;
        1)
          echo "DAST扫描完成，存在警告"
          echo -n "WARN" > $(results.scan-status.path)
          ;;
        2)
          echo "DAST扫描失败，存在高风险"
          echo -n "FAIL" > $(results.scan-status.path)
          exit 1
          ;;
      esac
      
      echo "DAST扫描完成"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
```

#### 安全门禁配置

**综合安全门禁Task:**
```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: security-gate-check
  namespace: tekton-pipelines
spec:
  description: 安全门禁检查 - 综合评估所有安全扫描结果
  params:
  - name: sast-status
    description: SAST扫描状态
    type: string
    default: "PASS"
  - name: sca-status
    description: SCA扫描状态
    type: string
    default: "PASS"
  - name: image-scan-status
    description: 镜像扫描状态
    type: string
    default: "PASS"
  - name: dast-status
    description: DAST扫描状态
    type: string
    default: "PASS"
  - name: critical-vuln-count
    description: 关键漏洞数量
    type: string
    default: "0"
  - name: high-vuln-count
    description: 高危漏洞数量
    type: string
    default: "0"
  - name: max-critical-allowed
    description: 允许的最大关键漏洞数
    type: string
    default: "0"
  - name: max-high-allowed
    description: 允许的最大高危漏洞数
    type: string
    default: "5"
  - name: gate-policy
    description: 门禁策略 (strict, moderate, relaxed)
    type: string
    default: "strict"
  results:
  - name: gate-result
    description: 门禁结果 (PASS/FAIL)
  - name: gate-summary
    description: 门禁检查摘要
  steps:
  - name: evaluate-gate
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      echo "======================================"
      echo "       安全门禁检查报告               "
      echo "======================================"
      echo ""
      echo "扫描状态汇总:"
      echo "  SAST (代码扫描):    $(params.sast-status)"
      echo "  SCA (依赖扫描):     $(params.sca-status)"
      echo "  Image (镜像扫描):   $(params.image-scan-status)"
      echo "  DAST (动态测试):    $(params.dast-status)"
      echo ""
      echo "漏洞统计:"
      echo "  关键漏洞: $(params.critical-vuln-count) / 阈值: $(params.max-critical-allowed)"
      echo "  高危漏洞: $(params.high-vuln-count) / 阈值: $(params.max-high-allowed)"
      echo ""
      echo "门禁策略: $(params.gate-policy)"
      echo "======================================"
      
      GATE_PASSED="true"
      FAIL_REASON=""
      
      # 根据策略检查
      case "$(params.gate-policy)" in
        strict)
          # 严格模式: 所有扫描必须通过
          if [ "$(params.sast-status)" != "PASS" ]; then
            GATE_PASSED="false"
            FAIL_REASON="${FAIL_REASON}SAST扫描失败; "
          fi
          if [ "$(params.sca-status)" != "PASS" ]; then
            GATE_PASSED="false"
            FAIL_REASON="${FAIL_REASON}SCA扫描失败; "
          fi
          if [ "$(params.image-scan-status)" != "PASS" ]; then
            GATE_PASSED="false"
            FAIL_REASON="${FAIL_REASON}镜像扫描失败; "
          fi
          ;;
        moderate)
          # 中等模式: 关键扫描必须通过
          if [ "$(params.sast-status)" != "PASS" ]; then
            GATE_PASSED="false"
            FAIL_REASON="${FAIL_REASON}SAST扫描失败; "
          fi
          if [ "$(params.image-scan-status)" != "PASS" ]; then
            GATE_PASSED="false"
            FAIL_REASON="${FAIL_REASON}镜像扫描失败; "
          fi
          ;;
        relaxed)
          # 宽松模式: 仅检查关键漏洞数量
          echo "宽松模式: 仅检查漏洞数量阈值"
          ;;
      esac
      
      # 检查漏洞数量阈值
      CRITICAL=$(params.critical-vuln-count)
      MAX_CRITICAL=$(params.max-critical-allowed)
      HIGH=$(params.high-vuln-count)
      MAX_HIGH=$(params.max-high-allowed)
      
      if [ "$CRITICAL" -gt "$MAX_CRITICAL" ]; then
        GATE_PASSED="false"
        FAIL_REASON="${FAIL_REASON}关键漏洞数($CRITICAL)超过阈值($MAX_CRITICAL); "
      fi
      
      if [ "$HIGH" -gt "$MAX_HIGH" ]; then
        GATE_PASSED="false"
        FAIL_REASON="${FAIL_REASON}高危漏洞数($HIGH)超过阈值($MAX_HIGH); "
      fi
      
      echo ""
      if [ "$GATE_PASSED" = "true" ]; then
        echo "✓ 安全门禁检查通过"
        echo -n "PASS" > $(results.gate-result.path)
        echo -n "所有安全检查通过" > $(results.gate-summary.path)
      else
        echo "✗ 安全门禁检查失败"
        echo "失败原因: $FAIL_REASON"
        echo -n "FAIL" > $(results.gate-result.path)
        echo -n "$FAIL_REASON" > $(results.gate-summary.path)
        exit 1
      fi
```

#### 完整DevSecOps流水线YAML示例

```yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: devsecops-complete-pipeline
  namespace: tekton-pipelines
spec:
  description: 完整DevSecOps流水线 - 集成SAST、SCA、镜像扫描、DAST
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  - name: image-registry
    type: string
    default: "192.168.1.61:80"
  - name: sonar-project-key
    type: string
  - name: gate-policy
    type: string
    default: "strict"
  workspaces:
  - name: source
  - name: maven-cache
  - name: security-reports
  - name: sbom
  - name: dockerconfig
  - name: sonar-token
  - name: dependency-check-db
  - name: trivy-db
  
  tasks:
  # ========== 阶段1: 代码获取 ==========
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    workspaces:
    - name: output
      workspace: source
  
  # ========== 阶段2: 并行安全扫描 ==========
  # 2.1 SAST - 代码安全扫描
  - name: sast-scan
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: sonarqube-sast-scan
    params:
    - name: sonar-project-key
      value: $(params.sonar-project-key)
    - name: sonar-quality-gate
      value: "true"
    workspaces:
    - name: source
      workspace: source
    - name: sonar-token
      workspace: sonar-token
  
  # 2.2 SCA - 依赖漏洞扫描
  - name: sca-scan
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: dependency-check-scan
    params:
    - name: project-name
      value: $(params.app-name)
    - name: fail-on-cvss
      value: "7"
    workspaces:
    - name: source
      workspace: source
    - name: reports
      workspace: security-reports
    - name: dependency-check-db
      workspace: dependency-check-db
  
  # ========== 阶段3: 构建与测试 ==========
  - name: unit-test
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-test
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
  
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    - sast-scan
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "$(params.image-registry)/$(params.app-name):$(params.git-revision)"
    workspaces:
    - name: source
      workspace: source
    - name: dockerconfig
      workspace: dockerconfig
  
  # ========== 阶段4: 镜像安全扫描 ==========
  - name: image-security-scan
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: trivy-image-security-scan
    params:
    - name: image
      value: "$(params.image-registry)/$(params.app-name):$(params.git-revision)"
    - name: severity
      value: "HIGH,CRITICAL"
    - name: exit-code
      value: "0"  # 不直接失败，由门禁统一判断
    workspaces:
    - name: reports
      workspace: security-reports
    - name: trivy-db
      workspace: trivy-db
  
  # ========== 阶段5: SBOM生成 ==========
  - name: generate-sbom
    runAfter:  # 依赖任务: 
    - image-security-scan
    taskRef:
      name: generate-sbom
    params:
    - name: image
      value: "$(params.image-registry)/$(params.app-name):$(params.git-revision)"
    - name: app-name
      value: $(params.app-name)
    - name: app-version
      value: $(params.git-revision)
    workspaces:
    - name: sbom
      workspace: sbom
  
  # ========== 阶段6: 安全门禁 ==========
  - name: security-gate
    runAfter:  # 依赖任务: 
    - sast-scan
    - sca-scan
    - image-security-scan
    taskRef:
      name: security-gate-check
    params:
    - name: sast-status
      value: "$(tasks.sast-scan.results.scan-status)"
    - name: sca-status
      value: "$(tasks.sca-scan.results.scan-result)"
    - name: image-scan-status
      value: "$(tasks.image-security-scan.results.scan-status)"
    - name: critical-vuln-count
      value: "$(tasks.image-security-scan.results.critical-count)"
    - name: high-vuln-count
      value: "$(tasks.image-security-scan.results.high-count)"
    - name: gate-policy
      value: $(params.gate-policy)
  
  # ========== 阶段7: 推广镜像 (仅通过门禁后) ==========
  - name: promote-image
    runAfter:  # 依赖任务: 
    - security-gate
    - generate-sbom
    when:
    - input: "$(tasks.security-gate.results.gate-result)"
      operator: in  # 条件判断: 包含
      values: ["PASS"]
    taskRef:
      name: crane-copy
    params:
    - name: source
      value: "$(params.image-registry)/$(params.app-name):$(params.git-revision)"
    - name: destination
      value: "$(params.image-registry)/prod/$(params.app-name):$(params.git-revision)"
  
  finally:  # 最终执行(无论成功失败)
  # ========== 最终: 安全报告 ==========
  - name: security-report
    taskRef:
      name: send-security-report
    params:
    - name: app-name
      value: $(params.app-name)
    - name: git-revision
      value: $(params.git-revision)
    - name: sast-status
      value: "$(tasks.sast-scan.results.scan-status)"
    - name: sca-status
      value: "$(tasks.sca-scan.results.scan-result)"
    - name: image-scan-status
      value: "$(tasks.image-security-scan.results.scan-status)"
    - name: gate-result
      value: "$(tasks.security-gate.results.gate-result)"
```

---

## 6. CKA/CKS 考点融入

### 6.1 CKA 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Pod | TaskRun（任务执行实例） 创建 Pod 执行 Task | 3.3 节 |
| PVC | Workspace 持久化存储 | 3.2 节 |
| ServiceAccount | Pipeline 执行身份 | 3.8 节 |
| RBAC | ServiceAccount 权限 | 3.8 节 |
| ConfigMap/Secret | 凭证管理 | 3.8 节 |

### 6.2 CKS 相关考点

| 考点 | 知识点 | 本模块覆盖 |
|------|--------|-----------|
| Secret 管理 | Harbor 凭证、Git SSH Key | 3.8 节 |
| RBAC | 最小权限 ServiceAccount | 3.8 节 |
| 安全上下文 | Pod securityContext | 3.3 节 |
| 网络策略 | Tekton 命名空间隔离 | 3.1 节 |
| 镜像安全 | 镜像签名验证 | 3.3 节 |

### 6.3 多环境推广流水线

> **多环境推广流水线** 实现应用从开发到生产的自动化部署，确保代码质量在每个环境都得到验证。

#### 架构图：多环境推广流水线

```
+================================================================+
|                    多环境推广流水线架构                          |
+================================================================+
|                                                                 |
|  Git Push                                                       |
|       |                                                         |
|       v                                                         |
|  +----------------+    +----------------+    +----------------+|
|  | 开发环境 (Dev) |--->| 测试环境 (Test)|--->| 预生产 (Staging)||
|  |                |    |                |    |                ||
|  | 自动部署       |    | 自动化测试     |    | 验证测试       ||
|  | 冒烟测试       |    | 集成测试       |    | 性能测试       ||
|  | 开发验证       |    | 安全扫描       |    | 回归测试       ||
|  +----------------+    +----------------+    +----------------+|
|         |                      |                      |         |
|         |                      |                      |         |
|         +----------------------+----------------------+         |
|                              |                                  |
|                              v                                  |
|                    +----------------+                          |
|                    | 生产环境 (Prod) |                          |
|                    |                |                          |
|                    | 人工审批       |                          |
|                    | 灰度发布       |                          |
|                    | 全量发布       |                          |
|                    +----------------+                          |
|                                                                 |
+================================================================+
```

#### 6.3.1 开发环境自动部署

```yaml
# 开发环境 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: dev-deploy-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: git-url
    type: string
  - name: git-revision
    type: string
  - name: app-name
    type: string
  - name: image-tag
    type: string
  workspaces:
  - name: source
  - name: maven-cache
  - name: dockerconfig
  - name: kubeconfig
  
  tasks:
  - name: git-clone
    taskRef:
      name: git-clone
      kind: ClusterTask
    params:
    - name: url
      value: $(params.git-url)
    - name: revision
      value: $(params.git-revision)
    workspaces:
    - name: output
      workspace: source
  
  - name: unit-test
    runAfter:  # 依赖任务: 
    - git-clone
    taskRef:
      name: maven-test
    workspaces:
    - name: source
      workspace: source
    - name: maven-cache
      workspace: maven-cache
  
  - name: build-image
    runAfter:  # 依赖任务: 
    - unit-test
    taskRef:
      name: kaniko-build-push
    params:
    - name: image
      value: "192.168.1.61/dev/$(params.app-name):$(params.image-tag)"
    workspaces:
    - name: source
      workspace: source
    - name: dockerconfig
      workspace: dockerconfig
  
  - name: deploy-to-dev
    runAfter:  # 依赖任务: 
    - build-image
    taskRef:
      name: k8s-deploy
    params:
    - name: namespace
      value: "dev"
    - name: app-name
      value: "$(params.app-name)"
    - name: image
      value: "192.168.1.61/dev/$(params.app-name):$(params.image-tag)"
    - name: configmap
      value: "$(params.app-name)-dev-config"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
  
  - name: smoke-test
    runAfter:  # 依赖任务: 
    - deploy-to-dev
    taskRef:
      name: http-smoke-test
    params:
    - name: url
      value: "http://$(params.app-name).dev.svc.cluster.local:8080/health"
    - name: timeout
      value: "60"
```

```yaml
# K8s 部署 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: k8s-deploy
  namespace: tekton-pipelines
spec:
  params:
  - name: namespace
    type: string
  - name: app-name
    type: string
  - name: image
    type: string
  - name: configmap
    type: string
    default: ""
  workspaces:
  - name: kubeconfig
    description: Kubernetes config file
  steps:
  - name: deploy
    image: 192.168.1.61/tekton/bitnami/kubectl:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      export KUBECONFIG=$(workspaces.kubeconfig.path)/config
      
      echo "Deploying to namespace: $(params.namespace)"
      echo "App: $(params.app-name)"
      echo "Image: $(params.image)"
      
      # 创建或更新 Deployment
      cat <<EOF | kubectl apply -f -
      apiVersion: apps/v1  # API 版本
      kind: Deployment  # K8s 部署
      metadata:
        name: $(params.app-name)
        namespace: $(params.namespace)
      spec:
        replicas: 1  # 副本数: 1
        selector:
          matchLabels:
            app: $(params.app-name)
        template:
          metadata:
            labels:
              app: $(params.app-name)
          spec:
            containers:
            - name: app
              image: $(params.image)
              ports:
              - containerPort: 8080
              envFrom:
              - configMapRef:
                  name: $(params.configmap)
                  optional: true
      EOF
      
      # 等待部署完成
      kubectl rollout status deployment/$(params.app-name) -n $(params.namespace) --timeout=300s
      
      echo "Deployment completed successfully!"
```

#### 6.3.2 测试环境自动化测试

```yaml
# 测试环境 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: test-env-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: image-tag
    type: string
  - name: test-suite
    type: string
    default: "integration"
  workspaces:
  - name: kubeconfig
  - name: test-results
  
  tasks:
  - name: deploy-to-test
    taskRef:
      name: k8s-deploy
    params:
    - name: namespace
      value: "test"
    - name: app-name
      value: "$(params.app-name)"
    - name: image
      value: "192.168.1.61/dev/$(params.app-name):$(params.image-tag)"
    - name: configmap
      value: "$(params.app-name)-test-config"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
  
  - name: integration-test
    runAfter:  # 依赖任务: 
    - deploy-to-test
    taskRef:
      name: run-test-suite
    params:
    - name: test-type
      value: "integration"
    - name: target-url
      value: "http://$(params.app-name).test.svc.cluster.local:8080"
    workspaces:
    - name: results
      workspace: test-results
  
  - name: security-scan
    runAfter:  # 依赖任务: 
    - deploy-to-test
    taskRef:
      name: trivy-image-scan
    params:
    - name: image
      value: "192.168.1.61/dev/$(params.app-name):$(params.image-tag)"
    - name: severity
      value: "HIGH,CRITICAL"
    - name: exit-code
      value: "0"  # 测试环境不阻塞
  
  - name: api-test
    runAfter:  # 依赖任务: 
    - integration-test
    taskRef:
      name: newman-postman
    params:
    - name: collection
      value: "tests/api/$(params.app-name)-api.json"
    - name: environment
      value: "tests/env/test.json"
```

```yaml
# 测试套件执行 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: run-test-suite
  namespace: tekton-pipelines
spec:
  params:
  - name: test-type
    type: string
  - name: target-url
    type: string
  - name: timeout
    type: string
    default: "300"
  workspaces:
  - name: results
  steps:
  - name: run-tests
    image: 192.168.1.61/tekton/maven:3.9-eclipse-temurin-17  # 镜像地址(Harbor)
    script: |
      #!/bin/bash
      set -e
      
      echo "Running $(params.test-type) tests against $(params.target-url)"
      
      # 执行测试
      mvn test \
        -Dtest.profile=$(params.test-type) \
        -Dtarget.url=$(params.target-url) \
        -Doutput.dir=$(workspaces.results.path) \
        -B
      
      echo "Tests completed. Results saved to $(workspaces.results.path)"
    resources:
      requests:
        cpu: 500m  # CPU 500m
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "2"
        memory: 2Gi  # 内存 2Gi
```

#### 6.3.3 预生产环境验证

```yaml
# 预生产环境 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: staging-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: image-tag
    type: string
  workspaces:
  - name: kubeconfig
  - name: perf-results
  
  tasks:
  - name: promote-to-staging
    taskRef:
      name: crane-copy
    params:
    - name: source
      value: "192.168.1.61/dev/$(params.app-name):$(params.image-tag)"
    - name: destination
      value: "192.168.1.61/staging/$(params.app-name):$(params.image-tag)"
  
  - name: deploy-to-staging
    runAfter:  # 依赖任务: 
    - promote-to-staging
    taskRef:
      name: k8s-deploy
    params:
    - name: namespace
      value: "staging"
    - name: app-name
      value: "$(params.app-name)"
    - name: image
      value: "192.168.1.61/staging/$(params.app-name):$(params.image-tag)"
    - name: configmap
      value: "$(params.app-name)-staging-config"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
  
  - name: performance-test
    runAfter:  # 依赖任务: 
    - deploy-to-staging
    taskRef:
      name: k6-load-test
    params:
    - name: script
      value: "tests/perf/$(params.app-name)-load.js"
    - name: duration
      value: "5m"
    - name: vus
      value: "100"
    workspaces:
    - name: results
      workspace: perf-results
  
  - name: regression-test
    runAfter:  # 依赖任务: 
    - deploy-to-staging
    taskRef:
      name: run-test-suite
    params:
    - name: test-type
      value: "regression"
    - name: target-url
      value: "http://$(params.app-name).staging.svc.cluster.local:8080"
```

```yaml
# K6 性能测试 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: k6-load-test
  namespace: tekton-pipelines
spec:
  params:
  - name: script
    type: string
  - name: duration
    type: string
    default: "5m"
  - name: vus
    type: string
    default: "50"
  workspaces:
  - name: results
  steps:
  - name: run-k6
    image: 192.168.1.61/tekton/grafana/k6:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      echo "Running performance test..."
      echo "Duration: $(params.duration)"
      echo "VUs: $(params.vus)"
      
      k6 run \
        --duration $(params.duration) \
        --vus $(params.vus) \
        --out json=$(workspaces.results.path)/k6-results.json \
        $(params.script)
      
      echo "Performance test completed!"
    resources:
      requests:
        cpu: "1"
        memory: 1Gi  # 内存 1Gi
      limits:
        cpu: "4"
        memory: 4Gi  # 内存 4Gi
```

#### 6.3.4 生产环境审批发布

```yaml
# 生产环境 Pipeline（带人工审批）
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: production-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: image-tag
    type: string
  - name: approver
    type: string
    description: Email of the approver
  workspaces:
  - name: kubeconfig
  
  tasks:
  - name: pre-deploy-check
    taskRef:
      name: production-readiness-check
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: image-tag
      value: "$(params.image-tag)"
  
  - name: request-approval
    runAfter:  # 依赖任务: 
    - pre-deploy-check
    taskRef:
      name: send-approval-request
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: image-tag
      value: "$(params.image-tag)"
    - name: approver
      value: "$(params.approver)"
  
  # 等待审批（通过外部系统或手动触发）
  - name: wait-for-approval
    runAfter:  # 依赖任务: 
    - request-approval
    taskRef:
      name: wait-for-external-signal
    params:
    - name: timeout
      value: "24h"
  
  - name: deploy-to-prod
    runAfter:  # 依赖任务: 
    - wait-for-approval
    taskRef:
      name: k8s-canary-deploy
    params:
    - name: namespace
      value: "production"
    - name: app-name
      value: "$(params.app-name)"
    - name: image
      value: "192.168.1.61/prod/$(params.app-name):$(params.image-tag)"
    - name: canary-percentage
      value: "10"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
  
  - name: canary-analysis
    runAfter:  # 依赖任务: 
    - deploy-to-prod
    taskRef:
      name: canary-health-check
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: duration
      value: "10m"
  
  - name: full-rollout
    runAfter:  # 依赖任务: 
    - canary-analysis
    when:
    - input: "$(tasks.canary-analysis.results.status)"
      operator: in  # 条件判断: 包含
      values: ["healthy"]
    taskRef:
      name: k8s-promote-canary
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: namespace
      value: "production"
```

```yaml
# 金丝雀部署 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: k8s-canary-deploy
  namespace: tekton-pipelines
spec:
  params:
  - name: namespace
    type: string
  - name: app-name
    type: string
  - name: image
    type: string
  - name: canary-percentage
    type: string
    default: "10"
  workspaces:
  - name: kubeconfig
  steps:
  - name: canary-deploy
    image: 192.168.1.61/tekton/bitnami/kubectl:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      export KUBECONFIG=$(workspaces.kubeconfig.path)/config
      
      echo "Starting canary deployment..."
      echo "Canary percentage: $(params.canary-percentage)%"
      
      # 创建 Canary Deployment
      cat <<EOF | kubectl apply -f -
      apiVersion: apps/v1  # API 版本
      kind: Deployment  # K8s 部署
      metadata:
        name: $(params.app-name)-canary
        namespace: $(params.namespace)
      spec:
        replicas: 1  # 副本数: 1
        selector:
          matchLabels:
            app: $(params.app-name)
            version: canary
        template:
          metadata:
            labels:
              app: $(params.app-name)
              version: canary
          spec:
            containers:
            - name: app
              image: $(params.image)
              ports:
              - containerPort: 8080
      EOF
      
      # 更新 Service 权重（需要 Service Mesh 或 Ingress Controller 支持）
      echo "Canary deployment created. Traffic split: $(params.canary-percentage)%"
      
      # 等待 Canary Pod 就绪
      kubectl rollout status deployment/$(params.app-name)-canary -n $(params.namespace) --timeout=300s
```

#### 6.3.5 环境间配置差异管理(ConfigMap/Secret)

```yaml
# 环境配置管理 Pipeline
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: config-sync-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: source-env
    type: string
    default: "dev"
  - name: target-env
    type: string
  workspaces:
  - name: source
  - name: kubeconfig
  
  tasks:
  - name: validate-config
    taskRef:
      name: config-validator
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: environment
      value: "$(params.target-env)"
    workspaces:
    - name: source
      workspace: source
  
  - name: sync-configmap
    runAfter:  # 依赖任务: 
    - validate-config
    taskRef:
      name: k8s-config-sync
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: source-namespace
      value: "$(params.source-env)"
    - name: target-namespace
      value: "$(params.target-env)"
    - name: resource-type
      value: "configmap"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
  
  - name: sync-secret
    runAfter:  # 依赖任务: 
    - validate-config
    taskRef:
      name: k8s-config-sync
    params:
    - name: app-name
      value: "$(params.app-name)"
    - name: source-namespace
      value: "$(params.source-env)"
    - name: target-namespace
      value: "$(params.target-env)"
    - name: resource-type
      value: "secret"
    workspaces:
    - name: kubeconfig
      workspace: kubeconfig
```

```yaml
# 配置验证 Task（防止敏感信息泄露）
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: config-validator
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: environment
    type: string
  workspaces:
  - name: source
  steps:
  - name: validate
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      CONFIG_DIR="$(workspaces.source.path)/config/$(params.environment)"
      
      echo "Validating configuration for $(params.app-name) in $(params.environment)"
      
      # 检查配置文件是否存在
      if [ ! -f "$CONFIG_DIR/configmap.yaml" ]; then
        echo "ERROR: ConfigMap file not found: $CONFIG_DIR/configmap.yaml"
        exit 1
      fi
      
      # 检查是否包含敏感信息（简单检查）
      if grep -iE "password|secret|token|key" "$CONFIG_DIR/configmap.yaml"; then
        echo "WARNING: Potential sensitive data in ConfigMap!"
        echo "Sensitive data should be in Secrets, not ConfigMaps."
        exit 1
      fi
      
      # 验证 Secret 引用正确
      if [ -f "$CONFIG_DIR/secret.yaml" ]; then
        echo "Secret file found. Validating..."
        # 检查 Secret 是否使用 base64 编码
        if grep -q "stringData:" "$CONFIG_DIR/secret.yaml"; then
          echo "WARNING: Secret uses stringData. Ensure it's not committed to Git."
        fi
      fi
      
      echo "Configuration validation passed!"
```

```yaml
# 配置同步 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: k8s-config-sync
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: source-namespace
    type: string
  - name: target-namespace
    type: string
  - name: resource-type
    type: string
  workspaces:
  - name: kubeconfig
  steps:
  - name: sync
    image: 192.168.1.61/tekton/bitnami/kubectl:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      export KUBECONFIG=$(workspaces.kubeconfig.path)/config
      
      RESOURCE="$(params.resource-type)"
      APP="$(params.app-name)"
      SOURCE_NS="$(params.source-namespace)"
      TARGET_NS="$(params.target-namespace)"
      
      echo "Syncing $RESOURCE for $APP from $SOURCE_NS to $TARGET_NS"
      
      if [ "$RESOURCE" = "configmap" ]; then
        # 导出 ConfigMap
        kubectl get configmap "${APP}-config" -n "$SOURCE_NS" -o yaml | \
          sed "s/namespace: $SOURCE_NS/namespace: $TARGET_NS/" | \
          kubectl apply -f -
      elif [ "$RESOURCE" = "secret" ]; then
        # 导出 Secret（注意：需要特殊处理）
        kubectl get secret "${APP}-secret" -n "$SOURCE_NS" -o yaml | \
          sed "s/namespace: $SOURCE_NS/namespace: $TARGET_NS/" | \
          kubectl apply -f -
      fi
      
      echo "$RESOURCE synced successfully!"
```

```yaml
# 环境差异对比 Task
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: env-diff-checker
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: env1
    type: string
  - name: env2
    type: string
  workspaces:
  - name: kubeconfig
  steps:
  - name: compare
    image: 192.168.1.61/tekton/bitnami/kubectl:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      
      export KUBECONFIG=$(workspaces.kubeconfig.path)/config
      
      APP="$(params.app-name)"
      ENV1="$(params.env1)"
      ENV2="$(params.env2)"
      
      echo "Comparing configuration between $ENV1 and $ENV2"
      
      # 对比 ConfigMap
      echo "=== ConfigMap Differences ==="
      kubectl get configmap "${APP}-config" -n "$ENV1" -o json | jq '.data' > /tmp/env1-config.json
      kubectl get configmap "${APP}-config" -n "$ENV2" -o json | jq '.data' > /tmp/env2-config.json
      
      if diff /tmp/env1-config.json /tmp/env2-config.json; then
        echo "ConfigMaps are identical"
      else
        echo "WARNING: ConfigMaps differ between environments!"
        diff /tmp/env1-config.json /tmp/env2-config.json || true
      fi
      
      # 对比环境变量（从 Deployment 中提取）
      echo "=== Environment Variable Differences ==="
      kubectl get deployment "$APP" -n "$ENV1" -o json | jq '.spec.template.spec.containers[0].env' > /tmp/env1-env.json
      kubectl get deployment "$APP" -n "$ENV2" -o json | jq '.spec.template.spec.containers[0].env' > /tmp/env2-env.json
      
      diff /tmp/env1-env.json /tmp/env2-env.json || echo "Environment variables differ (this may be expected)"
```

---

## 7. 高频面试题

### Q1: Tekton 的核心组件有哪些？它们之间如何协作？（难度：中等）

**答案：** Tekton 的核心组件包括：**Task** 是最小执行单元，定义一组 Steps（容器），每个 Step 在同一个 Pod 中按顺序执行，共享 Workspace。**Pipeline** 定义多个 Task 的编排关系（串行、并行、条件执行），通过 params 和 results 在 Task 间传递数据。**TaskRun** 是 Task 的执行实例，创建一个 Pod 执行 Task 中的所有 Steps。**PipelineRun** 是 Pipeline 的执行实例，为每个 Task 创建 TaskRun。**Workspace** 是 Task 间共享数据的机制，支持 emptyDir、PVC、ConfigMap、Secret 等类型。**Trigger** 组件（EventListener、TriggerBinding、TriggerTemplate）负责接收外部事件（如 Git Webhook）并自动创建 PipelineRun。协作流程：EventListener 接收 HTTP 事件 -> TriggerBinding 从事件中提取参数 -> TriggerTemplate 使用参数创建 PipelineRun -> PipelineRun 为每个 Task 创建 TaskRun -> TaskRun 创建 Pod 执行 Steps。

### Q2: Tekton Pipeline 中如何实现 Task 间的数据传递？（难度：中等）

**答案：** Tekton Task 间数据传递有两种方式：**Workspace** 和 **Results/Params**。Workspace 是文件级别的数据共享，多个 Task 可以挂载同一个 PVC 作为 Workspace，在一个 Task 中写入文件，另一个 Task 中读取。适合传递源码、构建产物等大量数据。Results/Params 是变量级别的数据传递，Task 可以通过 `results` 字段输出字符串结果（如镜像 digest、测试报告路径），Pipeline 中通过 `$(tasks.<task-name>.results.<result-name>)` 引用该结果并传递给下游 Task 的 params。适合传递少量结构化数据。注意事项：Results 有大小限制（通常 4KB）；Workspace 使用 PVC 时需要注意读写顺序（串行 Task 可以共享 PVC，并行 Task 需要使用不同的 subPath 或 readOnly 模式）。推荐组合使用：大文件用 Workspace，小变量用 Results/Params。

### Q3: Tekton Trigger 的工作流程是什么？（难度：中等）

**答案：** Tekton Trigger 的工作流程：1）**EventListener** 是一个 HTTP 服务（K8s Service + Deployment），监听指定端口接收外部事件（如 Git Webhook、自定义 HTTP 请求）；2）**Interceptor**（可选）在 TriggerBinding 之前对事件进行预处理（如过滤、验证、修改）；3）**TriggerBinding** 从事件 payload 中提取参数（如 Git commit SHA、分支名、仓库名），绑定到模板参数；4）**TriggerTemplate** 定义 PipelineRun 的 YAML 模板，使用 Binding 提取的参数填充模板；5）EventListener 调用 K8s API 创建 PipelineRun。一个 EventListener 可以配置多个 Trigger，每个 Trigger 可以有不同的 Binding 和 Template。Trigger 支持多种 Interceptor：GitHub/Gitea（自托管 Git 服务） Interceptor（验证签名）、GitLab Interceptor、CEL Interceptor（通用表达式过滤）、Webhook Interceptor（调用外部服务验证）。

### Q4: Tekton 与 ArgoCD 如何衔接实现完整的 CI/CD？（难度：困难）

**答案：** Tekton（CI）与 ArgoCD（CD）通过 Git 仓库实现解耦衔接。完整流程：1）开发者推送代码到应用 Git 仓库；2）Git Webhook 触发 Tekton Pipeline；3）Tekton Pipeline 执行 CI 流程：Git Clone -> 单元测试 -> 构建镜像 -> 推送到 Harbor；4）Tekton 的最后一步更新 Helm values Git 仓库中的 image.tag（将新镜像版本号写入 values.yaml 并提交）；5）ArgoCD Watch Helm values Git 仓库，检测到 values.yaml 变更；6）ArgoCD 自动 Sync 新配置到 K8s 集群（使用新的 image.tag 拉取新镜像）。这种衔接方式的优势：CI 和 CD 完全解耦，可以独立升级和替换；所有变更都通过 Git 记录，可审计、可回滚；ArgoCD 的 Self-Heal（自动修复） 确保集群状态与 Git 一致。关键点：Tekton 需要有权限 push 到 Helm values Git 仓库；ArgoCD 的 Application source 指向 Helm values Git 仓库。

### Q5: Tekton 的 Workspace 有哪些类型？如何选择？（难度：中等）

**答案：** Tekton Workspace 支持以下类型：1）**emptyDir**：临时目录，TaskRun 结束后数据丢失，适合 Task 内部 Steps 间共享临时数据；2）**configMap**：将 K8s ConfigMap 挂载为 Workspace，只读，适合配置文件；3）**secret**：将 K8s Secret 挂载为 Workspace，只读，适合敏感信息（如凭证文件）；4）**persistentVolumeClaim**：使用已有 PVC，数据持久化，适合跨 TaskRun 共享数据（如 Maven 缓存、Docker 构建缓存）；5）**volumeClaimTemplate**：动态创建 PVC，Tekton 自动管理生命周期，适合每次 PipelineRun 需要独立存储的场景。选择建议：源码和构建产物使用 PVC 或 volumeClaimTemplate；Maven/npm 依赖缓存使用 PVC（跨 PipelineRun 复用）；配置文件使用 configMap；凭证使用 secret；临时文件使用 emptyDir。生产环境推荐使用 PVC 作为 Maven/Docker 缓存，显著加速构建。

### Q6: 如何优化 Tekton Pipeline 的执行速度？（难度：中等）

**答案：** Tekton Pipeline 性能优化的关键点：1）**依赖缓存**：使用 PVC 缓存 Maven/Gradle/npm 依赖，避免每次构建重新下载；2）**Docker Layer 缓存**：使用 BuildKit 或 Kaniko 的缓存功能，避免重复构建相同的 Docker Layer；3）**并行执行**：将独立的 Task（如 lint、unit-test）配置为并行执行，缩短总耗时；4）**小镜像**：使用精简的基础镜像（如 Alpine、distroless），减少镜像拉取时间；5）**Workspace 复用**：使用 PVC 而非 emptyDir，避免每次 TaskRun 重新克隆 Git 仓库；6）**资源合理分配**：为 CPU 密集型 Task（编译）分配更多 CPU，IO 密集型 Task（测试）分配更多内存；7）**条件执行**：使用 when 条件跳过不必要的 Task（如文档构建在非 main 分支跳过）；8）**使用 Kaniko**：替代 Docker-in-Docker，无需特权模式，安全性更好且性能更优。推荐使用 Kaniko + PVC 缓存的组合方案。

### Q7: Tekton 的安全最佳实践是什么？（难度：中等）

**答案：** Tekton 安全最佳实践：1）**最小权限 ServiceAccount**：每个 Pipeline 使用专用的 ServiceAccount，只授予必要的权限（RBAC），不应使用 cluster-admin；2）**Secret 管理**：Git 凭证和 Registry 凭证存储在 K8s Secret 中，通过 Workspace 挂载给 Task，不应硬编码在 Pipeline YAML 中；3）**避免特权模式**：Docker Build Task 使用 Kaniko 替代 Docker-in-Docker，避免 privileged: true；4）**网络隔离**：Tekton 命名空间使用 NetworkPolicy（网络策略） 限制 Egress（只允许访问 Git 仓库、Harbor、Maven Central）；5）**镜像安全**：所有 Task 使用的镜像应来自可信仓库，启用镜像签名验证；6）**Pipeline 参数校验**：使用 CEL Interceptor 验证 Webhook 请求的合法性；7）**审计日志**：启用 K8s API Server 审计日志，记录所有 PipelineRun 的创建和修改；8）**资源限制**：为所有 Task 设置 resources.requests 和 resources.limits，防止资源耗尽。

### Q8: Tekton Pipeline 中如何处理错误和重试？（难度：中等）

**答案：** Tekton 的错误处理和重试机制：1）**Step 级别重试**：在 Step 中配置 `retries` 字段，Step 失败后自动重试指定次数；2）**Task 级别重试**：在 PipelineRun 中配置 `retries` 字段，TaskRun 失败后自动重试；3）**finally**：Pipeline 中定义 finally Tasks，无论 Pipeline 成功或失败都会执行（适合清理和通知）；4）**when 条件**：使用 when 条件控制 Task 是否执行，避免不必要的失败；5）**onError**：Step 中配置 `onError` 字段（continue/stopAndFail），控制 Step 失败后的行为。重试配置示例：`retries: 3` 表示最多重试 3 次。注意事项：重试的 TaskRun 会创建新的 Pod，Workspace 数据需要使用 PVC 才能在重试间保留；finally Tasks 不能有 runAfter 或 when 条件；Step 的 onError: continue 不会导致 Task 失败，后续 Step 仍会执行。推荐：关键步骤（如推送镜像）配置重试，非关键步骤（如通知）使用 onError: continue。

### Q9: 如何在 Tekton 中实现多服务并行构建？（难度：困难）

**答案：** 多服务并行构建有几种方案：1）**多个 PipelineRun**：为每个服务创建独立的 PipelineRun，使用 Tekton Trigger 或脚本批量触发，适合服务间无依赖的场景；2）**Pipeline 内并行 Tasks**：在单个 Pipeline 中定义多个 Task，不设置 runAfter，Tekton 自动并行执行，适合少量服务的场景；3）**PipelineRef 动态生成**：使用 TriggerTemplate 批量创建多个 PipelineRun，每个服务一个 PipelineRun，适合大量服务的场景。推荐方案三，具体实现：EventListener 接收 Git Push 事件 -> CEL Interceptor 判断变更的目录/文件 -> 根据变更范围动态生成对应服务的 PipelineRun。例如：修改了 order-service 目录，只触发 order-service 的 PipelineRun。这种方案实现了按需构建，避免无关服务的无效构建。配合 ArgoCD 的 ApplicationSet（应用集），可以实现完整的多服务 CI/CD 自动化。

### Q10: Tekton Dashboard 提供了哪些功能？（难度：简单）

**答案：** Tekton Dashboard 是 Tekton 的 Web UI，提供以下功能：1）**Pipeline 列表**：查看所有 Pipeline 和 PipelineRun 的状态、耗时、创建时间；2）**PipelineRun 详情**：查看 PipelineRun 的执行拓扑图（DAG），展示 Task 间的依赖关系和执行状态；3）**TaskRun 详情**：查看 TaskRun 的 Steps 列表、日志、资源消耗、耗时；4）**日志查看**：实时查看 Step 的输出日志，支持全文搜索；5）**CRD 管理**：查看和编辑 Pipeline、Task、Trigger 等 CRD；6）**集群信息**：查看 Tekton 安装的组件和版本。Dashboard 的局限性：功能相对基础，不如 Jenkins 或 GitLab CI 的 UI 丰富；不支持直接创建/编辑 Pipeline（需要通过 kubectl 或 tkn CLI）；不支持 Pipeline 可视化编辑器。建议：日常使用 tkn CLI 进行操作，Dashboard 用于查看和监控。

### Q11: Tekton 如何实现构建缓存？（难度：中等）

**答案：** Tekton 构建缓存从三个层面实现：1）**依赖缓存**：Maven/Gradle/npm 依赖缓存到 PVC，后续构建直接从缓存读取。配置方式：在 Task 中将 Maven 本地仓库路径指向 PVC 挂载路径（`-Dmaven.repo.local=/path/to/cache/.m2/repository`）。2）**Docker Layer 缓存**：使用 Kaniko 的 `--cache=true` 和 `--cache-repo` 参数，将 Docker Layer 缓存推送到 Registry。每次构建时 Kaniko 先从缓存仓库拉取已有的 Layer，只构建变更的 Layer。3）**Git 浅克隆**：使用 `git clone --depth=1` 只克隆最近一次提交，减少克隆时间。Tekton 的 git-clone ClusterTask（集群级任务） 支持 `submodules` 和 `depth` 参数。缓存效果：Maven 缓存可以减少 60-80% 的依赖下载时间；Docker Layer 缓存可以减少 50-90% 的构建时间（取决于变更范围）。推荐使用 PVC + Kaniko Cache 的组合方案。

### Q12: 如何监控 Tekton Pipeline 的执行状态？（难度：中等）

**答案：** Tekton 监控的几个层面：1）**Tekton Metrics**：Tekton Controller 内置 Prometheus metrics 端点，关键指标包括 `tekton_taskrun_duration_seconds`（TaskRun 耗时）、`tekton_taskrun_count`（TaskRun 总数，按状态分类）、`tekton_pipelinerun_duration_seconds`（PipelineRun 耗时）。2）**Grafana（可视化面板） Dashboard**：导入 Tekton 官方 Grafana Dashboard（Dashboard ID 14675），展示 Pipeline 执行趋势、成功率、耗时分布。3）**告警规则**：配置 Prometheus 告警：PipelineRun 失败、TaskRun 超时、PipelineRun 执行时间超过阈值。4）**通知集成**：在 Pipeline 的 finally 中添加通知 Task，构建成功/失败时发送 Slack/钉钉/邮件通知。5）**tkn CLI**：`tkn pipelinerun list` 查看最近执行记录，`tkn pipelinerun describe` 查看详情。6）**Tekton Dashboard**：Web UI 查看实时执行状态和日志。推荐：Prometheus + Grafana + 通知 Task 的组合方案。

### Q13: Tekton 中如何使用 Kaniko 替代 Docker-in-Docker？（难度：中等）

**答案：** Kaniko 是 Google 开源的容器镜像构建工具，无需 Docker Daemon，直接在用户空间执行 Dockerfile 构建并推送到 Registry。优势：不需要特权模式（privileged: true），安全性更好；不需要 Docker-in-Docker，避免了 Docker Socket 挂载的安全风险；支持缓存。使用方式：创建 Kaniko Task，使用 `gcr.io/kaniko-project/executor:latest` 镜像，通过环境变量配置 Registry 认证。关键参数：`--destination`（目标镜像地址）、`--context`（构建上下文）、`--dockerfile`（Dockerfile 路径）、`--cache=true`（启用缓存）、`--cache-repo`（缓存仓库地址）。认证方式：在 Task 中挂载包含 `/config.json` 的 Secret 到 `/kaniko/.docker/config.json`。Kaniko 的局限性：不支持多阶段构建中的 COPY --from=（需要额外配置）；不支持 Docker 的所有 BuildKit 特性。

### Q14: 如何实现 Tekton Pipeline 的版本管理？（难度：困难）

**答案：** Tekton Pipeline 的版本管理有以下方案：1）**GitOps 管理 Pipeline**：将 Pipeline YAML 存储在 Git 仓库中，通过 ArgoCD 或 kubectl apply 管理。每次修改 Pipeline 提交到 Git，ArgoCD 自动同步到集群。2）**Helm Chart 管理**：将 Pipeline 封装为 Helm Chart，通过 Helm 部署。适合需要参数化配置的场景。3）**Tekton Hub**：使用 Tekton Hub 共享和版本化 Task/Pipeline，通过 `tkn hub install` 安装指定版本。4）**分支策略**：不同环境使用不同的 Pipeline 版本（dev 分支使用最新版，main 分支使用稳定版）。推荐方案一（GitOps 管理 Pipeline），将 Pipeline YAML 与应用代码放在同一个 Git 仓库（或独立的 infra 仓库），通过 ArgoCD 管理。这样 Pipeline 的变更也享受 Git 的版本控制、Code Review、审计等能力。注意事项：修改 Pipeline 后需要重新创建 PipelineRun 才能使用新版本（已运行的 PipelineRun 不受影响）。

### Q15: Tekton 与 Jenkins 相比有什么优势和劣势？（难度：中等）

**答案：** Tekton 的优势：1）**K8s 原生**：Tekton 是 K8s CRD，天然集成 K8s 生态，不需要独立部署和维护 Jenkins 服务器；2）**声明式**：Pipeline 以 YAML 定义，版本化管理，可 Code Review；3）**云原生**：每个 Step 运行在独立容器中，资源隔离好，弹性伸缩；4）**轻量级**：不需要 Jenkins Agent，直接使用 K8s 调度；5）**CNCF 标准**：CNCF 毕业项目，与 ArgoCD 等 CNCF 项目天然互补。Tekton 的劣势：1）**UI 功能弱**：Dashboard 功能远不如 Jenkins Blue Ocean；2）**插件生态**：Task Catalog 不如 Jenkins 插件生态丰富；3）**学习曲线**：需要理解 K8s 概念（Pod、PVC、ServiceAccount）；4）**调试困难**：Step 失败后需要查看 Pod 日志，不如 Jenkins 交互式调试方便；5）**复杂流程**：复杂条件逻辑（如审批、人工干预）不如 Jenkins Pipeline（Groovy）灵活。选择建议：K8s 原生环境优先选 Tekton，已有 Jenkins 且团队熟悉则继续使用 Jenkins。

---

## 8. 故障排查案例

### 案例 1：PipelineRun 卡在 Pending 状态

**现象：**
```
tkn pipelinerun describe ci-order-service-xxx -n tekton-pipelines
# Status: Pending
# No TaskRuns created
```

**排查步骤：**
```bash
# 1. 检查 Tekton Controller 日志
kubectl logs -n tekton-pipelines deploy/tekton-pipelines-controller --tail=50
# 发现：Failed to create TaskRun: PVC "ci-workspace" not found

# 2. 检查 PVC
kubectl get pvc -n tekton-pipelines
# 发现：ci-workspace PVC 不存在

# 3. 检查 StorageClass
kubectl get storageclass
# 发现：local-path StorageClass 存在
```

**解决方案：**
```bash
# 创建缺失的 PVC
kubectl apply -f - <<EOF
apiVersion: v1  # API 版本
kind: PersistentVolumeClaim  # PVC 持久卷声明
metadata:
  name: ci-workspace
  namespace: tekton-pipelines
spec:
  accessModes:
  - ReadWriteOnce  # 单节点读写
  storageClassName: local-path  # 存储类名称
  resources:
    requests:
      storage: 10Gi
EOF

# 删除卡住的 PipelineRun 并重新创建
tkn pipelinerun cancel ci-order-service-xxx -n tekton-pipelines
```

### 案例 2：TaskRun 执行失败（Maven 依赖下载失败）

**现象：**
```
tkn taskrun logs <taskrun-name> -n tekton-pipelines
# [ERROR] Failed to execute goal on project order-service: Could not resolve dependencies
# Connection timed out
```

**排查步骤：**
```bash
# 1. 检查网络连通性（离线环境应使用 Nexus 私服）
kubectl exec -it <taskrun-pod> -n tekton-pipelines -- curl -I http://192.168.1.61:8081/repository/maven-public/
# 发现：Connection timed out（Nexus 未部署或网络不通）

# 2. 检查 Maven settings.xml 是否挂载
kubectl get configmap maven-settings -n tekton-pipelines -o yaml
# 发现：ConfigMap 不存在或未在 Task 中引用

# 3. 检查 Maven 缓存 PVC
kubectl get pvc maven-cache -n tekton-pipelines
# 发现：PVC 存在但为空（首次构建无缓存）
```

**解决方案：**
```bash
# 方案一（推荐）：配置 Nexus 私服
# 1. 部署 Nexus 到 192.168.1.61:8081（见第10节）
# 2. 创建 maven-settings ConfigMap（见 3.5 节）
# 3. 在 Pipeline 的 unit-test Task 中挂载 maven-settings workspace

# 方案二：使用离线 Maven 本地缓存
# 在有外网的机器上预下载依赖：
# mvn clean package -Dmaven.repo.local=/tmp/maven-cache
# 打包传输到离线环境，挂载到 maven-cache PVC

# 方案三：检查 Nexus 连通性（如果已部署）
# 确认 Nexus 服务正常运行且网络可达
curl -s http://192.168.1.61:8081/service/rest/v1/status
```

### 案例 3：Kaniko Build 失败（认证或网络问题）

**现象：**
```
tkn taskrun logs <taskrun-name> -n tekton-pipelines
# error pushing image: denied: requested access to the resource is denied
# 或
# error pushing image: failed to resolve source
```

**排查步骤：**
```bash
# 1. 检查 Harbor Secret
kubectl get secret harbor-secret -n tekton-pipelines -o yaml
# 发现：Secret 存在

# 2. 检查 Secret 挂载路径（Kaniko 使用 /kaniko/.docker/config.json）
kubectl get taskrun <taskrun-name> -n tekton-pipelines -o yaml | grep -A 10 "dockerconfig"
# 发现：Secret 已挂载到 /kaniko/.docker

# 3. 检查 Secret 内容
kubectl get secret harbor-secret -n tekton-pipelines -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
# 发现：config.json 格式错误

# 4. 检查 Harbor 连通性（从 Worker 节点）
curl -sv http://192.168.1.61/v2/ 2>&1 | head -20
# 发现：HTTP Harbor 可达
```

**解决方案：**
```bash
# 重新创建 Harbor Secret（确保格式正确）
kubectl delete secret harbor-secret -n tekton-pipelines

kubectl create secret docker-registry harbor-secret \
  --namespace tekton-pipelines \
  --docker-server=192.168.1.61:80 \
  --docker-username=admin \
  --docker-password=Harbor12345

# 验证 Secret
kubectl get secret harbor-secret -n tekton-pipelines -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .

# 注意：Kaniko Task 中 dockerconfig workspace 的 mountPath 必须为 /kaniko/.docker
# Harbor 使用 HTTP 时需要添加 --skip-tls-verify 参数（已在 Task 中配置）
```

### 案例 4：Git Clone 失败（SSH Key 问题）

**现象：**
```
tkn taskrun logs <taskrun-name> -n tekton-pipelines
# git@192.168.1.61: Permission denied (publickey)
# fatal: Could not read from remote repository
```

**排查步骤：**
```bash
# 1. 检查 Git Secret
kubectl get secret git-secret -n tekton-pipelines -o yaml
# 发现：Secret 存在

# 2. 检查 SSH Key 格式
kubectl get secret git-secret -n tekton-pipelines -o jsonpath='{.data.ssh-key}' | base64 -d | head -1
# 发现：SSH Key 格式正确（以 -----BEGIN 开头）

# 3. 检查 ServiceAccount 关联
kubectl get sa tekton-ci-sa -n tekton-pipelines -o yaml | grep secrets
# 发现：git-secret 已关联到 ServiceAccount

# 4. 检查 Git 仓库 SSH Key 配置
# 发现：Gitea 仓库未添加此 SSH Key 的公钥
```

**解决方案：**
```bash
# 方案一：将公钥添加到 Gitea 仓库的 Deploy Keys
kubectl get secret git-secret -n tekton-pipelines -o jsonpath='{.data.ssh-key}' | base64 -d
# 将公钥添加到 Gitea: 仓库 -> Settings -> Deploy Keys

# 方案二：使用 HTTPS + Token 替代 SSH
# 创建新的 Secret 使用 HTTPS 方式
kubectl create secret generic git-https-secret \
  --namespace tekton-pipelines \
  --from-literal=username=admin \
  --from-literal=password=gitea-token-example
```

### 案例 5：PipelineRun 执行超时

**现象：**
```
tkn pipelinerun describe ci-order-service-xxx -n tekton-pipelines
# Status: Failed (PipelineRunTimeout)
# Message: PipelineRun "ci-order-service-xxx" failed to finish within "1h0m0s"
```

**排查步骤：**
```bash
# 1. 检查 PipelineRun 的 timeout 配置
tkn pipelinerun describe ci-order-service-xxx -n tekton-pipelines | grep -i timeout
# 发现：timeout: 1h0m0s（默认 1 小时）

# 2. 检查各 Task 的耗时
tkn pipelinerun describe ci-order-service-xxx -n tekton-pipelines
# 发现：build-image Task 耗时 45 分钟（Kaniko 构建慢）

# 3. 检查 Kaniko 构建日志
# 发现：每次构建都重新下载所有依赖（无缓存）
```

**解决方案：**
```bash
# 方案一：增大 PipelineRun 超时时间
# 在 PipelineRun 中添加：
# spec:
#   timeout: 2h0m0s

# 方案二：启用 Kaniko 缓存
# 使用 Kaniko 的 --cache=true --cache-repo 参数

# 方案三：优化 Dockerfile（减少 Layer 数量、多阶段构建）
# 方案四：使用 Maven 缓存 PVC 加速依赖下载
```

### 案例 6：Update Helm Values Task 失败（Git Push 冲突）

**现象：**
```
tkn taskrun logs <taskrun-name> -n tekton-pipelines
# error: failed to push some refs to 'http://192.168.1.61:3000/demo/demo-manifests.git'
# hint: Updates were rejected because the tip of your current branch is behind
```

**排查步骤：**
```bash
# 1. 分析原因
# 多个 PipelineRun 同时执行 update-helm-values Task
# 都 clone 了同一个 Git 仓库，修改后 push 时发生冲突

# 2. 检查并发 PipelineRun
tkn pipelinerun list -n tekton-pipelines
# 发现：多个 PipelineRun 同时运行
```

**解决方案：**
```bash
# 方案一：使用 Git Pull --rebase 解决冲突
# 在 update-helm-values Task 中修改：
# git pull --rebase origin main
# git push origin main

# 方案二：使用 Git Lock 机制
# 在 push 前获取 Git Lock，push 后释放

# 方案三：串行化 PipelineRun（使用 Tekton 的 max-parallel-runs）
# 在 PipelineRun 中设置：
# spec:
#   pipelineSpec:
#     finally: [...]
#   workspaces: [...]

# 方案四：使用 Git API 直接更新文件（如 Gitea Contents API）
# 避免本地 clone/push 的冲突问题
```

### 案例 7：EventListener 无法接收 Webhook

**现象：**
```
Git Webhook 配置了 http://192.168.1.54:32090，但推送代码后 Tekton 没有创建 PipelineRun。
```

**排查步骤：**
```bash
# 1. 检查 EventListener Pod
kubectl get pods -n tekton-pipelines -l eventlistener=git-webhook-listener
# 发现：Pod Running

# 2. 检查 Service
kubectl get svc -n tekton-pipelines el-git-webhook-listener
# 发现：NodePort 32090 已配置

# 3. 手动测试 Webhook
curl -v -X POST http://192.168.1.54:32090 \
  -H "Content-Type: application/json" \
  -d '{"ref":"refs/heads/main","repository":{"clone_url":"http://192.168.1.61:3000/demo/test.git","name":"test"},"head_commit":{"id":"abc123"}}'
# 发现：Connection refused

# 4. 检查防火墙
# 发现：防火墙阻止了 32090 端口
```

**解决方案：**
```bash
# 方案一：开放防火墙端口
# 在防火墙中开放 32090 端口

# 方案二：使用 Ingress 暴露 EventListener
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1  # API 版本
kind: Ingress  # K8s 入口路由
metadata:
  name: el-ingress
  namespace: tekton-pipelines
spec:
  ingressClassName: nginx  # 使用 Nginx Ingress
  rules:
  - host: tekton-webhook.demo.local
    http:
      paths:
      - path: /
        pathType: Prefix  # 前缀匹配
        backend:
          service:
            name: el-git-webhook-listener
            port:  # 服务端口
              number: 8080
EOF

# 更新 Git Webhook URL
# https://tekton-webhook.demo.local
```

### 案例 8：TaskRun Pod 被 OOMKilled

**现象：**
```
tkn taskrun describe <taskrun-name> -n tekton-pipelines
# Status: Failed
# Message: Pod "xxx" terminated: OOMKilled
```

**排查步骤：**
```bash
# 1. 检查 Pod 事件
kubectl describe pod <taskrun-pod> -n tekton-pipelines | grep -A 5 "OOMKilled"
# 发现：Container exceeded memory limit

# 2. 检查 Task 的资源配置
tkn task describe maven-test -n tekton-pipelines | grep -A 5 "resources"
# 发现：memory limits=512Mi（不够 Maven 编译）

# 3. 检查节点资源
kubectl top nodes
# 发现：Worker 节点内存充足
```

**解决方案：**
```bash
# 增大 Task 的内存限制
kubectl patch task maven-test -n tekton-pipelines --type merge \
  -p '{"spec":{"steps":[{"name":"maven-test","resources":{"limits":{"memory":"4Gi"},"requests":{"memory":"1Gi"}}]}}'

# 或者重新创建 Task（修改 YAML）
```

### 案例 9：Pipeline as Code 同步失败

**现象：**
```
Pipeline as Code 配置提交到 Git 后，Tekton 没有自动更新 Pipeline 定义。
EventListener 日志显示事件接收成功，但 Pipeline 未同步。
```

**排查步骤：**
```bash
# 1. 检查 EventListener 日志
kubectl logs -n tekton-pipelines -l eventlistener=pipeline-as-code-listener --tail=50
# 发现：CEL Interceptor 过滤掉了事件
# "interceptors failed: CEL expression returned false"

# 2. 检查 CEL 过滤条件
kubectl get eventlistener pipeline-as-code-listener -n tekton-pipelines -o yaml | grep -A 5 "filter"
# 发现：filter 条件过于严格，只监听 .tekton/ 目录变更

# 3. 检查提交的文件路径
git show --name-only HEAD
# 发现：修改了 tekton/pipeline.yaml（没有点前缀）

# 4. 检查 sync-pipeline TaskRun 状态
tkn taskrun list -n tekton-pipelines | grep sync-pipeline
# 发现：没有创建 TaskRun

# 5. 检查 ServiceAccount 权限
kubectl auth can-i create pipelines -n tekton-pipelines --as=system:serviceaccount:tekton-pipelines:tekton-ci-sa
# 发现：yes（权限正常）
```

**解决方案：**
```bash
# 方案一：修改 CEL 过滤条件，匹配实际目录结构
kubectl patch eventlistener pipeline-as-code-listener -n tekton-pipelines --type merge -p '{
  "spec": {
    "triggers": [{
      "name": "pipeline-sync-trigger",
      "interceptors": [{
        "ref": {"name": "cel"},
        "params": [{
          "name": "filter",
          "value": "body.commits.exists(c, c.modified.exists(m, m.startsWith(\\'.tekton/\\') || m.startsWith(\\'tekton/\\')))"
        }]
      }]
    }]
  }
}'

# 方案二：统一目录结构，全部使用 .tekton/
# 重命名目录
mv tekton/ .tekton/
git add .
git commit -m "chore: rename tekton to .tekton for Pipeline as Code"
git push

# 方案三：检查 Interceptor 配置
# 确保 CEL 表达式语法正确
```

**预防措施：**
```yaml
# 使用更灵活的 CEL 条件
apiVersion: triggers.tekton.dev/v1beta1  # Tekton API 版本
kind: EventListener  # 事件监听器
metadata:
  name: pipeline-as-code-listener
spec:
  triggers:
  - name: pipeline-sync-trigger
    interceptors:
    - ref:
        name: "cel"
      params:
      - name: "filter"
        # 支持多种常见配置目录
        value: |
          body.commits.exists(c, 
            c.modified.exists(m, m.startsWith('.tekton/') || 
                                  m.startsWith('tekton/') || 
                                  m.startsWith('pipelines/') ||
                                  m.startsWith('.github/workflows/'))
          )
```

### 案例 10：安全扫描阻塞发布

**现象：**
```
Pipeline 在 security-gate 步骤失败，镜像无法推送到生产仓库。
错误信息：SECURITY GATE FAILED: Critical vulnerabilities (5) exceed threshold (0)
但开发团队认为这些漏洞不影响业务，需要紧急发布。
```

**排查步骤：**
```bash
# 1. 查看安全扫描报告
tkn taskrun logs <security-scan-taskrun> -n tekton-pipelines
# 发现：5个 CRITICAL 漏洞，都是基础镜像的 OpenSSL 问题

# 2. 检查漏洞详情
cat /workspace/reports/scan-abc123.json | jq '.Results[0].Vulnerabilities[] | select(.Severity=="CRITICAL")'
# 发现：
# - CVE-2023-XXXX: OpenSSL 缓冲区溢出
# - CVE-2023-YYYY: glibc 本地提权

# 3. 检查基础镜像版本
kubectl get taskrun <build-taskrun> -o yaml | grep "FROM"
# 发现：FROM 192.168.1.61/tekton/eclipse-temurin:17-jre（较旧版本）

# 4. 确认漏洞是否已修复
curl -s https://security-tracker.debian.org/tracker/CVE-2023-XXXX | grep "fixed"
# 发现：已在最新版本修复
```

**解决方案：**
```bash
# 方案一：更新基础镜像（推荐）
# 修改 Dockerfile，使用更新版本
sed -i 's|eclipse-temurin:17-jre|eclipse-temurin:17-jre-alpine|g' Dockerfile
git add Dockerfile
git commit -m "fix: update base image to fix CVEs"
git push

# 方案二：临时放宽门禁（紧急修复）
# 修改 Pipeline 参数，允许关键漏洞（不推荐长期使用）
tkn pipeline start devsecops-pipeline \
  -p max-critical-vulns="5" \
  -p app-name="my-app" \
  --showlog

# 方案三：漏洞例外审批流程
# 添加审批标记到镜像
kubectl annotate pipelinerun <pr-name> -n tekton-pipelines \
  security-exception="approved-by-security-team-20240101"
```

**长期改进：**
```yaml
# 添加漏洞白名单机制（仅用于已评估的漏洞）
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: security-gate-with-allowlist
spec:
  params:
  - name: scan-report-path
    type: string
  - name: allowlist-configmap
    type: string
    default: "vulnerability-allowlist"
  workspaces:
  - name: reports
  steps:
  - name: evaluate
    image: 192.168.1.61/tekton/alpine/git:2.40  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      
      # 加载白名单
      ALLOWLIST=$(kubectl get configmap $(params.allowlist-configmap) -o jsonpath='{.data.cves}' 2>/dev/null || echo "")
      
      # 解析扫描报告，排除白名单中的 CVE
      CRITICAL=$(cat $(workspaces.reports.path)/$(params.scan-report-path) | \
        jq -r '.Results[].Vulnerabilities[]? | select(.Severity=="CRITICAL") | .VulnerabilityID' | \
        grep -v -f <(echo "$ALLOWLIST") | wc -l)
      
      if [ "$CRITICAL" -gt 0 ]; then
        echo "Found $CRITICAL critical vulnerabilities not in allowlist"
        exit 1
      fi
```

### 案例 11：SonarQube质量门禁阻断

**现象：**
```
Pipeline在sast-scan步骤失败，SonarQube质量门禁未通过。
错误信息：ERROR: Quality Gate failed: New issues found
```

**排查步骤：**
```bash
# 1. 查看SonarQube扫描日志
tkn taskrun logs <sast-scan-taskrun> -n tekton-pipelines
# 发现：SonarQube检测到3个新的代码异味和1个安全漏洞

# 2. 登录SonarQube Web界面查看详情
# 访问 http://192.168.1.61:9000
# 查看项目质量门禁状态和问题列表

# 3. 检查质量门禁配置
curl -u $SONAR_TOKEN: http://192.168.1.61:9000/api/qualitygates/show?name=Sonar%20way
# 发现：新代码覆盖率要求80%，当前只有65%

# 4. 检查sonar-project.properties配置
cat sonar-project.properties
# 发现：未配置正确的测试报告路径
```

**解决方案：**
```bash
# 方案一：修复代码问题（推荐）
# 1. 根据SonarQube报告修复代码异味
# 2. 补充单元测试提高覆盖率
# 3. 修复安全漏洞

# 方案二：临时禁用质量门禁（仅用于紧急修复）
# 修改Pipeline参数
kubectl patch pipelinerun <pr-name> -n tekton-pipelines --type merge \
  -p '{"spec":{"params":[{"name":"sonar-quality-gate","value":"false"}]}}'

# 方案三：调整质量门禁阈值（需要SonarQube管理员权限）
# 在SonarQube中调整项目质量门禁配置
```

**预防措施：**
```yaml
# 在Pipeline中添加代码质量预检查
- name: code-lint
  runAfter:  # 依赖任务: 
  - git-clone
  taskRef:
    name: maven-checkstyle
  # 在提交前执行代码规范检查
```

---

### 案例 12：Trivy扫描发现高危漏洞

**现象：**
```
Pipeline在image-security-scan步骤失败。
错误信息：发现5个CRITICAL和12个HIGH级别漏洞，扫描失败。
```

**排查步骤：**
```bash
# 1. 查看Trivy扫描报告
tkn taskrun logs <image-scan-taskrun> -n tekton-pipelines
# 发现：基础镜像eclipse-temurin:17-jre存在多个CVE

# 2. 查看详细扫描报告
cat /workspace/reports/trivy/scan-report.json | jq '.Results[].Vulnerabilities[] | 
  select(.Severity=="CRITICAL") | {VulnerabilityID, PkgName, Severity, Title}'

# 3. 检查基础镜像版本
kubectl get taskrun <build-taskrun> -o yaml | grep "FROM"
# 发现：FROM 192.168.1.61/tekton/eclipse-temurin:17-jre

# 4. 查询漏洞详情
# CVE-2023-XXXX: OpenSSL缓冲区溢出
# CVE-2023-YYYY: glibc本地提权
# 均已在最新版本修复
```

**解决方案：**
```bash
# 方案一：更新基础镜像（推荐）
# 修改Dockerfile
sed -i 's|eclipse-temurin:17-jre|eclipse-temurin:17.0.9_9-jre|g' Dockerfile
git add Dockerfile
git commit -m "fix: update base image to fix CVEs"
git push

# 方案二：使用更轻量的基础镜像
# 改用Alpine版本
sed -i 's|eclipse-temurin:17-jre|eclipse-temurin:17-jre-alpine|g' Dockerfile

# 方案三：配置漏洞白名单（用于已评估的漏洞）
# 创建漏洞白名单ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: vulnerability-allowlist
  namespace: tekton-pipelines
data:
  cves: |
    CVE-2023-XXXX  # 已评估，不影响业务
    CVE-2023-YYYY  # 已评估，已采取缓解措施
EOF
```

**长期改进：**
```yaml
# 配置定期基础镜像更新检查
apiVersion: batch/v1  # API 版本
kind: CronJob
metadata:
  name: base-image-update-check
  namespace: tekton-pipelines
spec:
  schedule: "0 2 * * 1"  # 每周一凌晨2点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: check-updates
            image: 192.168.1.61/tekton/aquasec/trivy:latest  # 镜像地址(Harbor)
            command:
            - /bin/sh
            - -c
            - |
              trivy image --severity CRITICAL eclipse-temurin:17-jre
          restartPolicy: OnFailure
```

---

### 案例 13：SBOM生成失败

**现象：**
```
Pipeline在generate-sbom步骤失败。
错误信息：failed to generate SBOM: unable to determine image source
```

**排查步骤：**
```bash
# 1. 查看SBOM生成日志
tkn taskrun logs <sbom-taskrun> -n tekton-pipelines
# 发现：Syft无法访问镜像

# 2. 检查镜像是否存在
curl -s http://192.168.1.61/v2/order-service/manifests/v1.0.0
# 发现：镜像存在，但Harbor返回401 Unauthorized

# 3. 检查Syft镜像凭证配置
kubectl get task generate-sbom -n tekton-pipelines -o yaml | grep -A 5 "env"
# 发现：Syft Task未配置Registry凭证

# 4. 检查Harbor认证
kubectl get secret harbor-secret -n tekton-pipelines
# 发现：Secret存在，但未挂载到Syft Task
```

**解决方案：**
```bash
# 方案一：修改Syft Task，添加Registry凭证
# 更新Task定义，挂载dockerconfig workspace
kubectl patch task generate-sbom -n tekton-pipelines --type merge -p '{
  "spec": {
    "workspaces": [
      {"name": "sbom"},
      {"name": "dockerconfig", "description": "Registry credentials"}
    ],
    "steps": [{
      "name": "generate-sbom",
      "image": "192.168.1.61/tekton/anchore/syft:latest",
      "env": [
        {"name": "DOCKER_CONFIG", "value": "$(workspaces.dockerconfig.path)"}
      ]
    }]
  }
}'

# 方案二：使用Syft的离线模式
# 预先将镜像导出为tar，然后扫描
syft packages docker-archive:/tmp/image.tar -o spdx-json

# 方案三：配置Harbor匿名访问（仅用于测试环境）
# 在Harbor项目中配置公开访问权限
```

**验证修复：**
```bash
# 重新运行SBOM生成
tkn task start generate-sbom \
  -p image="192.168.1.61:80/order-service:v1.0.0" \
  -p app-name="order-service" \
  -w name=sbom,emptyDir="" \
  -w name=dockerconfig,secret=harbor-secret \
  --showlog

# 检查生成的SBOM
cat /workspace/sbom/sbom.json | jq '.packages | length'
```

---

### 案例 11：跨环境配置泄露

**现象：**
```
生产环境应用启动失败，日志显示连接到了测试数据库。
检查发现 ConfigMap 中包含了测试环境的敏感信息。
```

**排查步骤：**
```bash
# 1. 检查生产环境 ConfigMap
kubectl get configmap my-app-config -n production -o yaml
# 发现：
# data:
#   DATABASE_URL: jdbc:mysql://test-db:3306/testdb
#   API_KEY: test-api-key-12345

# 2. 检查配置同步 Pipeline
tkn pipelinerun logs config-sync-pipeline-run-xxx -n tekton-pipelines
# 发现：从 dev 环境同步 ConfigMap 到 production

# 3. 检查 Git 仓库中的配置
ls -la config/
# 发现：
# config/
#   ├── dev/
#   │   └── configmap.yaml  # 包含 dev 特定配置
#   ├── test/
#   │   └── configmap.yaml
#   └── prod/
#       └── configmap.yaml  # 但 prod 配置被 dev 覆盖了

# 4. 检查配置验证 Task
tkn task logs config-validator -n tekton-pipelines
# 发现：验证通过，没有检测到敏感信息

# 5. 检查同步脚本
kubectl get task k8s-config-sync -o yaml | grep -A 20 "script:"
# 发现：使用了 sed 替换 namespace，但没有验证配置内容
```

**解决方案：**
```bash
# 方案一：立即停止并修复
# 1. 回滚生产配置
kubectl rollout undo deployment/my-app -n production

# 2. 创建正确的生产 ConfigMap
kubectl create configmap my-app-config -n production --from-literal=DATABASE_URL="jdbc:mysql://prod-db:3306/proddb" --dry-run=client -o yaml | kubectl apply -f -

# 3. 重启应用
kubectl rollout restart deployment/my-app -n production

# 方案二：增强配置验证
# 更新 config-validator Task，检查环境特定值
cat <<'EOF' | kubectl apply -f -
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: config-validator-enhanced
  namespace: tekton-pipelines
spec:
  params:
  - name: app-name
    type: string
  - name: environment
    type: string
  - name: allowed-patterns
    type: string
    default: ""
  workspaces:
  - name: source
  steps:
  - name: validate
    image: 192.168.1.61/tekton/bitnami/kubectl:latest  # 镜像地址(Harbor)
    script: |
      #!/bin/sh
      set -e
      
      ENV="$(params.environment)"
      CONFIG_FILE="$(workspaces.source.path)/config/$ENV/configmap.yaml"
      
      echo "Validating config for environment: $ENV"
      
      # 检查配置文件是否存在
      if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERROR: Config file not found: $CONFIG_FILE"
        exit 1
      fi
      
      # 环境特定验证规则
      case "$ENV" in
        production|prod)
          # 生产环境不应该包含测试/开发关键词
          if grep -iE "test|dev|localhost|192.168|10\\." "$CONFIG_FILE"; then
            echo "ERROR: Production config contains non-production values!"
            exit 1
          fi
          # 检查是否使用生产数据库
          if ! grep -q "prod-db" "$CONFIG_FILE"; then
            echo "WARNING: Production config may not use production database"
          fi
          ;;
        staging|preprod)
          # 预生产环境验证
          if grep -q "prod-db" "$CONFIG_FILE"; then
            echo "ERROR: Staging config should not use production database!"
            exit 1
          fi
          ;;
      esac
      
      # 检查敏感信息
      if grep -iE "password|secret|token|key" "$CONFIG_FILE"; then
        echo "ERROR: ConfigMap contains potential sensitive data!"
        echo "Sensitive data should be in Secrets, not ConfigMaps."
        exit 1
      fi
      
      echo "Configuration validation passed for $ENV"
EOF

# 方案三：实施配置分离策略
# 使用不同的 Git 仓库或分支管理不同环境的配置
# production 分支只包含生产配置
```

**预防措施：**
```yaml
# 使用 External Secrets Operator 管理敏感配置
# 避免将敏感信息存储在 Git 中

# 配置模板化，环境值通过变量注入
apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: my-app-config
data:
  # 使用占位符，实际值由 CI/CD 注入
  DATABASE_URL: "${DB_URL}"
  LOG_LEVEL: "${LOG_LEVEL}"
```

```bash
# 使用 kubeval/kustomize 验证配置
# 在 Pipeline 中添加配置验证步骤

# 验证 Kubernetes 资源
kubeval config/prod/*.yaml --strict

# 使用 conftest 进行策略检查
conftest test config/prod/configmap.yaml --policy policies/
```

---

## 9. 多架构CI流水线（进阶）

### 9.1 多架构镜像概述

**多架构镜像（Multi-arch Image）** 是指一个镜像标签可以同时支持多种 CPU 架构（如 amd64、arm64），Docker 会根据宿主机架构自动拉取对应的镜像。

**多架构镜像原理：**

```
+================================================================+
|                   多架构镜像原理                                 |
+================================================================+
|                                                                 |
|  docker pull myapp:v1.0                                         |
|                                                                 |
|  Manifest List (索引清单):                                       |
|  +----------------------------------------------------------+  |
|  |  mediaType: application/vnd.docker.distribution.manifest  |  |
|  |             .list.v2+json                                 |  |
|  |  manifests:                                               |  |
|  |    - platform: linux/amd64                                |  |
|  |      digest: sha256:abc123...  → amd64 镜像               |  |
|  |    - platform: linux/arm64                                |  |
|  |      digest: sha256:def456...  → arm64 镜像               |  |
|  |    - platform: linux/arm/v7                               |  |
|  |      digest: sha256:ghi789...  → armv7 镜像               |  |
|  +----------------------------------------------------------+  |
|                                                                 |
|  拉取流程:                                                       |
|  1. 客户端请求镜像                                               |
|  2. Registry 返回 Manifest List                                 |
|  3. 客户端匹配当前平台                                           |
|  4. 拉取对应架构的镜像层                                         |
|                                                                 |
+================================================================+
```

**常见架构支持：**

| 架构 | 适用场景 | 示例平台 |
|------|----------|----------|
| linux/amd64 | x86_64 服务器 | 大多数云服务器、物理机 |
| linux/arm64 | ARM 服务器 | AWS Graviton、Apple Silicon |
| linux/arm/v7 | 嵌入式设备 | Raspberry Pi |
| windows/amd64 | Windows 容器 | Windows Server |

### 9.2 Docker Buildx 集成

**buildx** 是 Docker 的构建扩展，支持多架构构建和 BuildKit 高级特性。

**安装 buildx（在 Tekton Task 中）：**

```bash
# 在 Tekton Task 中启用 buildx
# 方法 1: 使用支持 buildx 的基础镜像
# 方法 2: 在 Task 中安装 buildx

# 安装 buildx 插件
DOCKER_BUILDKIT=1
docker buildx version

# 创建多架构构建器
docker buildx create --name multiarch-builder --use

# 启动构建器
docker buildx inspect --bootstrap
```

**buildx 多架构构建命令：**

```bash
# 多架构构建并推送
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag 192.168.1.61:80/mall/order:v1.0.0 \
  --push \
  .

# 查看镜像 manifest
docker buildx imagetools inspect \
  192.168.1.61:80/mall/order:v1.0.0
```

### 9.3 Tekton 多架构构建 Task

**Task 定义：**

```yaml
# tasks/multi-arch-build.yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: multi-arch-build
  namespace: tekton-pipelines
spec:
  description: 多架构容器镜像构建 Task
  params:
  - name: image-name
    description: 镜像名称（不含 registry 和 tag）
    type: string
  - name: image-tag
    description: 镜像标签
    type: string
    default: "latest"
  - name: registry
    description: 镜像仓库地址
    type: string
    default: "192.168.1.61:80"
  - name: platforms
    description: 目标平台列表
    type: string
    default: "linux/amd64,linux/arm64"
  - name: dockerfile
    description: Dockerfile 路径
    type: string
    default: "Dockerfile"
  - name: context
    description: 构建上下文路径
    type: string
    default: "."
  
  workspaces:
  - name: source
    description: 源代码工作空间
    mountPath: /workspace/source
  - name: dockerconfig
    description: Docker 配置（用于认证）
    mountPath: /root/.docker
  
  steps:
  # 步骤 1: 设置 QEMU 模拟器（用于跨平台构建）
  - name: setup-qemu
    image: tonistiigi/binfmt:latest
    script: |
      #!/bin/sh
      echo ">>> 设置 QEMU 模拟器"
      # binfmt_misc 已在宿主机配置，此处确认可用
      ls /proc/sys/fs/binfmt_misc/
  
  # 步骤 2: 设置 buildx 构建器
  - name: setup-buildx
    image: docker:24.0.5
    env:
    - name: DOCKER_HOST
      value: tcp://localhost:2375
    script: |
      #!/bin/sh
      echo ">>> 创建多架构构建器"
      docker buildx create --name multiarch-builder --use --driver docker-container
      docker buildx inspect --bootstrap
  
  # 步骤 3: 多架构构建
  - name: build-multiarch
    image: docker:24.0.5
    env:
    - name: DOCKER_HOST
      value: tcp://localhost:2375
    script: |
      #!/bin/sh
      set -e
      
      IMAGE_NAME="$(params.registry)/$(params.image-name):$(params.image-tag)"
      PLATFORMS="$(params.platforms)"
      
      echo ">>> 构建多架构镜像: ${IMAGE_NAME}"
      echo ">>> 目标平台: ${PLATFORMS}"
      
      cd /workspace/source/$(params.context)
      
      # 多架构构建并推送
      docker buildx build \
        --platform "${PLATFORMS}" \
        --tag "${IMAGE_NAME}" \
        --file "$(params.dockerfile)" \
        --push \
        .
      
      echo ">>> 构建完成，验证 manifest"
      docker buildx imagetools inspect "${IMAGE_NAME}"
  
  # 步骤 4: 生成构建报告
  - name: report
    image: alpine:3.18
    script: |
      #!/bin/sh
      echo "=========================================="
      echo "多架构镜像构建报告"
      echo "=========================================="
      echo "镜像: $(params.registry)/$(params.image-name):$(params.image-tag)"
      echo "平台: $(params.platforms)"
      echo "时间: $(date)"
      echo "=========================================="
```

**使用 DinD (Docker-in-Docker) 的 Sidecar（边车代理） 配置：**

```yaml
# Pipeline 中使用 DinD sidecar
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: PipelineRun  # 流水线执行实例
metadata:
  name: multi-arch-build-run
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: multi-arch-pipeline
  workspaces:
  - name: source
    persistentVolumeClaim:
      claimName: tekton-workspace-pvc
  - name: dockerconfig
    secret:
      secretName: harbor-credentials
  podTemplate:
    # DinD sidecar
    sidecars:
    - image: docker:24.0.5-dind
      name: dind
      env:
      - name: DOCKER_TLS_CERTDIR
        value: ""
      securityContext:
        privileged: true
    # 等待 DinD 就绪
    volumes:
    - name: dind-storage
      emptyDir: {}
```

### 9.4 平台特定测试

**不同架构运行不同测试：**

```yaml
# tasks/platform-test.yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: platform-test
  namespace: tekton-pipelines
spec:
  description: 平台特定测试 Task
  params:
  - name: platform
    description: 目标平台
    type: string
  - name: image-name
    description: 测试镜像名称
    type: string
  
  workspaces:
  - name: source
    mountPath: /workspace/source
  
  steps:
  # 根据平台选择测试策略
  - name: detect-platform
    image: alpine:3.18
    script: |
      #!/bin/sh
      PLATFORM="$(params.platform)"
      
      case "${PLATFORM}" in
        linux/amd64)
          echo "amd64" > /tmp/platform-type
          echo ">>> 执行 amd64 特定测试"
          ;;
        linux/arm64)
          echo "arm64" > /tmp/platform-type
          echo ">>> 执行 arm64 特定测试"
          ;;
        *)
          echo "unknown" > /tmp/platform-type
          echo ">>> 执行通用测试"
          ;;
      esac
  
  # 运行单元测试
  - name: unit-test
    image: golang:1.21-alpine
    script: |
      #!/bin/sh
      cd /workspace/source
      
      echo ">>> 运行单元测试 ($(params.platform))"
      go test -v ./...
      
      # 平台特定测试
      PLATFORM_TYPE=$(cat /tmp/platform-type)
      if [ "${PLATFORM_TYPE}" = "amd64" ]; then
        echo ">>> 运行 amd64 性能基准测试"
        go test -bench=. -run=^$ ./benchmark/...
      fi
  
  # 运行集成测试
  - name: integration-test
    image: docker:24.0.5
    script: |
      #!/bin/sh
      echo ">>> 运行集成测试 ($(params.platform))"
      
      # 拉取对应架构的镜像
      docker pull --platform $(params.platform) $(params.image-name)
      
      # 运行测试容器
      docker run --rm \
        --platform $(params.platform) \
        $(params.image-name) \
        /app/test-runner
```

**并行执行多平台测试：**

```yaml
# pipeline/multi-platform-test.yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: multi-platform-test-pipeline
  namespace: tekton-pipelines
spec:
  params:
  - name: image-name
    type: string
  - name: image-tag
    type: string
  
  workspaces:
  - name: source
  - name: dockerconfig
  
  tasks:
  # 并行测试 amd64
  - name: test-amd64
    taskRef:
      name: platform-test
    params:
    - name: platform
      value: linux/amd64
    - name: image-name
      value: $(params.image-name):$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
  
  # 并行测试 arm64
  - name: test-arm64
    taskRef:
      name: platform-test
    params:
    - name: platform
      value: linux/arm64
    - name: image-name
      value: $(params.image-name):$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
  
  # 汇总测试结果
  - name: test-summary
    runAfter:  # 依赖任务: 
    - test-amd64
    - test-arm64
    taskRef:
      name: test-summary
    params:
    - name: amd64-result
      value: $(tasks.test-amd64.results.status)
    - name: arm64-result
      value: $(tasks.test-arm64.results.status)
```

### 9.5 Manifest List 创建

**手动创建 Manifest List（高级场景）：**

```yaml
# tasks/create-manifest.yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Task  # Tekton 任务
metadata:
  name: create-manifest-list
  namespace: tekton-pipelines
spec:
  description: 创建多架构 Manifest List
  params:
  - name: base-image
    description: 基础镜像名称（不含 arch 后缀）
    type: string
  - name: image-tag
    description: 镜像标签
    type: string
  - name: registry
    description: 镜像仓库
    type: string
    default: "192.168.1.61:80"
  
  steps:
  - name: create-manifest
    image: docker:24.0.5
    script: |
      #!/bin/sh
      set -e
      
      REGISTRY="$(params.registry)"
      BASE_IMAGE="$(params.base-image)"
      TAG="$(params.image-tag)"
      
      # 架构特定镜像
      AMD64_IMAGE="${REGISTRY}/${BASE_IMAGE}-amd64:${TAG}"
      ARM64_IMAGE="${REGISTRY}/${BASE_IMAGE}-arm64:${TAG}"
      
      # 最终镜像标签
      FINAL_IMAGE="${REGISTRY}/${BASE_IMAGE}:${TAG}"
      
      echo ">>> 创建 Manifest List"
      echo "  amd64: ${AMD64_IMAGE}"
      echo "  arm64: ${ARM64_IMAGE}"
      echo "  最终: ${FINAL_IMAGE}"
      
      # 创建 manifest list
      docker manifest create ${FINAL_IMAGE} \
        ${AMD64_IMAGE} \
        ${ARM64_IMAGE}
      
      # 设置 manifest 注解
      docker manifest annotate ${FINAL_IMAGE} ${AMD64_IMAGE} \
        --os linux --arch amd64
      
      docker manifest annotate ${FINAL_IMAGE} ${ARM64_IMAGE} \
        --os linux --arch arm64
      
      # 推送 manifest list
      docker manifest push ${FINAL_IMAGE}
      
      echo ">>> Manifest List 创建完成"
      docker manifest inspect ${FINAL_IMAGE}
```

### 9.6 Harbor 多架构支持

**Harbor 配置多架构镜像：**

```bash
# Harbor 原生支持多架构镜像
# 无需特殊配置，只需正确推送 manifest list

# 验证 Harbor 中的多架构镜像
curl -s -u admin:Harbor12345 \
  "https://192.168.1.61/api/v2.0/projects/mall/repositories/order/artifacts?v1.0.0" | jq .

# 输出示例:
# {
#   "digest": "sha256:abc123...",
#   "tags": [{"name": "v1.0.0"}],
#   "manifest_metadata": {
#     "manifest_list": true,
#     "platforms": [
#       {"os": "linux", "architecture": "amd64"},
#       {"os": "linux", "architecture": "arm64"}
#     ]
#   }
# }
```

**Harbor 多架构镜像清理策略：**

```yaml
# Harbor Retention Policy（保留策略）
# 保留最近 10 个多架构镜像标签

apiVersion: v1  # API 版本
kind: ConfigMap  # K8s 配置映射
metadata:
  name: harbor-retention-policy
data:
  policy.yaml: |
    algorithm: or
    rules:
    - kind: tagCount
      pattern: "10"  # 保留最近 10 个标签
      excludedRepos:
      - "mall/*-amd64"  # 排除架构特定镜像
      - "mall/*-arm64"
```

### 9.7 完整多架构 CI Pipeline

**端到端 Pipeline 示例：**

```yaml
# pipeline/multi-arch-ci.yaml
apiVersion: tekton.dev/v1beta1  # Tekton API 版本
kind: Pipeline  # Tekton 流水线
metadata:
  name: multi-arch-ci-pipeline
  namespace: tekton-pipelines
spec:
  description: 完整的多架构 CI Pipeline
  params:
  - name: app-name
    type: string
  - name: git-revision
    type: string
  - name: image-tag
    type: string
  
  workspaces:
  - name: source
  - name: dockerconfig
  
  tasks:
  # 1. 克隆代码
  - name: git-clone
    taskRef:
      name: git-clone
    params:
    - name: url
      value: https://github.com/myorg/$(params.app-name).git
    - name: revision
      value: $(params.git-revision)
    workspaces:
    - name: output
      workspace: source
  
  # 2. 并行构建多架构镜像
  - name: build-amd64
    runAfter: [git-clone]  # 依赖任务: git-clone
    taskRef:
      name: build-arch-specific
    params:
    - name: platform
      value: linux/amd64
    - name: image-name
      value: 192.168.1.61:80/mall/$(params.app-name)-amd64:$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
    - name: dockerconfig
      workspace: dockerconfig
  
  - name: build-arm64
    runAfter: [git-clone]  # 依赖任务: git-clone
    taskRef:
      name: build-arch-specific
    params:
    - name: platform
      value: linux/arm64
    - name: image-name
      value: 192.168.1.61:80/mall/$(params.app-name)-arm64:$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
    - name: dockerconfig
      workspace: dockerconfig
  
  # 3. 并行运行平台测试
  - name: test-amd64
    runAfter: [build-amd64]  # 依赖任务: build-amd64
    taskRef:
      name: platform-test
    params:
    - name: platform
      value: linux/amd64
    - name: image-name
      value: 192.168.1.61:80/mall/$(params.app-name)-amd64:$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
  
  - name: test-arm64
    runAfter: [build-arm64]  # 依赖任务: build-arm64
    taskRef:
      name: platform-test
    params:
    - name: platform
      value: linux/arm64
    - name: image-name
      value: 192.168.1.61:80/mall/$(params.app-name)-arm64:$(params.image-tag)
    workspaces:
    - name: source
      workspace: source
  
  # 4. 创建 Manifest List
  - name: create-manifest
    runAfter: [test-amd64, test-arm64]  # 依赖任务: test-amd64, test-arm64
    taskRef:
      name: create-manifest-list
    params:
    - name: base-image
      value: mall/$(params.app-name)
    - name: image-tag
      value: $(params.image-tag)
    workspaces:
    - name: dockerconfig
      workspace: dockerconfig
  
  # 5. 安全扫描
  - name: security-scan
    runAfter: [create-manifest]  # 依赖任务: create-manifest
    taskRef:
      name: trivy-scan
    params:
    - name: image
      value: 192.168.1.61:80/mall/$(params.app-name):$(params.image-tag)
  
  # 6. 生成 SBOM
  - name: generate-sbom
    runAfter: [create-manifest]  # 依赖任务: create-manifest
    taskRef:
      name: sbom-generate
    params:
    - name: image
      value: 192.168.1.61:80/mall/$(params.app-name):$(params.image-tag)
```

**Pipeline 执行流程图：**

```
+================================================================+
|                   多架构 CI Pipeline 流程                        |
+================================================================+
|                                                                 |
|  git-clone                                                      |
|      |                                                          |
|      +----------------+----------------+                        |
|      |                |                |                        |
|      v                v                v                        |
|  build-amd64     build-arm64                                  |
|      |                |                                        |
|      v                v                                        |
|  test-amd64       test-arm64                                  |
|      |                |                                        |
|      +-------+--------+                                        |
|              |                                                 |
|              v                                                 |
|       create-manifest                                          |
|              |                                                 |
|      +-------+-------+                                         |
|      |               |                                         |
|      v               v                                         |
|  security-scan   generate-sbom                                 |
|      |               |                                         |
|      +-------+-------+                                         |
|              |                                                 |
|              v                                                 |
|         Pipeline 完成                                          |
|                                                                 |
+================================================================+
```

### 9.8 CKA/CKS 考点关联

| 考点 | 关联内容 |
|------|----------|
| **容器镜像** | 理解镜像层、manifest list 概念 |
| **多架构支持** | amd64/arm64 架构差异 |
| **CI/CD** | Pipeline 编排、并行执行 |
| **安全** | 镜像扫描、SBOM 生成 |
| **Registry** | Harbor 多架构镜像管理 |

**高频面试题：**

1. **Q: 什么是 Manifest List？**
   - A: Manifest List（也称 Image Index）是多架构镜像的索引清单，包含指向不同架构镜像的引用。Docker 客户端根据当前平台自动选择对应的镜像。

2. **Q: buildx 如何实现跨平台构建？**
   - A: buildx 使用 QEMU 模拟器在宿主机上模拟目标架构，或使用原生节点构建（多节点构建器）。对于 Go/Rust 等编译型语言，可使用交叉编译无需模拟器。

3. **Q: 多架构构建的性能优化方法？**
   - A: (1) 使用原生节点构建而非 QEMU 模拟；(2) 利用构建缓存（--cache-from）；(3) 并行构建不同架构；(4) 对于 Go 应用使用交叉编译。

---

## 10. 生产环境建议

### 10.1 生产级 Tekton 配置

```yaml
# 生产级 TektonConfig
spec:
  pipeline:
    await-sidecar-readiness: true
    disable-affinity-assistant: false  # 启用亲和性助手
    metrics.taskrun.duration-type: histogram
    default-service-account: tekton-ci-sa
    default-timeout-minutes: 60
    default-managed-by-label: tekton-pipelines
  trigger:
    enable-api-fields: beta  # 启用 Beta API 字段
  addon:
    params:
    - name: clusterTask
      value: "true"
```

### 9.2 生产最佳实践

| 领域 | 建议 |
|------|------|
| **缓存** | Maven/npm 依赖缓存到 PVC，Docker Layer 缓存到 Registry |
| **安全** | 使用 Kaniko 替代 Docker-in-Docker，最小权限 SA |
| **并行** | 独立 Task 并行执行，缩短总耗时 |
| **通知** | Pipeline 成功/失败发送通知（Slack/钉钉） |
| **监控** | Prometheus（指标监控系统） 采集 Tekton metrics + Grafana Dashboard |
| **超时** | PipelineRun 设置合理超时（1-2 小时） |
| **重试** | 关键 Task（推送镜像）配置重试 3 次 |
| **日志** | 集中收集 TaskRun 日志到 Loki/ES |
| **清理** | 定期清理旧的 PipelineRun 和 TaskRun |
| **版本** | Pipeline YAML 通过 GitOps 管理 |
| **Webhook** | 使用 Gitea Webhook Interceptor 验证签名 |
| **CI/CD 解耦** | Tekton CI -> Git -> ArgoCD CD |

---

## 10. 离线前置准备

> **本章节是离线环境部署 Tekton 的前置条件，必须在有外网的服务器上完成所有准备工作后，再传输到离线集群。**

### 10.1 镜像预推送清单

以下所有镜像需要从有外网的服务器拉取，打标签后推送到 Harbor（192.168.1.61:80，HTTP）。

#### Tekton 核心组件镜像

| 原始镜像 | Harbor 目标路径 | 用途 |
|---------|---------------|------|
| `gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/controller:v0.58.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/pipeline/cmd/controller:v0.58.x` | Pipeline Controller |
| `gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/webhook:v0.58.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/pipeline/cmd/webhook:v0.58.x` | Pipeline Webhook |
| `gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/resolvers:v0.58.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/pipeline/cmd/resolvers:v0.58.x` | Pipeline Resolvers |
| `gcr.io/tekton-releases/github.com/tektoncd/triggers/cmd/controller:v0.27.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/triggers/cmd/controller:v0.27.x` | Triggers Controller |
| `gcr.io/tekton-releases/github.com/tektoncd/triggers/cmd/webhook:v0.27.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/triggers/cmd/webhook:v0.27.x` | Triggers Webhook |
| `gcr.io/tekton-releases/github.com/tektoncd/triggers/cmd/interceptors:v0.27.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/triggers/cmd/interceptors:v0.27.x` | Triggers Interceptors |
| `gcr.io/tekton-releases/github.com/tektoncd/dashboard/cmd/dashboard:v0.46.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/dashboard/cmd/dashboard:v0.46.x` | Tekton Dashboard |
| `gcr.io/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/operator/cmd/operator:v0.76.x` | Tekton Operator |
| `gcr.io/tekton-releases/github.com/tektoncd/results/cmd/api:v0.10.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/results/cmd/api:v0.10.x` | Results API（可选） |
| `gcr.io/tekton-releases/github.com/tektoncd/results/cmd/watcher:v0.10.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/results/cmd/watcher:v0.10.x` | Results Watcher（可选） |
| `gcr.io/tekton-releases/github.com/tektoncd/results/cmd/web:v0.10.x` | `192.168.1.61/tekton-releases/github.com/tektoncd/results/cmd/web:v0.10.x` | Results Web（可选） |

#### Tekton Task 步骤镜像

| 原始镜像 | Harbor 目标路径 | 用途 |
|---------|---------------|------|
| `gcr.io/kaniko-project/executor:latest` | `192.168.1.61/tekton/kaniko-project/executor:latest` | Kaniko 镜像构建 |
| `docker.io/maven:3.9-eclipse-temurin-17` | `192.168.1.61/tekton/maven:3.9-eclipse-temurin-17` | Maven Java 构建 |
| `docker.io/alpine/git:2.40` | `192.168.1.61/tekton/alpine/git:2.40` | Git 操作 |
| `docker.io/curlimages/curl:8.0` | `192.168.1.61/tekton/curlimages/curl:8.0` | HTTP 请求/通知 |
| `gcr.io/tekton-releases/github.com/tektoncd/catalog/task/git-clone:0.9` | `192.168.1.61/tekton-releases/github.com/tektoncd/catalog/task/git-clone:0.9` | git-clone ClusterTask |

> **注意：** 上述版本号中的 `x` 需要替换为实际安装的版本号。建议先在有外网服务器上执行 `kubectl apply` 查看实际拉取的镜像版本，再进行镜像同步。

#### 批量镜像同步脚本

```bash
#!/bin/bash
# 在有外网的服务器上执行
# 用途：批量拉取 Tekton 相关镜像并推送到 Harbor

HARBOR="192.168.1.61:80"
HARBOR_USER="admin"
HARBOR_PASS="Harbor12345"

# 登录 Harbor
echo "$HARBOR_PASS" | docker login $HARBOR -u "$HARBOR_USER" --password-stdin

# Tekton 核心镜像（版本号请根据实际安装版本调整）
declare -A IMAGES=(
  ["gcr.io/kaniko-project/executor:latest"]="$HARBOR/tekton/kaniko-project/executor:latest"
  ["docker.io/maven:3.9-eclipse-temurin-17"]="$HARBOR/tekton/maven:3.9-eclipse-temurin-17"
  ["docker.io/alpine/git:2.40"]="$HARBOR/tekton/alpine/git:2.40"
  ["docker.io/curlimages/curl:8.0"]="$HARBOR/tekton/curlimages/curl:8.0"
)

for src in "${!IMAGES[@]}"; do
  dst="${IMAGES[$src]}"
  echo "=== Processing: $src -> $dst ==="
  docker pull "$src" || { echo "FAILED to pull $src"; continue; }
  docker tag "$src" "$dst"
  docker push "$dst" || { echo "FAILED to push $dst"; continue; }
  echo "=== Done: $dst ==="
done

echo "All images synced to Harbor!"
```

### 10.2 Harbor 仓库准备

```bash
# 在 Harbor 中创建以下项目（通过 Harbor UI 或 API）
# 1. tekton-releases  - 存放 Tekton 核心组件镜像
# 2. tekton           - 存放 Task 步骤镜像（Kaniko、Maven 等）
# 3. tektoncd         - 存放 Tekton Dashboard 等组件（如果 YAML 中使用 ghcr.io）

# Harbor 项目创建 API 示例：
# curl -u "admin:Harbor12345" -X POST "http://192.168.1.61/api/v2.0/projects" \
#   -H "Content-Type: application/json" \
#   -d '{"project_name":"tekton","public":true}'
```

### 10.3 Nexus 私服准备（可选）

```bash
# 如果使用 Nexus 作为 Maven 私服，需要预先配置：
# 1. 在 Nexus 中创建以下仓库：
#    - maven-central (proxy): 代理 https://repo.maven.apache.org/maven2/
#    - maven-releases (hosted): 存放内部发布包
#    - maven-snapshots (hosted): 存放内部快照包
#    - maven-public (group): 将以上三个仓库组合

# 2. 预下载项目依赖到 Nexus（在有外网的服务器上）：
#    将项目 pom.xml 中的依赖下载到 Nexus 代理仓库中
#    mvn dependency:resolve -DremoteRepositories=http://nexus:8081/repository/maven-public/

# 3. 或者使用离线 Maven 本地缓存：
#    在有外网的机器上执行一次完整构建：
#    mvn clean package -Dmaven.repo.local=/tmp/maven-cache
#    然后将 /tmp/maven-cache 打包传输到离线环境
#    在 Task 中挂载到 /root/.m2/repository
```

### 10.4 YAML 文件离线准备

```bash
# 在有外网的服务器上执行：

# 1. 下载所有需要的 YAML
curl -sL https://storage.googleapis.com/tekton-releases/operator/latest/release.yaml -o tekton-operator.yaml
curl -sL https://storage.googleapis.com/tekton-releases/dashboard/latest/latest-release.yaml -o tekton-dashboard.yaml

# 2. 批量替换镜像地址
for file in tekton-operator.yaml tekton-dashboard.yaml; do
  sed -i 's|gcr.io/tekton-releases|192.168.1.61/tekton-releases|g' "$file"
  sed -i 's|ghcr.io/tektoncd|192.168.1.61/tektoncd|g' "$file"
  sed -i 's|quay.io/|192.168.1.61/quay/|g' "$file"
  sed -i 's|registry.k8s.io/|192.168.1.61/k8s/|g' "$file"
  sed -i 's|docker.io/|192.168.1.61/dockerio/|g' "$file"
  sed -i 's|gcr.io/|192.168.1.61/gcr/|g' "$file"
done

# 3. 检查替换结果
grep -h "image:" tekton-operator.yaml tekton-dashboard.yaml | sort -u

# 4. 传输到 Master 节点
scp tekton-operator.yaml tekton-dashboard.yaml root@<Master节点IP>:/root/
```

### 10.5 离线环境验证清单

```bash
# 在离线集群 Master 节点上执行以下验证：

# 1. 验证所有镜像可从 Harbor 拉取
for img in \
  "192.168.1.61/tekton/kaniko-project/executor:latest" \
  "192.168.1.61/tekton/maven:3.9-eclipse-temurin-17" \
  "192.168.1.61/tekton/alpine/git:2.40" \
  "192.168.1.61/tekton/curlimages/curl:8.0"; do
  echo "Testing: $img"
  crictl pull --insecure-registry "$img" && echo "OK" || echo "FAILED"
done

# 2. 验证 Harbor 连通性
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.61/api/v2.0/systeminfo
# 预期返回 200

# 3. 验证 Gitea 连通性
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.61:3000/
# 预期返回 200

# 4. 验证 Nexus 连通性（如果部署了 Nexus）
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.61:8081/service/rest/v1/status
# 预期返回 200

# 5. 验证 StorageClass
kubectl get storageclass local-path
# 预期：local-path 存在且为默认

# 6. 验证节点资源
kubectl top nodes
# 确认 Master 和 Worker 节点有足够资源
```
