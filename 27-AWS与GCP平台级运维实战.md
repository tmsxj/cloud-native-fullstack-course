# 模块27：AWS与GCP平台级运维实战

---

## 一、理论核心

### 1.1 云平台运维核心职责

云平台运维（CloudOps/SRE）不是简单的服务器管理，而是涵盖身份治理、网络架构、成本优化、安全合规、自动化运维的系统性工程。AWS 和 GCP 作为全球前两大云厂商，其运维体系代表了行业最高标准。

| 职责维度 | AWS 运维重点 | GCP 运维重点 | 通用技能要求 |
|---------|-------------|-------------|------------|
| **身份治理** | IAM Policy、Role、SSO、Organizations | IAM、Service Account、Workload Identity、Cloud Identity | 最小权限原则、权限边界、临时凭证 |
| **网络架构** | VPC、Subnet、Security Group、NACL、Transit Gateway | VPC、Subnet、Firewall Rules、Cloud Interconnect | 网络分段、流量监控、DDoS防护 |
| **成本治理** | Cost Explorer、Budgets、Savings Plans、Reserved Instances | Billing、Budgets、Committed Use Discounts、SUD | 标签策略、成本分摊、资源优化 |
| **监控告警** | CloudWatch、X-Ray、CloudTrail、Config | Cloud Monitoring、Cloud Trace、Cloud Logging、Cloud Audit Logs | 指标采集、日志分析、链路追踪 |
| **安全合规** | GuardDuty、Inspector、Macie、Security Hub | Security Command Center、Chronicle、DLP API | 漏洞扫描、合规检查、威胁检测 |
| **自动化运维** | Systems Manager、Lambda、EventBridge、Step Functions | Cloud Scheduler、Cloud Functions、Workflows、Deployment Manager | 基础设施即代码、事件驱动、自动化修复 |

**关键要点**：
- AWS 和 GCP 的 IAM 模型有本质差异：AWS 基于 Role + Policy 的显式授权，GCP 基于 IAM + Service Account 的隐式继承
- 云平台运维的核心指标是 MTTR（平均修复时间）和 MTBF（平均故障间隔），而非传统的服务器在线率
- 成本治理是云平台运维的独有挑战，资源按需付费模式下，"用多少付多少"容易变成"用多少亏多少"
- 2025 年 AWS US-EAST-1 大规模故障影响 400 万+企业，云平台运维必须设计多区域容灾架构

### 1.2 AWS 核心运维服务矩阵

| 服务类别 | 服务名称 | 运维用途 | 对标GCP服务 |
|---------|---------|---------|-----------|
| **计算** | EC2 / Auto Scaling / Lambda | 虚拟机管理、弹性伸缩、Serverless | Compute Engine / MIG / Cloud Functions |
| **存储** | S3 / EBS / EFS | 对象存储、块存储、文件存储 | Cloud Storage / Persistent Disk / Filestore |
| **网络** | VPC / ELB / Route 53 / CloudFront | 虚拟网络、负载均衡、DNS、CDN | VPC / Cloud LB / Cloud DNS / Cloud CDN |
| **数据库** | RDS / DynamoDB / ElastiCache | 关系型/NoSQL/缓存数据库 | Cloud SQL / Firestore / Memorystore |
| **监控** | CloudWatch / X-Ray / CloudTrail | 指标监控、链路追踪、操作审计 | Cloud Monitoring / Cloud Trace / Cloud Logging |
| **安全** | IAM / KMS / WAF / GuardDuty | 身份管理、密钥加密、Web防火墙、威胁检测 | IAM / Cloud KMS / Cloud Armor / Security Command Center |
| **配置** | AWS Config / Systems Manager | 资源配置审计、自动化运维 | Cloud Asset Inventory / OS Config |
| **编排** | CloudFormation / ECS / EKS | 基础设施即代码、容器编排 | Deployment Manager / Cloud Run / GKE |

**关键要点**：
- CloudTrail 记录所有 API 调用，是故障排查和安全审计的"黑匣子"，必须启用并配置日志加密
- CloudWatch 的 AIOps 功能（CloudWatch Insights）可自动分析日志模式，定位异常根因
- AWS Config 持续监控资源配置变更，非合规配置自动标记，是安全合规的核心工具
- Systems Manager（SSM）提供无代理的远程管理、补丁自动化、参数存储，替代传统 SSH 登录

### 1.3 GCP 核心运维服务矩阵

| 服务类别 | 服务名称 | 运维用途 | 对标AWS服务 |
|---------|---------|---------|-----------|
| **计算** | Compute Engine / MIG / Cloud Functions | 虚拟机、托管实例组、函数计算 | EC2 / Auto Scaling / Lambda |
| **存储** | Cloud Storage / Persistent Disk / Filestore | 对象存储、块存储、文件存储 | S3 / EBS / EFS |
| **网络** | VPC / Cloud Load Balancing / Cloud DNS / Cloud CDN | 虚拟网络、负载均衡、DNS、CDN | VPC / ELB / Route 53 / CloudFront |
| **数据库** | Cloud SQL / Firestore / Memorystore / BigQuery | 关系型/NoSQL/缓存/数据仓库 | RDS / DynamoDB / ElastiCache / Redshift |
| **监控** | Cloud Monitoring / Cloud Trace / Cloud Logging | 指标监控、链路追踪、日志管理 | CloudWatch / X-Ray / CloudWatch Logs |
| **安全** | IAM / Cloud KMS / Cloud Armor / Security Command Center | 身份管理、密钥加密、WAF、安全中心 | IAM / KMS / WAF / GuardDuty |
| **配置** | Cloud Asset Inventory / OS Config | 资产清单、操作系统配置管理 | AWS Config / Systems Manager |
| **编排** | Deployment Manager / Cloud Run / GKE | 基础设施即代码、容器服务、K8s | CloudFormation / ECS / EKS |

**关键要点**：
- GCP 的 Cloud Monitoring 与 GKE 深度集成，自动采集容器指标，无需额外配置 Prometheus
- Cloud Trace 自动采样分布式链路，与 Cloud Logging 关联，实现"一键从日志跳转到链路"
- Security Command Center 提供统一的安全态势视图，整合漏洞、威胁、合规发现
- GKE 的 Autopilot 模式是全托管 K8s，节点管理完全由 Google 负责，运维负担最低

---

### 1.5 多云成本优化与出海合规

成本优化和合规是出海企业运维的核心职责，直接关系到公司利润和合法运营。

| 优化策略 | 适用场景 | 实施方式 | 节省比例 |
|----------|----------|----------|----------|
| 预留实例/包年包月 | 稳定长期负载（数据库、基础服务） | 购买1年/3年预留实例，相比按量最高折扣60% | 30-60% |
| 弹性伸缩（Auto Scaling） | 波动负载（Web/API服务） | 配置CPU/内存阈值自动扩缩容，低峰自动缩容 | 20-40% |
| Spot/抢占式实例 | 无状态计算任务（CI/CD、批处理） | 出价低于按量价，可被回收，适合容错任务 | 60-90% |
| 存储分层 | 数据生命周期管理 | 热数据SSD、温数据HDD、冷数据归档（S3 Glacier） | 30-50% |
| 账单分析与资源清理 | 发现闲置资源 | 定期导出账单CSV，按标签/项目分析，下线闲置实例 | 10-20% |
| 右 sizing | 实例规格与实际负载匹配 | CloudWatch监控后降配高配低用实例 | 15-30% |
| 跨Region部署优化 | 全球业务 | 选择低成本Region（如亚太-曼谷比东京便宜30%） | 20-40% |

| 合规要求 | 适用地区 | 核心要求 | 运维落地 |
|----------|----------|----------|----------|
| GDPR（欧盟） | 欧盟27国 | 数据最小化、用户同意权、被遗忘权、数据可携带权 | 用户数据存储在欧盟Region、提供数据导出接口、Cookie合规 |
| PDPA（新加坡） | 新加坡 | 数据保护令、同意机制、跨境传输限制 | 数据本地化存储、跨境传输需标准合同条款 |
| PIPL（中国） | 中国大陆 | 数据分类分级、跨境传输评估、个人信息处理同意 | 数据境内存储、敏感数据出境需安全评估 |
| LGPD（巴西） | 巴西 | 数据处理记录、DPO任命、用户权利响应 | 本地化存储、隐私政策公示、数据泄露72小时通知 |

**关键要点**：
- 成本优化的核心原则：不浪费（清理闲置）+ 不多花（预留折扣）+ 用对资源（right sizing）
- 弹性伸缩配置建议：最小实例数保证基础可用性，最大实例数防止成本失控，冷却时间避免频繁扩缩
- 出海合规的核心原则：数据本地化存储、跨境传输需合法基础、用户权利保障机制
- GDPR最严条款：第17条"被遗忘权"要求系统能够彻底删除用户数据，运维需实现数据删除API
- 合规不是一次性配置，需要持续审计：每季度进行合规检查，每年进行安全评估

---

## 二、实操演练

### 任务1：AWS IAM 身份治理与权限审计

**任务目标**：配置 AWS IAM 多账号组织架构，实施最小权限原则，定期审计权限使用情况。

**操作步骤**：

```bash
# 步骤1：配置AWS CLI多账号配置文件
mkdir -p ~/.aws
cat > ~/.aws/config << 'EOF'
[profile production]
region = us-east-1
output = json

[profile staging]
region = us-east-1
output = json

[profile dev]
region = us-east-1
output = json
EOF

cat > ~/.aws/credentials << 'EOF'
[production]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[staging]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

[dev]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
EOF

# 步骤2：创建跨账号只读运维角色（Production账号）
aws iam create-role \
    --role-name CrossAccountReadOnlyOps \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"AWS": "arn:aws:iam::STAGING-ACCOUNT-ID:root"},
            "Action": "sts:AssumeRole",
            "Condition": {
                "Bool": {"aws:MultiFactorAuthPresent": "true"}
            }
        }]
    }' \
    --profile production
# 预期输出：包含Role ARN的JSON

# 步骤3：为运维角色附加只读策略
aws iam attach-role-policy \
    --role-name CrossAccountReadOnlyOps \
    --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess \
    --profile production

# 步骤4：使用IAM Access Analyzer分析外部访问
aws accessanalyzer create-analyzer \
    --analyzer-name ExternalAccessAnalyzer \
    --type ACCOUNT \
    --profile production
# 预期输出：Analyzer ARN

# 步骤5：生成IAM凭证报告（审计用户密码和Access Key年龄）
aws iam generate-credential-report --profile production
aws iam get-credential-report --profile production | jq -r '.Content' | base64 -d > credential_report.csv
# 预期输出：CSV格式的凭证报告，包含所有用户的密码年龄、Access Key年龄、MFA状态

# 步骤6：查找超过90天未轮换的Access Key
awk -F',' 'NR>1 && $10>90 {print $1, $10}' credential_report.csv
# 预期输出：用户名和Access Key年龄（天数）

# 步骤7：使用AWS Config评估合规性
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "iam-password-policy",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "IAM_PASSWORD_POLICY"
        },
        "InputParameters": "{\"RequireUppercaseCharacters\":\"true\",\"RequireLowercaseCharacters\":\"true\",\"RequireSymbols\":\"true\",\"RequireNumbers\":\"true\",\"MinimumPasswordLength\":\"14\",\"PasswordReusePrevention\":\"24\",\"MaxPasswordAge\":\"90\"}"
    }' \
    --profile production
# 预期输出：ConfigRule的ARN和合规状态
```

**注意事项**：
- 跨账号角色必须配置 MFA 条件（`aws:MultiFactorAuthPresent: true`），防止凭证泄露后被滥用
- IAM Access Analyzer 自动分析资源策略，发现对外部账号或互联网的意外共享
- 凭证报告应每周生成一次，超过 90 天的 Access Key 强制轮换或删除
- AWS Config 规则应覆盖密码策略、S3 公开访问、安全组开放端口等关键合规项

### 任务2：AWS VPC 网络架构设计与故障排查

**任务目标**：设计多可用区 VPC 架构，配置网络流量监控，排查常见的网络连通性问题。

**操作步骤**：

```bash
# 步骤1：创建多可用区VPC（3个AZ）
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ProductionVPC},{Key=Environment,Value=production}]' \
    --query 'Vpc.VpcId' \
    --output text \
    --profile production)
echo "VPC ID: $VPC_ID"

# 步骤2：创建3个子网（每个AZ一个）
for i in 1 2 3; do
    AZ=$(aws ec2 describe-availability-zones \
        --query "AvailabilityZones[$((i-1))].ZoneName" \
        --output text \
        --profile production)
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block "10.0.${i}.0/24" \
        --availability-zone $AZ \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=PrivateSubnet-${i}},{Key=AZ,Value=${AZ}}]" \
        --query 'Subnet.SubnetId' \
        --output text \
        --profile production)
    echo "Subnet ${i} in ${AZ}: $SUBNET_ID"
done

# 步骤3：创建Internet Gateway并附加到VPC
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ProductionIGW}]' \
    --query 'InternetGateway.InternetGatewayId' \
    --output text \
    --profile production)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --profile production

# 步骤4：配置路由表（公网子网指向IGW，私网子网指向NAT Gateway）
RT_PUBLIC=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --profile production)
aws ec2 create-route --route-table-id $RT_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --profile production

# 步骤5：使用VPC Reachability Analyzer诊断网络连通性
aws ec2 create-network-insights-path \
    --source $INSTANCE_ID_1 \
    --destination $INSTANCE_ID_2 \
    --protocol tcp \
    --destination-port 443 \
    --tag-specifications 'ResourceType=network-insights-path,Tags=[{Key=Name,Value=WebToDB}]' \
    --profile production
# 预期输出：NetworkInsightsPathId

# 步骤6：启动路径分析
aws ec2 start-network-insights-analysis \
    --network-insights-path-id $PATH_ID \
    --profile production
# 预期输出：分析结果，显示路径是否可达及阻断原因（如安全组规则、NACL规则）

# 步骤7：使用VPC Flow Logs监控网络流量
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $VPC_ID \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name /aws/vpc/flowlogs \
    --deliver-logs-permission-arn arn:aws:iam::ACCOUNT-ID:role/FlowLogsRole \
    --profile production
# 预期输出：FlowLogIds

# 步骤8：查询被安全组拒绝的流量（CloudWatch Logs Insights）
aws logs start-query \
    --log-group-name /aws/vpc/flowlogs \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, srcAddr, dstAddr, dstPort, action | filter action == "REJECT" | stats count() by dstPort, dstAddr | sort count desc' \
    --profile production
# 预期输出：被拒绝的流量统计，按目标端口和地址分组
```

**注意事项**：
- VPC Reachability Analyzer 是排查网络连通性问题的利器，可自动识别安全组、NACL、路由表的阻断规则
- Flow Logs 建议只采集 REJECT 流量（`--traffic-type REJECT`），减少日志量和存储成本
- 生产环境应配置 VPC Endpoints（如 S3、DynamoDB），避免流量经过公网
- NAT Gateway 按小时计费，高流量场景可考虑自建 NAT 实例（成本更低但需自行维护）

### 任务3：AWS 成本治理与资源优化

**任务目标**：建立 AWS 成本监控体系，识别闲置资源，实施 Savings Plans 和 Reserved Instances 优化。

**操作步骤**：

```bash
# 步骤1：创建成本预算告警（月度预算5000美元，80%和100%阈值）
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text --profile production) \
    --budget '{
        "BudgetName": "MonthlyProductionBudget",
        "BudgetLimit": {"Amount": "5000", "Unit": "USD"},
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST",
        "CostFilters": {"TagKeyValue": ["user:Environment$production"]},
        "CostTypes": {"IncludeTax": true, "IncludeSubscription": true, "UseBlended": false}
    }' \
    --notifications-with-subscribers '[
        {
            "Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 80, "ThresholdType": "PERCENTAGE"},
            "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "ops@example.com"}]
        },
        {
            "Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE"},
            "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "ops@example.com"}, {"SubscriptionType": "EMAIL", "Address": "finance@example.com"}]
        }
    ]' \
    --profile production
# 预期输出：Budget的ARN

# 步骤2：使用Cost Explorer分析月度成本趋势
aws ce get-cost-and-usage \
    --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
    --granularity DAILY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE \
    --profile production | jq '.ResultsByTime[] | {Date: .TimePeriod.Start, Total: .Total.BlendedCost.Amount}'
# 预期输出：近30天按服务分组的每日成本

# 步骤3：查找闲置的EBS卷（未附加或低I/O）
aws ec2 describe-volumes \
    --filters Name=status,Values=available \
    --query 'Volumes[*].{ID:VolumeId,Size:Size,Type:VolumeType,CreateTime:CreateTime}' \
    --output table \
    --profile production
# 预期输出：未附加的EBS卷列表（可安全删除以节省成本）

# 步骤4：查找低利用率的EC2实例（CPU平均利用率<5%）
aws cloudwatch get-metric-statistics \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID \
    --start-time $(date -d '7 days ago' --utc +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date --utc +%Y-%m-%dT%H:%M:%SZ) \
    --period 86400 \
    --statistics Average \
    --profile production | jq '.Datapoints[] | {Time: .Timestamp, CPU: .Average}'
# 预期输出：近7天每日平均CPU利用率

# 步骤5：购买Savings Plans（计算资源1年期承诺）
aws savingsplans create-savings-plan \
    --savings-plan-type Compute \
    --term 1 \
    --payment-option AllUpfront \
    --commitment "100.0" \
    --profile production
# 预期输出：Savings Plan的ARN和折扣率（通常比按需节省30-40%）

# 步骤6：使用AWS Compute Optimizer获取资源优化建议
aws compute-optimizer get-ec2-instance-recommendations \
    --instance-arns arn:aws:ec2:us-east-1:ACCOUNT-ID:instance/$INSTANCE_ID \
    --profile production | jq '.instanceRecommendations[].recommendationOptions[] | {InstanceType: .instanceType, EstimatedMonthlySavings: .projectedUtilizationMetrics[0].value}'
# 预期输出：推荐的实例类型和预计月度节省金额
```

**注意事项**：
- Cost Explorer 数据有 24 小时延迟，实时成本监控需结合 CloudWatch Billing 指标
- 闲置 EBS 卷是成本浪费的主要来源之一，建议每周扫描并清理
- Compute Optimizer 免费提供资源优化建议，但需先启用该服务
- Savings Plans 比 Reserved Instances 更灵活，自动应用于匹配的用量，无需绑定特定实例

### 任务4：GCP 项目治理与资源组织

**任务目标**：建立 GCP 多项目治理架构，配置 IAM 策略和预算告警，实现资源的标准化管理。

**操作步骤**：

```bash
# 步骤1：创建GCP组织文件夹结构（生产/测试/开发）
gcloud resource-manager folders create \
    --display-name="Production" \
    --organization=YOUR_ORG_ID
# 预期输出：Folder ID

FOLDER_PROD=$(gcloud resource-manager folders list --organization=YOUR_ORG_ID --filter="displayName=Production" --format="value(name)")

gcloud resource-manager folders create \
    --display-name="Staging" \
    --organization=YOUR_ORG_ID

gcloud resource-manager folders create \
    --display-name="Development" \
    --organization=YOUR_ORG_ID

# 步骤2：在Production文件夹下创建项目
gcloud projects create prod-webapp-001 \
    --name="Production WebApp" \
    --folder=$FOLDER_PROD \
    --labels=environment=production,team=platform
# 预期输出：Project ID和创建状态

# 步骤3：配置项目级IAM策略（运维团队只读访问）
gcloud projects add-iam-policy-binding prod-webapp-001 \
    --member="group:ops-team@example.com" \
    --role="roles/compute.viewer"

gcloud projects add-iam-policy-binding prod-webapp-001 \
    --member="group:ops-team@example.com" \
    --role="roles/monitoring.viewer"

# 步骤4：创建自定义IAM角色（限制权限的运维角色）
gcloud iam roles create LimitedOpsRole \
    --project=prod-webapp-001 \
    --title="Limited Operations Role" \
    --description="运维只读+重启实例权限" \
    --permissions=compute.instances.get,compute.instances.list,compute.instances.start,compute.instances.stop,compute.instances.reset,monitoring.timeSeries.list,logging.logEntries.list \
    --stage=GA

# 步骤5：配置预算告警（项目月度预算1000美元）
gcloud billing budgets create \
    --billing-account=XXXXXX-XXXXXX-XXXXXX \
    --display-name="Production Budget Alert" \
    --budget-amount=1000USD \
    --threshold-rule=percent=50 \
    --threshold-rule=percent=80 \
    --threshold-rule=percent=100 \
    --all-updates-rule-pubsub-topic=projects/prod-webapp-001/topics/budget-alerts \
    --filter='resource.labels.project_id="prod-webapp-001"'
# 预期输出：Budget的ID和配置详情

# 步骤6：使用Cloud Asset Inventory搜索所有Compute Engine实例
gcloud asset search-all-resources \
    --asset-types="compute.googleapis.com/Instance" \
    --scope="projects/prod-webapp-001" \
    --format="table(displayName,location,state,labels)"
# 预期输出：项目下所有VM实例的列表

# 步骤7：启用必需API并配置服务账号
gcloud services enable compute.googleapis.com monitoring.googleapis.com logging.googleapis.com cloudasset.googleapis.com --project=prod-webapp-001

# 创建专用运维服务账号
gcloud iam service-accounts create ops-sa \
    --display-name="Operations Service Account" \
    --project=prod-webapp-001

# 为服务账号授予自定义角色
gcloud projects add-iam-policy-binding prod-webapp-001 \
    --member="serviceAccount:ops-sa@prod-webapp-001.iam.gserviceaccount.com" \
    --role="projects/prod-webapp-001/roles/LimitedOpsRole"
```

**注意事项**：
- GCP 的文件夹（Folder）层级支持资源策略继承，建议在组织级别设置统一的 IAM 和预算策略
- Cloud Asset Inventory 是 GCP 的资源发现利器，支持跨项目搜索所有资源类型
- 服务账号密钥应尽量避免使用，优先使用 Workload Identity（GKE）或 impersonation
- 预算告警的 Pub/Sub 主题可触发 Cloud Functions 实现自动化响应（如超预算时自动停止非关键实例）

### 任务5：GCP 监控告警与故障自动修复

**任务目标**：配置 GCP Cloud Monitoring 告警策略，实现基于日志的异常检测和自动修复（如实例重启）。

**操作步骤**：

```bash
# 步骤1：创建基于CPU利用率的告警策略
gcloud alpha monitoring policies create \
    --policy="displayName='High CPU Alert',
    conditions=[
      displayName='CPU > 80% for 5 minutes',
      conditionThreshold={
        filter='resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"',
        aggregations=[alignmentPeriod=300s,perSeriesAligner=ALIGN_MEAN],
        comparison=COMPARISON_GT,
        thresholdValue=0.8,
        duration=300s
      }
    ],
    alertStrategy=notificationRateLimit={period=3600s},
    notificationChannels=['projects/prod-webapp-001/notificationChannels/EMAIL_CHANNEL']"
# 预期输出：AlertPolicy的ID

# 步骤2：创建基于日志的告警（检测ERROR级别日志）
gcloud alpha monitoring policies create \
    --policy="displayName='Application Error Alert',
    conditions=[
      displayName='ERROR logs > 10 in 5 minutes',
      conditionThreshold={
        filter='resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/error_count\"',
        aggregations=[alignmentPeriod=300s,perSeriesAligner=ALIGN_SUM],
        comparison=COMPARISON_GT,
        thresholdValue=10,
        duration=0s
      }
    ]"
# 预期输出：AlertPolicy的ID

# 步骤3：配置Cloud Functions自动修复（CPU过高时重启实例）
cat > main.py << 'PYEOF'
import base64
import json
from google.cloud import compute_v1

def auto_repair_instance(event, context):
    """Cloud Function: 收到告警后自动重启实例"""
    pubsub_message = base64.b64decode(event['data']).decode('utf-8')
    alert_data = json.loads(pubsub_message)
    
    # 从告警数据中提取实例信息
    instance_name = alert_data['incident']['resource']['labels']['instance_name']
    zone = alert_data['incident']['resource']['labels']['zone']
    project = alert_data['incident']['resource']['labels']['project_id']
    
    # 创建Compute Engine客户端
    client = compute_v1.InstancesClient()
    
    # 执行重置操作（硬重启）
    operation = client.reset(project=project, zone=zone, instance=instance_name)
    operation.result()  # 等待操作完成
    
    print(f"Instance {instance_name} in {zone} has been reset due to high CPU alert")
    return f"Reset {instance_name} successfully"
PYEOF

cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-compute==1.*
EOF

# 部署Cloud Function
gcloud functions deploy auto-repair-instance \
    --runtime=python311 \
    --trigger-topic=high-cpu-alerts \
    --entry-point=auto_repair_instance \
    --memory=256MB \
    --timeout=60s \
    --region=us-central1 \
    --project=prod-webapp-001 \
    --service-account=ops-sa@prod-webapp-001.iam.gserviceaccount.com
# 预期输出：Function的URL和状态

# 步骤4：创建日志指标（将ERROR日志转换为监控指标）
gcloud logging metrics create error-count \
    --description="Count of ERROR level log entries" \
    --log-filter='severity>=ERROR' \
    --project=prod-webapp-001
# 预期输出：Metric的ID

# 步骤5：查看告警事件历史
gcloud monitoring alert-policies list \
    --project=prod-webapp-001 \
    --format="table(displayName,enabled,notificationChannels)"
# 预期输出：告警策略列表

# 步骤6：使用Cloud Trace分析延迟瓶颈
gcloud trace list \
    --project=prod-webapp-001 \
    --limit=20 \
    --filter='service:webapp'
# 预期输出：最近的Trace列表，包含延迟分布
```

**注意事项**：
- Cloud Functions 的自动修复应谨慎使用，生产环境建议先发送通知给值班人员，确认后再执行修复
- 日志指标（Log-based Metrics）可将任意日志模式转换为监控指标，是自定义告警的核心手段
- Cloud Trace 自动集成 GKE 和 Cloud Run，无需修改应用代码即可采集链路数据
- 告警策略的 `notificationRateLimit` 防止告警风暴，建议设置为每小时最多 1 条通知

---

## 三、面试真题

### 基础 高频 - Q1: AWS 和 GCP 的 IAM 模型有什么本质区别？

> **参考答案**：
> 1. **AWS IAM**：基于 Role + Policy 的显式授权模型。用户/服务假设 Role 获取临时凭证，Policy 定义具体权限（Allow/Deny），权限边界（Permission Boundary）限制最大权限范围
> 2. **GCP IAM**：基于 IAM + Service Account 的隐式继承模型。权限在组织/文件夹/项目/资源层级继承，Service Account 是主要身份类型，支持 Workload Identity（K8s Pod 直接映射 GCP 身份）
> 3. **关键差异**：AWS 的权限是"显式授予"（默认拒绝），GCP 的权限是"继承+显式拒绝"（组织级别授予，子级自动继承）
> 4. **运维建议**：AWS 适合精细化的权限控制，GCP 适合大规模多项目的统一治理

---

### 中等 高频 - Q2: 如何排查 AWS VPC 中两台 EC2 实例无法通信的问题？

> **参考答案**：
> 1. **使用 VPC Reachability Analyzer**：自动分析源到目标的路径，识别安全组、NACL、路由表的阻断规则
> 2. **检查安全组**：确认入站规则允许源实例的 IP/安全组访问目标端口，出站规则允许响应流量
> 3. **检查 NACL**：确认子网级别的 NACL 允许双向流量（NACL 是无状态的，需显式允许入站和出站）
> 4. **检查路由表**：确认子网关联的路由表包含到达目标子网的路由（同一 VPC 内默认互通，但自定义路由可能覆盖）
> 5. **检查 VPC Flow Logs**：查看 REJECT 流量记录，确认流量被哪个组件阻断
> 6. **常见陷阱**：安全组引用自身（self-referencing）时，需确保实例在同一安全组内；NACL 的规则顺序影响匹配结果

---

### 中等 高频 - Q3: AWS CloudWatch、CloudTrail、Config 三个服务分别解决什么问题？

> **参考答案**：
> 1. **CloudWatch**：资源性能监控（指标、日志、告警）。采集 EC2 CPU、内存、磁盘 I/O 等指标，支持自定义仪表盘和告警
> 2. **CloudTrail**：API 操作审计。记录所有 AWS API 调用（谁在什么时间做了什么），用于故障溯源和安全审计
> 3. **Config**：资源配置审计。持续监控资源配置变更，评估是否符合预定义规则（如 S3 是否公开、安全组是否开放 22 端口）
> 4. **三者关系**：CloudWatch 回答"系统运行得怎么样"，CloudTrail 回答"谁做了什么操作"，Config 回答"配置是否符合规范"
> 5. **运维场景**：EC2 突然无法访问 → CloudTrail 查谁修改了安全组 → Config 确认当前配置是否合规 → CloudWatch 查看实例指标是否正常

---

### 困难 中频 - Q4: 如何设计 AWS 多账号组织架构，实现安全与效率的平衡？

> **参考答案**：
> 1. **AWS Organizations**：创建组织，按环境（生产/测试/开发）或业务线划分账号，统一账单和策略
> 2. **Service Control Policies（SCP）**：在组织级别设置权限边界，限制子账号的最大权限（如禁止删除 CloudTrail、禁止创建公网 RDS）
> 3. **跨账号角色**：生产账号创建只读角色，允许运维账号通过 STS AssumeRole 访问，强制 MFA
> 4. **集中日志**：所有账号的 CloudTrail、Config、Flow Logs 集中到安全账号的 S3 存储桶，防止本地删除
> 5. **标签策略**：强制所有资源打上 Environment、Owner、CostCenter 标签，便于成本分摊和资源追踪
> 6. **共享服务**：VPC、Direct Connect、Route 53 等共享服务放在 Network 账号，通过 RAM 共享给其他账号

---

### 中等 中频 - Q5: GCP 的 Cloud Monitoring 和 AWS 的 CloudWatch 有什么区别？

> **参考答案**：
> 1. **集成深度**：Cloud Monitoring 与 GKE 深度集成，自动采集容器指标（Pod CPU/内存、节点状态），无需额外安装 Agent；CloudWatch 需要安装 CloudWatch Agent 才能采集内存/磁盘指标
> 2. **日志关联**：Cloud Monitoring 与 Cloud Logging 原生关联，点击指标可直接跳转到相关日志；CloudWatch 的 Metrics 和 Logs 需手动关联
> 3. **告警灵活性**：Cloud Monitoring 支持基于日志的告警（Log-based Alerts），可将任意日志模式转为告警；CloudWatch 需先创建 Logs Insights 查询再配置告警
> 4. **Trace 集成**：Cloud Trace 自动集成 Cloud Monitoring，链路延迟直接显示在监控面板；CloudWatch 需单独配置 X-Ray
> 5. **定价**：Cloud Monitoring 免费额度较高（每月 150MB 日志、1 亿个指标点），CloudWatch 按指标数量和日志量计费

---

### 困难 低频 - Q6: AWS 成本优化有哪些常用手段？如何评估优化效果？

> **参考答案**：
> 1. **Reserved Instances / Savings Plans**：1-3 年承诺，计算资源节省 30-60%，适合稳定负载
> 2. **Spot Instances**：利用闲置容量，价格仅为按需的 10-20%，适合批处理、CI/CD、容错应用
> 3. **Graviton 实例**：AWS 自研 ARM 处理器，性价比比 x86 高 40%，适合无架构绑定的应用
> 4. **存储优化**：EBS 从 gp2 升级到 gp3（性能提升 20%，价格降低 20%）；S3 生命周期策略自动转存到低频/归档存储
> 5. **闲置资源清理**：未附加的 EBS 卷、空闲的 Elastic IP、低利用率的 RDS 实例
> 6. **评估效果**：使用 Cost Explorer 对比优化前后的月度账单；Compute Optimizer 提供具体的节省金额预估
>
> **延伸知识**：AWS 的 Cost Anomaly Detection（成本异常检测）使用 ML 自动识别异常支出，无需手动设置阈值

---

### 基础 中频 - Q7: GCP 的 GKE Autopilot 和标准模式有什么区别？运维上如何选择？

> **参考答案**：
> 1. **GKE 标准模式**：用户管理节点池、机器类型、自动伸缩，灵活性高但运维负担重（需监控节点健康、升级节点版本）
> 2. **GKE Autopilot**：Google 管理所有节点基础设施，用户只需定义 Pod 资源请求，按 Pod 实际资源计费（非节点整机）
> 3. **运维差异**：
>    - 标准模式：需配置节点自动修复、节点升级策略、节点池扩缩容
>    - Autopilot：节点管理完全自动化，但限制较多（如不允许 privileged Pod、不允许 hostPath 卷）
> 4. **选型建议**：
>    - 需要自定义节点配置（GPU、本地 SSD、特定机器类型）→ 标准模式
>    - 追求最低运维负担、工作负载通用（Web 服务、API、微服务）→ Autopilot
>    - 成本敏感：Autopilot 按 Pod 计费可能更贵，但省去了节点闲置成本

---

### 中等 低频 - Q8: 云平台运维工程师的日常工作流程是什么？如何快速接手一个新账号？

> **参考答案**：
> 1. **日常巡检**：查看 CloudWatch/Cloud Monitoring 仪表盘，检查告警事件，确认无未处理的高优先级告警
> 2. **成本审查**：查看 Cost Explorer/ Billing 报表，识别异常支出，优化闲置资源
> 3. **安全审计**：查看 CloudTrail/Cloud Audit Logs 中的高风险操作（如权限提升、密钥删除），确认 Config 合规状态
> 4. **容量规划**：分析资源使用趋势（CPU、内存、存储），提前申请扩容或优化配置
> 5. **接手新账号 checklist**：
>    - 确认根账号 MFA 已启用，根账号凭证已安全保存
>    - 查看 IAM 用户列表，删除闲置用户和长期未轮换的 Access Key
>    - 检查 CloudTrail 是否启用并配置到集中存储桶
>    - 查看 VPC 架构图，确认网络分段和安全组规则
>    - 查看 Cost Explorer，了解主要成本来源和预算告警配置
>    - 确认关键资源的备份策略（RDS 快照、EBS 快照、S3 版本控制）
>    - 查看现有告警策略和通知渠道，确认值班人员配置正确
>
> **延伸知识**：建议制作"账号接管 runbook"，标准化接手流程，确保不遗漏关键检查项
