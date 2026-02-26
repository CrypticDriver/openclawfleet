# Architecture Design - OpenClawFleet

## 概览

本方案采用**分层架构**设计，将基础设施和应用实例分离，实现高可用、可扩展、成本优化的多实例部署。

## 架构分层

### Layer 1: 网络层（VPC Foundation）

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                     │
│                                                              │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ Public Subnet A      │  │ Public Subnet B      │        │
│  │ 10.0.1.0/24          │  │ 10.0.2.0/24          │        │
│  │ - ALB                │  │ - ALB                │        │
│  │ - NAT Gateway        │  │ - NAT Gateway (备用) │        │
│  └──────────────────────┘  └──────────────────────┘        │
│                                                              │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ Private Subnet A     │  │ Private Subnet B     │        │
│  │ 10.0.10.0/24         │  │ 10.0.11.0/24         │        │
│  │ - OpenClaw Instances │  │ - OpenClaw Instances │        │
│  │ - VPC Endpoints      │  │ - VPC Endpoints      │        │
│  └──────────────────────┘  └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

**设计原则：**
- 多 AZ 部署（us-west-2a, us-west-2b）
- 公私分离（Public 用于 ALB，Private 用于实例）
- CIDR 规划支持 256 个实例/子网

**成本：** $32.40/月（NAT Gateway）

### Layer 2: 共享资源层

#### 2.1 Application Load Balancer

```
Internet → ALB (Port 443)
            │
            ├─ /openclaw-1/* → Target Group 1
            ├─ /openclaw-2/* → Target Group 2
            ├─ /openclaw-N/* → Target Group N
            └─ /health       → Health Check
```

**功能：**
- SSL/TLS 终止（证书通过 ACM 管理）
- 路径路由（每实例独立路径）
- 健康检查（30 秒间隔）
- 访问日志（S3 存储）

**成本：** $16.20/月

#### 2.2 VPC Endpoints

```
OpenClaw Instances
        ↓
VPC Endpoint (PrivateLink)
        ↓
AWS Services (Bedrock/SSM/CloudWatch)
```

**Endpoints 列表：**
1. `com.amazonaws.region.bedrock-runtime` - Bedrock API
2. `com.amazonaws.region.ssm` - Systems Manager
3. `com.amazonaws.region.ssmmessages` - SSM Session Manager
4. `com.amazonaws.region.logs` - CloudWatch Logs

**优势：**
- 私有网络通信（不经过 Internet）
- 降低延迟（<5ms vs 50ms+）
- 提高安全性（无公网暴露）

**成本：** $21.60/月（$0.01/小时/endpoint × 3 × 720小时）

### Layer 3: 实例层（可水平扩展）

#### 3.1 Auto Scaling Group

```
                   ┌─────────────────┐
                   │ Launch Template │
                   │ - AMI           │
                   │ - Instance Type │
                   │ - User Data     │
                   └────────┬────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
    ┌────▼─────┐      ┌─────▼─────┐     ┌─────▼─────┐
    │Instance 1│      │Instance 2 │ ... │Instance N │
    │(AZ-a)    │      │(AZ-b)     │     │(AZ-a/b)   │
    └──────────┘      └───────────┘     └───────────┘
```

**扩缩容策略：**
- Min: 2（高可用）
- Desired: 5（正常负载）
- Max: 20（峰值负载）

**触发条件：**
- CPU > 70% → Scale Out
- CPU < 30% (5min) → Scale In
- Memory > 80% → Scale Out
- ALB Request Count > 1000/min → Scale Out

#### 3.2 实例配置

每个 OpenClaw 实例：

```yaml
Resources:
  - EC2 Instance (t4g.medium)
  - EBS Volume (30GB gp3)
  - IAM Instance Profile
  - Security Group (ALB only)
  - Elastic Network Interface

Configuration:
  - Bedrock Model: 可配置
  - Gateway Token: 自动生成
  - Channels: 可配置（WhatsApp/Telegram/Discord）
  - Memory: 可配置（MEMORY.md）
```

**启动流程（User Data）：**
```bash
#!/bin/bash
# 1. 安装依赖（Node.js, OpenClaw）
# 2. 从 SSM Parameter Store 读取配置
# 3. 启动 OpenClaw Gateway
# 4. 注册到 ALB Target Group
# 5. 报告健康状态到 CloudWatch
```

### Layer 4: 管理层

#### 4.1 集中式配置（SSM Parameter Store）

```
/openclaw/
  ├─ global/
  │   ├─ default-model           # 默认 Bedrock 模型
  │   ├─ instance-type           # 默认实例类型
  │   └─ vpc-endpoints-enabled   # VPC Endpoints 开关
  │
  ├─ instances/
  │   ├─ openclaw-1/
  │   │   ├─ model               # 实例专属模型
  │   │   ├─ token               # Gateway Token (SecureString)
  │   │   └─ channels            # 消息渠道配置
  │   │
  │   └─ openclaw-2/
  │       └─ ...
  │
  └─ shared/
      ├─ alb-url                 # ALB 地址
      ├─ vpc-id                  # VPC ID
      └─ bedrock-endpoint        # Bedrock Endpoint
```

**更新流程：**
1. 管理员通过 CLI/Console 更新参数
2. CloudWatch Event 触发 Lambda
3. Lambda 通知实例更新配置
4. 实例重启服务（零停机）

#### 4.2 监控和告警

**CloudWatch Dashboard：**
```
┌─────────────────────────────────────────────────┐
│ OpenClaw Multi-Instance Dashboard               │
├─────────────────────────────────────────────────┤
│                                                 │
│  Instance Count: 5  │  Healthy: 5  │  Degraded: 0 │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ CPU Utilization (by instance)             │ │
│  │ ▓▓▓▓░░░░ openclaw-1: 45%                 │ │
│  │ ▓▓▓░░░░░ openclaw-2: 38%                 │ │
│  │ ▓▓▓▓▓▓▓░ openclaw-3: 72%                 │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ Bedrock API Calls (last 1 hour)          │ │
│  │ Total: 1,234  │  Avg Latency: 180ms     │ │
│  │ Errors: 2 (0.16%)                        │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ Cost Estimate (MTD)                       │ │
│  │ Infrastructure: $70.20                    │ │
│  │ Instances: $155.00 (5 × $31)             │ │
│  │ Bedrock: $45.30                          │ │
│  │ Total: $270.50                           │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

**告警规则：**
- Instance CPU > 90% (5min) → SNS → Email/Slack
- Instance Memory > 95% → SNS + Auto Restart
- Bedrock API Error Rate > 5% → SNS + Lambda 调查
- ALB 5xx Error > 10/min → SNS + PagerDuty
- Instance Unhealthy → Auto Replace

## 数据流

### 用户请求流

```
1. User sends WhatsApp message
        ↓
2. WhatsApp → OpenClaw Gateway (via webhook)
        ↓
3. Gateway → ALB (HTTPS)
        ↓
4. ALB → Target Instance (path-based routing)
        ↓
5. Instance → Bedrock API (via VPC Endpoint)
        ↓
6. Bedrock → Response
        ↓
7. Instance → User (via WhatsApp webhook)
```

**延迟分析：**
- WhatsApp → Gateway: 100-300ms
- ALB → Instance: 5-10ms
- Instance → Bedrock: 50-200ms
- Bedrock 处理: 1000-3000ms
- Total: **1.2-3.5s**

### 配置更新流

```
1. Admin updates SSM Parameter
        ↓
2. CloudWatch Event Rule triggers
        ↓
3. Lambda fetches updated config
        ↓
4. Lambda → SNS Topic
        ↓
5. All instances subscribe to SNS
        ↓
6. Instances reload config
        ↓
7. CloudWatch Metric: Config Updated
```

**更新时间：** <30 秒

## 高可用设计

### 1. 多 AZ 部署

```
AZ-A (us-west-2a)         AZ-B (us-west-2b)
┌─────────────────┐      ┌─────────────────┐
│ ALB Node 1      │      │ ALB Node 2      │
│ Instance 1,3,5  │      │ Instance 2,4    │
│ NAT Gateway     │      │ NAT Gateway(备) │
└─────────────────┘      └─────────────────┘
```

**故障场景：**
- AZ-A 故障 → ALB 自动切换到 AZ-B
- Instance 故障 → Auto Scaling 自动替换
- NAT Gateway 故障 → 手动切换到备用

### 2. 健康检查

**ALB Health Check：**
```
Target: /health
Interval: 30s
Timeout: 5s
Healthy Threshold: 2
Unhealthy Threshold: 3
```

**Response 示例：**
```json
{
  "status": "healthy",
  "uptime": "3d 5h 23m",
  "memory": "45%",
  "bedrock": "reachable",
  "last_request": "2026-02-26T02:00:15Z"
}
```

### 3. 自动恢复

```
Instance Unhealthy
        ↓
ALB marks as unhealthy
        ↓
Auto Scaling detects
        ↓
Terminate old instance
        ↓
Launch new instance
        ↓
Register to Target Group
        ↓
Health Check passes
        ↓
Resume traffic
```

**恢复时间：** 3-5 分钟

## 安全架构

### 1. 网络安全

```
Security Group: ALB
- Inbound: 443 (0.0.0.0/0)
- Outbound: All

Security Group: OpenClaw Instances
- Inbound: 18789 (ALB SG only)
- Outbound: 443 (VPC Endpoints only)

Security Group: VPC Endpoints
- Inbound: 443 (Instance SG only)
```

### 2. IAM 权限

**实例 IAM Role：**
```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*:*:foundation-model/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/openclaw/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/openclaw/*"
    }
  ]
}
```

**最小权限原则：**
- 每实例只能访问自己的配置
- 不能访问其他实例的 Token
- 不能修改 VPC/ALB 配置

### 3. 数据加密

- **传输中：** TLS 1.2+ (ALB → Instance)
- **静态：** EBS KMS 加密
- **敏感数据：** SSM SecureString (KMS 加密)

## 成本优化策略

### 1. 实例层

**Spot Instances：**
- 用于非关键实例（开发/测试）
- 节省 70-90%
- 配合 Auto Scaling 混合使用

```yaml
MixedInstancesPolicy:
  OnDemand: 2           # 保证可用性
  Spot: 8               # 成本优化
  SpotAllocationStrategy: lowest-price
```

**Savings Plans：**
- 1 年承诺：节省 30%
- 3 年承诺：节省 50%

### 2. 存储层

**EBS 优化：**
- 使用 gp3（比 gp2 便宜 20%）
- 定期快照并删除旧快照
- 使用 S3 Lifecycle 归档日志

### 3. 网络层

**NAT Gateway 替代：**
- NAT Instance（t4g.micro）：$6/月（节省 $26）
- 风险：单点故障

**VPC Endpoints 优化：**
- 按需启用（开发环境可关闭）
- 节省 $22/月

### 4. Bedrock 优化

**模型选择：**
- 简单任务：Nova 2 Lite（$0.30/$2.50）
- 复杂任务：Claude Sonnet 4.5（$3/$15）
- 批量任务：异步处理降低成本

**Prompt 优化：**
- 减少不必要的 System Prompt
- 使用流式输出（降低延迟）
- 缓存常见响应

## 扩展性

### 当前容量

- **Max Instances:** 20（硬限制）
- **Max TPS:** ~200（每实例 10 TPS）
- **Max Users:** ~10,000（每实例 500 用户）

### 扩展路径

**100+ 实例：**
- 使用 NLB 替代 ALB（性能更好）
- 多 VPC 部署（每 VPC 50 实例）
- 中心化配置服务（替代 SSM）

**1000+ 实例：**
- Kubernetes (EKS) 部署
- Service Mesh (Istio)
- 分布式配置（Consul）

## 监控指标

### 关键指标（KPI）

1. **可用性：** 99.9% uptime
2. **延迟：** P99 < 3s
3. **错误率：** < 0.1%
4. **成本效率：** < $50/实例/月

### 告警优先级

**P0 (立即响应):**
- All instances down
- Bedrock API unavailable
- Data loss detected

**P1 (15 分钟内):**
- 50% instances unhealthy
- Error rate > 5%
- Cost anomaly detected

**P2 (1 小时内):**
- Single instance unhealthy
- High CPU (>80%)
- Config drift detected

---

**Architecture Version:** 1.0  
**Last Updated:** 2026-02-26  
**Author:** OpenClawFleet Team
