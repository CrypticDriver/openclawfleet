# Deployment Guide - OpenClaw Multi-Deployment

## Prerequisites

### AWS Account Setup

1. **AWS CLI configured:**
   ```bash
   aws configure
   # Enter your credentials
   ```

2. **Required IAM permissions:**
   - EC2 (full)
   - CloudFormation (full)
   - VPC (full)
   - ELB (full)
   - IAM (create roles)
   - SSM (full)
   - CloudWatch (full)
   - Bedrock (full)

3. **EC2 Key Pair:**
   ```bash
   # Create if you don't have one
   aws ec2 create-key-pair \
     --region us-west-2 \
     --key-name openclaw-key \
     --query 'KeyMaterial' \
     --output text > openclaw-key.pem
   
   chmod 400 openclaw-key.pem
   ```

4. **Enable Bedrock Models:**
   - Go to [Bedrock Console](https://console.aws.amazon.com/bedrock)
   - Request access to models:
     - Amazon Nova 2 Lite
     - Claude Sonnet 4.5
     - (Optional) Other models

### Cost Preparation

Review the cost structure:

- **Foundation (one-time):** $37-75/month
  - VPC + NAT Gateway: $32.40
  - ALB: $16.20
  - VPC Endpoints: $21.60 (optional)

- **Per Instance:** $31-34/month
  - EC2 (t4g.medium): $24
  - EBS: $2.40
  - Bedrock usage: $5-8

**Total for 5 instances:** ~$200-240/month

## Step-by-Step Deployment

### Phase 1: Deploy Foundation (10-15 minutes)

This creates the shared infrastructure (VPC, ALB, VPC Endpoints).

```bash
cd openclaw-multi-deployment

./scripts/deploy-foundation.sh \
  --region us-west-2 \
  --key-pair openclaw-key \
  --stack-name openclaw-foundation
```

**Options:**
- `--nat-redundancy` - Enable NAT in both AZs (+$32/mo, higher availability)
- `--no-vpc-endpoints` - Disable VPC Endpoints (-$22/mo, less secure)
- `--no-flow-logs` - Disable VPC Flow Logs (-$10/mo, less visibility)
- `--certificate-arn arn:aws:acm:...` - Use ACM certificate for HTTPS

**What happens:**
1. Creates VPC with public/private subnets in 2 AZs
2. Creates NAT Gateway for internet access
3. Creates Application Load Balancer
4. Creates VPC Endpoints for Bedrock/SSM
5. Creates Security Groups
6. Creates SSM parameters for configuration

**Validation:**
```bash
# Check VPC stack
aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-foundation

# Check ALB
aws elbv2 describe-load-balancers \
  --region us-west-2 \
  --names openclaw-shared-ALB
```

### Phase 2: Deploy OpenClaw Instances

#### Option A: Single Instance

```bash
./scripts/deploy-instance.sh \
  --name openclaw-prod-1 \
  --model global.amazon.nova-2-lite-v1:0 \
  --instance-type t4g.medium \
  --foundation-stack openclaw-foundation
```

**Parameters:**
- `--name` - Unique instance name
- `--model` - Bedrock model ID
- `--instance-type` - EC2 instance type (t4g.small/medium/large)
- `--channels` - Messaging channels (whatsapp,telegram,discord)

#### Option B: Batch Deployment

Deploy 5 instances at once:

```bash
./scripts/deploy-batch.sh \
  --count 5 \
  --prefix openclaw-prod \
  --model global.amazon.nova-2-lite-v1:0 \
  --instance-type t4g.medium
```

**What happens:**
1. Creates Launch Template with OpenClaw configuration
2. Creates Auto Scaling Group (min=1, desired=1, max=3)
3. Creates Target Group and registers to ALB
4. Adds ALB Listener Rule for path-based routing
5. Generates Gateway Token (stored in SSM)
6. Starts OpenClaw Gateway

**Wait time:** 3-5 minutes per instance

### Phase 3: Verify Deployment

#### Check Instance Status

```bash
./scripts/health-check.sh --all
```

Output:
```
Instance          Status    CPU    Memory   Uptime    Last Response
openclaw-prod-1   healthy   12%    45%      5m        200ms
openclaw-prod-2   healthy   8%     38%      4m        180ms
openclaw-prod-3   healthy   15%    52%      3m        220ms
```

#### Access Web UI

```bash
# Get ALB URL
ALB_URL=$(aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-shared \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

# Get instance token
TOKEN=$(aws ssm get-parameter \
  --region us-west-2 \
  --name /openclaw/openclaw-prod-1/token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Access
echo "Open: ${ALB_URL}/openclaw-prod-1/?token=${TOKEN}"
```

#### Connect Messaging Platforms

1. **WhatsApp:**
   - Open Web UI
   - Click "Channels" → "Add Channel" → "WhatsApp"
   - Scan QR code with WhatsApp

2. **Telegram:**
   - Create bot via @BotFather
   - Get bot token
   - Add in Web UI

3. **Discord:**
   - Create bot in Developer Portal
   - Copy token
   - Add in Web UI

Full guides: [OpenClaw Docs](https://docs.openclaw.ai)

## Post-Deployment Configuration

### Configure Auto Scaling

```bash
# Set scaling policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name openclaw-prod-1-asg \
  --policy-name cpu-scale-out \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 70.0
  }'
```

### Configure CloudWatch Alarms

```bash
# High CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name openclaw-prod-1-high-cpu \
  --alarm-description "Alert when CPU > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value=i-xxxxx \
  --alarm-actions arn:aws:sns:us-west-2:xxx:openclaw-shared-alerts
```

### Update Global Configuration

```bash
# Change default model for all instances
aws ssm put-parameter \
  --name /openclaw/global/default-model \
  --value "global.anthropic.claude-sonnet-4-5-20250929-v1:0" \
  --type String \
  --overwrite

# Instances will auto-reload config within 30 seconds
```

## Scaling Operations

### Scale Up (Add More Instances)

```bash
./scripts/scale-instances.sh --desired-count 10
```

### Scale Down

```bash
./scripts/scale-instances.sh --desired-count 3
```

### Update Instance Type

```bash
# Update launch template
./scripts/update-instance-type.sh \
  --instance-type t4g.large \
  --instances openclaw-prod-1,openclaw-prod-2

# Rolling update (zero downtime)
```

## Monitoring

### CloudWatch Dashboard

```bash
# Open dashboard
aws cloudwatch get-dashboard \
  --dashboard-name OpenClaw-Multi \
  --region us-west-2
```

Or visit: https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=OpenClaw-Multi

### View Logs

```bash
# Tail logs
aws logs tail /openclaw/openclaw-shared \
  --follow \
  --region us-west-2
```

### Cost Tracking

```bash
# Get current month cost
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --filter '{
    "Tags": {
      "Key": "Project",
      "Values": ["OpenClaw-Multi"]
    }
  }'
```

## Maintenance

### Update OpenClaw Version

```bash
# Update all instances to latest
./scripts/update-openclaw-version.sh \
  --version latest \
  --rolling-update
```

### Backup Configuration

```bash
# Backup SSM parameters
./scripts/backup-config.sh --output backup-$(date +%Y%m%d).json
```

### Restore Configuration

```bash
./scripts/restore-config.sh --input backup-20260226.json
```

## Troubleshooting

### Instance Won't Start

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name openclaw-prod-1

# Check instance logs
aws ssm start-session --target i-xxxxx
sudo journalctl -u openclaw -f
```

### ALB Health Check Failing

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Common issues:
# - Security group blocking ALB → Instance traffic
# - OpenClaw gateway not running
# - Health check path wrong
```

### High Costs

```bash
# Identify cost drivers
aws ce get-cost-and-usage \
  --time-period Start=2026-02-01,End=2026-02-28 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Optimization options:
# 1. Switch to Spot Instances (70% savings)
# 2. Use Savings Plans (30-50% savings)
# 3. Disable VPC Endpoints (-$22/mo)
# 4. Use Nova 2 Lite model (90% cheaper than Claude)
```

## Cleanup

### Delete Single Instance

```bash
aws cloudformation delete-stack \
  --stack-name openclaw-prod-1 \
  --region us-west-2
```

### Delete All Instances + Foundation

```bash
# Delete all instance stacks first
for stack in $(aws cloudformation list-stacks --region us-west-2 --query 'StackSummaries[?StackName~=`openclaw-prod`].StackName' --output text); do
  aws cloudformation delete-stack --stack-name $stack --region us-west-2
done

# Wait for deletion
sleep 300

# Delete shared resources
aws cloudformation delete-stack \
  --stack-name openclaw-shared \
  --region us-west-2

# Wait
sleep 180

# Delete foundation
aws cloudformation delete-stack \
  --stack-name openclaw-foundation \
  --region us-west-2
```

**⚠️ Warning:** This will delete everything including VPC, ALB, and all instances!

---

**Next:** [Management Guide](MANAGEMENT.md) | [Architecture](ARCHITECTURE.md) | [Troubleshooting](TROUBLESHOOTING.md)
