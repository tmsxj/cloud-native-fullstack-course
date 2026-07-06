# SonarQube 离线部署指南

本文档介绍如何在离线环境中部署 SonarQube 10.x 社区版，用于代码质量和安全扫描。

## 目录

1. [环境要求](#环境要求)
2. [离线部署步骤](#离线部署步骤)
3. [插件离线安装](#插件离线安装)
4. [GitLab CI 集成](#gitlab-ci-集成)
5. [Maven 集成](#maven-集成)
6. [Go 集成](#go-集成)
7. [故障排查](#故障排查)

---

## 环境要求

### 硬件要求

| 组件 | 最低配置 | 推荐配置 |
|------|---------|---------|
| CPU | 2核 | 4核+ |
| 内存 | 4GB | 8GB+ |
| 磁盘 | 20GB | 100GB+ SSD |

### 软件要求

- Docker 20.10+
- Docker Compose 2.0+
- PostgreSQL 13+ (使用容器部署)

### 端口要求

- 9000: SonarQube Web 界面
- 5432: PostgreSQL 数据库

---

## 离线部署步骤

### 1. 准备离线镜像

在有网络的环境中下载所需镜像：

```bash
# 拉取镜像
docker pull sonarqube:10.3-community
docker pull postgres:15-alpine

# 保存镜像
docker save sonarqube:10.3-community > sonarqube-10.3.tar
docker save postgres:15-alpine > postgres-15.tar

# 传输到离线环境后加载
docker load < sonarqube-10.3.tar
docker load < postgres-15.tar
```

### 2. 创建数据目录

```bash
# 创建持久化目录
mkdir -p /data/sonarqube/{data,logs,extensions}
mkdir -p /data/postgresql/{data,backup}

# 设置权限（SonarQube使用非root用户运行）
chown -R 1000:1000 /data/sonarqube
chmod -R 755 /data/sonarqube
```

### 3. 启动服务

使用 docker-compose 启动：

```bash
cd sonarqube
docker-compose up -d

# 查看日志
docker-compose logs -f sonarqube

# 等待服务启动完成（约1-2分钟）
```

### 4. 初始化配置

1. 访问 http://localhost:9000
2. 使用默认账号登录：
   - 用户名: `admin`
   - 密码: `admin`
3. 根据提示修改默认密码

### 5. 生成访问令牌

1. 点击右上角用户头像 → My Account → Security
2. 在 "Generate Tokens" 中输入令牌名称，如 `gitlab-ci`
3. 点击 Generate 生成令牌
4. **立即复制保存令牌**，刷新页面后将无法再次查看

---

## 插件离线安装

### 下载插件

在有网络的环境中下载所需插件：

```bash
mkdir -p sonarqube-plugins
cd sonarqube-plugins

# Java 插件
wget https://github.com/SonarSource/sonar-java/releases/download/7.30.0.34429/sonar-java-plugin-7.30.0.34429.jar

# Go 插件
wget https://github.com/SonarSource/sonar-go/releases/download/1.15.0.4655/sonar-go-plugin-1.15.0.4655.jar

# JavaScript/TypeScript 插件
wget https://github.com/SonarSource/SonarJS/releases/download/10.11.0.25043/sonar-javascript-plugin-10.11.0.25043.jar

# HTML 插件
wget https://github.com/SonarSource/sonar-html/releases/download/3.13.0.4821/sonar-html-plugin-3.13.0.4821.jar

# CSS 插件
wget https://github.com/SonarSource/sonar-css/releases/download/1.15.0.4675/sonar-css-plugin-1.15.0.4675.jar

# XML 插件
wget https://github.com/SonarSource/sonar-xml/releases/download/2.10.0.4108/sonar-xml-plugin-2.10.0.4108.jar

# 依赖检查插件
wget https://github.com/dependency-check/dependency-check-sonar-plugin/releases/download/3.0.1/sonar-dependency-check-plugin-3.0.1.jar

# Git 插件（通常已内置）
# wget https://github.com/SonarSource/sonar-scm-git/releases/download/...
```

### 安装插件

将下载的插件复制到 SonarQube 扩展目录：

```bash
# 复制插件到扩展目录
cp sonarqube-plugins/*.jar /data/sonarqube/extensions/plugins/

# 重启 SonarQube
docker-compose restart sonarqube

# 查看日志确认插件加载
docker-compose logs -f sonarqube | grep -i plugin
```

### 插件管理界面

1. 登录 SonarQube
2. Administration → Marketplace
3. 已安装的插件会显示在 "Installed" 标签页

---

## GitLab CI 集成

### 1. 配置 GitLab CI 变量

在 GitLab 项目中设置以下 CI/CD 变量：

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `SONAR_HOST_URL` | SonarQube 服务器地址 | `http://192.168.1.61:9000` |
| `SONAR_TOKEN` | 访问令牌 | `sqp_xxxxxxxxxxxx` |

设置路径：项目 → Settings → CI/CD → Variables

### 2. Maven 项目集成

```yaml
# .gitlab-ci.yml
sonarqube-check:
  stage: test
  image: maven:3.9-eclipse-temurin-17-alpine
  variables:
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
    GIT_DEPTH: "0"
  cache:
    key: "${CI_JOB_NAME}"
    paths:
      - .sonar/cache
  script:
    - mvn verify sonar:sonar
        -Dsonar.host.url=$SONAR_HOST_URL
        -Dsonar.token=$SONAR_TOKEN
        -Dsonar.qualitygate.wait=true
  allow_failure: false
  only:
    - merge_requests
    - main
    - develop
```

### 3. Go 项目集成

```yaml
# .gitlab-ci.yml
sonarqube-check:
  stage: test
  image:
    name: sonarsource/sonar-scanner-cli:latest
    entrypoint: [""]
  variables:
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
    GIT_DEPTH: "0"
  cache:
    key: "${CI_JOB_NAME}"
    paths:
      - .sonar/cache
  script:
    - sonar-scanner
        -Dsonar.projectKey=$CI_PROJECT_NAME
        -Dsonar.sources=.
        -Dsonar.host.url=$SONAR_HOST_URL
        -Dsonar.token=$SONAR_TOKEN
        -Dsonar.go.coverage.reportPaths=coverage.out
        -Dsonar.qualitygate.wait=true
  allow_failure: false
```

---

## Maven 集成

### pom.xml 配置

```xml
<project>
    <properties>
        <!-- SonarQube 配置 -->
        <sonar.host.url>http://192.168.1.61:9000</sonar.host.url>
        <sonar.projectKey>mall-demo-a</sonar.projectKey>
        <sonar.projectName>Mall Demo A - Spring Boot</sonar.projectName>
        <sonar.qualitygate.wait>true</sonar.qualitygate.wait>
        
        <!-- 代码覆盖率 -->
        <sonar.coverage.jacoco.xmlReportPaths>target/site/jacoco/jacoco.xml</sonar.coverage.jacoco.xmlReportPaths>
        
        <!-- 排除路径 -->
        <sonar.exclusions>**/generated/**,**/proto/**</sonar.exclusions>
    </properties>

    <build>
        <plugins>
            <!-- SonarQube 扫描插件 -->
            <plugin>
                <groupId>org.sonarsource.scanner.maven</groupId>
                <artifactId>sonar-maven-plugin</artifactId>
                <version>3.9.1.2184</version>
            </plugin>

            <!-- JaCoCo 覆盖率插件 -->
            <plugin>
                <groupId>org.jacoco</groupId>
                <artifactId>jacoco-maven-plugin</artifactId>
                <version>0.8.11</version>
                <executions>
                    <execution>
                        <id>prepare-agent</id>
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

            <!-- OWASP 依赖检查插件 -->
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

            <!-- CycloneDX SBOM 插件 -->
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
                    <outputFormat>json</outputFormat>
                    <outputName>bom</outputName>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
```

### 本地扫描命令

```bash
# 完整扫描（包含测试和覆盖率）
mvn clean verify sonar:sonar

# 仅扫描（跳过测试）
mvn sonar:sonar -DskipTests

# 指定 SonarQube 服务器
mvn sonar:sonar -Dsonar.host.url=http://192.168.1.61:9000 -Dsonar.token=YOUR_TOKEN

# 生成覆盖率报告
mvn jacoco:report

# 依赖漏洞检查
mvn org.owasp:dependency-check-maven:check

# 生成 SBOM
mvn cyclonedx:makeAggregateBom
```

---

## Go 集成

### sonar-project.properties 配置

```properties
# 项目标识
sonar.projectKey=mall-demo-b
sonar.projectName=Mall Demo B - Go
sonar.projectVersion=1.0

# 源代码路径
sonar.sources=.
sonar.exclusions=**/vendor/**,**/bin/**,**/*_test.go,**/docs/**

# 测试配置
sonar.tests=.
sonar.test.inclusions=**/*_test.go

# Go 特定配置
sonar.language=go
sonar.go.coverage.reportPaths=coverage.out
sonar.go.tests.reportPaths=report.json

# 编码设置
sonar.sourceEncoding=UTF-8

# 质量门禁
sonar.qualitygate.wait=true
```

### 本地扫描步骤

```bash
# 1. 安装 Sonar Scanner
# 下载地址: https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/

# 2. 运行测试并生成覆盖率报告
go test -v -race -coverprofile=coverage.out -covermode=atomic ./...

# 3. 生成测试报告（可选）
go test -json ./... > report.json

# 4. 运行 Sonar Scanner
sonar-scanner \
  -Dsonar.projectKey=mall-demo-b \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://192.168.1.61:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### 多模块项目配置

对于包含多个服务的 Go 项目：

```properties
# sonar-project.properties
sonar.projectKey=mall-demo-b
sonar.projectName=Mall Demo B - Go

# 多模块配置
sonar.modules=gateway,user-svc,order-svc

# Gateway 模块
gateway.sonar.projectName=API Gateway
gateway.sonar.sources=cmd/gateway,internal/gateway
gateway.sonar.go.coverage.reportPaths=coverage-gateway.out

# User Service 模块
user-svc.sonar.projectName=User Service
user-svc.sonar.sources=cmd/user-svc,internal/user
user-svc.sonar.go.coverage.reportPaths=coverage-user.out

# Order Service 模块
order-svc.sonar.projectName=Order Service
order-svc.sonar.sources=cmd/order-svc,internal/order
order-svc.sonar.go.coverage.reportPaths=coverage-order.out
```

---

## 故障排查

### 常见问题

#### 1. SonarQube 启动失败

**现象：** 容器启动后立即退出

**排查：**
```bash
# 查看日志
docker-compose logs sonarqube

# 检查权限
ls -la /data/sonarqube/

# 修复权限
chown -R 1000:1000 /data/sonarqube
```

**常见原因：**
- 数据目录权限不正确
- 内存不足（需要至少 4GB）
- 端口被占用

#### 2. 数据库连接失败

**现象：** 日志显示 PostgreSQL 连接错误

**解决：**
```bash
# 检查 PostgreSQL 状态
docker-compose ps postgres
docker-compose logs postgres

# 重置数据库（会丢失数据）
docker-compose down -v
docker-compose up -d
```

#### 3. 插件加载失败

**现象：** 插件未在 Marketplace 显示

**排查：**
```bash
# 检查插件文件权限
ls -la /data/sonarqube/extensions/plugins/

# 检查插件日志
docker-compose logs sonarqube | grep -i plugin

# 重启服务
docker-compose restart sonarqube
```

#### 4. 扫描失败 - 无法连接服务器

**现象：** CI 中扫描任务失败

**排查：**
```bash
# 从 CI Runner 测试连接
curl -I http://192.168.1.61:9000

# 检查防火墙
telnet 192.168.1.61 9000

# 验证令牌
curl -u YOUR_TOKEN: http://192.168.1.61:9000/api/system/status
```

#### 5. 内存不足错误

**现象：** 扫描过程中出现 OutOfMemoryError

**解决：**
```yaml
# docker-compose.yml 中增加内存限制
services:
  sonarqube:
    environment:
      - SONAR_SEARCH_JAVAOPTS=-Xmx2g -Xms2g
      - SONAR_WEB_JAVAOPTS=-Xmx1g -Xms1g
      - SONAR_CE_JAVAOPTS=-Xmx2g -Xms2g
```

### 性能优化

#### 1. 调整 Elasticsearch 内存

```yaml
# docker-compose.yml
services:
  sonarqube:
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
      - SONAR_SEARCH_JAVAOPTS=-Xmx2g -Xms2g -XX:+UseG1GC
```

#### 2. 数据库连接池优化

```yaml
# docker-compose.yml
services:
  sonarqube:
    environment:
      - SONAR_JDBC_URL=jdbc:postgresql://postgres:5432/sonar
      - SONAR_JDBC_USERNAME=sonar
      - SONAR_JDBC_PASSWORD=sonar
      - SONAR_JDBC_MAXACTIVE=60
      - SONAR_JDBC_MAXIDLE=10
      - SONAR_JDBC_MINIDLE=5
```

#### 3. 并行扫描优化

```yaml
# .gitlab-ci.yml
sonarqube-check:
  variables:
    SONAR_SCANNER_OPTS: "-Xmx2g -XX:+UseG1GC"
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
  cache:
    key: "${CI_JOB_NAME}"
    paths:
      - .sonar/cache
```

### 日志分析

```bash
# 查看实时日志
docker-compose logs -f sonarqube

# 查看最后 100 行
docker-compose logs --tail=100 sonarqube

# 查看特定日期日志
docker-compose logs --since="2024-01-01T00:00:00" sonarqube

# 导出日志
docker-compose logs sonarqube > sonarqube.log 2>&1
```

### 备份与恢复

#### 备份

```bash
#!/bin/bash
# backup-sonarqube.sh

BACKUP_DIR="/backup/sonarqube/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# 备份数据库
docker exec sonarqube_postgres pg_dump -U sonar sonar > $BACKUP_DIR/database.sql

# 备份配置和数据
tar -czf $BACKUP_DIR/data.tar.gz /data/sonarqube

echo "Backup completed: $BACKUP_DIR"
```

#### 恢复

```bash
#!/bin/bash
# restore-sonarqube.sh

BACKUP_DIR="$1"

# 停止服务
docker-compose down

# 恢复数据
tar -xzf $BACKUP_DIR/data.tar.gz -C /

# 恢复数据库
docker-compose up -d postgres
sleep 10
docker exec -i sonarqube_postgres psql -U sonar sonar < $BACKUP_DIR/database.sql

# 启动 SonarQube
docker-compose up -d sonarqube
```

---

## 参考资源

- [SonarQube 官方文档](https://docs.sonarqube.org/latest/)
- [SonarScanner for Maven](https://docs.sonarqube.org/latest/analysis/scan/sonarscanner-for-maven/)
- [SonarScanner 配置](https://docs.sonarqube.org/latest/analysis/scan/sonarscanner/)
- [SonarQube 插件库](https://docs.sonarqube.org/latest/instance-administration/plugin-version-matrix/)

---

*文档版本: 1.0*
*适用版本: SonarQube 10.x Community Edition*
