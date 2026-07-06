# 模块15：基础设施即代码(IaC) - Terraform与Ansible联动

---

## 1. 概述与架构图

### 1.1 IaC概念与价值

基础设施即代码(Infrastructure as Code, IaC)是通过代码来管理和配置基础设施的实践，将基础设施的定义、部署和管理过程自动化、版本化和可重复化。

**核心价值：**

| 价值点 | 说明 |
|--------|------|
| **版本控制** | 基础设施变更可追溯、可回滚 |
| **自动化** | 消除手动配置错误，提高部署效率 |
| **一致性** | 确保开发、测试、生产环境一致 |
| **协作** | 团队成员通过代码审查协作管理基础设施 |
| **文档化** | 代码即文档，基础设施状态清晰可见 |

### 1.2 Terraform + Ansible 架构

```
+================================================================================+
|                    Terraform + Ansible 联动架构                                |
+================================================================================+
|                                                                                |
|  +-------------------+                                                         |
|  |   Terraform       |  <-- 基础设施编排层 (Provisioning Layer)                |
|  |   (IaC Core)      |     负责: 创建/销毁/修改基础设施资源                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |  VMware vSphere    |    |  Cloud Providers   |    |  Local Resources   |      |
|  |  Provider          |    |  (AWS/Azure/GCP)   |    |  (Files/Exec)      |      |
|  +---------+----------+    +-------------------+    +-------------------+      |
|            |                                                                   |
|            |  1. 创建虚拟机/网络/存储                                            |
|            |  2. 输出资源信息(IP/主机名)                                         |
|            v                                                                   |
|  +-------------------+                                                         |
|  |   Ansible         |  <-- 配置管理层 (Configuration Layer)                   |
|  |   (Config Mgmt)   |     负责: 软件安装、系统配置、应用部署                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+    +-------------------+    +-------------------+      |
|  |  K8s Master Nodes |    |  K8s Worker Nodes  |    |  Harbor Registry   |      |
|  |  (kubeadm init)   |    |  (kubeadm join)    |    |  (镜像仓库)         |      |
|  +-------------------+    +-------------------+    +-------------------+      |
|                                                                                |
+================================================================================+
```

### 1.3 与Kubernetes的关系

```
+================================================================================+
|                    IaC 与 Kubernetes 分层架构                                  |
+================================================================================+
|                                                                                |
|  Layer 4: 应用层 (Application)                                                  |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |  Deployment       |  |  Service          |  |  Ingress          |          |
|  |  ConfigMap        |  |  Secret           |  |  HPA              |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|           |                      |                      |                      |
|           v                      v                      v                      |
|  Layer 3: Kubernetes集群层 (由kubeadm/kubespray部署)                            |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |  kube-apiserver   |  |  kubelet          |  |  kube-proxy       |          |
|  |  etcd             |  |  containerd       |  |  CNI (Calico)     |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|           |                      |                      |                      |
|           v                      v                      v                      |
|  Layer 2: 基础设施层 (由Terraform创建)                                          |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |  VMs (vSphere)    |  |  Networks         |  |  Storage          |          |
|  |  6 Nodes Cluster  |  |  VLAN/PortGroup   |  |  Datastore        |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|           |                      |                      |                      |
|           v                      v                      v                      |
|  Layer 1: 物理/虚拟化层                                                         |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |  ESXi Hosts       |  |  vCenter Server   |  |  Physical Storage |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
+================================================================================+
```

### 1.4 工具对比

| 特性 | Terraform | Ansible | Kubernetes YAML |
|------|-----------|---------|-----------------|
| **主要职责** | 基础设施创建 | 配置管理 | 应用部署 |
| **执行模式** | 声明式(Desired State，期望状态) | 命令式(Procedural) | 声明式 |
| **状态管理** | 本地/远程状态文件 | 无状态 | etcd存储 |
| **幂等性** | 是 | 是 | 是 |
| **适用场景** | 云资源/虚拟机 | 系统配置/软件安装 | 容器编排 |
| **本课程角色** | 创建VMware虚拟机 | 配置K8s节点 | 部署应用 |

---

## 2. 核心概念

### 2.1 Terraform核心概念

#### 2.1.1 Provider

Provider(提供者)是Terraform与基础设施平台交互的插件，负责API调用。

```hcl
# 常用Provider配置
terraform {
  required_providers {
    vsphere = {  # VMware虚拟化平台Provider
      source  = "hashicorp/vsphere"
      version = "2.5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.1"
    }
  }
}

provider "vsphere" {  # vSphere连接配置
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server
  
  allow_unverified_ssl = true
}
```

#### 2.1.2 Resource

Resource(资源)是要创建的基础设施对象。

```hcl
# vSphere虚拟机资源
resource "vsphere_virtual_machine" "k8s_master" {  # 创建K8s主节点虚拟机
  name             = "k8s-master-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  
  num_cpus = 2  # CPU核心数
  memory   = 4096  # 内存(MB)
  
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  
  disk {
    label            = "disk0"
    size             = 40
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}
```

#### 2.1.3 State文件

Terraform使用state(状态)文件记录实际基础设施状态。

```
terraform.tfstate (JSON格式)
├── version: 4
├── terraform_version: "1.6.0"
├── serial: 15 (每次apply递增)
├── lineage: "uuid" (工作区唯一标识)
└── resources: [
    {
      "mode": "managed",
      "type": "vsphere_virtual_machine",
      "name": "k8s_master",
      "provider": "provider[\"registry.terraform.io/hashicorp/vsphere\"]",
      "instances": [...]
    }
  ]
```

**State文件管理要点：**
- 永远不要手动编辑state文件
- 生产环境必须使用远程state后端
- state文件可能包含敏感信息，需加密存储

#### 2.1.4 Plan/Apply工作流

```
Terraform工作流

  +----------------+
  | 1. terraform   |
  |    init        |  <-- 初始化，下载Provider插件
  +--------+-------+
           |
           v
  +----------------+
  | 2. terraform   |
  |    plan        |  <-- 预览变更，对比期望与实际状态
  +--------+-------+      生成执行计划
           |
           v
  +----------------+
  | 3. Review Plan |  <-- 人工审查变更
  +--------+-------+
           |
           v
  +----------------+
  | 4. terraform   |
  |    apply       |  <-- 执行变更，创建/修改资源
  +--------+-------+
           |
           v
  +----------------+
  | 5. State Update|  <-- 更新state文件
  +----------------+
```

### 2.2 Ansible核心概念

#### 2.2.1 Inventory

Inventory(主机清单)定义管理的主机列表。

```ini
# /etc/ansible/hosts 或 inventory.ini
[k8s_master]
192.168.1.51 ansible_hostname=k8s-master1
192.168.1.52 ansible_hostname=k8s-master2
192.168.1.53 ansible_hostname=k8s-master3

[k8s_worker]
192.168.1.54 ansible_hostname=k8s-worker1
192.168.1.55 ansible_hostname=k8s-worker2
192.168.1.56 ansible_hostname=k8s-worker3

[k8s_all:children]
k8s_master
k8s_worker

[k8s_all:vars]
ansible_user=root
ansible_ssh_private_key_file=/root/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
```

#### 2.2.2 Playbook

Playbook(剧本)是Ansible的配置脚本，使用YAML编写。

```yaml
---
- name: 配置K8s Master节点
  hosts: k8s_master
  become: yes  # 提升为root权限
  vars:
    k8s_version: "1.28.0"  # K8s版本
    pod_cidr: "10.244.0.0/16"  # Pod网络CIDR
  
  tasks:
    - name: 安装containerd
      apt:
        name: containerd
        state: present
        update_cache: yes
    
    - name: 配置containerd
      template:
        src: config.toml.j2
        dest: /etc/containerd/config.toml
      notify: restart containerd
    
    - name: 初始化K8s集群
      command: >
        kubeadm init
        --apiserver-advertise-address={{ ansible_default_ipv4.address }}
        --pod-network-cidr={{ pod_cidr }}
        --kubernetes-version={{ k8s_version }}
      when: inventory_hostname == groups['k8s_master'][0]
  
  handlers:
    - name: restart containerd
      service:
        name: containerd
        state: restarted
```

#### 2.2.3 Role

Role(角色)是Ansible的可复用代码单元。

```
roles/
└── k8s_node/
    ├── defaults/          # 默认变量(优先级最低)
    │   └── main.yml
    ├── vars/              # 变量(优先级较高)
    │   └── main.yml
    ├── files/             # 静态文件
    │   └── containerd.service
    ├── templates/         # Jinja2模板
    │   └── config.toml.j2
    ├── tasks/             # 任务列表
    │   ├── main.yml
    │   ├── install.yml
    │   └── configure.yml
    ├── handlers/          # 处理器
    │   └── main.yml
    └── meta/              # 依赖信息
        └── main.yml
```

### 2.3 变量与模板

#### 2.3.1 Terraform变量

```hcl
# variables.tf
variable "vsphere_server" {  # vCenter连接变量
  description = "vCenter服务器地址"
  type        = string
  default     = "vcenter.example.com"
}

variable "master_count" {  # Master节点数量
  description = "Master节点数量"
  type        = number
  default     = 3
  validation {
    condition     = var.master_count >= 1 && var.master_count <= 5
    error_message = "Master节点数量必须在1-5之间"
  }
}

variable "master_ips" {
  description = "Master节点IP列表"
  type        = list(string)
  default     = ["192.168.1.51", "192.168.1.52", "192.168.1.53"]
}

variable "node_config" {
  description = "节点配置"
  type = map(object({
    cpu    = number
    memory = number
    disk   = number
  }))
  default = {
    master = { cpu = 2, memory = 4096, disk = 40 }
    worker = { cpu = 4, memory = 8192, disk = 60 }
  }
}
```

#### 2.3.2 Ansible变量优先级

```
优先级从高到低:

1. 命令行变量: -e "var=value"
2. 任务变量: vars:
3. 块变量: block:
4. Play变量: vars:
5. 主机变量: host_vars/
6. 组变量: group_vars/
7. Role默认变量: defaults/main.yml
```

#### 2.3.3 Jinja2模板

```jinja2
# templates/hosts.j2
# Jinja2模板，由Terraform生成，Ansible使用
127.0.0.1 localhost

{% for host in groups['k8s_master'] %}
{{ hostvars[host]['ansible_host'] }} {{ hostvars[host]['ansible_hostname'] }}
{% endfor %}

{% for host in groups['k8s_worker'] %}
{{ hostvars[host]['ansible_host'] }} {{ hostvars[host]['ansible_hostname'] }}
{% endfor %}
```

---

## 3. 离线前置准备

### 3.1 镜像与二进制清单

#### 3.1.1 Terraform相关

| 组件 | 版本 | 下载地址 | 用途 |
|------|------|----------|------|
| Terraform | 1.6.6 | https://releases.hashicorp.com/terraform/1.6.6/ | 基础设施编排 |
| vSphere Provider | 2.5.1 | registry.terraform.io | VMware虚拟机管理 |
| Local Provider | 2.4.1 | registry.terraform.io | 本地文件/执行 |
| Null Provider | 3.2.2 | registry.terraform.io | 触发器/Provisioner |
| Template Provider | 2.2.0 | registry.terraform.io | 模板渲染 |

#### 3.1.2 Ansible相关

| 组件 | 版本 | 下载地址 | 用途 |
|------|------|----------|------|
| Ansible | 2.15.0 | PyPI / 离线pip包 | 配置管理 |
| Python | 3.10+ | 系统仓库 | 运行环境 |
| PyVMomi | 8.0.0 | PyPI | VMware SDK |
| Jinja2 | 3.1.2 | PyPI | 模板引擎 |
| PyYAML | 6.0.1 | PyPI | YAML解析 |

#### 3.1.3 K8s相关二进制

| 组件 | 版本 | 用途 |
|------|------|------|
| kubeadm | 1.28.0 | 集群初始化 |
| kubelet | 1.28.0 | 节点管理 |
| kubectl | 1.28.0 | 命令行工具 |
| containerd | 1.7.8 | 容器运行时 |
| runc | 1.1.9 | 容器运行时工具 |
| CNI Plugins | 1.3.0 | 网络插件 |
| crictl | 1.28.0 | 容器调试工具 |
| etcdctl | 3.5.9 | etcd调试工具 |

### 3.2 Provider离线缓存

#### 3.2.1 Provider目录结构

```
/opt/terraform-plugins/
├── registry.terraform.io/
│   └── hashicorp/
│       ├── vsphere/
│       │   └── 2.5.1/
│       │       └── linux_amd64/
│       │           └── terraform-provider-vsphere_v2.5.1_x5
│       ├── local/
│       │   └── 2.4.1/
│       │       └── linux_amd64/
│       │           └── terraform-provider-local_v2.4.1_x5
│       ├── null/
│       │   └── 3.2.2/
│       │       └── linux_amd64/
│       │           └── terraform-provider-null_v3.2.2_x5
│       └── template/
│           └── 2.2.0/
│               └── linux_amd64/
│                   └── terraform-provider-template_v2.2.0_x4
└── plugin-cache/          # 本地缓存目录
```

#### 3.2.2 Terraform离线配置

```hcl
# terraform.tf
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }
  }
  
  # 本地Provider缓存
  provider_meta "hashicorp/vsphere" {}
}
```

```bash
# ~/.terraformrc (Terraform CLI配置)
plugin_cache_dir = "/opt/terraform-plugins/plugin-cache"  # Provider本地缓存目录
disable_checkpoint = true  # 禁用版本检查

provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform-plugins"
    include = ["registry.terraform.io/hashicorp/*"]
  }
  direct {
    exclude = ["registry.terraform.io/hashicorp/*"]
  }
}
```

### 3.3 Ansible离线安装

#### 3.3.1 准备离线pip包

```bash
# 在有外网的环境中准备
mkdir -p /opt/ansible-packages
cd /opt/ansible-packages

# 创建requirements.txt
cat > requirements.txt << 'EOF'
ansible==2.15.0
ansible-core==2.15.0
jinja2==3.1.2
pyyaml==6.0.1
cryptography==41.0.0
paramiko==3.3.1
pyvmomi==8.0.0
netaddr==0.8.0
EOF

# 下载所有依赖包
pip download -r requirements.txt -d ./packages

# 打包传输到离线环境
tar czvf ansible-packages.tar.gz packages/
```

#### 3.3.2 离线环境安装

```bash
# 在离线环境中安装
cd /opt/ansible-packages
tar xzvf ansible-packages.tar.gz

# 安装Ansible
pip install --no-index --find-links=./packages ansible

# 验证安装
ansible --version
```

---

## 4. 实战部署

### 4.1 Terraform安装与初始化(离线)

#### 4.1.1 安装Terraform

```bash
# 1. 下载Terraform二进制(离线环境已预下载)
# https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip

# 2. 解压安装
cd /opt/offline-packages
unzip terraform_1.6.6_linux_amd64.zip
mv terraform /usr/local/bin/
chmod +x /usr/local/bin/terraform

# 3. 验证安装
terraform version
# Terraform v1.6.6
# on linux_amd64
```

#### 4.1.2 配置Provider缓存

```bash
# 1. 创建Provider目录
mkdir -p /opt/terraform-plugins/registry.terraform.io/hashicorp

# 2. 解压预下载的Provider包
cd /opt/offline-packages/providers
for provider in *.zip; do
    unzip -q "$provider" -d /opt/terraform-plugins/registry.terraform.io/hashicorp/
done

# 3. 配置Terraform使用本地Provider
cat > ~/.terraformrc << 'EOF'
provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform-plugins"
    include = ["registry.terraform.io/*/*"]
  }
}
disable_checkpoint = true
EOF
```

#### 4.1.3 初始化Terraform工作目录

```bash
# 1. 创建工作目录
mkdir -p /opt/terraform-k8s
cd /opt/terraform-k8s

# 2. 创建基础配置文件
cat > versions.tf << 'EOF'
terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.5.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.2"
    }
  }
}
EOF

# 3. 初始化(使用本地Provider)
terraform init

# 预期输出:
# Initializing the backend...
# Initializing provider plugins...
# - Finding hashicorp/vsphere versions matching "2.5.1"...
# - Finding hashicorp/local versions matching "2.4.1"...
# - Finding hashicorp/null versions matching "3.2.2"...
# - Installing hashicorp/vsphere v2.5.1...
# - Installed hashicorp/vsphere v2.5.1 (unauthenticated)
# - Installing hashicorp/local v2.4.1...
# - Installed hashicorp/local v2.4.1 (unauthenticated)
# - Installing hashicorp/null v3.2.2...
# - Installed hashicorp/null v3.2.2 (unauthenticated)
# Terraform has been successfully initialized!
```

### 4.2 使用Terraform创建VMware虚拟机

#### 4.2.1 配置vSphere Provider

```hcl
# vsphere.tf
# vSphere连接配置
data "vsphere_datacenter" "dc" {  # 数据中心
  name = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {  # 数据存储
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {  # 网络配置
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.vsphere_cluster}/Resources"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# 虚拟机模板
data "vsphere_virtual_machine" "template" {
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc.id
}
```

#### 4.2.2 创建Master节点

```hcl
# masters.tf
# K8s Master节点配置
resource "vsphere_virtual_machine" "master" {  # 创建Master节点
  count            = var.master_count  # 节点数量
  name             = "k8s-master-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  
  num_cpus = var.master_cpu  # CPU核心数
  memory   = var.master_memory  # 内存(MB)
  guest_id = data.vsphere_virtual_machine.template.guest_id
  
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  
  # 网络配置
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }
  
  # 系统盘
  disk {
    label            = "disk0"
    size             = var.master_disk
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  # 从模板克隆
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    
    customize {
      linux_options {
        host_name = "k8s-master-${count.index + 1}"
        domain    = var.vm_domain
      }
      
      network_interface {
        ipv4_address = var.master_ips[count.index]
        ipv4_netmask = 24
      }
      
      ipv4_gateway = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }
  
  # 元数据标签
  tags = [vsphere_tag.k8s_master.id]
}

# 创建标签
resource "vsphere_tag_category" "environment" {
  name        = "environment"
  cardinality = "SINGLE"
  description = "Environment category"
  
  associable_types = [
    "VirtualMachine",
  ]
}

resource "vsphere_tag" "k8s_master" {
  name        = "k8s-master"
  category_id = vsphere_tag_category.environment.id
  description = "Kubernetes Master Node"
}
```

#### 4.2.3 创建Worker节点

```hcl
# workers.tf
# K8s Worker节点配置
resource "vsphere_virtual_machine" "worker" {  # 创建Worker节点
  count            = var.worker_count  # 节点数量
  name             = "k8s-worker-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  
  num_cpus = var.worker_cpu
  memory   = var.worker_memory
  guest_id = data.vsphere_virtual_machine.template.guest_id
  
  scsi_type = data.vsphere_virtual_machine.template.scsi_type
  
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }
  
  disk {
    label            = "disk0"
    size             = var.worker_disk
    eagerly_scrub    = false
    thin_provisioned = true
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    
    customize {
      linux_options {
        host_name = "k8s-worker-${count.index + 1}"
        domain    = var.vm_domain
      }
      
      network_interface {
        ipv4_address = var.worker_ips[count.index]
        ipv4_netmask = 24
      }
      
      ipv4_gateway = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }
  
  tags = [vsphere_tag.k8s_worker.id]
}

resource "vsphere_tag" "k8s_worker" {
  name        = "k8s-worker"
  category_id = vsphere_tag_category.environment.id
  description = "Kubernetes Worker Node"
}
```

#### 4.2.4 变量定义

```hcl
# variables.tf
# vSphere连接变量
variable "vsphere_server" {
  description = "vCenter服务器地址"
  type        = string
}

variable "vsphere_user" {
  description = "vCenter用户名"
  type        = string
}

variable "vsphere_password" {
  description = "vCenter密码"
  type        = string
  sensitive   = true
}

variable "vsphere_datacenter" {
  description = "数据中心名称"
  type        = string
  default     = "Datacenter"
}

variable "vsphere_datastore" {
  description = "数据存储名称"
  type        = string
  default     = "datastore1"
}

variable "vsphere_cluster" {
  description = "集群名称"
  type        = string
  default     = "Cluster"
}

variable "vsphere_network" {
  description = "网络名称"
  type        = string
  default     = "VM Network"
}

# 虚拟机模板变量
variable "vm_template" {
  description = "虚拟机模板名称"
  type        = string
  default     = "ubuntu-22.04-template"
}

variable "vm_domain" {
  description = "虚拟机域名"
  type        = string
  default     = "local"
}

variable "vm_gateway" {
  description = "默认网关"
  type        = string
  default     = "192.168.1.1"
}

variable "vm_dns_servers" {
  description = "DNS服务器列表"
  type        = list(string)
  default     = ["192.168.1.1", "8.8.8.8"]
}

# Master节点变量
variable "master_count" {
  description = "Master节点数量"
  type        = number
  default     = 3
  
  validation {
    condition     = var.master_count >= 1 && var.master_count <= 5
    error_message = "Master节点数量必须在1-5之间"
  }
}

variable "master_cpu" {
  description = "Master节点CPU核心数"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "Master节点内存(MB)"
  type        = number
  default     = 4096
}

variable "master_disk" {
  description = "Master节点磁盘(GB)"
  type        = number
  default     = 40
}

variable "master_ips" {
  description = "Master节点IP列表"
  type        = list(string)
  default     = ["192.168.1.51", "192.168.1.52", "192.168.1.53"]
}

# Worker节点变量
variable "worker_count" {
  description = "Worker节点数量"
  type        = number
  default     = 3
  
  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "Worker节点数量必须在1-10之间"
  }
}

variable "worker_cpu" {
  description = "Worker节点CPU核心数"
  type        = number
  default     = 4
}

variable "worker_memory" {
  description = "Worker节点内存(MB)"
  type        = number
  default     = 8192
}

variable "worker_disk" {
  description = "Worker节点磁盘(GB)"
  type        = number
  default     = 60
}

variable "worker_ips" {
  description = "Worker节点IP列表"
  type        = list(string)
  default     = ["192.168.1.54", "192.168.1.55", "192.168.1.56"]
}
```

#### 4.2.5 输出定义

```hcl
# outputs.tf
# 输出Master节点信息
output "master_nodes" {  # 输出Master节点信息
  description = "Master节点信息"
  value = [
    for i, vm in vsphere_virtual_machine.master : {
      name       = vm.name
      ip_address = vm.guest_ip_addresses[0]
      hostname   = "k8s-master-${i + 1}"
    }
  ]
}

# 输出Worker节点信息
output "worker_nodes" {
  description = "Worker节点信息"
  value = [
    for i, vm in vsphere_virtual_machine.worker : {
      name       = vm.name
      ip_address = vm.guest_ip_addresses[0]
      hostname   = "k8s-worker-${i + 1}"
    }
  ]
}

# 输出Ansible Inventory
output "ansible_inventory" {
  description = "Ansible Inventory内容"
  value       = local_file.ansible_inventory.content
  sensitive   = false
}

# 生成Ansible Inventory文件
resource "local_file" "ansible_inventory" {
  content  = <<-EOF
[k8s_master]
%{ for i, ip in var.master_ips ~}
${ip} ansible_hostname=k8s-master-${i + 1}
%{ endfor ~}

[k8s_worker]
%{ for i, ip in var.worker_ips ~}
${ip} ansible_hostname=k8s-worker-${i + 1}
%{ endfor ~}

[k8s_all:children]
k8s_master
k8s_worker

[k8s_all:vars]
ansible_user=root
ansible_ssh_private_key_file=/root/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
EOF
  filename = "${path.module}/inventory.ini"
}

# 生成hosts文件
resource "local_file" "hosts_file" {
  content  = <<-EOF
127.0.0.1 localhost

# Master nodes
%{ for i, ip in var.master_ips ~}
${ip} k8s-master-${i + 1}
%{ endfor ~}

# Worker nodes
%{ for i, ip in var.worker_ips ~}
${ip} k8s-worker-${i + 1}
%{ endfor ~}
EOF
  filename = "${path.module}/hosts"
}
```

#### 4.2.6 执行创建

```bash
# 1. 创建terraform.tfvars文件(包含敏感信息)
cat > terraform.tfvars << 'EOF'
vsphere_server   = "vcenter.example.com"
vsphere_user     = "administrator@vsphere.local"
vsphere_password = "YourPassword"

master_count = 3
worker_count = 3

master_ips = ["192.168.1.51", "192.168.1.52", "192.168.1.53"]
worker_ips = ["192.168.1.54", "192.168.1.55", "192.168.1.56"]
EOF

# 2. 格式化配置
terraform fmt

# 3. 验证配置
terraform validate

# 4. 预览变更
terraform plan

# 5. 执行创建
terraform apply -auto-approve

# 6. 查看输出
terraform output
```

### 4.3 Ansible安装与配置(离线)

#### 4.3.1 安装Ansible

```bash
# 1. 安装Python3和pip
apt-get update
apt-get install -y python3 python3-pip python3-venv sshpass

# 2. 离线安装Ansible
cd /opt/ansible-packages
pip3 install --no-index --find-links=./packages ansible

# 3. 验证安装
ansible --version
# ansible [core 2.15.0]
#   config file = /etc/ansible/ansible.cfg
#   configured module search path = ['/root/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
#   ansible python module location = /usr/local/lib/python3.10/dist-packages/ansible
#   ansible collection location = /root/.ansible/collections:/usr/share/ansible/collections
#   executable location = /usr/local/bin/ansible
#   python version = 3.10.12 (main, Nov 20 2023, 15:14:05) [GCC 11.4.0] (/usr/bin/python3)
#   jinja version = 3.1.2
#   libyaml = True
```

#### 4.3.2 配置Ansible

```bash
# 1. 创建Ansible配置
cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
inventory = /opt/terraform-k8s/inventory.ini
host_key_checking = False
forks = 10
timeout = 30
remote_user = root
private_key_file = /root/.ssh/id_rsa
log_path = /var/log/ansible.log

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
EOF

# 2. 配置SSH免密登录
ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa

# 3. 复制公钥到所有节点
for ip in 192.168.1.51 192.168.1.52 192.168.1.53 192.168.1.54 192.168.1.55 192.168.1.56; do
    sshpass -p 'YourPassword' ssh-copy-id -o StrictHostKeyChecking=no root@$ip
done

# 4. 测试连通性
ansible all -m ping
```

### 4.4 使用Ansible配置K8s节点

#### 4.4.1 创建Role结构

```bash
# 创建Role目录结构
mkdir -p /opt/ansible-k8s/roles
cd /opt/ansible-k8s/roles

# 初始化Roles
ansible-galaxy init common
ansible-galaxy init containerd
ansible-galaxy init k8s_node
ansible-galaxy init k8s_master
```

#### 4.4.2 common Role - 系统初始化

```yaml
# roles/common/tasks/main.yml
---
- name: 设置主机名
  hostname:
    name: "{{ ansible_hostname }}"

- name: 配置/etc/hosts
  template:
    src: hosts.j2
    dest: /etc/hosts
    backup: yes

- name: 关闭Swap
  shell: |
    swapoff -a
    sed -i '/swap/d' /etc/fstab
  changed_when: true

- name: 加载内核模块
  modprobe:
    name: "{{ item }}"
    state: present
  loop:
    - overlay
    - br_netfilter

- name: 配置内核参数
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    reload: yes
  loop:
    - { key: "net.bridge.bridge-nf-call-iptables", value: "1" }
    - { key: "net.bridge.bridge-nf-call-ip6tables", value: "1" }
    - { key: "net.ipv4.ip_forward", value: "1" }
    - { key: "vm.swappiness", value: "0" }

- name: 安装基础软件包
  apt:
    name:
      - apt-transport-https
      - ca-certificates
      - curl
      - gnupg
      - lsb-release
      - ipvsadm
      - ipset
      - conntrack
      - socat
      - ebtables
      - ethtool
      - jq
      - git
    state: present
    update_cache: yes

- name: 配置时间同步
  apt:
    name: chrony
    state: present

- name: 启动chrony
  service:
    name: chronyd
    state: started
    enabled: yes
```

```jinja2
{# roles/common/templates/hosts.j2 #}
127.0.0.1 localhost

# Master nodes
{% for host in groups['k8s_master'] %}
{{ hostvars[host]['ansible_host'] }} {{ hostvars[host]['ansible_hostname'] }}
{% endfor %}

# Worker nodes
{% for host in groups['k8s_worker'] %}
{{ hostvars[host]['ansible_host'] }} {{ hostvars[host]['ansible_hostname'] }}
{% endfor %}
```

#### 4.4.3 containerd Role - 容器运行时

```yaml
# roles/containerd/tasks/main.yml
---
- name: 创建containerd配置目录
  file:
    path: /etc/containerd
    state: directory
    mode: '0755'

- name: 安装containerd二进制
  copy:
    src: "{{ item }}"
    dest: "/usr/local/bin/{{ item | basename }}"
    mode: '0755'
  loop:
    - /opt/offline-packages/binaries/containerd
    - /opt/offline-packages/binaries/ctr
  notify: restart containerd

- name: 安装runc
  copy:
    src: /opt/offline-packages/binaries/runc
    dest: /usr/local/sbin/runc
    mode: '0755'

- name: 安装CNI插件
  unarchive:
    src: /opt/offline-packages/binaries/cni-plugins-linux-amd64-v1.3.0.tgz
    dest: /opt/cni/bin
    remote_src: yes

- name: 配置containerd
  template:
    src: config.toml.j2
    dest: /etc/containerd/config.toml
  notify: restart containerd

- name: 创建containerd服务文件
  template:
    src: containerd.service.j2
    dest: /etc/systemd/system/containerd.service

- name: 启动containerd
  systemd:
    name: containerd
    state: started
    enabled: yes
    daemon_reload: yes

- name: 安装crictl
  copy:
    src: /opt/offline-packages/binaries/crictl
    dest: /usr/local/bin/crictl
    mode: '0755'

- name: 配置crictl
  template:
    src: crictl.yaml.j2
    dest: /etc/crictl.yaml
```

```yaml
# roles/containerd/handlers/main.yml
---
- name: restart containerd
  systemd:
    name: containerd
    state: restarted
```

```jinja2
{# roles/containerd/templates/config.toml.j2 #}
version = 2
root = "/var/lib/containerd"
state = "/run/containerd"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"
    
    [plugins."io.containerd.grpc.v1.cri".containerd]
      default_runtime_name = "runc"
      
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
    
    [plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://{{ harbor_host }}"]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
          endpoint = ["https://{{ harbor_host }}"]
      
      [plugins."io.containerd.grpc.v1.cri".registry.configs]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."{{ harbor_host }}".tls]
          insecure_skip_verify = true
```

#### 4.4.4 k8s_node Role - K8s节点组件

```yaml
# roles/k8s_node/tasks/main.yml
---
- name: 创建K8s二进制目录
  file:
    path: /usr/local/bin
    state: directory
    mode: '0755'

- name: 安装K8s二进制文件
  copy:
    src: "{{ item }}"
    dest: "/usr/local/bin/{{ item | basename }}"
    mode: '0755'
  loop:
    - /opt/offline-packages/binaries/kubeadm
    - /opt/offline-packages/binaries/kubelet
    - /opt/offline-packages/binaries/kubectl

- name: 安装etcdctl
  copy:
    src: /opt/offline-packages/binaries/etcdctl
    dest: /usr/local/bin/etcdctl
    mode: '0755'

- name: 创建kubelet服务目录
  file:
    path: /etc/systemd/system/kubelet.service.d
    state: directory
    mode: '0755'

- name: 配置kubelet服务
  template:
    src: kubelet.service.j2
    dest: /etc/systemd/system/kubelet.service

- name: 配置kubelet参数
  template:
    src: 10-kubeadm.conf.j2
    dest: /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

- name: 启用kubelet
  systemd:
    name: kubelet
    enabled: yes
    daemon_reload: yes

- name: 加载K8s镜像
  shell: |
    ctr -n k8s.io images import /opt/offline-packages/images/{{ item }}
  loop:
    - k8s-images-v1.28.0.tar
    - pause-3.9.tar
  when: inventory_hostname in groups['k8s_master']
```

#### 4.4.5 k8s_master Role - 初始化集群

```yaml
# roles/k8s_master/tasks/main.yml
---
- name: 检查集群是否已初始化
  stat:
    path: /etc/kubernetes/admin.conf
  register: k8s_admin_conf

- name: 初始化K8s集群(仅在第一个Master上执行)
  shell: |
    kubeadm init \
      --apiserver-advertise-address={{ ansible_default_ipv4.address }} \
      --control-plane-endpoint={{ k8s_api_endpoint }} \
      --pod-network-cidr={{ pod_cidr }} \
      --service-cidr={{ service_cidr }} \
      --kubernetes-version={{ k8s_version }} \
      --upload-certs \
      --cri-socket=unix:///run/containerd/containerd.sock
  when: 
    - inventory_hostname == groups['k8s_master'][0]
    - not k8s_admin_conf.stat.exists
  register: kubeadm_init

- name: 生成join命令
  shell: kubeadm token create --print-join-command
  register: kubeadm_join_command
  when: inventory_hostname == groups['k8s_master'][0]
  run_once: true

- name: 保存join命令到文件
  copy:
    content: "{{ kubeadm_join_command.stdout }}"
    dest: /opt/k8s-join-command.sh
  when: inventory_hostname == groups['k8s_master'][0]
  delegate_to: localhost
  run_once: true

- name: 配置kubectl
  file:
    path: /root/.kube
    state: directory
    mode: '0755'

- name: 复制admin.conf
  copy:
    src: /etc/kubernetes/admin.conf
    dest: /root/.kube/config
    remote_src: yes
    mode: '0600'
  when: inventory_hostname == groups['k8s_master'][0]

- name: 其他Master加入集群
  shell: |
    {{ hostvars[groups['k8s_master'][0]]['kubeadm_join_command']['stdout'] }} \
      --control-plane --certificate-key $(kubeadm init phase upload-certs --upload-certs | tail -1)
  when: 
    - inventory_hostname in groups['k8s_master']
    - inventory_hostname != groups['k8s_master'][0]
    - not k8s_admin_conf.stat.exists
```

#### 4.4.6 主Playbook

```yaml
# site.yml
---
- name: 配置所有K8s节点
  hosts: k8s_all
  become: yes
  roles:
    - common
    - containerd
    - k8s_node

- name: 初始化K8s Master
  hosts: k8s_master
  become: yes
  roles:
    - k8s_master

- name: Worker节点加入集群
  hosts: k8s_worker
  become: yes
  tasks:
    - name: 检查是否已加入集群
      stat:
        path: /etc/kubernetes/kubelet.conf
      register: kubelet_conf

    - name: Worker节点加入集群
      shell: "{{ lookup('file', '/opt/k8s-join-command.sh') }}"
      when: not kubelet_conf.stat.exists
```

#### 4.4.7 执行Ansible Playbook

```bash
# 1. 语法检查
ansible-playbook site.yml --syntax-check

# 2. 干运行(不实际执行)
ansible-playbook site.yml --check

# 3. 执行部署
ansible-playbook site.yml

# 4. 查看执行结果
ansible-playbook site.yml -v        # 详细输出
ansible-playbook site.yml -vvv      # 更详细输出
```

### 4.5 Terraform+Ansible联动部署完整集群

#### 4.5.1 联动架构

```
+================================================================================+
|                    Terraform + Ansible 联动部署流程                             |
+================================================================================+
|                                                                                |
|  Step 1: Terraform 创建基础设施                                                 |
|  +-------------------+                                                         |
|  | terraform apply   |  --> 创建VMware虚拟机                                    |
|  +---------+---------+     生成inventory.ini                                   |
|            |           生成hosts文件                                            |
|            v                                                                   |
|  Step 2: 等待虚拟机就绪                                                         |
|  +-------------------+                                                         |
|  | null_resource     |  --> 使用local-exec执行等待脚本                          |
|  | wait_for_vms      |     确保SSH可连接                                        |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  Step 3: Ansible 配置节点                                                       |
|  +-------------------+                                                         |
|  | local-exec      |  --> 调用ansible-playbook                                 |
|  | provisioner       |     配置containerd + K8s                                 |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  Step 4: 验证集群                                                               |
|  +-------------------+                                                         |
|  | null_resource     |  --> 执行kubectl验证                                     |
|  | verify_cluster    |     检查节点状态                                         |
|  +-------------------+                                                         |
|                                                                                |
+================================================================================+
```

#### 4.5.2 添加Provisioner

```hcl
# provisioner.tf
# 等待虚拟机SSH就绪
resource "null_resource" "wait_for_vms" {
  depends_on = [
    vsphere_virtual_machine.master,
    vsphere_virtual_machine.worker
  ]
  
  provisioner "local-exec" {
    command = <<-EOF
      for ip in ${join(" ", concat(var.master_ips, var.worker_ips))}; do
        echo "Waiting for $ip..."
        until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$ip "echo OK" 2>/dev/null; do
          sleep 5
        done
        echo "$ip is ready"
      done
    EOF
  }
}

# 执行Ansible Playbook
resource "null_resource" "ansible_provision" {
  depends_on = [null_resource.wait_for_vms]
  
  triggers = {
    always_run = timestamp()
  }
  
  provisioner "local-exec" {
    working_dir = path.module
    command     = "ansible-playbook -i inventory.ini /opt/ansible-k8s/site.yml"
    environment = {
      ANSIBLE_CONFIG = "/etc/ansible/ansible.cfg"
    }
  }
}

# 验证集群
resource "null_resource" "verify_cluster" {
  depends_on = [null_resource.ansible_provision]
  
  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for cluster to be ready..."
      sleep 30
      
      # 检查节点状态
      ssh -o StrictHostKeyChecking=no root@${var.master_ips[0]} "kubectl get nodes"
      
      # 等待所有节点Ready
      ssh -o StrictHostKeyChecking=no root@${var.master_ips[0]} "kubectl wait --for=condition=Ready nodes --all --timeout=300s"
      
      echo "Cluster is ready!"
      ssh -o StrictHostKeyChecking=no root@${var.master_ips[0]} "kubectl get nodes -o wide"
    EOF
  }
}
```

#### 4.5.3 一键部署脚本

```bash
#!/bin/bash
# deploy.sh - 一键部署K8s集群

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="/opt/terraform-k8s"
ANSIBLE_DIR="/opt/ansible-k8s"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform未安装"
        exit 1
    fi
    
    # 检查Ansible
    if ! command -v ansible &> /dev/null; then
        log_error "Ansible未安装"
        exit 1
    fi
    
    # 检查SSH密钥
    if [ ! -f /root/.ssh/id_rsa ]; then
        log_warn "SSH密钥不存在，正在生成..."
        ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa
    fi
    
    log_info "前置条件检查通过"
}

# 执行Terraform
deploy_infrastructure() {
    log_info "Step 1: 创建基础设施..."
    cd "$TERRAFORM_DIR"
    
    terraform init
    terraform plan -out=tfplan
    terraform apply tfplan
    
    log_info "基础设施创建完成"
}

# 配置SSH免密
configure_ssh() {
    log_info "Step 2: 配置SSH免密登录..."
    cd "$TERRAFORM_DIR"
    
    # 获取所有节点IP
    MASTER_IPS=$(terraform output -json master_nodes | jq -r '.[].ip_address')
    WORKER_IPS=$(terraform output -json worker_nodes | jq -r '.[].ip_address')
    ALL_IPS="$MASTER_IPS $WORKER_IPS"
    
    # 复制公钥
    for ip in $ALL_IPS; do
        log_info "配置 $ip 的SSH..."
        sshpass -p 'YourPassword' ssh-copy-id -o StrictHostKeyChecking=no root@$ip || true
    done
    
    log_info "SSH配置完成"
}

# 执行Ansible
configure_nodes() {
    log_info "Step 3: 配置K8s节点..."
    cd "$ANSIBLE_DIR"
    
    # 更新inventory
    cp "$TERRAFORM_DIR/inventory.ini" ./
    
    # 执行Playbook
    ansible-playbook -i inventory.ini site.yml
    
    log_info "节点配置完成"
}

# 验证集群
verify_cluster() {
    log_info "Step 4: 验证集群..."
    
    # 获取第一个Master IP
    FIRST_MASTER=$(terraform -chdir="$TERRAFORM_DIR" output -json master_nodes | jq -r '.[0].ip_address')
    
    # 检查节点状态
    log_info "节点状态:"
    ssh -o StrictHostKeyChecking=no root@$FIRST_MASTER "kubectl get nodes -o wide"
    
    # 检查系统Pod
    log_info "系统Pod状态:"
    ssh -o StrictHostKeyChecking=no root@$FIRST_MASTER "kubectl get pods -n kube-system"
    
    log_info "集群验证完成"
}

# 保存kubeconfig
save_kubeconfig() {
    log_info "Step 5: 保存kubeconfig..."
    
    FIRST_MASTER=$(terraform -chdir="$TERRAFORM_DIR" output -json master_nodes | jq -r '.[0].ip_address')
    
    mkdir -p ~/.kube
    scp -o StrictHostKeyChecking=no root@$FIRST_MASTER:/etc/kubernetes/admin.conf ~/.kube/config
    
    log_info "kubeconfig已保存到 ~/.kube/config"
}

# 主函数
main() {
    log_info "开始部署K8s集群..."
    
    check_prerequisites
    deploy_infrastructure
    configure_ssh
    configure_nodes
    verify_cluster
    save_kubeconfig
    
    log_info "K8s集群部署完成!"
    log_info "使用 'kubectl get nodes' 查看集群状态"
}

# 清理函数
cleanup() {
    log_info "执行清理..."
    cd "$TERRAFORM_DIR"
    terraform destroy -auto-approve
    log_info "清理完成"
}

# 根据参数执行
case "${1:-deploy}" in
    deploy)
        main
        ;;
    destroy)
        cleanup
        ;;
    *)
        echo "用法: $0 [deploy|destroy]"
        exit 1
        ;;
esac
```

#### 4.5.4 执行部署

```bash
# 1. 赋予执行权限
chmod +x /opt/terraform-k8s/deploy.sh

# 2. 执行部署
/opt/terraform-k8s/deploy.sh deploy

# 3. 查看部署结果
kubectl get nodes -o wide
kubectl get pods -n kube-system

# 4. 如需销毁
/opt/terraform-k8s/deploy.sh destroy
```

---

## 5. 状态管理与协作

### 5.1 远程状态后端

#### 5.1.1 State文件问题

```
本地State文件的问题:

1. 团队协作困难
   - 多个开发者无法同时操作
   - State文件冲突

2. 安全风险
   - 可能包含敏感数据
   - 本地存储易丢失

3. 缺乏锁定机制
   - 并发操作导致状态损坏
```

#### 5.1.2 Local后端配置

```hcl
# backend.tf - 本地后端(默认)
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
```

#### 5.1.3 S3后端配置(生产推荐)

```hcl
# backend.tf - S3后端配置
terraform {
  backend "s3" {
    bucket = "my-terraform-state-bucket"
    key    = "k8s-cluster/terraform.tfstate"
    region = "us-east-1"
    
    # 启用State加密
    encrypt = true
    
    # DynamoDB表用于状态锁定
    dynamodb_table = "terraform-locks"
    
    # 工作区前缀
    workspace_key_prefix = "workspaces"
  }
}
```

```bash
# 初始化S3后端
terraform init

# 迁移现有State到S3
terraform init -migrate-state
```

#### 5.1.4 其他后端选项

| 后端类型 | 适用场景 | 特点 |
|----------|----------|------|
| **local** | 本地测试 | 简单，无需配置 |
| **s3** | AWS环境 | 成熟稳定，支持锁定 |
| **gcs** | GCP环境 | 原生集成 |
| **azurerm** | Azure环境 | 原生集成 |
| **consul** | 多数据中心 | 高可用 |
| **kubernetes** | K8s环境 | 使用Secret存储 |
| **pg** | PostgreSQL | 企业级 |

### 5.2 状态锁定

#### 5.2.1 锁定机制

```
状态锁定流程:

1. terraform apply 开始
        |
        v
2. 获取锁 (Acquire Lock)
   - DynamoDB (S3后端)
   - Consul KV
        |
        v
3. 执行变更
        |
        v
4. 释放锁 (Release Lock)
        |
        v
5. 其他操作可以开始
```

#### 5.2.2 强制解锁

```bash
# 查看锁定状态
terraform force-unlock -help

# 强制解锁(谨慎使用!)
terraform force-unlock <LOCK_ID>

# 示例
terraform force-unlock f53f4091-d95a-11e7-8520-5f03a3c4b1c6
```

### 5.3 工作区管理

#### 5.3.1 工作区概念

```
Terraform工作区:

+--------------------------------------------------+
|              Terraform配置                        |
|  (main.tf, variables.tf, outputs.tf)             |
+--------------------------------------------------+
           |                    |                    |
           v                    v                    v
    +-------------+      +-------------+      +-------------+
    |  default    |      |   staging   |      |  production |
    |  工作区     |      |   工作区    |      |   工作区    |
    +-------------+      +-------------+      +-------------+
    | terraform   |      | terraform   |      | terraform   |
    | .tfstate    |      | .tfstate    |      | .tfstate    |
    | .env:dev    |      | .env:stg    |      | .env:prod   |
    +-------------+      +-------------+      +-------------+
```

#### 5.3.2 工作区操作

```bash
# 查看当前工作区
terraform workspace list
* default

# 创建新工作区
terraform workspace new staging
terraform workspace new production

# 切换工作区
terraform workspace select staging

# 显示当前工作区
terraform workspace show

# 删除工作区
terraform workspace delete staging
```

#### 5.3.3 工作区变量配置

```hcl
# variables.tf
variable "environment" {
  description = "环境名称"
  type        = string
  default     = "dev"
}

variable "instance_count" {
  description = "实例数量"
  type        = map(number)
  default = {
    dev  = 1
    stg  = 3
    prod = 5
  }
}

# main.tf
resource "vsphere_virtual_machine" "node" {
  count = var.instance_count[var.environment]
  # ...
}
```

```bash
# 不同环境使用不同tfvars文件
terraform workspace select dev
terraform apply -var-file="envs/dev.tfvars"

terraform workspace select prod
terraform apply -var-file="envs/prod.tfvars"
```

---

## 6. 生产级实践

### 6.1 模块封装

#### 6.1.1 模块结构

```
terraform-modules/
├── modules/
│   ├── vsphere-vm/           # 虚拟机模块
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   ├── k8s-cluster/          # K8s集群模块
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── network/              # 网络模块
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
└── environments/
    ├── dev/
    │   └── main.tf
    ├── staging/
    │   └── main.tf
    └── prod/
        └── main.tf
```

#### 6.1.2 模块调用示例

```hcl
# environments/prod/main.tf
module "k8s_network" {
  source = "../../modules/network"
  
  network_name    = "k8s-prod-network"
  vlan_id         = 100
  subnet_cidr     = "192.168.100.0/24"
  gateway         = "192.168.100.1"
}

module "k8s_masters" {
  source = "../../modules/vsphere-vm"
  
  vm_count        = 3
  vm_prefix       = "k8s-master"
  cpu             = 4
  memory          = 8192
  disk_size       = 100
  network_id      = module.k8s_network.network_id
  ip_addresses    = ["192.168.100.11", "192.168.100.12", "192.168.100.13"]
  
  tags = {
    environment = "production"
    role        = "master"
  }
}

module "k8s_workers" {
  source = "../../modules/vsphere-vm"
  
  vm_count        = 5
  vm_prefix       = "k8s-worker"
  cpu             = 8
  memory          = 16384
  disk_size       = 200
  network_id      = module.k8s_network.network_id
  ip_addresses    = ["192.168.100.21", "192.168.100.22", "192.168.100.23", 
                     "192.168.100.24", "192.168.100.25"]
  
  tags = {
    environment = "production"
    role        = "worker"
  }
}
```

### 6.2 变量验证

#### 6.2.1 基础验证

```hcl
variable "master_count" {
  description = "Master节点数量"
  type        = number
  default     = 3
  
  validation {
    condition     = var.master_count >= 1 && var.master_count <= 7
    error_message = "Master节点数量必须是奇数且在1-7之间"
  }
  
  validation {
    condition     = var.master_count % 2 == 1
    error_message = "Master节点数量必须是奇数(用于etcd仲裁)"
  }
}
```

#### 6.2.2 复杂验证

```hcl
variable "ip_addresses" {
  description = "节点IP地址列表"
  type        = list(string)
  
  validation {
    condition = alltrue([
      for ip in var.ip_addresses : can(regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", ip))
    ])
    error_message = "所有IP地址必须是有效的IPv4地址"
  }
}

variable "node_config" {
  description = "节点配置"
  type = object({
    cpu    = number
    memory = number
    disk   = number
  })
  
  validation {
    condition     = var.node_config.cpu >= 2
    error_message = "CPU核心数至少为2"
  }
  
  validation {
    condition     = var.node_config.memory >= 2048
    error_message = "内存至少为2GB"
  }
}
```

### 6.3 敏感数据处理

#### 6.3.1 敏感变量

```hcl
# variables.tf
variable "vsphere_password" {
  description = "vCenter密码"
  type        = string
  sensitive   = true  # 标记为敏感
}

variable "ssh_private_key" {
  description = "SSH私钥"
  type        = string
  sensitive   = true
}
```

#### 6.3.2 使用Vault管理密钥

```hcl
# 使用HashiCorp Vault
provider "vault" {
  address = "https://vault.example.com:8200"
}

data "vault_kv_secret_v2" "vsphere" {
  mount = "secret"
  name  = "vsphere/credentials"
}

provider "vsphere" {
  user           = data.vault_kv_secret_v2.vsphere.data["username"]
  password       = data.vault_kv_secret_v2.vsphere.data["password"]
  vsphere_server = "vcenter.example.com"
}
```

#### 6.3.3 环境变量传递

```bash
# 使用环境变量(不写入文件)
export TF_VAR_vsphere_password="YourSecurePassword"
export TF_VAR_ssh_private_key="$(cat /root/.ssh/id_rsa)"

# 执行Terraform
terraform apply
```

---

## 7. 故障排查案例

### 案例1: Provider下载失败

**现象:**
```
Error: Failed to query available provider packages
Could not retrieve the list of available versions for provider
hashicorp/vsphere: could not connect to registry.terraform.io
```

**原因:** 离线环境无法连接Terraform Registry

**解决方案:**
```bash
# 1. 确认Provider已下载到本地
ls -la /opt/terraform-plugins/registry.terraform.io/hashicorp/vsphere/

# 2. 检查.terraformrc配置
cat ~/.terraformrc

# 3. 重新初始化
cd /opt/terraform-k8s
rm -rf .terraform .terraform.lock.hcl
terraform init

# 4. 如果仍失败，手动安装Provider
mkdir -p .terraform/providers/registry.terraform.io/hashicorp/vsphere/2.5.1/linux_amd64
cp /opt/terraform-plugins/registry.terraform.io/hashicorp/vsphere/2.5.1/linux_amd64/* \
   .terraform/providers/registry.terraform.io/hashicorp/vsphere/2.5.1/linux_amd64/

# 5. 创建锁定文件
cat > .terraform.lock.hcl << 'EOF'
provider "registry.terraform.io/hashicorp/vsphere" {
  version = "2.5.1"
  hashes = [
    "h1:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  ]
}
EOF
```

### 案例2: vSphere连接失败

**现象:**
```
Error: error setting up new vSphere SOAP client: Post "https://vcenter.example.com/sdk":
dial tcp: lookup vcenter.example.com: no such host
```

**原因:** DNS解析失败或网络不通

**解决方案:**
```bash
# 1. 检查DNS解析
nslookup vcenter.example.com

# 2. 添加到hosts
echo "192.168.1.10 vcenter.example.com" >> /etc/hosts

# 3. 检查网络连通性
ping vcenter.example.com
telnet vcenter.example.com 443

# 4. 检查vSphere证书(如果使用自签名)
# 在terraform.tf中设置
provider "vsphere" {
  # ...
  allow_unverified_ssl = true
}
```

### 案例3: 虚拟机克隆失败

**现象:**
```
Error: error cloning virtual machine: A specified parameter was not correct: spec.pool
```

**原因:** Resource Pool配置错误

**解决方案:**
```hcl
# 检查Resource Pool配置
data "vsphere_resource_pool" "pool" {
  # 方式1: 使用集群默认Resource Pool
  name          = "${var.vsphere_cluster}/Resources"
  datacenter_id = data.vsphere_datacenter.dc.id
  
  # 方式2: 使用特定Resource Pool
  # name          = "${var.vsphere_cluster}/Resources/Production"
}

# 验证Resource Pool存在
# 在vCenter中: 集群 -> 配置 -> 资源池
```

### 案例4: Ansible连接失败

**现象:**
```
UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: 
Permission denied (publickey,password).", "unreachable": true}
```

**原因:** SSH密钥未配置或密码错误

**解决方案:**
```bash
# 1. 检查SSH密钥
ls -la /root/.ssh/

# 2. 重新生成密钥
ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -y

# 3. 复制公钥到节点
for ip in 192.168.1.51 192.168.1.52; do
    sshpass -p 'YourPassword' ssh-copy-id -o StrictHostKeyChecking=no root@$ip
done

# 4. 测试连接
ansible all -m ping -vvv

# 5. 检查Ansible配置
grep -E "^(private_key_file|ansible_user)" /etc/ansible/ansible.cfg
```

### 案例5: K8s初始化失败

**现象:**
```
[ERROR FileAvailable--etc-kubernetes-manifests-kube-apiserver.yaml]: 
/etc/kubernetes/manifests/kube-apiserver.yaml already exists
[ERROR Port-10250]: Port 10250 is in use
```

**原因:** 节点已有K8s配置残留

**解决方案:**
```bash
# 1. 重置节点(在所有节点上执行)
kubeadm reset -f

# 2. 清理残留文件
rm -rf /etc/kubernetes/
rm -rf /var/lib/kubelet/
rm -rf /var/lib/etcd/
rm -rf $HOME/.kube/

# 3. 清理iptables规则
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

# 4. 清理CNI配置
rm -rf /etc/cni/net.d/
rm -rf /opt/cni/bin/

# 5. 重新执行Ansible
ansible-playbook -i inventory.ini site.yml
```

---

## 8. CKA/CKS考点

### 考点1: 集群安装与配置

**考试内容:**
- 使用kubeadm安装K8s集群
- 配置高可用Master节点
- 升级K8s版本

**相关命令:**
```bash
# 初始化集群
kubeadm init --pod-network-cidr=10.244.0.0/16

# 加入节点
kubeadm join 192.168.1.51:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# 升级集群
kubeadm upgrade plan
kubeadm upgrade apply v1.28.0

# 生成新token
kubeadm token create --print-join-command
```

### 考点2: 集群故障排查

**考试内容:**
- 诊断节点NotReady问题
- 排查Pod启动失败
- 检查网络连通性

**相关命令:**
```bash
# 查看节点状态
kubectl get nodes -o wide
kubectl describe node <node-name>

# 查看系统Pod
kubectl get pods -n kube-system

# 查看kubelet日志
journalctl -u kubelet -f

# 检查容器运行时
crictl ps
crictl logs <container-id>
```

### 考点3: 安全管理

**考试内容:**
- 配置TLS证书
- 启用RBAC
- 配置Pod安全策略

**相关命令:**
```bash
# 查看证书有效期
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep Not

# 更新证书
kubeadm certs renew all

# 检查RBAC
kubectl auth can-i create pods --as=system:serviceaccount:default:default
```

### 考点4: 网络配置

**考试内容:**
- 配置CNI插件
- 排查网络问题
- 配置Service网络

**相关命令:**
```bash
# 查看CNI配置
cat /etc/cni/net.d/10-calico.conflist

# 检查网络连通性
kubectl run test --image=busybox --rm -it --restart=Never -- ping <pod-ip>

# 查看Service
kubectl get svc -o wide
```

### 考点5: etcd管理

**考试内容:**
- 备份和恢复etcd
- 检查etcd集群健康
- 配置etcd加密

**相关命令:**
```bash
# 备份etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 恢复etcd
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-backup.db \
  --data-dir=/var/lib/etcd-restored

# 检查etcd健康
ETCDCTL_API=3 etcdctl endpoint health
```

---

## 9. 面试题

### 面试题1: Terraform与Ansible的区别是什么？如何选择？

**参考答案:**

Terraform和Ansible都是基础设施自动化工具，但有不同侧重点:

| 维度 | Terraform | Ansible |
|------|-----------|---------|
| **主要用途** | 基础设施创建/销毁 | 配置管理/应用部署 |
| **执行模式** | 声明式 | 命令式 |
| **状态管理** | 有状态文件 | 无状态 |
| **幂等性** | 自动处理 | 需要模块支持 |
| **云原生** | 更好支持云平台 | 通用性更强 |

**选择建议:**
- 创建云资源/虚拟机 → Terraform
- 系统配置/软件安装 → Ansible
- 两者结合 → Terraform创建资源，Ansible配置节点

### 面试题2: 如何在离线环境中使用Terraform？

**参考答案:**

离线环境使用Terraform的关键是Provider缓存:

1. **预下载Provider:**
   ```bash
   # 有外网环境
   terraform init
   # 复制.terraform/providers到离线环境
   ```

2. **配置本地Provider镜像:**
   ```hcl
   # ~/.terraformrc
   provider_installation {
     filesystem_mirror {
       path = "/opt/terraform-plugins"
     }
   }
   ```

3. **使用本地模块:**
   ```hcl
   module "example" {
     source = "/path/to/local/module"
   }
   ```

### 面试题3: 如何设计高可用的K8s集群架构？

**参考答案:**

**控制面高可用:**
- 3个或5个Master节点(奇数用于etcd仲裁)
- 使用负载均衡器暴露API Server
- etcd堆叠模式或外部etcd集群

**数据面高可用:**
- 至少2个Worker节点
- 跨可用区部署
- 使用DaemonSet部署关键组件

**网络高可用:**
- CNI插件支持网络策略
- CoreDNS多副本部署
- Ingress Controller多实例

### 面试题4: Terraform State文件损坏如何恢复？

**参考答案:**

**恢复方法:**

1. **使用备份:**
   ```bash
   # 如果启用了远程后端，从S3/GCS恢复
   aws s3 cp s3://bucket/terraform.tfstate.backup .
   ```

2. **手动修复:**
   ```bash
   # 导出当前状态
   terraform state pull > terraform.tfstate.backup
   
   # 编辑修复
   vim terraform.tfstate
   
   # 推送修复后的状态
   terraform state push terraform.tfstate
   ```

3. **重新导入:**
   ```bash
   # 删除损坏的资源记录
   terraform state rm vsphere_virtual_machine.example
   
   # 重新导入现有资源
   terraform import vsphere_virtual_machine.example /dc/vm/example
   ```

### 面试题5: 如何实现GitOps工作流？

**参考答案:**

**GitOps核心原则:**
1. 声明式配置
2. 版本控制
3. 自动同步
4. 持续协调

**实现方案:**

```
Git仓库(单一事实来源)
    |
    v
ArgoCD/Flux (GitOps工具)
    |
    v
Kubernetes集群
```

**Terraform + GitOps:**
- 使用Terraform Cloud/Enterprise
- 配置VCS驱动的工作流
- 自动Plan和Apply

**Ansible + GitOps:**
- 使用Ansible Tower/AWX
- 配置Webhook触发
- 自动执行Playbook

---

## 10. VMware Workstation Pro实战（个人测试环境）

> 本节针对使用VMware Workstation Pro的个人测试环境，提供IaC自动化方案。
> 
> **适用场景**: Windows 10/11 + VMware Workstation Pro + Ubuntu虚拟机
> **核心工具**: Terraform + `vmware-workstation` Provider + cloud-init

### 10.1 VMware Workstation与vSphere的区别

| 特性 | VMware Workstation Pro | VMware vSphere |
|------|------------------------|----------------|
| **定位** | 桌面虚拟化 | 企业服务器虚拟化 |
| **API** | REST API (有限) | vSphere API (完整) |
| **Terraform Provider** | `elsudano/vmware-workstation` | `hashicorp/vsphere` |
| **适用场景** | 个人开发/测试 | 生产环境 |
| **成本** | 一次性购买/试用 | 订阅制 |

### 10.2 环境准备

#### 10.2.1 安装VMware Workstation Pro

```powershell
# Windows 10/11 安装VMware Workstation Pro 16.5
# 下载地址: https://support.broadcom.com/security-advisory

# 安装后验证
vmrun -T ws list
# 输出运行的虚拟机列表
```

#### 10.2.2 配置VMware REST API

VMware Workstation Pro 16+ 支持REST API，需要手动启用：

```powershell
# 以管理员身份运行PowerShell
# 启用Workstation REST API (默认端口8697)

# 1. 找到vmrest.exe路径
$vmrestPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe"

# 2. 生成API证书
& $vmrestPath -c  # 生成证书，按提示设置用户名密码

# 3. 启动REST API服务
& $vmrestPath -d  # 后台运行

# 4. 验证API
$headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("username:password"))
}
Invoke-RestMethod -Uri "http://localhost:8697/api/vms" -Headers $headers
```

#### 10.2.3 准备Ubuntu 22.04镜像

```powershell
# 下载Ubuntu 22.04 Server ISO
# https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso

# 创建基础虚拟机（用于克隆）
# 手动创建一台Ubuntu 22.04虚拟机，安装完成后:
# 1. 安装openssh-server
# 2. 配置静态IP
# 3. 安装cloud-init
# 4. 关闭虚拟机，作为模板
```

### 10.3 Terraform配置

#### 10.3.1 Provider配置

```hcl
# versions.tf
terraform {
  required_providers {
    vmware-workstation = {
      source  = "elsudano/vmware-workstation"
      version = "1.0.0"
    }
  }
}

# provider.tf
provider "vmware-workstation" {
  host     = "http://localhost:8697"
  username = var.vmware_username
  password = var.vmware_password
}
```

#### 10.3.2 创建K8s节点虚拟机

```hcl
# variables.tf
variable "vmware_username" {
  description = "VMware Workstation REST API username"
  type        = string
  default     = "admin"
}

variable "vmware_password" {
  description = "VMware Workstation REST API password"
  type        = string
  sensitive   = true
}

variable "k8s_nodes" {
  description = "K8s节点配置"
  type = map(object({
    hostname = string
    ip       = string
    cpu      = number
    memory   = number
    disk     = number
    role     = string  # master/worker/harbor
  }))
  default = {
    m1 = {
      hostname = "k8s-master-1"
      ip       = "192.168.1.51"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    m2 = {
      hostname = "k8s-master-2"
      ip       = "192.168.1.52"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    m3 = {
      hostname = "k8s-master-3"
      ip       = "192.168.1.53"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    w1 = {
      hostname = "k8s-worker-1"
      ip       = "192.168.1.54"
      cpu      = 4
      memory   = 8192
      disk     = 100
      role     = "worker"
    }
    w2 = {
      hostname = "k8s-worker-2"
      ip       = "192.168.1.55"
      cpu      = 4
      memory   = 8192
      disk     = 100
      role     = "worker"
    }
    hb = {
      hostname = "harbor-registry"
      ip       = "192.168.1.61"
      cpu      = 2
      memory   = 2048
      disk     = 200
      role     = "harbor"
    }
  }
}
```

```hcl
# main.tf
# 创建虚拟机目录
resource "vmware-workstation_folder" "k8s" {
  path = "K8s-Cluster"
}

# 创建K8s节点
resource "vmware-workstation_vm" "k8s_nodes" {
  for_each = var.k8s_nodes

  name       = each.value.hostname
  folder     = vmware-workstation_folder.k8s.path
  
  # 从模板克隆
  clone {
    source_vm = "Ubuntu-22.04-Template"
    linked    = false  # 完整克隆
  }

  # 硬件配置
  cpus   = each.value.cpu
  memory = each.value.memory

  # 磁盘配置
  disk {
    size = each.value.disk
  }

  # 网络配置 (使用VMnet8 NAT网络)
  network {
    type        = "nat"
    mac_address = "00:50:56:00:00:${format("%02x", 51 + index(keys(var.k8s_nodes), each.key))}"
  }

  # cloud-init配置
  cloud_init {
    user_data = templatefile("${path.module}/cloud-init.yml", {
      hostname = each.value.hostname
      ip       = each.value.ip
      role     = each.value.role
    })
  }

  # 启动虚拟机
  power = "on"

  # 等待cloud-init完成
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait"
    ]
    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_ed25519")
      host        = each.value.ip
    }
  }
}
```

#### 10.3.3 cloud-init配置

```yaml
# cloud-init.yml
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

# 配置静态IP
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - ${ip}/24
      gateway4: 192.168.1.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 114.114.114.114

# SSH配置
ssh_authorized_keys:
  - ssh-ed25519 AAAAC3NzaC... root@showdoc

# 安装必要软件包
packages:
  - openssh-server
  - curl
  - wget
  - vim
  - net-tools
  - htop

# 内核优化 (K8s准备)
runcmd:
  - |
    cat >> /etc/sysctl.conf <<EOF
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOF
  - sysctl --system
  - |
    cat >> /etc/modules-load.d/k8s.conf <<EOF
    overlay
    br_netfilter
    EOF
  - modprobe overlay
  - modprobe br_netfilter
  - echo "K8s node ${hostname} (${role}) initialized" >> /var/log/cloud-init.log
```

### 10.4 Ansible集成

```yaml
# ansible/inventory.yml
all:
  children:
    masters:
      hosts:
        m1:
          ansible_host: 192.168.1.51
        m2:
          ansible_host: 192.168.1.52
        m3:
          ansible_host: 192.168.1.53
    workers:
      hosts:
        w1:
          ansible_host: 192.168.1.54
        w2:
          ansible_host: 192.168.1.55
    harbor:
      hosts:
        hb:
          ansible_host: 192.168.1.61
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

```yaml
# ansible/k8s-setup.yml
---
- name: 配置K8s基础环境
  hosts: all
  become: yes
  tasks:
    - name: 安装containerd
      apt:
        name: containerd
        state: present
        update_cache: yes

    - name: 配置containerd
      shell: |
        mkdir -p /etc/containerd
        containerd config default > /etc/containerd/config.toml
        sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
        systemctl restart containerd

    - name: 安装kubeadm/kubelet/kubectl
      apt:
        name:
          - kubelet
          - kubeadm
          - kubectl
        state: present

    - name: 禁用swap
      shell: |
        swapoff -a
        sed -i '/swap/d' /etc/fstab

- name: 初始化K8s Master
  hosts: m1
  become: yes
  tasks:
    - name: kubeadm init
      shell: |
        kubeadm init \
          --control-plane-endpoint "192.168.1.51:6443" \
          --pod-network-cidr=10.244.0.0/16 \
          --upload-certs
      args:
        creates: /etc/kubernetes/admin.conf

    - name: 配置kubectl
      shell: |
        mkdir -p $HOME/.kube
        cp /etc/kubernetes/admin.conf $HOME/.kube/config
        chown $(id -u):$(id -g) $HOME/.kube/config
```

### 10.5 执行部署

```bash
# 1. 初始化Terraform
cd terraform-workstation
terraform init

# 2. 查看执行计划
terraform plan -var="vmware_password=your_password"

# 3. 创建虚拟机
terraform apply -var="vmware_password=your_password" -auto-approve

# 4. 等待虚拟机启动完成
# (cloud-init会自动配置网络)

# 5. 使用Ansible配置K8s
cd ../ansible
ansible-playbook -i inventory.yml k8s-setup.yml

# 6. 验证集群
ssh root@192.168.1.51 kubectl get nodes
```

### 10.6 与现有SSH配置集成

你的`.ssh/config`可以直接使用：

```bash
# 使用现有SSH配置连接
ssh m1  # 连接到192.168.1.51
ssh w1  # 连接到192.168.1.54

# Ansible使用SSH配置
ansible -i inventory.yml masters -m ping
```

### 10.7 注意事项

| 问题 | 解决方案 |
|------|----------|
| Workstation REST API不稳定 | 使用`vmrun`命令行作为备选 |
| 虚拟机IP不固定 | 使用cloud-init配置静态IP |
| Windows防火墙阻止 | 开放8697端口 |
| 资源不足 | 调整worker节点为2C4G测试 |

### 10.8 备选方案：vmrun + Shell脚本

如果Terraform Provider不稳定，可以使用vmrun：

```bash
#!/bin/bash
# create-vms.sh

VMRUN="/mnt/c/Program Files (x86)/VMware/VMware Workstation/vmrun.exe"
TEMPLATE="C:\VMs\Ubuntu-22.04-Template\Ubuntu-22.04-Template.vmx"

# 创建Master节点
for i in 1 2 3; do
  VMX="C:\VMs\k8s-master-${i}\k8s-master-${i}.vmx"
  "$VMRUN" -T ws clone "$TEMPLATE" "$VMX" full
  "$VMRUN" -T ws start "$VMX"
done

# 创建Worker节点
for i in 1 2; do
  VMX="C:\VMs\k8s-worker-${i}\k8s-worker-${i}.vmx"
  "$VMRUN" -T ws clone "$TEMPLATE" "$VMX" full
  "$VMRUN" -T ws start "$VMX"
done
```

---

## 11. VMware Workstation完整操作指南（Windows环境）

> 本节提供VMware Workstation 16 Pro + Terraform的完整操作指南。
> 
> **适用版本**: VMware Workstation 16 Pro (16.2.5 build-20904516)
> **目标**: 实现K8s集群环境的一键创建、销毁、复刻

---

### 11.1 基础镜像制作（黄金镜像）

#### 11.1.1 创建模板虚拟机

```powershell
# 步骤1: 在VMware中创建新虚拟机
# 文件 -> 新建虚拟机 -> 自定义(高级)

# 配置参数:
# - 兼容性: Workstation 16.x
# - 操作系统: Linux -> Ubuntu 64位
# - 虚拟机名称: Ubuntu-22.04-Template
# - 位置: C:\VMs\Ubuntu-22.04-Template
# - CPU: 2核
# - 内存: 4096MB (模板可大些，克隆后调整)
# - 网络: NAT (VMnet8)
# - SCSI控制器: LSI Logic
# - 虚拟磁盘: 50GB，拆分为多个文件
# - CD/DVD: 选择Ubuntu 22.04 ISO
```

#### 11.1.2 安装Ubuntu 22.04

```bash
# 启动虚拟机，按提示安装
# 语言: English (避免中文路径问题)
# 键盘: English (US)
# 安装类型: Ubuntu Server

# 关键配置:
# - Hostname: ubuntu-template
# - 用户名: root (或创建用户后启用root)
# - 密码: 设置强密码
# - 磁盘分区: 使用整个磁盘，LVM
# - 软件选择: 仅OpenSSH server（最小化安装）
```

#### 11.1.3 安装cloud-init和必要工具

```bash
# 登录模板虚拟机
ssh root@192.168.1.xxx  # 安装过程中的临时IP

# 更新系统
apt update && apt upgrade -y

# 安装cloud-init（关键！用于初始化配置）
apt install -y cloud-init

# 安装必要工具
apt install -y \
    openssh-server \
    curl \
    wget \
    vim \
    net-tools \
    iputils-ping \
    htop \
    qemu-guest-agent

# 配置SSH（允许root登录，用于Ansible）
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# 配置GRUB（加快启动）
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
update-grub

# 清理（减小镜像大小）
apt clean
apt autoremove -y
rm -rf /var/log/*
rm -rf /tmp/*
history -c
```

#### 11.1.4 配置cloud-init数据源

```bash
# 配置VMware数据源
cat > /etc/cloud/cloud.cfg.d/99-vmware.cfg <<'EOF'
datasource_list: [ VMware, NoCloud, None ]
datasource:
  VMware:
    allow_raw_data: true
EOF

# 重置cloud-init（确保下次启动重新初始化）
cloud-init clean --logs --seed
rm -rf /var/lib/cloud/*

# 关闭虚拟机
shutdown -h now
```

#### 11.1.5 转换为模板

```powershell
# 在VMware中:
# 1. 右键虚拟机 -> 管理 -> 克隆
# 2. 选择"创建完整克隆"
# 3. 命名为 "Ubuntu-22.04-Template-Base"
# 4. 原虚拟机可删除，保留Base作为模板

# 或者使用vmrun克隆（后续用）
```

**模板文件位置**:
```
C:\VMs\Ubuntu-22.04-Template-Base\
├── Ubuntu-22.04-Template-Base.vmx      # 虚拟机配置文件
├── Ubuntu-22.04-Template-Base.vmdk     # 虚拟磁盘
└── ...
```

---

### 11.2 启用VMware REST API

#### 11.2.1 配置REST API服务

```powershell
# 以管理员身份运行PowerShell

# 1. 找到vmrest.exe路径
$vmrestPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe"

# 2. 检查版本（需要16.0+）
& $vmrestPath --version
# 输出: VMware Workstation REST API 1.2.0

# 3. 生成API证书（首次运行）
& $vmrestPath -c
# 按提示设置:
# - 用户名: admin
# - 密码: 设置强密码（记住！）
# - 证书保存到: %APPDATA%\VMware\vmrest.crt

# 4. 启动REST API服务（后台运行）
Start-Process -FilePath $vmrestPath -ArgumentList "-d" -WindowStyle Hidden

# 5. 验证服务状态
Invoke-RestMethod -Uri "http://localhost:8697/api/vms" -Method Get
# 如果返回401，说明服务正常，需要认证
```

#### 11.2.2 配置开机自启（可选）

```powershell
# 创建计划任务，开机自动启动REST API
$action = New-ScheduledTaskAction -Execute "$vmrestPath" -Argument "-d"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries

Register-ScheduledTask -TaskName "VMware REST API" `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings

# 测试
Start-ScheduledTask -TaskName "VMware REST API"
```

#### 11.2.3 防火墙配置

```powershell
# 开放8697端口
New-NetFirewallRule -DisplayName "VMware REST API" `
    -Direction Inbound `
    -LocalPort 8697 `
    -Protocol TCP `
    -Action Allow

# 验证
Test-NetConnection -ComputerName localhost -Port 8697
```

---

### 11.3 Terraform配置详解

#### 11.3.1 项目目录结构

```
terraform-vmware/
├── versions.tf           # Provider版本
├── provider.tf           # Provider配置
├── variables.tf          # 变量定义
├── main.tf              # 主要资源
├── outputs.tf           # 输出信息
├── terraform.tfvars     # 变量值（不提交Git）
├── cloud-init.yml.tpl   # cloud-init模板
└── ansible/             # Ansible配置
    ├── inventory.yml
    └── k8s-setup.yml
```

#### 11.3.2 完整Terraform配置

```hcl
# versions.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    vmware-workstation = {
      source  = "elsudano/vmware-workstation"
      version = "~> 1.0"
    }
  }
}
```

```hcl
# provider.tf
provider "vmware-workstation" {
  host     = "http://localhost:8697"
  username = var.vmware_username
  password = var.vmware_password
}
```

```hcl
# variables.tf
variable "vmware_username" {
  description = "VMware REST API用户名"
  type        = string
  default     = "admin"
}

variable "vmware_password" {
  description = "VMware REST API密码"
  type        = string
  sensitive   = true
}

variable "vm_base_path" {
  description = "虚拟机存储路径"
  type        = string
  default     = "C:/VMs"
}

variable "template_path" {
  description = "模板虚拟机路径"
  type        = string
  default     = "C:/VMs/Ubuntu-22.04-Template-Base/Ubuntu-22.04-Template-Base.vmx"
}

variable "k8s_nodes" {
  description = "K8s节点配置"
  type = map(object({
    hostname = string
    ip       = string
    cpu      = number
    memory   = number
    disk     = number
    role     = string
  }))
  default = {
    m1 = {
      hostname = "k8s-master-1"
      ip       = "192.168.1.51"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    m2 = {
      hostname = "k8s-master-2"
      ip       = "192.168.1.52"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    m3 = {
      hostname = "k8s-master-3"
      ip       = "192.168.1.53"
      cpu      = 2
      memory   = 2048
      disk     = 50
      role     = "master"
    }
    w1 = {
      hostname = "k8s-worker-1"
      ip       = "192.168.1.54"
      cpu      = 4
      memory   = 8192
      disk     = 100
      role     = "worker"
    }
    w2 = {
      hostname = "k8s-worker-2"
      ip       = "192.168.1.55"
      cpu      = 4
      memory   = 8192
      disk     = 100
      role     = "worker"
    }
    hb = {
      hostname = "harbor-registry"
      ip       = "192.168.1.61"
      cpu      = 2
      memory   = 2048
      disk     = 200
      role     = "harbor"
    }
  }
}

variable "ssh_public_key" {
  description = "SSH公钥"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDIhz2GK/XCUj4i6Q5yQJNL1MGj9n2tT8ZJ4J4J4J4J4 root@showdoc"
}
```

```hcl
# terraform.tfvars（根据实际情况修改）
vmware_password = "你的REST_API密码"
ssh_public_key  = "你的SSH公钥"
```

```hcl
# main.tf
# 创建虚拟机目录
resource "vmware-workstation_folder" "k8s" {
  path = "${var.vm_base_path}/K8s-Cluster"
}

# 创建K8s节点虚拟机
resource "vmware-workstation_vm" "k8s_nodes" {
  for_each = var.k8s_nodes

  name   = each.value.hostname
  folder = vmware-workstation_folder.k8s.path

  # 从模板克隆
  clone {
    source_vm = var.template_path
    linked    = false  # 完整克隆，独立磁盘
  }

  # 硬件配置
  cpus   = each.value.cpu
  memory = each.value.memory

  # 网络配置 - NAT模式
  network {
    type        = "nat"
    mac_address = format("00:50:56:00:00:%02x", 51 + index(keys(var.k8s_nodes), each.key))
  }

  # cloud-init配置（通过CD-ROM挂载）
  cdrom {
    iso_path = vmware-workstation_cloudinit_iso.node_init[each.key].iso_path
  }

  # 启动虚拟机
  power = "on"

  # 等待cloud-init完成
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "echo 'Node ${each.value.hostname} initialized successfully'"
    ]
    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_ed25519")
      host        = each.value.ip
      timeout     = "5m"
    }
  }

  lifecycle {
    prevent_destroy = false  # 允许删除
  }
}

# 生成cloud-init ISO
resource "vmware-workstation_cloudinit_iso" "node_init" {
  for_each = var.k8s_nodes

  iso_path = "${var.vm_base_path}/cloud-init-${each.value.hostname}.iso"
  
  user_data = templatefile("${path.module}/cloud-init.yml.tpl", {
    hostname = each.value.hostname
    ip       = each.value.ip
    gateway  = "192.168.1.1"
    dns      = ["8.8.8.8", "114.114.114.114"]
    ssh_key  = var.ssh_public_key
  })
}
```

```yaml
# cloud-init.yml.tpl
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

# 配置静态IP
network:
  version: 2
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - ${ip}/24
      routes:
        - to: default
          via: ${gateway}
      nameservers:
        addresses: ${jsonencode(dns)}

# SSH配置
ssh_authorized_keys:
  - ${ssh_key}

# 禁用密码登录（安全）
ssh_pwauth: false

# 安装必要软件包
packages:
  - openssh-server
  - curl
  - wget
  - vim
  - net-tools
  - htop
  - qemu-guest-agent

# 内核优化（K8s准备）
runcmd:
  - |
    cat >> /etc/sysctl.conf <<EOF
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    vm.swappiness = 0
    EOF
  - sysctl --system
  - |
    cat >> /etc/modules-load.d/k8s.conf <<EOF
    overlay
    br_netfilter
    EOF
  - modprobe overlay
  - modprobe br_netfilter
  - swapoff -a
  - sed -i '/swap/d' /etc/fstab
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "K8s node ${hostname} initialized" >> /var/log/cloud-init.log

final_message: "The system is finally up, after $UPTIME seconds"
```

```hcl
# outputs.tf
output "node_ips" {
  description = "K8s节点IP地址"
  value = {
    for name, node in var.k8s_nodes : name => node.ip
  }
}

output "ssh_commands" {
  description = "SSH连接命令"
  value = {
    for name, node in var.k8s_nodes : name => "ssh root@${node.ip}"
  }
}

output "ansible_inventory" {
  description = "Ansible inventory配置"
  value = <<-EOT
    [masters]
    ${join("\n", [for name, node in var.k8s_nodes : "${name} ansible_host=${node.ip}" if node.role == "master"])}
    
    [workers]
    ${join("\n", [for name, node in var.k8s_nodes : "${name} ansible_host=${node.ip}" if node.role == "worker"])}
    
    [harbor]
    ${join("\n", [for name, node in var.k8s_nodes : "${name} ansible_host=${node.ip}" if node.role == "harbor"])}
    
    [all:vars]
    ansible_user=root
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
  EOT
}
```

---

### 11.4 执行部署

#### 11.4.1 初始化Terraform

```powershell
# 进入项目目录
cd terraform-vmware

# 初始化（下载Provider）
terraform init

# 验证配置
terraform validate
```

#### 11.4.2 查看执行计划

```powershell
# 查看将要创建的资源
terraform plan -var="vmware_password=你的密码"

# 输出示例:
# Plan: 13 to add, 0 to change, 0 to destroy.
# + vmware-workstation_folder.k8s
# + vmware-workstation_cloudinit_iso.node_init["m1"]
# + vmware-workstation_vm.k8s_nodes["m1"]
# ...
```

#### 11.4.3 创建虚拟机

```powershell
# 创建所有资源（约10-15分钟）
terraform apply -var="vmware_password=你的密码" -auto-approve

# 输出:
# Apply complete! Resources: 13 added, 0 changed, 0 destroyed.
# 
# Outputs:
# node_ips = {
#   "hb" = "192.168.1.61"
#   "m1" = "192.168.1.51"
#   ...
# }
```

#### 11.4.4 验证部署

```powershell
# 测试SSH连接
ssh root@192.168.1.51 "hostname && ip addr show ens33"

# 查看所有节点
terraform output node_ips

# 生成Ansible inventory
terraform output ansible_inventory > ansible/inventory_generated.yml
```

---

### 11.5 虚拟机生命周期管理

#### 11.5.1 启动/停止虚拟机

```powershell
# 使用vmrun控制（不需要Terraform）
$vmrun = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$vmPath = "C:\VMs\K8s-Cluster\k8s-master-1\k8s-master-1.vmx"

# 启动
& $vmrun -T ws start $vmPath

# 停止（优雅关机）
& $vmrun -T ws stop $vmPath

# 强制关机
& $vmrun -T ws stop $vmPath hard

# 暂停
& $vmrun -T ws suspend $vmPath

# 恢复
& $vmrun -T ws start $vmPath

# 列出运行中的VM
& $vmrun -T ws list
```

#### 11.5.2 删除虚拟机

```powershell
# 方式1: 使用Terraform（推荐，清理所有资源）
terraform destroy -var="vmware_password=你的密码" -auto-approve

# 方式2: 删除单个节点
terraform destroy -target=vmware-workstation_vm.k8s_nodes[\"w2\"] -auto-approve

# 方式3: 手动删除（vmrun + 删除文件）
& $vmrun -T ws stop "C:\VMs\K8s-Cluster\k8s-worker-2\k8s-worker-2.vmx" hard
Remove-Item -Recurse -Force "C:\VMs\K8s-Cluster\k8s-worker-2"
```

#### 11.5.3 修改虚拟机配置

```hcl
# 修改variables.tf中的配置
variable "k8s_nodes" {
  default = {
    w1 = {
      memory = 16384  # 从8G改为16G
      # ...其他配置
    }
  }
}

# 应用变更（需要重建VM）
terraform apply
```

#### 11.5.4 创建快照

```powershell
# 创建快照（重要操作前）
& $vmrun -T ws snapshot "C:\VMs\K8s-Cluster\k8s-master-1\k8s-master-1.vmx" "before-upgrade"

# 列出快照
& $vmrun -T ws listSnapshots "C:\VMs\K8s-Cluster\k8s-master-1\k8s-master-1.vmx"

# 恢复快照
& $vmrun -T ws revertToSnapshot "C:\VMs\K8s-Cluster\k8s-master-1\k8s-master-1.vmx" "before-upgrade"

# 删除快照
& $vmrun -T ws deleteSnapshot "C:\VMs\K8s-Cluster\k8s-master-1\k8s-master-1.vmx" "before-upgrade"
```

---

### 11.6 快速复刻指南

#### 11.6.1 新电脑环境准备

```powershell
# 步骤1: 安装VMware Workstation Pro 16.5
# 下载并安装，输入许可证密钥

# 步骤2: 复制模板虚拟机
# 从旧电脑复制: C:\VMs\Ubuntu-22.04-Template-Base
# 放到新电脑相同位置

# 步骤3: 启用REST API（见11.2节）

# 步骤4: 安装Terraform
# 下载: https://www.terraform.io/downloads
# 解压到C:\terraform，添加到PATH

# 步骤5: 复制Terraform项目
# 复制terraform-vmware文件夹

# 步骤6: 修改terraform.tfvars
# 更新vmware_password和ssh_public_key
```

#### 11.6.2 一键创建环境

```powershell
# 执行脚本 create-env.ps1
$script = @'
# 启用REST API
$vmrest = "C:\Program Files (x86)\VMware\VMware Workstation\vmrest.exe"
Start-Process -FilePath $vmrest -ArgumentList "-d" -WindowStyle Hidden
Start-Sleep -Seconds 5

# 进入Terraform目录
cd C:\terraform-vmware

# 创建环境
terraform init
terraform apply -auto-approve

# 输出连接信息
terraform output ssh_commands
'@

$script | Out-File -FilePath "create-env.ps1" -Encoding UTF8

# 运行
.\create-env.ps1
```

#### 11.6.3 一键销毁环境

```powershell
# 执行脚本 destroy-env.ps1
$script = @'
cd C:\terraform-vmware
terraform destroy -auto-approve

# 清理残留ISO文件
Remove-Item -Force C:\VMs\cloud-init-*.iso -ErrorAction SilentlyContinue

Write-Host "Environment destroyed successfully"
'@

$script | Out-File -FilePath "destroy-env.ps1" -Encoding UTF8

# 运行
.\destroy-env.ps1
```

---

### 11.7 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| REST API连接失败 | 服务未启动 | `vmrest.exe -d` |
| 认证失败 | 密码错误 | 重新生成证书 `vmrest.exe -c` |
| 模板找不到 | 路径错误 | 检查`template_path`变量 |
| cloud-init不生效 | ISO未挂载 | 检查虚拟机CD-ROM设置 |
| IP配置失败 | 网络不匹配 | 确认VMnet8子网是192.168.1.0/24 |
| SSH连不上 | 防火墙/密钥 | 检查Windows防火墙和SSH密钥 |

---

### 11.8 Terraform安装指南

#### 11.8.1 Windows安装

```powershell
# 方法1: 使用Chocolatey（推荐）
# 安装Chocolatey（如果未安装）
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 安装Terraform
choco install terraform -y

# 验证安装
terraform version
# 输出: Terraform v1.6.x
```

```powershell
# 方法2: 手动下载安装
# 1. 下载Terraform
# 访问: https://developer.hashicorp.com/terraform/downloads
# 下载Windows amd64版本: terraform_1.6.x_windows_amd64.zip

# 2. 解压到C:\terraform
Expand-Archive -Path terraform_1.6.x_windows_amd64.zip -DestinationPath C:\terraform

# 3. 添加到PATH环境变量
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\terraform", "User")

# 4. 重启PowerShell，验证
c:\terraform\terraform version
```

#### 11.8.2 配置Terraform（可选）

```powershell
# 启用自动补全（PowerShell）
terraform -install-autocomplete

# 配置插件缓存目录（避免重复下载）
[Environment]::SetEnvironmentVariable("TF_PLUGIN_CACHE_DIR", "C:\terraform\plugin-cache", "User")
New-Item -ItemType Directory -Path "C:\terraform\plugin-cache" -Force
```

#### 11.8.3 升级Terraform

```powershell
# 使用Chocolatey升级
choco upgrade terraform -y

# 或手动升级：下载新版本，替换C:\terraform目录下的文件
```

#### 11.8.4 离线安装Terraform

```powershell
# 场景：无法访问互联网，需要离线安装

# 步骤1: 在有网络的电脑下载
# 访问: https://developer.hashicorp.com/terraform/downloads
# 下载: terraform_1.6.x_windows_amd64.zip

# 步骤2: 复制到离线电脑
# 将zip文件复制到离线电脑的 C:\Downloads\

# 步骤3: 解压安装
Expand-Archive -Path "C:\Downloads\terraform_1.6.x_windows_amd64.zip" -DestinationPath "C:\terraform"

# 步骤4: 添加到PATH（当前会话）
$env:Path += ";C:\terraform"

# 步骤5: 永久添加到PATH（用户级别）
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\terraform", "User")

# 步骤6: 验证
C:\terraform\terraform version
```

---

### 11.9 完整软件安装清单（在线+离线）

#### 11.9.1 VMware Workstation Pro 16.5

| 安装方式 | 步骤 |
|----------|------|
| **在线安装** | 1. 访问 https://support.broadcom.com/security-advisory<br>2. 登录Broadcom账号<br>3. 下载VMware Workstation Pro 16.5<br>4. 运行安装程序 |
| **离线安装** | 1. 在线环境下载 `VMware-workstation-full-16.5.x-xxxxxxx.exe`<br>2. 复制到离线电脑<br>3. 运行安装程序，输入许可证密钥 |

#### 11.9.2 Terraform

| 安装方式 | 步骤 |
|----------|------|
| **在线安装** | `choco install terraform -y` 或官网下载 |
| **离线安装** | 见11.8.4节，下载zip解压即可 |

#### 11.9.3 Chocolatey（Windows包管理器）

| 安装方式 | 步骤 |
|----------|------|
| **在线安装** | 见11.8.1节，PowerShell执行安装脚本 |
| **离线安装** | 1. 在线环境下载Chocolatey安装包<br>2. 离线执行本地安装脚本 |

```powershell
# Chocolatey离线安装
# 1. 在线电脑下载安装包
# 访问: https://chocolatey.org/install#individual
# 下载: chocolatey.1.x.x.nupkg

# 2. 离线安装
choco install chocolatey -y --source C:\Downloads\chocolatey.1.x.x.nupkg
```

#### 11.9.4 OpenSSH Client（Windows）

| 安装方式 | 步骤 |
|----------|------|
| **在线安装** | `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` |
| **离线安装** | 1. 下载OpenSSH离线包<br>2. `Add-WindowsCapability -Path C:\OpenSSH -Name OpenSSH.Client~~~~0.0.1.0` |

#### 11.9.5 Git（可选，用于下载Terraform模块）

| 安装方式 | 步骤 |
|----------|------|
| **在线安装** | `choco install git -y` |
| **离线安装** | 1. 下载 `Git-2.x.x-64-bit.exe`<br>2. 离线运行安装程序 |

---

## 12. 生产环境建议

### 12.1 架构设计建议

```
生产环境推荐架构:

+================================================================================+
|                              生产环境架构                                       |
+================================================================================+
|                                                                                |
|  负载均衡层                                                                      |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |   HAProxy/NGINX   |  |   HAProxy/NGINX   |  |   VIP (Keepalived)|          |
|  |   (Active)        |  |   (Standby)       |  |   192.168.1.50    |          |
|  +---------+---------+  +---------+---------+  +-------------------+          |
|            |                      |                                            |
|            +----------+-----------+                                            |
|                       |                                                        |
|  控制面(3节点)                                                                  |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |   Master-1        |  |   Master-2        |  |   Master-3        |          |
|  |   etcd            |  |   etcd            |  |   etcd            |          |
|  |   api-server      |  |   api-server      |  |   api-server      |          |
|  |   4C/8G           |  |   4C/8G           |  |   4C/8G           |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
|  数据面(3-5节点)                                                                |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |   Worker-1        |  |   Worker-2        |  |   Worker-3        |          |
|  |   8C/16G          |  |   8C/16G          |  |   8C/16G          |          |
|  |   200GB SSD       |  |   200GB SSD       |  |   200GB SSD       |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
|  存储层                                                                         |
|  +-------------------+  +-------------------+  +-------------------+          |
|  |   vSAN/VMFS       |  |   NFS/iSCSI       |  |   备份存储         |          |
|  +-------------------+  +-------------------+  +-------------------+          |
|                                                                                |
+================================================================================+
```

### 11.2 配置建议

| 配置项 | 开发环境 | 测试环境 | 生产环境 |
|--------|----------|----------|----------|
| **Master节点** | 1 | 3 | 3-5 |
| **Worker节点** | 1-2 | 2-3 | 3-10+ |
| **Master配置** | 2C/4G | 2C/4G | 4C/8G+ |
| **Worker配置** | 2C/4G | 4C/8G | 8C/16G+ |
| **磁盘类型** | Thin | Thin | Thick Eager |
| **网络** | 单网卡 | 单网卡 | 多网卡绑定 |
| **存储** | 本地存储 | 共享存储 | vSAN/FC |
| **备份** | 无 | 每周 | 每日+异地 |

### 11.3 运维建议

**日常运维:**
```bash
# 1. 监控检查
kubectl top nodes
kubectl top pods --all-namespaces

# 2. 日志检查
kubectl logs -n kube-system -l component=kube-apiserver --tail=100

# 3. 证书检查
kubeadm certs check-expiration

# 4. etcd健康检查
ETCDCTL_API=3 etcdctl endpoint health

# 5. 节点状态
kubectl get nodes -o wide
kubectl get pods --all-namespaces -o wide
```

**备份策略:**
```bash
# 1. etcd定期备份
0 2 * * * /usr/local/bin/etcd-backup.sh

# 2. Terraform State备份
# 使用S3版本控制或定期导出

# 3. Ansible Playbook版本控制
# 使用Git管理，定期备份仓库
```

**安全建议:**
1. 使用专用Service Account运行Terraform
2. 启用vSphere角色权限分离
3. 定期轮换SSH密钥和API凭证
4. 启用审计日志记录所有操作
5. 使用网络隔离(管理网、业务网、存储网)

---

## 附录

### A. 参考文档

- [Terraform官方文档](https://www.terraform.io/docs)
- [vSphere Provider文档](https://registry.terraform.io/providers/hashicorp/vsphere/latest/docs)
- [Ansible官方文档](https://docs.ansible.com/)
- [K8s kubeadm文档](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)

### B. 常用命令速查

```bash
# Terraform
terraform init                    # 初始化
terraform plan                    # 预览变更
terraform apply                   # 执行变更
terraform destroy                 # 销毁资源
terraform show                    # 显示状态
terraform state list              # 列出资源
terraform state rm <resource>     # 删除状态
terraform import <resource> <id>  # 导入资源

# Ansible
ansible all -m ping               # 测试连通性
ansible-playbook site.yml         # 执行Playbook
ansible-playbook --check site.yml # 干运行
ansible-playbook --tags k8s site.yml  # 按标签执行
ansible-playbook --limit master site.yml  # 限定主机
```

### C. 离线资源清单模板

```yaml
# offline-resources.yaml
terraform:
  version: "1.6.6"
  download_url: "https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip"

providers:
  - name: vsphere
    version: "2.5.1"
    source: "hashicorp/vsphere"
  - name: local
    version: "2.4.1"
    source: "hashicorp/local"
  - name: null
    version: "3.2.2"
    source: "hashicorp/null"

ansible:
  version: "2.15.0"
  python_packages:
    - ansible-core==2.15.0
    - jinja2==3.1.2
    - pyyaml==6.0.1
    - cryptography==41.0.0
    - paramiko==3.3.1

k8s_binaries:
  version: "1.28.0"
  components:
    - kubeadm
    - kubelet
    - kubectl
    - containerd
    - runc
    - crictl
    - etcdctl

k8s_images:
  - registry.k8s.io/kube-apiserver:v1.28.0
  - registry.k8s.io/kube-controller-manager:v1.28.0
  - registry.k8s.io/kube-scheduler:v1.28.0
  - registry.k8s.io/kube-proxy:v1.28.0
  - registry.k8s.io/pause:3.9
  - registry.k8s.io/etcd:3.5.9-0
  - registry.k8s.io/coredns/coredns:v1.10.1
```

---

*文档版本: 1.0*
*最后更新: 2026-05-24*
*适用环境: VMware vSphere + Ubuntu 22.04 LTS + Kubernetes 1.28*
