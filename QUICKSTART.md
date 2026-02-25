# Quick Start Guide

## 最快 5 分钟部署

### 1. 准备（2 分钟）

```bash
# Clone 仓库
git clone https://github.com/CrypticDriver/openclaw-multi-deployment.git
cd openclaw-multi-deployment

# 配置 AWS CLI
aws configure

# 创建 EC2 Key Pair
aws ec2 create-key-pair \
  --region us-west-2 \
  --key-name openclaw-key \
  --query 'KeyMaterial' \
  --output text > openclaw-key.pem

chmod 400 openclaw-key.pem
```

### 2. 部署基础设施（10 分钟）

```bash
./scripts/deploy-foundation.sh \
  --region us-west-2 \
  --key-pair openclaw-key \
  --stack-name openclaw-foundation
```

等待完成后，你会看到：
```
✓ VPC Foundation deployed successfully!
✓ Shared Resources deployed successfully!

Foundation Details:
  VPC ID: vpc-xxxxx
  ALB URL: http://openclaw-shared-ALB-xxxxx.us-west-2.elb.amazonaws.com
```

### 3. 部署第一个 OpenClaw 实例（3 分钟）

```bash
./scripts/deploy-instance.sh \
  --name openclaw-prod-1 \
  --model global.amazon.nova-2-lite-v1:0 \
  --instance-type t4g.medium
```

### 4. 访问（1 分钟）

```bash
# 获取访问 URL 和 Token
ALB_URL=$(aws cloudformation describe-stacks \
  --stack-name openclaw-shared \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

TOKEN=$(aws ssm get-parameter \
  --name /openclaw/openclaw-prod-1/token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

echo "访问: ${ALB_URL}/openclaw-prod-1/?token=${TOKEN}"
```

打开浏览器访问这个 URL！🎉

---

## 部署更多实例

### 批量部署 5 个实例

```bash
./scripts/deploy-batch.sh \
  --count 5 \
  --prefix openclaw-prod \
  --model global.amazon.nova-2-lite-v1:0
```

### 查看所有实例状态

```bash
./scripts/health-check.sh --all
```

---

## 连接消息平台

### WhatsApp（最简单）

1. 打开 Web UI
2. 点击 "Channels" → "Add Channel" → "WhatsApp"
3. 用手机 WhatsApp 扫码

### Telegram

1. 找 @BotFather 创建 bot
2. 复制 bot token
3. 在 Web UI 添加 Telegram channel

### Discord

1. 创建 Discord bot (https://discord.com/developers/applications)
2. 复制 bot token
3. 在 Web UI 添加 Discord channel

完整指南：https://docs.openclaw.ai/channels

---

## 常见问题

**Q: 成本多少？**
A: 基础设施 $37/月 + 每实例 $31/月。5 个实例总计约 $200/月。

**Q: 可以用 Spot Instances 吗？**
A: 可以！编辑 Launch Template 使用 Spot，节省 70%。

**Q: 如何升级 OpenClaw 版本？**
A: `./scripts/update-openclaw-version.sh --version latest --rolling-update`

**Q: 如何备份配置？**
A: `./scripts/backup-config.sh --output backup.json`

---

**完整文档：** [README.md](README.md) | [Architecture](ARCHITECTURE.md) | [Deployment Guide](docs/DEPLOYMENT.md)

**遇到问题？** [Troubleshooting](docs/TROUBLESHOOTING.md)

**Created by 狗蛋 for Chijiaer** 🐕✨
