# OpenClawFleet 🚢

**Deploy and manage a fleet of OpenClaw instances on AWS**

**Fleet Management** | **Cost Optimized** | **Unified Dashboard**

---

## 🚀 Quick Deploy

### Step 1: Download Template

**[📥 Download: 00-master-all-in-one.yaml](https://raw.githubusercontent.com/CrypticDriver/openclawfleet/master/cloudformation/00-master-all-in-one.yaml)**

(Right-click → Save As)

### Step 2: Deploy

1. Open [AWS CloudFormation Console](https://console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create)
2. Upload template
3. Fill parameters:
   - **KeyPairName:** Your EC2 Key Pair *(required)*
   - **InstanceCount:** How many instances (1-10)
   - **InstanceNamePrefix:** Name prefix (e.g., `openclaw`)
4. Submit
5. Wait 15-20 minutes
6. Open **DashboardURL** from Outputs

**Done!** 🎉

---

## 🎯 What You Get

```
┌─────────────────────────────────────┐
│  🐕 OpenClawFleet Dashboard         │
│                                     │
│  Total: 5 instances                 │
│                                     │
│  ┌──────────────┐ ┌──────────────┐ │
│  │ openclaw-1   │ │ openclaw-2   │ │
│  │ ✓ Healthy    │ │ ✓ Healthy    │ │
│  │ [Open UI]    │ │ [Open UI]    │ │
│  └──────────────┘ └──────────────┘ │
│                                     │
│  ┌──────────────┐ ┌──────────────┐ │
│  │ openclaw-3   │ │ openclaw-4   │ │
│  │ ✓ Healthy    │ │ ✓ Healthy    │ │
│  │ [Open UI]    │ │ [Open UI]    │ │
│  └──────────────┘ └──────────────┘ │
│                                     │
│  ┌──────────────┐                  │
│  │ openclaw-5   │                  │
│  │ ✓ Healthy    │                  │
│  │ [Open UI]    │                  │
│  └──────────────┘                  │
└─────────────────────────────────────┘
```

**Features:**
- ✅ Deploy 1-10 OpenClaw instances
- ✅ Unified management dashboard
- ✅ Shared VPC (cost optimized)
- ✅ Auto Scaling & high availability
- ✅ One-click access to any instance

---

## 💰 Cost

| Instances | Monthly Cost | Savings vs Individual |
|-----------|--------------|----------------------|
| 1 | ~$103 | - |
| 3 | ~$169 | 33% ($80/mo) |
| 5 | ~$235 | 44% ($180/mo) |
| 10 | ~$400 | 53% ($430/mo) |

**Break-even:** 3+ instances

**Cost breakdown:**
- Foundation (VPC, ALB): $70/mo (shared)
- Each instance: $33/mo

---

## 📚 Documentation

- **[Deployment Guide](LAUNCH_STACK_GUIDE.md)** - Step-by-step tutorial
- **[Architecture](ARCHITECTURE.md)** - Design deep dive
- **[Management](docs/MANAGEMENT.md)** - Operations guide

---

## 🎓 Use Cases

### SaaS Provider
Deploy 10-100 instances for customers with unified management.

### Enterprise
Multi-team deployment with centralized monitoring.

### Development
Dev/staging/prod environments with easy cleanup.

---

## 🏗️ Architecture

```
                    ┌─────────────────┐
                    │  Internet GW    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │       ALB       │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
      /openclaw-1/      /openclaw-2/      /openclaw-3/
           │                 │                 │
           ▼                 ▼                 ▼
    ┌──────────┐      ┌──────────┐      ┌──────────┐
    │ Instance │      │ Instance │      │ Instance │
    │    1     │      │    2     │      │    3     │
    └──────────┘      └──────────┘      └──────────┘
```

**Key features:**
- Single VPC for all instances (cost optimized)
- Path-based ALB routing
- Lambda-powered dashboard
- SSM Parameter Store for secrets

---

## 🚀 Quick Start (CLI)

```bash
# Download template
curl -o /tmp/openclawfleet.yaml \
  https://raw.githubusercontent.com/CrypticDriver/openclawfleet/master/cloudformation/00-master-all-in-one.yaml

# Deploy
aws cloudformation create-stack \
  --region us-west-2 \
  --stack-name openclawfleet \
  --template-body file:///tmp/openclawfleet.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=YOUR_KEY \
    ParameterKey=InstanceCount,ParameterValue=5 \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
  --region us-west-2 \
  --stack-name openclawfleet

# Get dashboard URL
aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclawfleet \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
  --output text
```

---

## 🤝 Contributing

Issues and PRs welcome!

---

## 📜 License

MIT

---

## 🔗 Links

- **GitHub:** https://github.com/CrypticDriver/openclawfleet
- **OpenClaw:** https://github.com/openclaw/openclaw
- **Documentation:** See `/docs`

---

**Created by 狗蛋 for Chijiaer**  
**2026-02-26**

---

**Ready to deploy your fleet?** [Get started →](#-quick-deploy)
