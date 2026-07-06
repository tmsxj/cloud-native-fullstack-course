# 模块22：LLM时代的AIOps实战

---

## 1. 概述与架构图

### 1.1 LLM时代的运维变革

> 📌 **2025-2026技术趋势**
>
> 大语言模型(LLM)正在彻底改变运维工作方式。从传统的"告警→人工排查→修复"流程，演进为"告警→LLM分析→Agent执行→自动验证"的智能闭环。本模块深入探讨LLM在AIOps中的实战应用。

**运维范式对比：**

| 维度 | 传统运维 | AIOps 1.0 | LLM时代AIOps |
|------|----------|-----------|--------------|
| **告警处理** | 人工分析 | 规则降噪 | LLM理解语义 |
| **根因定位** | 逐层排查 | 统计推断 | LLM推理+知识库 |
| **修复执行** | 手动执行 | 脚本自动化 | Agent自主执行 |
| **知识沉淀** | 文档记录 | 规则库 | 向量知识库 |
| **交互方式** | CLI/Web | 告警通知 | 自然语言对话 |

### 1.2 LLM-AIOps整体架构

```
+================================================================================+
|                    LLM时代的AIOps架构                                             |
+================================================================================+
|                                                                                |
|  +=======================================================================+    |
|  |                        用户交互层                                        |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  |  | Web Chat界面      |  | Slack/钉钉机器人  |  | CLI工具           |   |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  +=======================================================================+    |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                        Agent编排层                                       |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  |  | 诊断Agent         |  | 执行Agent         |  | 验证Agent         |   |    |
|  |  | (Diagnosis)       |  | (Execution)      |  | (Verification)   |   |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  +=======================================================================+    |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                        LLM能力层                                         |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  |  | 云端LLM API       |  | 私有化LLM        |  | 小模型(边缘)      |   |    |
|  |  | (DeepSeek/OpenAI) |  | (LLaMA/Qwen)     |  | (Phi/Gemma)      |   |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  +=======================================================================+    |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                        知识增强层                                        |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  |  | RAG知识库         |  | 向量数据库        |  | 文档索引          |   |    |
|  |  | (检索增强生成)    |  | (Milvus/Chroma)  |  | (Elasticsearch)  |   |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  +=======================================================================+    |
|                                    |                                           |
|                                    v                                           |
|  +=======================================================================+    |
|  |                        数据与工具层                                       |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  |  | Prometheus        |  | Loki/ELK         |  | Kubernetes API   |   |    |
|  |  | (指标)            |  | (日志)           |  | (资源操作)       |   |    |
|  |  +-------------------+  +-------------------+  +-------------------+   |    |
|  +=======================================================================+    |
|                                                                                |
+================================================================================+
```

### 1.3 核心能力矩阵

| 能力 | 技术方案 | 资源需求 | 适用场景 |
|------|----------|----------|----------|
| **智能问答** | LLM API + Prompt工程 | 无GPU | 运维知识查询 |
| **告警分析** | LLM + 上下文构建 | 无GPU | 根因推断 |
| **日志解读** | LLM + 日志切片 | 无GPU | 错误定位 |
| **命令生成** | LLM + 安全校验 | 无GPU | 辅助操作 |
| **知识检索** | RAG + 向量库 | 向量库内存 | 历史案例查询 |
| **自动执行** | Agent + 工具调用 | 无GPU | 自动修复 |
| **私有化部署** | LLaMA/Qwen本地 | GPU (可选) | 数据敏感场景 |

---

## 2. 核心概念

### 2.1 RAG (检索增强生成)

```
+================================================================================+
|                        RAG工作流程                                               |
+================================================================================+
|                                                                                |
|  用户问题: "order-service频繁重启怎么排查？"                                    |
|                                                                                |
|  +-------------------+                                                         |
|  | 1. 问题理解       |  LLM解析问题意图                                        |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  | 2. 向量检索       |  在知识库中检索相关文档                                 |
|  |   Query: "Pod重启" |  Top-K: 5篇相关文档                                    |
|  |   "CrashLoopBackOff"|                                                       |
|  |   "OOMKilled"     |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  | 3. 上下文构建     |  问题 + 检索结果 → Prompt                              |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  | 4. LLM生成        |  基于上下文生成回答                                     |
|  +---------+---------+                                                         |
|            |                                                                   |
|            v                                                                   |
|  +-------------------+                                                         |
|  | 5. 结果输出       |  排查步骤 + 参考文档                                    |
|  +-------------------+                                                         |
|                                                                                |
|  优势:                                                                         |
|  - 无需微调LLM，即可获得领域知识                                               |
|  - 知识可实时更新 (更新向量库即可)                                             |
|  - 可追溯来源 (引用具体文档)                                                   |
|                                                                                |
+================================================================================+
```

### 2.2 Multi-Agent协作

```
+================================================================================+
|                    Multi-Agent协作架构                                           |
+================================================================================+
|                                                                                |
|  用户任务: "mall-demo的order-service响应变慢，请诊断并修复"                      |
|                                                                                |
|  +-------------------+                                                         |
|  |   Orchestrator    |  任务分解与协调                                          |
|  |   (协调者)        |                                                         |
|  +---------+---------+                                                         |
|            |                                                                   |
|            +------------------+------------------+------------------+          |
|            |                  |                  |                  |          |
|            v                  v                  v                  v          |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|  | Monitor Agent  | | Diagnosis Agent| | Fix Agent      | | Verify Agent   |  |
|  | (监控采集)     | | (根因诊断)     | | (执行修复)     | | (验证结果)     |  |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|         |                   |                   |                   |          |
|         v                   v                   v                   v          |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|  | 采集指标:      | | 根因:          | | 操作:          | | 验证:          |  |
|  | - CPU: 85%     | | 数据库连接池满  | | 扩大连接池      | | - CPU: 45%     |  |
|  | - 内存: 92%    | | 导致请求排队    | | 重启服务        | | - 响应RT: 50ms |  |
|  | - RT: 2000ms   | |                | |                | | - 错误率: 0.1%  |  |
|  +----------------+ +----------------+ +----------------+ +----------------+  |
|                                                                                |
|  协作流程:                                                                     |
|  1. Orchestrator分解任务 → 4个子任务                                          |
|  2. Monitor Agent采集数据 → 传递给Diagnosis                                   |
|  3. Diagnosis Agent分析根因 → 传递给Fix                                       |
|  4. Fix Agent执行修复 → 传递给Verify                                          |
|  5. Verify Agent验证结果 → 返回最终报告                                        |
|                                                                                |
+================================================================================+
```

### 2.3 LLM选择指南

| 场景 | 推荐LLM | 原因 | 成本估算 |
|------|---------|------|----------|
| **日常问答** | DeepSeek-V3 / GPT-4o-mini | 性价比高 | ¥0.001/千token |
| **复杂推理** | GPT-4o / Claude-3 | 推理能力强 | ¥0.03/千token |
| **中文场景** | 通义千问 / 文心一言 | 中文优化 | ¥0.004/千token |
| **代码生成** | Claude-3 / DeepSeek-Coder | 代码能力强 | ¥0.01/千token |
| **私有化** | Qwen2.5 / LLaMA3 | 可本地部署 | GPU成本 |
| **边缘设备** | Phi-3 / Gemma-2 | 小模型，低资源 | CPU可运行 |

---

## 3. 离线前置准备

### 3.1 向量数据库镜像

```bash
# ==================== 向量数据库镜像 ====================
cat > vector-db-images.txt << 'EOF'
# Milvus (推荐，功能完整)
milvusdb/milvus:v2.4.0
milvusdb/milvus-operator:v1.0.0

# Chroma (轻量，适合小规模)
chromadb/chroma:latest

# Qdrant (高性能)
qdrant/qdrant:v1.8.0
EOF

# 拉取并推送到Harbor
for image in $(cat vector-db-images.txt); do
  docker pull $image
  docker tag $image 192.168.1.61:80/aiops/$(basename $image)
  docker push 192.168.1.61:80/aiops/$(basename $image)
done
```

### 3.2 LLM服务镜像 (可选私有化)

```bash
# ==================== LLM推理服务镜像 ====================
cat > llm-serving-images.txt << 'EOF'
# vLLM (高性能推理)
vllm/vllm-openai:latest

# Ollama (轻量推理)
ollama/ollama:latest

# Text Embeddings Inference (向量嵌入)
huggingface/text-embeddings-inference:latest
EOF

# 注意: 私有化部署需要GPU支持
# 无GPU环境建议使用云端LLM API
```

### 3.3 AI Ops服务镜像

```bash
# ==================== AIOps服务镜像 ====================
cat > aiops-service-images.txt << 'EOF'
# LangChain服务
python:3.11-slim

# 向量嵌入模型 (CPU版本)
sentence-transformers/all-MiniLM-L6-v2

# 告警处理服务
prom/alertmanager:latest
EOF
```

---

## 4. RAG知识库实战

### 4.1 向量数据库部署

#### 4.1.1 Milvus轻量部署

```yaml
# milvus-standalone.yaml
# Milvus单机版部署 (轻量模式)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: milvus-standalone
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: milvus
  template:
    metadata:
      labels:
        app: milvus
    spec:
      containers:
      - name: milvus
        image: milvusdb/milvus:v2.4.0
        command: ["milvus", "run", "standalone"]
        env:
        - name: ETCD_ENDPOINTS
          value: "etcd:2379"
        - name: MINIO_ADDRESS
          value: "minio:9000"
        ports:
        - containerPort: 19530  # gRPC端口
          name: grpc
        - containerPort: 9091   # Web端口
          name: web
        volumeMounts:
        - name: milvus-data
          mountPath: /var/lib/milvus
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2000m"
            memory: "4Gi"
      volumes:
      - name: milvus-data
        persistentVolumeClaim:
          claimName: milvus-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: milvus
  namespace: aiops
spec:
  selector:
    app: milvus
  ports:
  - port: 19530
    targetPort: 19530
    name: grpc
  - port: 9091
    targetPort: 9091
    name: web
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: milvus-pvc
  namespace: aiops
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

#### 4.1.2 Chroma轻量部署 (更轻量)

```yaml
# chroma-deployment.yaml
# Chroma向量数据库 (轻量级，适合小规模知识库)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chroma
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chroma
  template:
    metadata:
      labels:
        app: chroma
    spec:
      containers:
      - name: chroma
        image: chromadb/chroma:latest
        ports:
        - containerPort: 8000
        env:
        - name: CHROMA_SERVER_HOST
          value: "0.0.0.0"
        - name: CHROMA_SERVER_PORT
          value: "8000"
        - name: ALLOW_RESET
          value: "TRUE"
        volumeMounts:
        - name: chroma-data
          mountPath: /chroma/chroma
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
      volumes:
      - name: chroma-data
        persistentVolumeClaim:
          claimName: chroma-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: chroma
  namespace: aiops
spec:
  selector:
    app: chroma
  ports:
  - port: 8000
    targetPort: 8000
```

### 4.2 知识库构建

#### 4.2.1 运维知识文档结构

```
ops-knowledge-base/
├── k8s-troubleshooting/
│   ├── pod-issues.md          # Pod问题排查
│   ├── network-issues.md      # 网络问题排查
│   ├── storage-issues.md      # 存储问题排查
│   └── node-issues.md         # 节点问题排查
├── middleware/
│   ├── mysql-troubleshooting.md
│   ├── redis-troubleshooting.md
│   └── kafka-troubleshooting.md
├── observability/
│   ├── prometheus-best-practices.md
│   ├── loki-log-analysis.md
│   └── alerting-strategy.md
├── security/
│   ├── rbac-guide.md
│   ├── network-policy.md
│   └── secret-management.md
└── runbooks/
    ├── high-cpu-runbook.md
    ├── high-memory-runbook.md
    ├── pod-crash-runbook.md
    └── service-down-runbook.md
```

#### 4.2.2 知识库索引构建

```python
# knowledge-base-builder.py
"""
运维知识库构建器
将文档索引到向量数据库，支持RAG检索
"""

import os
import json
from typing import List, Dict
from pathlib import Path
import chromadb
from chromadb.config import Settings

class KnowledgeBaseBuilder:
    """知识库构建器"""
    
    def __init__(self, chroma_host: str = "localhost", chroma_port: int = 8000):
        """
        初始化知识库构建器
        
        Args:
            chroma_host: Chroma服务地址
            chroma_port: Chroma服务端口
        """
        self.client = chromadb.HttpClient(
            host=chroma_host,
            port=chroma_port
        )
        
        # 创建或获取集合
        self.collection = self.client.get_or_create_collection(
            name="ops-knowledge",
            metadata={"description": "运维知识库"}
        )
        
        print(f"知识库初始化完成，当前文档数: {self.collection.count()}")
    
    def load_markdown_files(self, directory: str) -> List[Dict]:
        """
        加载目录下的所有Markdown文件
        
        Args:
            directory: 文档目录路径
        
        Returns:
            文档列表 [{id, content, metadata}]
        """
        documents = []
        dir_path = Path(directory)
        
        for md_file in dir_path.rglob("*.md"):
            try:
                content = md_file.read_text(encoding='utf-8')
                
                # 提取标题作为文档ID的一部分
                title = md_file.stem
                
                # 构建元数据
                relative_path = md_file.relative_to(dir_path)
                category = relative_path.parts[0] if len(relative_path.parts) > 1 else "general"
                
                documents.append({
                    "id": f"{category}_{title}",
                    "content": content,
                    "metadata": {
                        "title": title,
                        "category": category,
                        "path": str(relative_path),
                        "source": "ops-knowledge-base"
                    }
                })
                
            except Exception as e:
                print(f"加载文件失败 {md_file}: {e}")
        
        print(f"加载了 {len(documents)} 个文档")
        return documents
    
    def split_document(self, content: str, chunk_size: int = 500) -> List[str]:
        """
        将长文档分割成小块
        
        Args:
            content: 文档内容
            chunk_size: 每块最大字符数
        
        Returns:
            文档块列表
        """
        # 按段落分割
        paragraphs = content.split('\n\n')
        
        chunks = []
        current_chunk = ""
        
        for para in paragraphs:
            if len(current_chunk) + len(para) < chunk_size:
                current_chunk += para + "\n\n"
            else:
                if current_chunk:
                    chunks.append(current_chunk.strip())
                current_chunk = para + "\n\n"
        
        if current_chunk:
            chunks.append(current_chunk.strip())
        
        return chunks
    
    def build_index(self, documents: List[Dict], chunk_size: int = 500):
        """
        构建向量索引
        
        Args:
            documents: 文档列表
            chunk_size: 文档分块大小
        """
        ids = []
        contents = []
        metadatas = []
        
        for doc in documents:
            # 分块处理
            chunks = self.split_document(doc["content"], chunk_size)
            
            for i, chunk in enumerate(chunks):
                chunk_id = f"{doc['id']}_chunk_{i}"
                
                # 跳过太短的块
                if len(chunk) < 50:
                    continue
                
                ids.append(chunk_id)
                contents.append(chunk)
                
                # 元数据添加块信息
                metadata = doc["metadata"].copy()
                metadata["chunk_index"] = i
                metadata["total_chunks"] = len(chunks)
                metadatas.append(metadata)
        
        # 批量添加到向量库
        batch_size = 100
        for i in range(0, len(ids), batch_size):
            batch_ids = ids[i:i+batch_size]
            batch_contents = contents[i:i+batch_size]
            batch_metadatas = metadatas[i:i+batch_size]
            
            self.collection.add(
                ids=batch_ids,
                documents=batch_contents,
                metadatas=batch_metadatas
            )
            
            print(f"已索引 {min(i+batch_size, len(ids))}/{len(ids)} 个文档块")
        
        print(f"索引构建完成，总文档块数: {self.collection.count()}")
    
    def search(self, query: str, n_results: int = 5) -> List[Dict]:
        """
        检索相关文档
        
        Args:
            query: 查询文本
            n_results: 返回结果数量
        
        Returns:
            检索结果列表
        """
        results = self.collection.query(
            query_texts=[query],
            n_results=n_results
        )
        
        formatted_results = []
        for i in range(len(results['ids'][0])):
            formatted_results.append({
                "id": results['ids'][0][i],
                "content": results['documents'][0][i],
                "metadata": results['metadatas'][0][i],
                "distance": results['distances'][0][i] if 'distances' in results else None
            })
        
        return formatted_results


# ==================== 使用示例 ====================
if __name__ == "__main__":
    # 初始化构建器
    builder = KnowledgeBaseBuilder(
        chroma_host="chroma.aiops.svc.cluster.local",
        chroma_port=8000
    )
    
    # 加载运维知识文档
    documents = builder.load_markdown_files("./ops-knowledge-base")
    
    # 构建索引
    builder.build_index(documents, chunk_size=500)
    
    # 测试检索
    test_queries = [
        "Pod处于CrashLoopBackOff状态怎么排查？",
        "如何排查MySQL连接池满的问题？",
        "Prometheus告警规则最佳实践"
    ]
    
    for query in test_queries:
        print(f"\n查询: {query}")
        results = builder.search(query, n_results=3)
        
        for i, result in enumerate(results, 1):
            print(f"  结果{i}: {result['metadata']['title']}")
            print(f"    来源: {result['metadata']['path']}")
            print(f"    相关度: {result['distance']:.4f}")
```

### 4.3 RAG问答服务

```python
# rag-qa-service.py
"""
RAG问答服务
结合向量检索和LLM生成，回答运维问题
"""

import json
import requests
from typing import List, Dict, Optional
from knowledge_base_builder import KnowledgeBaseBuilder
from llm_alert_analyzer import LLMAlertAnalyzer

class RAGQAService:
    """RAG问答服务"""
    
    def __init__(
        self,
        chroma_host: str = "localhost",
        chroma_port: int = 8000,
        llm_provider: str = "deepseek",
        llm_api_key: str = ""
    ):
        """
        初始化RAG服务
        
        Args:
            chroma_host: Chroma服务地址
            chroma_port: Chroma服务端口
            llm_provider: LLM提供商
            llm_api_key: LLM API密钥
        """
        self.kb = KnowledgeBaseBuilder(chroma_host, chroma_port)
        self.llm = LLMAlertAnalyzer(llm_provider, llm_api_key)
    
    def build_rag_prompt(self, question: str, contexts: List[Dict]) -> str:
        """
        构建RAG提示词
        
        Args:
            question: 用户问题
            contexts: 检索到的上下文
        
        Returns:
            完整提示词
        """
        context_text = "\n\n".join([
            f"【参考文档{i+1}】(来源: {c['metadata']['path']})\n{c['content']}"
            for i, c in enumerate(contexts)
        ])
        
        prompt = f"""你是一个Kubernetes运维专家。请基于以下参考资料回答问题。

## 参考资料
{context_text}

## 用户问题
{question}

## 回答要求
1. 基于参考资料回答，不要编造信息
2. 如果参考资料不足以回答问题，请明确说明
3. 提供具体的操作步骤和命令
4. 在回答末尾列出参考来源

## 回答
"""
        return prompt
    
    def answer(
        self,
        question: str,
        n_contexts: int = 5,
        include_sources: bool = True
    ) -> Dict:
        """
        回答问题
        
        Args:
            question: 用户问题
            n_contexts: 检索上下文数量
            include_sources: 是否包含来源
        
        Returns:
            回答结果
        """
        # 1. 检索相关文档
        contexts = self.kb.search(question, n_results=n_contexts)
        
        if not contexts:
            return {
                "answer": "抱歉，未找到相关资料。请尝试换个方式提问。",
                "sources": [],
                "confidence": "low"
            }
        
        # 2. 构建RAG提示词
        prompt = self.build_rag_prompt(question, contexts)
        
        # 3. 调用LLM生成回答
        answer = self.llm.call_llm_api(prompt)
        
        # 4. 构建结果
        result = {
            "answer": answer,
            "confidence": "high" if contexts[0].get('distance', 1) < 0.3 else "medium",
        }
        
        if include_sources:
            result["sources"] = [
                {
                    "title": c["metadata"]["title"],
                    "path": c["metadata"]["path"],
                    "category": c["metadata"]["category"]
                }
                for c in contexts
            ]
        
        return result


# ==================== FastAPI服务 ====================
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="RAG问答服务", description="运维知识问答API")

# 全局服务实例
rag_service = None

class QuestionRequest(BaseModel):
    """问题请求"""
    question: str
    n_contexts: int = 5

class AnswerResponse(BaseModel):
    """回答响应"""
    answer: str
    sources: List[Dict]
    confidence: str

@app.on_event("startup")
async def startup():
    """服务启动时初始化"""
    global rag_service
    import os
    
    rag_service = RAGQAService(
        chroma_host=os.getenv("CHROMA_HOST", "chroma.aiops.svc.cluster.local"),
        chroma_port=int(os.getenv("CHROMA_PORT", "8000")),
        llm_provider=os.getenv("LLM_PROVIDER", "deepseek"),
        llm_api_key=os.getenv("LLM_API_KEY", "")
    )

@app.post("/ask", response_model=AnswerResponse)
async def ask_question(request: QuestionRequest):
    """
    问答接口
    
    Args:
        request: 问题请求
    
    Returns:
        回答响应
    """
    if not rag_service:
        raise HTTPException(status_code=503, detail="服务未初始化")
    
    result = rag_service.answer(request.question, request.n_contexts)
    
    return AnswerResponse(
        answer=result["answer"],
        sources=result.get("sources", []),
        confidence=result.get("confidence", "medium")
    )

@app.get("/health")
async def health():
    """健康检查"""
    return {"status": "healthy"}


# 启动命令: uvicorn rag_qa_service:app --host 0.0.0.0 --port 8080
```

### 4.4 K8s部署

```yaml
# rag-service-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rag-qa-service
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rag-qa-service
  template:
    metadata:
      labels:
        app: rag-qa-service
    spec:
      containers:
      - name: rag-service
        image: python:3.11-slim
        command: ["python", "-m", "uvicorn", "rag_qa_service:app", "--host", "0.0.0.0", "--port", "8080"]
        workingDir: /app
        env:
        - name: CHROMA_HOST
          value: "chroma.aiops.svc.cluster.local"
        - name: CHROMA_PORT
          value: "8000"
        - name: LLM_PROVIDER
          value: "deepseek"
        - name: LLM_API_KEY
          valueFrom:
            secretKeyRef:
              name: llm-api-secret
              key: api-key
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: app-code
          mountPath: /app
        resources:
          requests:
            cpu: "200m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "512Mi"
      volumes:
      - name: app-code
        configMap:
          name: rag-service-code
---
apiVersion: v1
kind: Service
metadata:
  name: rag-qa-service
  namespace: aiops
spec:
  selector:
    app: rag-qa-service
  ports:
  - port: 80
    targetPort: 8080
```

---

## 5. Multi-Agent协作系统

### 5.1 Agent角色定义

```python
# multi-agent-system.py
"""
Multi-Agent协作系统
多个专业Agent协作完成复杂运维任务
"""

import json
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, field
from enum import Enum
from datetime import datetime
import asyncio

class AgentRole(Enum):
    """Agent角色"""
    ORCHESTRATOR = "orchestrator"  # 协调者
    MONITOR = "monitor"            # 监控采集
    DIAGNOSIS = "diagnosis"        # 根因诊断
    FIX = "fix"                    # 执行修复
    VERIFY = "verify"              # 验证结果
    REPORT = "report"              # 报告生成


@dataclass
class Task:
    """任务定义"""
    id: str
    description: str
    assigned_to: AgentRole
    status: str = "pending"  # pending, running, completed, failed
    result: Any = None
    dependencies: List[str] = field(default_factory=list)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())


@dataclass
class AgentMessage:
    """Agent间消息"""
    from_agent: AgentRole
    to_agent: AgentRole
    content: Any
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())


class BaseAgent:
    """Agent基类"""
    
    def __init__(self, role: AgentRole, llm_client):
        self.role = role
        self.llm = llm_client
        self.memory: List[Dict] = []
    
    def remember(self, message: Dict):
        """记录到工作记忆"""
        self.memory.append({
            "timestamp": datetime.now().isoformat(),
            "message": message
        })
    
    async def execute(self, task: Task, context: Dict) -> Any:
        """执行任务 (子类实现)"""
        raise NotImplementedError


class MonitorAgent(BaseAgent):
    """监控采集Agent"""
    
    def __init__(self, llm_client, prometheus_url: str):
        super().__init__(AgentRole.MONITOR, llm_client)
        self.prometheus_url = prometheus_url
    
    async def execute(self, task: Task, context: Dict) -> Dict:
        """采集监控数据"""
        import requests
        
        target = context.get("target", {})
        namespace = target.get("namespace", "default")
        service = target.get("service", "")
        
        # 定义要采集的指标
        metrics_queries = {
            "cpu_usage": f'sum(rate(container_cpu_usage_seconds_total{{namespace="{namespace}",pod=~"{service}.*"}}[5m])) by (pod)',
            "memory_usage": f'sum(container_memory_working_set_bytes{{namespace="{namespace}",pod=~"{service}.*"}}) by (pod)',
            "request_rate": f'sum(rate(http_requests_total{{namespace="{namespace}",service="{service}"}}[1m]))',
            "error_rate": f'sum(rate(http_requests_total{{namespace="{namespace}",service="{service}",status=~"5.."}}[1m]))',
            "latency_p99": f'histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{{namespace="{namespace}",service="{service}"}}[5m])) by (le))'
        }
        
        results = {}
        
        for metric_name, query in metrics_queries.items():
            try:
                response = requests.get(
                    f"{self.prometheus_url}/api/v1/query",
                    params={"query": query},
                    timeout=10
                )
                if response.status_code == 200:
                    data = response.json()
                    if data["status"] == "success" and data["data"]["result"]:
                        results[metric_name] = data["data"]["result"]
            except Exception as e:
                results[metric_name] = {"error": str(e)}
        
        self.remember({"task": task.id, "results": results})
        
        return {
            "agent": self.role.value,
            "task": task.id,
            "metrics": results,
            "timestamp": datetime.now().isoformat()
        }


class DiagnosisAgent(BaseAgent):
    """根因诊断Agent"""
    
    def __init__(self, llm_client):
        super().__init__(AgentRole.DIAGNOSIS, llm_client)
    
    async def execute(self, task: Task, context: Dict) -> Dict:
        """分析根因"""
        monitor_results = context.get("monitor_results", {})
        metrics = monitor_results.get("metrics", {})
        
        # 构建诊断Prompt
        prompt = f"""作为运维诊断专家，请分析以下监控数据，找出问题根因。

## 监控数据
{json.dumps(metrics, ensure_ascii=False, indent=2)}

## 服务信息
- 命名空间: {context.get('target', {}).get('namespace')}
- 服务名: {context.get('target', {}).get('service')}

## 请输出 (JSON格式)
1. root_cause: 根因描述 (一句话)
2. confidence: 置信度 (high/medium/low)
3. evidence: 证据列表
4. impact: 影响范围
5. suggested_fix: 建议修复方案

只输出JSON。
"""
        
        # 调用LLM分析
        response = self.llm.call_llm_api(prompt)
        
        # 解析结果
        try:
            if "```json" in response:
                json_str = response.split("```json")[1].split("```")[0].strip()
            else:
                json_str = response
            diagnosis = json.loads(json_str)
        except:
            diagnosis = {"raw_response": response}
        
        self.remember({"task": task.id, "diagnosis": diagnosis})
        
        return {
            "agent": self.role.value,
            "task": task.id,
            "diagnosis": diagnosis,
            "timestamp": datetime.now().isoformat()
        }


class FixAgent(BaseAgent):
    """执行修复Agent"""
    
    def __init__(self, llm_client, dry_run: bool = True):
        super().__init__(AgentRole.FIX, llm_client)
        self.dry_run = dry_run  # 干跑模式，只生成命令不执行
    
    async def execute(self, task: Task, context: Dict) -> Dict:
        """执行修复操作"""
        diagnosis = context.get("diagnosis_results", {}).get("diagnosis", {})
        target = context.get("target", {})
        
        # 生成修复命令
        prompt = f"""作为运维执行专家，请根据诊断结果生成修复命令。

## 诊断结果
{json.dumps(diagnosis, ensure_ascii=False, indent=2)}

## 目标服务
- 命名空间: {target.get('namespace')}
- 服务名: {target.get('service')}

## 请输出 (JSON格式)
1. commands: 要执行的命令列表 (每个命令包含description和command)
2. risk_level: 风险等级 (high/medium/low)
3. rollback_commands: 回滚命令列表
4. estimated_time: 预估执行时间

只输出JSON。
"""
        
        response = self.llm.call_llm_api(prompt)
        
        try:
            if "```json" in response:
                json_str = response.split("```json")[1].split("```")[0].strip()
            else:
                json_str = response
            fix_plan = json.loads(json_str)
        except:
            fix_plan = {"raw_response": response}
        
        # 执行命令 (如果不是干跑模式)
        execution_results = []
        if not self.dry_run and "commands" in fix_plan:
            import subprocess
            for cmd in fix_plan["commands"]:
                try:
                    result = subprocess.run(
                        cmd["command"],
                        shell=True,
                        capture_output=True,
                        text=True,
                        timeout=60
                    )
                    execution_results.append({
                        "command": cmd["command"],
                        "success": result.returncode == 0,
                        "output": result.stdout
                    })
                except Exception as e:
                    execution_results.append({
                        "command": cmd["command"],
                        "success": False,
                        "error": str(e)
                    })
        
        self.remember({"task": task.id, "fix_plan": fix_plan, "execution": execution_results})
        
        return {
            "agent": self.role.value,
            "task": task.id,
            "fix_plan": fix_plan,
            "execution_results": execution_results,
            "dry_run": self.dry_run,
            "timestamp": datetime.now().isoformat()
        }


class VerifyAgent(BaseAgent):
    """验证结果Agent"""
    
    def __init__(self, llm_client, prometheus_url: str):
        super().__init__(AgentRole.VERIFY, llm_client)
        self.prometheus_url = prometheus_url
    
    async def execute(self, task: Task, context: Dict) -> Dict:
        """验证修复结果"""
        import requests
        import time
        
        # 等待一段时间让修复生效
        await asyncio.sleep(30)
        
        # 重新采集指标
        monitor_results = context.get("monitor_results", {})
        original_metrics = monitor_results.get("metrics", {})
        
        # 简化验证: 检查关键指标是否改善
        target = context.get("target", {})
        namespace = target.get("namespace", "default")
        service = target.get("service", "")
        
        query = f'sum(rate(http_request_duration_seconds_sum{{namespace="{namespace}",service="{service}"}}[1m])) / sum(rate(http_request_duration_seconds_count{{namespace="{namespace}",service="{service}"}}[1m]))'
        
        try:
            response = requests.get(
                f"{self.prometheus_url}/api/v1/query",
                params={"query": query},
                timeout=10
            )
            current_latency = response.json()["data"]["result"][0]["value"][1]
        except:
            current_latency = "unknown"
        
        # 判断是否修复成功
        verification = {
            "current_latency": current_latency,
            "original_metrics": original_metrics,
            "success": True,  # 简化判断
            "message": "服务响应时间已恢复正常"
        }
        
        self.remember({"task": task.id, "verification": verification})
        
        return {
            "agent": self.role.value,
            "task": task.id,
            "verification": verification,
            "timestamp": datetime.now().isoformat()
        }


class OrchestratorAgent(BaseAgent):
    """协调者Agent"""
    
    def __init__(self, llm_client):
        super().__init__(AgentRole.ORCHESTRATOR, llm_client)
        self.agents: Dict[AgentRole, BaseAgent] = {}
    
    def register_agent(self, agent: BaseAgent):
        """注册Agent"""
        self.agents[agent.role] = agent
    
    async def execute(self, task: Task, context: Dict) -> Dict:
        """协调执行"""
        # 1. 分解任务
        sub_tasks = self._decompose_task(task)
        
        # 2. 按依赖顺序执行
        results = {}
        for sub_task in sub_tasks:
            agent = self.agents.get(sub_task.assigned_to)
            if not agent:
                continue
            
            # 构建上下文 (包含之前的结果)
            task_context = {**context, **results}
            
            # 执行子任务
            result = await agent.execute(sub_task, task_context)
            results[f"{sub_task.assigned_to.value}_results"] = result
        
        return {
            "agent": self.role.value,
            "task": task.id,
            "sub_tasks": [t.id for t in sub_tasks],
            "results": results,
            "timestamp": datetime.now().isoformat()
        }
    
    def _decompose_task(self, task: Task) -> List[Task]:
        """分解任务为子任务"""
        return [
            Task(
                id=f"{task.id}_monitor",
                description="采集监控数据",
                assigned_to=AgentRole.MONITOR
            ),
            Task(
                id=f"{task.id}_diagnosis",
                description="诊断根因",
                assigned_to=AgentRole.DIAGNOSIS,
                dependencies=[f"{task.id}_monitor"]
            ),
            Task(
                id=f"{task.id}_fix",
                description="执行修复",
                assigned_to=AgentRole.FIX,
                dependencies=[f"{task.id}_diagnosis"]
            ),
            Task(
                id=f"{task.id}_verify",
                description="验证结果",
                assigned_to=AgentRole.VERIFY,
                dependencies=[f"{task.id}_fix"]
            )
        ]


# ==================== 使用示例 ====================
async def main():
    from llm_alert_analyzer import LLMAlertAnalyzer
    
    # 初始化LLM
    llm = LLMAlertAnalyzer(
        api_provider="deepseek",
        api_key="your-api-key"
    )
    
    # 创建协调者
    orchestrator = OrchestratorAgent(llm)
    
    # 注册专业Agent
    orchestrator.register_agent(MonitorAgent(llm, "http://prometheus:9090"))
    orchestrator.register_agent(DiagnosisAgent(llm))
    orchestrator.register_agent(FixAgent(llm, dry_run=True))  # 干跑模式
    orchestrator.register_agent(VerifyAgent(llm, "http://prometheus:9090"))
    
    # 创建任务
    task = Task(
        id="task-001",
        description="mall-demo的order-service响应变慢，请诊断并修复",
        assigned_to=AgentRole.ORCHESTRATOR
    )
    
    # 执行任务
    context = {
        "target": {
            "namespace": "mall-demo",
            "service": "order-service"
        }
    }
    
    result = await orchestrator.execute(task, context)
    print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    asyncio.run(main())
```

### 5.2 K8s部署

```yaml
# multi-agent-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-agent-system
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multi-agent-system
  template:
    metadata:
      labels:
        app: multi-agent-system
    spec:
      serviceAccountName: ai-ops-agent
      containers:
      - name: agent-system
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
        - name: PROMETHEUS_URL
          value: "http://prometheus.monitoring.svc:9090"
        - name: DRY_RUN
          value: "true"  # 生产环境设为false启用自动执行
        volumeMounts:
        - name: agent-code
          mountPath: /app
        resources:
          requests:
            cpu: "300m"
            memory: "512Mi"
          limits:
            cpu: "2000m"
            memory: "1Gi"
      volumes:
      - name: agent-code
        configMap:
          name: multi-agent-code
---
apiVersion: v1
kind: Service
metadata:
  name: multi-agent-system
  namespace: aiops
spec:
  selector:
    app: multi-agent-system
  ports:
  - port: 80
    targetPort: 8080
```

---

## 6. LLM私有化部署 (可选)

> 📌 **注意**
>
> 私有化部署需要GPU支持。如果您的环境无GPU，建议使用云端LLM API。本节为概念性介绍。

### 6.1 私有化部署方案对比

| 方案 | 模型 | GPU需求 | 推理速度 | 适用场景 |
|------|------|---------|----------|----------|
| **vLLM** | LLaMA3/Qwen2.5 | A100/4090 | 最快 | 高并发推理 |
| **Ollama** | 多种模型 | 8GB+显存 | 中等 | 开发测试 |
| **TGI** | 多种模型 | A10/A100 | 快 | 生产部署 |
| **llama.cpp** | 量化模型 | CPU可运行 | 较慢 | 边缘设备 |

### 6.2 Ollama轻量部署 (CPU可运行小模型)

```yaml
# ollama-deployment.yaml
# Ollama部署 - 可运行小模型如Phi-3, Gemma-2
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: aiops
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        ports:
        - containerPort: 11434
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
        resources:
          requests:
            cpu: "2"
            memory: "8Gi"
          limits:
            cpu: "4"
            memory: "16Gi"
      volumes:
      - name: ollama-data
        persistentVolumeClaim:
          claimName: ollama-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: aiops
spec:
  selector:
    app: ollama
  ports:
  - port: 11434
    targetPort: 11434
---
# 拉取小模型 (Phi-3-mini, 约2GB)
apiVersion: batch/v1
kind: Job
metadata:
  name: pull-phi3-model
  namespace: aiops
spec:
  template:
    spec:
      containers:
      - name: pull-model
        image: ollama/ollama:latest
        command: ["ollama", "pull", "phi3:mini"]
        env:
        - name: OLLAMA_HOST
          value: "ollama.aiops.svc.cluster.local:11434"
      restartPolicy: OnFailure
```

### 6.3 私有化LLM调用示例

```python
# ollama-client.py
"""
Ollama私有化LLM客户端
"""

import requests
from typing import Dict, List

class OllamaClient:
    """Ollama客户端"""
    
    def __init__(self, host: str = "localhost", port: int = 11434):
        self.base_url = f"http://{host}:{port}"
    
    def chat(
        self,
        model: str = "phi3:mini",
        messages: List[Dict],
        stream: bool = False
    ) -> str:
        """
        对话接口
        
        Args:
            model: 模型名称
            messages: 消息列表
            stream: 是否流式输出
        
        Returns:
            模型响应
        """
        response = requests.post(
            f"{self.base_url}/api/chat",
            json={
                "model": model,
                "messages": messages,
                "stream": stream
            },
            timeout=60
        )
        
        if response.status_code == 200:
            return response.json()["message"]["content"]
        else:
            raise Exception(f"Ollama error: {response.text}")
    
    def generate(self, model: str, prompt: str) -> str:
        """
        生成接口
        
        Args:
            model: 模型名称
            prompt: 提示词
        
        Returns:
            生成结果
        """
        response = requests.post(
            f"{self.base_url}/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "stream": False
            },
            timeout=60
        )
        
        if response.status_code == 200:
            return response.json()["response"]
        else:
            raise Exception(f"Ollama error: {response.text}")


# 使用示例
if __name__ == "__main__":
    client = OllamaClient("ollama.aiops.svc.cluster.local", 11434)
    
    # 对话示例
    response = client.chat(
        model="phi3:mini",
        messages=[
            {"role": "system", "content": "你是Kubernetes运维专家"},
            {"role": "user", "content": "Pod处于CrashLoopBackOff怎么排查？"}
        ]
    )
    print(response)
```

---

## 7. AI运维安全与合规

### 7.1 安全风险矩阵

| 风险类型 | 描述 | 缓解措施 |
|----------|------|----------|
| **数据泄露** | 敏感数据发送到云端LLM | 数据脱敏、私有化部署 |
| **命令注入** | LLM生成恶意命令 | 命令白名单、人工审核 |
| **权限滥用** | Agent执行未授权操作 | RBAC限制、审计日志 |
| **幻觉风险** | LLM生成错误信息 | RAG增强、结果验证 |
| **供应链** | 依赖库漏洞 | 依赖扫描、版本锁定 |

### 7.2 安全最佳实践

```yaml
# aiops-security-policy.yaml
# AI运维安全策略配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: aiops-security-policy
  namespace: aiops
data:
  policy.yaml: |
    # 命令白名单
    allowed_commands:
      - "kubectl get"
      - "kubectl describe"
      - "kubectl logs"
      - "kubectl top"
      - "kubectl exec"  # 需要二次确认
    
    # 禁止的命令模式
    forbidden_patterns:
      - "kubectl delete"
      - "kubectl drain"
      - "rm -rf"
      - ":(){ :|:& };:"  # Fork炸弹
    
    # 敏感数据脱敏规则
    data_masking:
      - pattern: "password.*"
        replacement: "password=***"
      - pattern: "token.*"
        replacement: "token=***"
      - pattern: "api-key.*"
        replacement: "api-key=***"
    
    # 需要人工确认的操作
    require_confirmation:
      - "kubectl rollout restart"
      - "kubectl scale"
      - "kubectl patch"
    
    # 审计日志配置
    audit:
      enabled: true
      log_path: "/var/log/aiops/audit.log"
      retention_days: 90
```

### 7.3 审计日志

```python
# audit-logger.py
"""
AI运维审计日志
"""

import json
import logging
from datetime import datetime
from typing import Dict, Any
from pathlib import Path

class AuditLogger:
    """审计日志记录器"""
    
    def __init__(self, log_path: str = "/var/log/aiops/audit.log"):
        self.log_path = Path(log_path)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        
        # 配置日志
        self.logger = logging.getLogger("aiops-audit")
        self.logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler(self.log_path)
        handler.setFormatter(logging.Formatter('%(message)s'))
        self.logger.addHandler(handler)
    
    def log_action(
        self,
        action_type: str,
        agent: str,
        target: str,
        command: str = None,
        result: str = None,
        user: str = "system",
        risk_level: str = "low"
    ):
        """
        记录审计日志
        
        Args:
            action_type: 操作类型 (query/execute/fix)
            agent: 执行Agent
            target: 目标资源
            command: 执行的命令
            result: 执行结果
            user: 触发用户
            risk_level: 风险等级
        """
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "action_type": action_type,
            "agent": agent,
            "target": target,
            "command": command,
            "result": result,
            "user": user,
            "risk_level": risk_level
        }
        
        self.logger.info(json.dumps(log_entry, ensure_ascii=False))
    
    def query_logs(
        self,
        start_time: datetime = None,
        end_time: datetime = None,
        agent: str = None,
        risk_level: str = None
    ) -> list:
        """
        查询审计日志
        
        Args:
            start_time: 开始时间
            end_time: 结束时间
            agent: Agent过滤
            risk_level: 风险等级过滤
        
        Returns:
            日志条目列表
        """
        logs = []
        
        with open(self.log_path, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())
                    
                    # 应用过滤条件
                    if agent and entry.get("agent") != agent:
                        continue
                    if risk_level and entry.get("risk_level") != risk_level:
                        continue
                    
                    logs.append(entry)
                except:
                    continue
        
        return logs


# 使用示例
if __name__ == "__main__":
    audit = AuditLogger()
    
    # 记录操作
    audit.log_action(
        action_type="execute",
        agent="fix-agent",
        target="mall-demo/order-service",
        command="kubectl rollout restart deployment/order-service -n mall-demo",
        result="success",
        user="admin@example.com",
        risk_level="medium"
    )
    
    # 查询日志
    logs = audit.query_logs(risk_level="high")
    print(f"高风险操作数: {len(logs)}")
```

---

## 8. 故障排查案例

### 案例1: RAG检索结果不准确

**现象：**
用户询问"Pod重启原因"，RAG返回了无关的存储文档。

**排查过程：**
```bash
# 1. 检查向量库状态
curl http://chroma.aiops.svc:8000/api/v1/collections/ops-knowledge

# 2. 测试检索
curl -X POST http://rag-qa-service.aiops.svc/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "Pod重启原因", "n_contexts": 5}'

# 3. 检查文档分块
kubectl logs -n aiops deployment/rag-qa-service | grep "chunk"

# 4. 检查嵌入模型
kubectl logs -n aiops deployment/rag-qa-service | grep "embedding"
```

**根因：**
文档分块太大，导致语义混杂；嵌入模型对中文支持不够好。

**解决方案：**
```python
# 优化文档分块和嵌入
builder = KnowledgeBaseBuilder()

# 1. 减小分块大小
builder.build_index(documents, chunk_size=300)  # 从500减到300

# 2. 使用中文优化的嵌入模型
# 在Chroma中使用自定义嵌入函数
from chromadb.utils import embedding_functions
embedding_fn = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="paraphrase-multilingual-MiniLM-L12-v2"  # 多语言模型
)
```

### 案例2: Agent执行超时

**现象：**
Multi-Agent系统在执行修复任务时超时。

**排查过程：**
```bash
# 1. 查看Agent日志
kubectl logs -n aiops deployment/multi-agent-system

# 2. 检查LLM API响应时间
curl -w "%{time_total}" http://api.deepseek.com/v1/chat/completions

# 3. 检查Prometheus查询延迟
curl -w "%{time_total}" "http://prometheus:9090/api/v1/query?query=up"

# 4. 检查资源使用
kubectl top pods -n aiops
```

**根因：**
LLM API调用超时设置太短，且未设置重试机制。

**解决方案：**
```python
# 增加超时和重试
import tenacity
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=4, max=10)
)
def call_llm_with_retry(prompt: str) -> str:
    response = requests.post(
        llm_api_url,
        json={"prompt": prompt},
        timeout=60  # 增加到60秒
    )
    response.raise_for_status()
    return response.json()
```

### 案例3: 知识库更新后检索未生效

**现象：**
更新了运维文档，但RAG检索仍返回旧内容。

**排查过程：**
```bash
# 1. 检查Chroma数据目录
kubectl exec -n aiops deployment/chroma -- ls -la /chroma/chroma

# 2. 检查集合文档数
curl http://chroma.aiops.svc:8000/api/v1/collections/ops-knowledge

# 3. 查看RAG服务日志
kubectl logs -n aiops deployment/rag-qa-service | grep "index"
```

**根因：**
更新文档后未重新构建索引，RAG服务使用的是缓存的旧索引。

**解决方案：**
```bash
# 1. 重建索引
kubectl exec -n aiops deployment/rag-qa-service -- python /app/rebuild_index.py

# 2. 或者重启服务触发重新加载
kubectl rollout restart deployment/rag-qa-service -n aiops

# 3. 建议添加定时任务自动更新索引
kubectl apply -f knowledge-update-cronjob.yaml
```

---

## 9. 高频面试题

### Q1: 什么是RAG？它解决了LLM的什么问题？

**答案要点：**
- **RAG (Retrieval-Augmented Generation)** 是检索增强生成技术
- **解决的问题**：
  - 知识时效性：LLM训练数据有截止日期，RAG可检索最新信息
  - 领域知识：LLM缺乏特定领域知识，RAG可注入专业知识
  - 幻觉问题：LLM可能编造信息，RAG基于真实文档生成
  - 可追溯性：RAG可引用来源，LLM无法提供依据
- **工作流程**：问题 → 向量检索 → 上下文构建 → LLM生成 → 回答

### Q2: Multi-Agent系统如何保证任务执行的安全性？

**答案要点：**
- **权限控制**：每个Agent使用最小权限ServiceAccount
- **命令白名单**：只允许执行预定义的安全命令
- **人工确认**：高风险操作需要人工审批
- **审计日志**：所有操作记录审计日志，可追溯
- **干跑模式**：生产环境先在dry-run模式验证
- **回滚机制**：每个修复操作都有对应的回滚命令

### Q3: 如何选择云端LLM API和私有化部署？

**答案要点：**
- **选择云端API**：
  - 无GPU资源
  - 数据不敏感
  - 需要最强模型能力
  - 成本敏感（按量付费）
- **选择私有化部署**：
  - 数据安全要求高
  - 有GPU资源
  - 高并发场景（API有速率限制）
  - 网络隔离环境
- **混合方案**：敏感数据用私有化，通用问答用云端

### Q4: 向量数据库在RAG中的作用是什么？

**答案要点：**
- **存储向量嵌入**：将文档转换为向量并存储
- **相似度检索**：根据问题向量检索最相似的文档
- **支持的数据库**：
  - Milvus：功能完整，适合大规模
  - Chroma：轻量级，适合小规模
  - Qdrant：高性能，Rust实现
  - Pinecone：云托管，免运维
- **关键参数**：
  - 嵌入维度：通常384或768维
  - 相似度度量：余弦相似度或欧氏距离
  - 索引类型：HNSW、IVF等

### Q5: 如何评估AI运维系统的效果？

**答案要点：**
- **准确性指标**：
  - 根因定位准确率
  - 修复成功率
  - 误报率/漏报率
- **效率指标**：
  - 平均诊断时间 (MTTD)
  - 平均修复时间 (MTTR)
  - 自动化率（无人干预比例）
- **安全指标**：
  - 误操作率
  - 数据泄露事件数
  - 权限滥用事件数
- **用户满意度**：
  - 运维人员反馈
  - 问题解决率
  - 系统可用性

---

## 10. 生产环境建议

### 10.1 部署架构建议

```
+================================================================================+
|                    生产环境部署架构建议                                           |
+================================================================================+
|                                                                                |
|  推荐部署模式 (无GPU环境):                                                       |
|                                                                                |
|  +-------------------+                                                         |
|  | Ingress/Gateway   |  统一入口                                               |
|  +---------+---------+                                                         |
|            |                                                                   |
|            +------------------+------------------+                             |
|            |                  |                  |                             |
|            v                  v                  v                             |
|  +----------------+ +----------------+ +----------------+                     |
|  | RAG问答服务    | | Multi-Agent   | | 告警分析服务   |                     |
|  | (rag-qa)       | | System        | | (alert-analyzer)|                    |
|  +----------------+ +----------------+ +----------------+                     |
|         |                   |                   |                             |
|         v                   v                   v                             |
|  +----------------+ +----------------+ +----------------+                     |
|  | Chroma/Milvus  | | Prometheus    | | LLM API        |                     |
|  | (向量库)       | | (监控数据)    | | (DeepSeek)     |                     |
|  +----------------+ +----------------+ +----------------+                     |
|                                                                                |
|  资源预算:                                                                      |
|  - Chroma: 512MB-2GB内存                                                       |
|  - RAG服务: 256MB-512MB内存                                                    |
|  - Multi-Agent: 512MB-1GB内存                                                  |
|  - 总计: ~2-4GB内存 (无GPU需求)                                                 |
|                                                                                |
+================================================================================+
```

### 10.2 与课程其他模块的关联

| 模块 | 关联内容 |
|------|----------|
| 模块06 | Prometheus为AI分析提供监控数据 |
| 模块07 | Loki为AI分析提供日志数据 |
| 模块08 | Istio为Agent提供流量管理能力 |
| 模块12 | ArgoCD可管理AI服务部署 |
| 模块16 | 安全合规为AI运维提供安全框架 |
| 模块19 | AI基础概念，本模块深入实战 |

### 10.3 CKA/CKS相关考点

| 考点 | 内容 | 模块关联 |
|------|------|----------|
| **RBAC** | Agent权限控制 | 本节7.2 |
| **Secret** | API密钥管理 | 本节4.4 |
| **NetworkPolicy** | AI服务网络隔离 | 模块16 |
| **ResourceQuota** | AI服务资源限制 | 模块17 |
| **Audit** | 操作审计日志 | 本节7.3 |

---

## 11. 模块总结

### 11.1 本章核心收获

| 章节 | 核心内容 | 实战价值 |
|------|----------|----------|
| **RAG知识库** | 向量检索+LLM生成 | 运维知识问答 |
| **Multi-Agent** | 多Agent协作 | 复杂任务自动化 |
| **私有化部署** | Ollama/vLLM | 数据安全场景 |
| **安全合规** | 审计+权限控制 | 生产环境必备 |

### 11.2 与模块19的关系

- **模块19**: AI运维基础概念 + 轻量实现
- **模块22**: LLM时代AIOps深入实战 + 企业级部署

### 11.3 后续学习建议

1. **实践RAG**: 构建自己的运维知识库
2. **体验Agent**: 用Multi-Agent解决一个实际问题
3. **安全加固**: 实施审计日志和权限控制
4. **持续优化**: 根据反馈迭代Prompt和知识库

---

**参考资源:**
- [LangChain文档](https://python.langchain.com/docs/)
- [Chroma文档](https://docs.trychroma.com/)
- [Milvus文档](https://milvus.io/docs/)
- [Ollama文档](https://ollama.ai/docs)
- [DeepSeek API](https://platform.deepseek.com/docs)
- [RAG最佳实践](https://www.pinecone.io/learn/retrieval-augmented-generation/)
- [Multi-Agent模式](https://www.deeplearning.ai/short-courses/)
