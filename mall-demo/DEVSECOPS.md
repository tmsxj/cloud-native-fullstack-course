# DevSecOps 完整实践指南

> 本文档详细介绍了在Mall Demo项目中实施DevSecOps的完整方案，包括安全工具链、SBOM管理、安全门禁配置等内容。

---

## 目录

1. [DevSecOps概述](#1-devsecops概述)
2. [安全扫描工具链](#2-安全扫描工具链)
3. [SBOM软件物料清单](#3-sbom软件物料清单)
4. [安全门禁配置](#4-安全门禁配置)
5. [完整流水线示例](#5-完整流水线示例)
6. [离线环境适配](#6-离线环境适配)
7. [故障排查](#7-故障排查)

---

## 1. DevSecOps概述

### 1.1 什么是DevSecOps

DevSecOps是一种将安全实践集成到DevOps流程中的方法论。它强调在软件开发生命周期的每个阶段都融入安全考虑，而不是将安全作为最后的检查点。

**核心理念：**
- **安全左移 (Shift Left Security)**：在开发早期发现和修复安全问题
- **自动化优先**：将安全扫描自动化集成到CI/CD流水线
- **持续监控**：在生产环境持续监控安全状态
- **共享责任**：开发、运维、安全团队共同承担安全责任

### 1.2 为什么需要DevSecOps

传统安全模式的痛点：
| 传统模式 | DevSecOps模式 |
|---------|--------------|
| 安全测试在开发后期进行 | 安全测试贯穿整个SDLC |
| 安全团队与开发团队分离 | 安全是每个人的责任 |
| 手动安全审查 | 自动化安全扫描 |
| 修复成本高 | 早期发现问题，低成本修复 |
| 发布延迟 | 安全不阻碍发布 |

**收益：**
- 减少70%以上的生产环境安全漏洞
- 缩短50%的安全修复时间
- 提高开发团队的安全意识
- 满足合规要求（等保2.0、GDPR等）

### 1.3 安全左移理念

安全左移是指在软件开发生命周期中尽早进行安全测试和修复。

```
传统模式:  开发 → 测试 → 部署 → [安全扫描] → 发现漏洞 → 回滚修复

DevSecOps: [安全扫描] → 开发 → [安全扫描] → 测试 → [安全扫描] → 部署 → [持续监控]
                ↑              ↑              ↑
              代码提交      构建阶段       镜像扫描
```

---

## 2. 安全扫描工具链

### 2.1 静态应用安全测试(SAST)

#### SonarQube代码质量扫描

SonarQube是业界领先的代码质量管理平台，支持多种编程语言的静态分析。

**核心功能：**
- 代码异味检测
- 安全漏洞识别
- 代码覆盖率分析
- 技术债务评估

**Maven集成配置：**

```xml
<!-- pom.xml 中添加SonarQube插件 -->
<plugin>
    <groupId>org.sonarsource.scanner.maven</groupId>
    <artifactId>sonar-maven-plugin</artifactId>
    <version>3.9.1.2184</version>
</plugin>

<!-- JaCoCo覆盖率插件 -->
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>0.8.11</version>
    <executions>
        <execution>
            <goals>
                <goal>prepare-agent</goal>
            </goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>test</phase>
            <goals>
                <goal>report</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

**Go项目集成配置：**

```yaml
# .gitlab-ci.yml 中的SonarQube配置
security:sonarqube:
  stage: security
  image: sonarsource/sonar-scanner-cli:latest
  script:
    - sonar-scanner
        -Dsonar.projectKey=mall-demo-b
        -Dsonar.sources=.
        -Dsonar.go.coverage.reportPaths=coverage.out
        -Dsonar.qualitygate.wait=true
```

**sonar-project.properties配置：**

```properties
# SonarQube项目配置
sonar.projectKey=mall-demo
sonar.projectName=Mall Demo
sonar.projectVersion=1.0

# 源代码路径
sonar.sources=.
sonar.exclusions=**/vendor/**,**/bin/**,**/target/**

# 测试配置
sonar.tests=.
sonar.test.inclusions=**/*_test.go,**/*Test.java

# 覆盖率报告路径
sonar.go.coverage.reportPaths=coverage.out
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml

# 编码设置
sonar.sourceEncoding=UTF-8
```

#### 漏洞规则配置

SonarQube内置了丰富的安全规则库：

| 规则类别 | 说明 | 严重程度 |
|---------|------|---------|
| SQL注入 | 检测不安全的SQL拼接 | 阻断 |
| XSS攻击 | 跨站脚本漏洞 | 阻断 |
| 硬编码凭证 | 密码、密钥硬编码 | 严重 |
| 不安全的反序列化 | 反序列化漏洞 | 阻断 |
| 敏感数据泄露 | 日志中打印敏感信息 | 严重 |

**自定义规则配置：**

```java
// 在SonarQube管理界面配置自定义规则
// 或使用API导入自定义规则集

// 示例：禁止直接打印敏感信息
@Rule(
    key = "NoSensitiveLogging",
    name = "禁止日志打印敏感信息",
    description = "检测代码中是否直接打印密码、token等敏感信息",
    priority = Priority.BLOCKER,
    tags = {"security", "sensitive-data"}
)
public class NoSensitiveLoggingRule extends IssuableSubscriptionVisitor {
    // 规则实现
}
```

#### 质量门禁设置

质量门禁(Quality Gate)是代码合并的门槛条件。

**推荐配置：**

```yaml
# 质量门禁条件
conditions:
  # 覆盖率
  - metric: coverage
    operator: LT
    threshold: 80
  
  # 重复代码
  - metric: duplicated_lines_density
    operator: GT
    threshold: 3
  
  # 阻断问题
  - metric: blocker_violations
    operator: GT
    threshold: 0
  
  # 严重问题
  - metric: critical_violations
    operator: GT
    threshold: 0
  
  # 安全热点
  - metric: security_hotspots_reviewed
    operator: LT
    threshold: 100
```

### 2.2 软件成分分析(SCA)

#### 依赖漏洞扫描

SCA工具用于分析项目依赖的第三方组件，识别已知漏洞。

**OWASP Dependency Check (Maven)：**

```xml
<!-- pom.xml 配置 -->
<plugin>
    <groupId>org.owasp</groupId>
    <artifactId>dependency-check-maven</artifactId>
    <version>8.4.0</version>
    <configuration>
        <failBuildOnCVSS>7</failBuildOnCVSS>
        <suppressionFiles>
            <suppressionFile>dependency-check-suppressions.xml</suppressionFile>
        </suppressionFiles>
    </configuration>
</plugin>
```

**govulncheck (Go)：**

```bash
# 安装govulncheck
go install golang.org/x/vuln/cmd/govulncheck@latest

# 扫描项目
govulncheck ./...

# 生成JSON报告
govulncheck -format json ./... > vuln-report.json
```

#### Maven/Go依赖检查

**Maven依赖树分析：**

```bash
# 查看完整依赖树
mvn dependency:tree

# 分析依赖冲突
mvn dependency:analyze

# 仅查看有漏洞的依赖
mvn org.owasp:dependency-check-maven:check
```

**Go依赖检查：**

```bash
# 查看依赖列表
go list -m all

# 查看依赖详情
go mod graph

# 清理未使用依赖
go mod tidy

# 验证依赖
go mod verify
```

#### 许可证合规检查

**FOSSA集成：**

```yaml
# .gitlab-ci.yml
license:check:
  stage: security
  image: fossa/fossa-cli:latest
  script:
    - fossa analyze
    - fossa test
```

**常用开源许可证风险等级：**

| 许可证 | 风险等级 | 说明 |
|-------|---------|------|
| MIT | 低 | 宽松许可 |
| Apache-2.0 | 低 | 宽松许可，含专利授权 |
| BSD | 低 | 宽松许可 |
| GPL-2.0/3.0 | 高 | 传染性许可 |
| LGPL | 中 | 弱传染性许可 |
| AGPL | 高 | 强传染性许可 |

### 2.3 容器镜像安全

#### Trivy镜像扫描

Trivy是Aqua Security开源的容器安全扫描工具，支持漏洞扫描、密钥检测、配置检查。

**安装Trivy：**

```bash
# 使用安装脚本
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# 或使用Docker
docker pull aquasec/trivy:latest
```

**镜像扫描命令：**

```bash
# 基础扫描
trivy image myapp:latest

# 指定严重级别
trivy image --severity HIGH,CRITICAL myapp:latest

# 生成JSON报告
trivy image --format json -o report.json myapp:latest

# 生成SARIF报告(GitLab兼容)
trivy image --format sarif -o report.sarif myapp:latest

# 扫描特定OS
trivy image --vuln-type os myapp:latest

# 扫描库依赖
trivy image --vuln-type library myapp:latest
```

**文件系统扫描：**

```bash
# 扫描源代码
trivy filesystem --scanners vuln,secret,config .

# 扫描特定目录
trivy fs --severity HIGH,CRITICAL /app
```

**GitLab CI集成：**

```yaml
security:trivy-scan:
  stage: security
  image: aquasec/trivy:latest
  script:
    # 文件系统扫描
    - trivy filesystem --scanners vuln,secret,config 
        --format sarif -o trivy-fs-report.sarif .
    # 镜像扫描
    - trivy image --format sarif -o trivy-image-report.sarif $IMAGE_NAME
  artifacts:
    reports:
      sast: trivy-fs-report.sarif
    paths:
      - trivy-*.sarif
```

#### 基础镜像安全

**选择安全的基础镜像：**

| 镜像类型 | 推荐选择 | 说明 |
|---------|---------|------|
| Java应用 | eclipse-temurin:17-jre-alpine | 官方维护，定期更新 |
| Go应用 | scratch / distroless | 最小化攻击面 |
| Node.js | node:18-alpine | 轻量级，安全更新及时 |
| Python | python:3.11-slim | 移除不必要的包 |

**Dockerfile安全实践：**

```dockerfile
# 使用特定版本标签，避免latest
FROM eclipse-temurin:17-jre-alpine@sha256:abc123...

# 使用非root用户
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# 最小化层数
COPY --chown=appuser:appgroup target/*.jar app.jar

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app.jar"]
```

#### 镜像签名验证

**Cosign镜像签名：**

```bash
# 安装Cosign
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# 生成密钥对
cosign generate-key-pair

# 签名镜像
cosign sign --key cosign.key $HARBOR_REGISTRY/myapp:$TAG

# 验证签名
cosign verify --key cosign.pub $HARBOR_REGISTRY/myapp:$TAG
```

**GitLab CI签名集成：**

```yaml
sign:image:
  stage: push
  image: bitnami/cosign:latest
  script:
    - cosign sign --key $COSIGN_PRIVATE_KEY $IMAGE_NAME
  only:
    - main
```

### 2.4 动态应用安全测试(DAST)

#### 运行时安全测试

DAST工具在应用运行时进行安全测试，模拟攻击者行为。

**OWASP ZAP集成：**

```yaml
# .gitlab-ci.yml
dast:scan:
  stage: security
  image: owasp/zap2docker-stable:latest
  script:
    - zap-baseline.py -t http://target-app:8080 -r zap-report.html
  artifacts:
    paths:
      - zap-report.html
  allow_failure: true
```

**GitLab内置DAST：**

```yaml
include:
  - template: DAST.gitlab-ci.yml

variables:
  DAST_WEBSITE: "http://target-app:8080"
  DAST_FULL_SCAN_ENABLED: "true"
```

#### API安全测试

**使用RESTler进行API模糊测试：**

```bash
# 编译RESTler
docker pull mcr.microsoft.com/restlerfuzzer/restler:latest

# 生成API规范
docker run -v $(pwd):/data restler compile /data/api_spec.json

# 执行测试
docker run -v $(pwd):/data restler fuzz /data/Compile
```

**Postman + Newman安全测试：**

```yaml
api:security-test:
  stage: security
  image: postman/newman:latest
  script:
    - newman run security-tests.json --reporters cli,junit
  artifacts:
    reports:
      junit: newman/*.xml
```

---

## 3. SBOM软件物料清单

### 3.1 什么是SBOM

SBOM (Software Bill of Materials) 是软件物料清单，记录了软件产品使用的所有组件及其依赖关系。

**SBOM的重要性：**
- 快速响应供应链安全事件（如Log4j漏洞）
- 满足合规要求（美国EO 14028）
- 许可证合规管理
- 软件资产管理

**主流SBOM格式：**

| 格式 | 标准组织 | 特点 |
|-----|---------|------|
| CycloneDX | OWASP | 轻量级，安全导向 |
| SPDX | Linux基金会 | 许可证导向，ISO标准 |
| SWID | ISO/IEC 19770-2 | 软件识别标签 |

### 3.2 生成SBOM

#### Maven: cyclonedx-maven-plugin

```xml
<!-- pom.xml 配置 -->
<plugin>
    <groupId>org.cyclonedx</groupId>
    <artifactId>cyclonedx-maven-plugin</artifactId>
    <version>2.7.9</version>
    <executions>
        <execution>
            <phase>package</phase>
            <goals>
                <goal>makeAggregateBom</goal>
            </goals>
        </execution>
    </executions>
    <configuration>
        <projectType>application</projectType>
        <schemaVersion>1.5</schemaVersion>
        <includeBomSerialNumber>true</includeBomSerialNumber>
        <includeCompileScope>true</includeCompileScope>
        <includeProvidedScope>true</includeProvidedScope>
        <includeRuntimeScope>true</includeRuntimeScope>
        <includeSystemScope>true</includeSystemScope>
        <includeTestScope>false</includeTestScope>
        <includeLicenseText>false</includeLicenseText>
        <outputReactorProjects>true</outputReactorProjects>
        <outputFormat>json</outputFormat>
        <outputName>bom</outputName>
    </configuration>
</plugin>
```

**生成命令：**

```bash
# 生成聚合SBOM
mvn cyclonedx:makeAggregateBom

# 为单个模块生成
mvn cyclonedx:makeBom

# 输出位置
target/bom.json
target/bom.xml
```

#### Go: syft工具

**安装Syft：**

```bash
# 使用安装脚本
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# 或使用Docker
docker pull anchore/syft:latest
```

**生成SBOM：**

```bash
# 扫描Go模块
syft packages dir:. -o cyclonedx-json > sbom.json

# 扫描特定目录
syft packages dir:./cmd -o spdx-json > sbom.spdx.json

# 扫描容器镜像
syft packages $IMAGE_NAME -o cyclonedx-json > sbom.json

# 生成多种格式
syft packages dir:. -o cyclonedx-json=cyclonedx.json -o spdx-json=spdx.json -o syft-json=syft.json
```

**输出格式选项：**

| 格式 | 用途 |
|-----|------|
| cyclonedx-json | 标准CycloneDX格式 |
| cyclonedx-xml | XML格式CycloneDX |
| spdx-json | SPDX 2.3格式 |
| spdx-tag-value | SPDX标签值格式 |
| syft-json | Syft原生格式 |
| table | 终端表格展示 |

### 3.3 SBOM归档和追溯

**SBOM版本管理：**

```bash
# 命名规范
sbom-{project}-{version}-{timestamp}.json

# 示例
sbom-mall-demo-a-1.2.3-20240115-143022.json
```

**Harbor SBOM存储：**

```bash
# 推送SBOM到Harbor附件
curl -X POST "https://$HARBOR/api/v2.0/projects/$PROJECT/repositories/$REPO/artifacts/$TAG/accessories" \
  -H "Content-Type: application/vnd.cyclonedx+json" \
  -H "Authorization: Basic $TOKEN" \
  -d @sbom.json
```

**GitLab CI集成：**

```yaml
sbom:generate:
  stage: .post
  script:
    # Maven项目
    - mvn cyclonedx:makeAggregateBom
    # Go项目
    - syft packages dir:. -o cyclonedx-json > sbom.json
  artifacts:
    paths:
      - target/bom.json
      - sbom.json
    expire_in: 1 year

sbom:upload:
  stage: .post
  needs:
    - job: sbom:generate
      artifacts: true
  script:
    - ./scripts/upload-sbom.sh
```

---

## 4. 安全门禁配置

### 4.1 阻断策略

#### 高危漏洞阻断

```yaml
# GitLab CI安全门禁配置
security:gate:
  stage: security
  script:
    # 解析Trivy报告
    - |
      CRITICAL_COUNT=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' trivy-report.json)
      if [ "$CRITICAL_COUNT" -gt 0 ]; then
        echo "ERROR: Found $CRITICAL_COUNT critical vulnerabilities"
        exit 1
      fi
    # 解析SonarQube质量门禁
    - |
      STATUS=$(curl -s -u $SONAR_TOKEN: "$SONAR_HOST/api/qualitygates/project_status?projectKey=$CI_PROJECT_NAME" | jq -r '.projectStatus.status')
      if [ "$STATUS" != "OK" ]; then
        echo "ERROR: SonarQube Quality Gate failed"
        exit 1
      fi
  allow_failure: false
```

#### 代码覆盖率门禁

```yaml
# JaCoCo覆盖率检查
coverage:gate:
  stage: test
  script:
    - mvn jacoco:check
  coverage: '/Total.*?([0-9]{1,3})%/'
```

**JaCoCo配置：**

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <configuration>
        <rules>
            <rule>
                <element>BUNDLE</element>
                <limits>
                    <limit>
                        <counter>INSTRUCTION</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.80</minimum>
                    </limit>
                    <limit>
                        <counter>BRANCH</counter>
                        <value>COVEREDRATIO</value>
                        <minimum>0.70</minimum>
                    </limit>
                </limits>
            </rule>
        </rules>
    </configuration>
</plugin>
```

#### 技术债务门禁

**SonarQube技术债务配置：**

```properties
# 技术债务比例限制
sonar.technicalDebt.rating.thresholds=0.05,0.10,0.20,0.50

# 代码重复率限制
sonar.cpd.exclusions=**/generated/**,**/proto/**
```

### 4.2 例外处理

#### 漏洞白名单

**Trivy忽略配置 (.trivyignore)：**

```
# 格式: CVE-ID # 原因 # 到期日期
CVE-2023-1234 # 不影响生产环境，等待官方修复 # 2024-03-01
CVE-2023-5678 # 误报，已确认不存在 # 2024-06-01

# 按包忽略
CVE-2023-9999 # pkg:github.com/example/lib # 2024-12-31
```

**OWASP Dependency Check抑制文件：**

```xml
<!-- dependency-check-suppressions.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
    <suppress>
        <notes><![CDATA[
            此CVE不影响当前使用场景，等待官方修复
        ]]></notes>
        <cve>CVE-2023-1234</cve>
        <packageUrl regex="true">^pkg:maven/com\.example/.*$</packageUrl>
        <cpe>cpe:/a:example:library</cpe>
        <vulnerabilityName regex="true">.*</vulnerabilityName>
        <until>2024-03-01</until>
    </suppress>
</suppressions>
```

#### 临时豁免流程

```yaml
# 豁免审批流程
security:waiver:
  stage: security
  script:
    - echo "Security waiver requested for $CI_COMMIT_SHA"
    - |
      curl -X POST "$SECURITY_API/waivers" \
        -H "Authorization: Bearer $SECURITY_TOKEN" \
        -d "{
          \"commit\": \"$CI_COMMIT_SHA\",
          \"reason\": \"$WAIVER_REASON\",
          \"approver\": \"$WAIVER_APPROVER\",
          \"expiry\": \"$WAIVER_EXPIRY\"
        }"
  when: manual
  only:
    variables:
      - $WAIVER_REQUEST == "true"
```

---

## 5. 完整流水线示例

### 5.1 流水线流程图

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Git Push  │────▶│  SAST扫描   │────▶│  SCA扫描    │────▶│   构建      │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
  代码提交            SonarQube         依赖检查           编译打包
  触发流水线          代码质量          漏洞扫描           单元测试

┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  镜像扫描   │────▶│   DAST      │────▶│   部署      │────▶│ 运行时监控  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
  Trivy扫描           API安全测试        K8s部署            Falco监控
  漏洞检测            模糊测试           ArgoCD同步          异常检测
```

### 5.2 完整GitLab CI配置

```yaml
# 完整DevSecOps流水线
stages:
  - build
  - test
  - security-sast
  - security-sca
  - package
  - container-security
  - dast
  - deploy
  - monitor

variables:
  SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
  GIT_DEPTH: "0"
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: "/certs"

# ========== BUILD STAGE ==========
build:
  stage: build
  script:
    - mvn compile
  artifacts:
    paths:
      - target/classes/

# ========== TEST STAGE ==========
test:
  stage: test
  needs: [build]
  script:
    - mvn test
  artifacts:
    reports:
      junit: target/surefire-reports/*.xml
    paths:
      - target/site/jacoco/

# ========== SAST STAGE ==========
sonarqube:
  stage: security-sast
  needs: [test]
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn sonar:sonar -Dsonar.qualitygate.wait=true
  allow_failure: false

gosec:
  stage: security-sast
  image: securego/gosec:latest
  script:
    - gosec -fmt sarif -out gosec.sarif ./...
  artifacts:
    reports:
      sast: gosec.sarif
  allow_failure: true

# ========== SCA STAGE ==========
dependency-check:
  stage: security-sca
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn org.owasp:dependency-check-maven:check -DfailBuildOnCVSS=7
  artifacts:
    paths:
      - target/dependency-check-report.html
  allow_failure: false

trivy-fs:
  stage: security-sca
  image: aquasec/trivy:latest
  script:
    - trivy fs --scanners vuln,secret --format sarif -o trivy-fs.sarif .
  artifacts:
    reports:
      sast: trivy-fs.sarif
  allow_failure: true

# ========== PACKAGE STAGE ==========
package:
  stage: package
  needs: [sonarqube, dependency-check]
  script:
    - mvn package -DskipTests
  artifacts:
    paths:
      - target/*.jar

# ========== CONTAINER SECURITY STAGE ==========
build-image:
  stage: container-security
  image: docker:24-dind
  services: [docker:24-dind]
  needs: [package]
  script:
    - docker build -t $IMAGE_NAME .
    - docker push $IMAGE_NAME

trivy-image:
  stage: container-security
  image: aquasec/trivy:latest
  needs: [build-image]
  script:
    - trivy image --exit-code 1 --severity HIGH,CRITICAL $IMAGE_NAME
  allow_failure: false

sbom:
  stage: container-security
  image: anchore/syft:latest
  needs: [build-image]
  script:
    - syft packages $IMAGE_NAME -o cyclonedx-json > sbom.json
  artifacts:
    paths:
      - sbom.json

# ========== DAST STAGE ==========
dast:
  stage: dast
  image: owasp/zap2docker-stable:latest
  needs: [deploy-staging]
  script:
    - zap-baseline.py -t $STAGING_URL -r zap-report.html
  artifacts:
    paths:
      - zap-report.html
  allow_failure: true

# ========== DEPLOY STAGE ==========
deploy-staging:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: staging
  script:
    - kubectl apply -f k8s/staging/

deploy-production:
  stage: deploy
  image: bitnami/kubectl:latest
  needs: [trivy-image, dast]
  environment:
    name: production
  when: manual
  only:
    - main
  script:
    - kubectl apply -f k8s/production/

# ========== MONITOR STAGE ==========
falco-alert:
  stage: monitor
  image: alpine/curl:latest
  script:
    - echo "Falco alerts monitoring..."
  when: always
```

---

## 6. 离线环境适配

### 6.1 SonarQube离线部署

#### 离线安装步骤

```bash
# 1. 在有网络环境下载镜像
docker pull sonarqube:10.3-community
docker pull postgres:15-alpine

# 保存镜像
docker save sonarqube:10.3-community > sonarqube.tar
docker save postgres:15-alpine > postgres.tar

# 2. 传输到离线环境并加载
docker load < sonarqube.tar
docker load < postgres.tar
```

#### 离线插件安装

```bash
# 下载插件（有网络环境）
PLUGINS=(
  "https://github.com/SonarSource/sonar-java/releases/download/7.30.0.34429/sonar-java-plugin-7.30.0.34429.jar"
  "https://github.com/SonarSource/sonar-go/releases/download/1.15.0.4655/sonar-go-plugin-1.15.0.4655.jar"
  "https://github.com/dependency-check/dependency-check-sonar-plugin/releases/download/3.0.1/sonar-dependency-check-plugin-3.0.1.jar"
)

for url in "${PLUGINS[@]}"; do
  wget -P plugins/ "$url"
done

# 离线安装
# 将plugins目录挂载到SonarQube容器
# /opt/sonarqube/extensions/plugins
```

### 6.2 Trivy离线漏洞数据库

```bash
# 下载漏洞数据库（有网络环境）
trivy image --download-db-only

# 导出数据库
tar -czf trivy-db.tar.gz ~/.cache/trivy/db/

# 离线环境导入
mkdir -p ~/.cache/trivy/db/
tar -xzf trivy-db.tar.gz -C ~/.cache/trivy/db/

# 使用离线数据库扫描
trivy image --skip-db-update myapp:latest
```

### 6.3 私有依赖仓库配置

#### Maven私有仓库

```xml
<!-- settings.xml -->
<settings>
  <mirrors>
    <mirror>
      <id>internal-repository</id>
      <name>Internal Mirror</name>
      <url>https://nexus.company.com/repository/maven-public/</url>
      <mirrorOf>*</mirrorOf>
    </mirror>
  </mirrors>
  
  <profiles>
    <profile>
      <id>offline</id>
      <repositories>
        <repository>
          <id>internal</id>
          <url>https://nexus.company.com/repository/maven-releases/</url>
        </repository>
      </repositories>
    </profile>
  </profiles>
</settings>
```

#### Go私有仓库

```bash
# 配置Go环境变量
export GOPROXY=https://goproxy.company.com,direct
export GONOSUMDB=*.company.com
export GOPRIVATE=*.company.com

# 配置Git认证
git config --global url."https://$TOKEN@git.company.com/".insteadOf "https://git.company.com/"
```

---

## 7. 故障排查

### 7.1 安全扫描失败处理

#### SonarQube连接失败

```bash
# 检查连接
curl -u $SONAR_TOKEN: $SONAR_HOST/api/system/status

# 常见错误及解决
# 1. 证书错误
# 解决：导入自签名证书到Java信任库
keytool -import -alias sonarqube -file sonarqube.crt -keystore $JAVA_HOME/lib/security/cacerts

# 2. 内存不足
# 解决：增加Maven内存设置
export MAVEN_OPTS="-Xmx2g -XX:MaxMetaspaceSize=512m"
```

#### Trivy数据库更新失败

```bash
# 检查网络连接
curl -I https://ghcr.io/v2/aquasecurity/trivy-db/manifests/latest

# 使用代理
export HTTPS_PROXY=http://proxy.company.com:8080
trivy image --reset myapp:latest

# 完全离线模式
trivy image --skip-db-update --skip-java-db-update myapp:latest
```

### 7.2 误报处理

#### 识别误报

```bash
# 查看漏洞详情
trivy image --format json myapp:latest | jq '.Results[].Vulnerabilities[] | select(.VulnerabilityID == "CVE-2023-XXXX")'

# 验证是否真实存在
# 1. 检查代码是否使用了相关功能
# 2. 检查官方CVE说明
# 3. 检查官方修复版本
```

#### 提交误报反馈

```bash
# Trivy误报
# 在GitHub提交Issue: https://github.com/aquasecurity/trivy/issues

# SonarQube误报
# 在SonarSource社区反馈: https://community.sonarsource.com/
```

### 7.3 性能优化

#### 扫描性能优化

```yaml
# 并行扫描优化
security:parallel:
  parallel:
    matrix:
      - SERVICE: [user-service, order-service, inventory-service]
  script:
    - trivy fs --severity HIGH,CRITICAL ./$SERVICE

# 增量扫描
trivy fs --skip-dirs "vendor/,node_modules/" .

# 缓存优化
cache:
  key: trivy-db
  paths:
    - .trivy-cache/
```

#### 内存优化

```bash
# Maven内存设置
export MAVEN_OPTS="-Xmx4g -XX:+UseG1GC"

# Trivy内存限制
trivy image --memory 4g myapp:latest

# SonarQube分析优化
mvn sonar:sonar -Dsonar.scm.exclusions.disabled=true
```

---

## 附录

### A. 安全工具对比

| 工具 | 类型 | 支持语言 | 开源 | 集成难度 |
|-----|------|---------|------|---------|
| SonarQube | SAST | 多语言 | 是 | 中 |
| Trivy | SCA/镜像 | 多语言 | 是 | 低 |
| Gosec | SAST | Go | 是 | 低 |
| OWASP DC | SCA | Java/.NET | 是 | 中 |
| Snyk | SCA/SAST | 多语言 | 否 | 低 |
| Checkmarx | SAST | 多语言 | 否 | 高 |

### B. 参考资源

- [OWASP DevSecOps Guideline](https://owasp.org/www-project-devsecops-guideline/)
- [CycloneDX Specification](https://cyclonedx.org/specification/overview/)
- [SPDX Specification](https://spdx.dev/specifications/)
- [NIST SSDF](https://csrc.nist.gov/projects/ssdf)
- [CNCF Cloud Native Security](https://github.com/cncf/tag-security)

### C. 安全检查清单

**代码提交前：**
- [ ] 本地运行单元测试
- [ ] 本地运行安全扫描
- [ ] 代码审查通过
- [ ] 敏感信息检查

**合并前：**
- [ ] SonarQube质量门禁通过
- [ ] 依赖漏洞扫描通过
- [ ] 代码覆盖率达标
- [ ] 安全审查通过

**发布前：**
- [ ] 容器镜像扫描通过
- [ ] SBOM已生成
- [ ] 镜像已签名
- [ ] DAST扫描完成

---

*文档版本: 1.0*
*最后更新: 2024年*
