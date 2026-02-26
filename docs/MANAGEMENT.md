# Management Guide - OpenClawFleet

## Daily Operations

### Check Instance Health

```bash
# Check all instances
./scripts/health-check.sh --all

# Check specific instance
./scripts/health-check.sh --instance openclaw-prod-1
```

**Output:**
```
Instance              Status     CPU    Memory   Uptime       ALB Health
─────────────────────────────────────────────────────────────────────────
openclaw-prod-1       healthy    12%    N/A      3d 5h        ALB: 1/1
openclaw-prod-2       healthy    8%     N/A      3d 5h        ALB: 1/1
openclaw-prod-3       degraded   78%    N/A      12h          ALB: 0/1  ⚠️
```

### List All Instances

```bash
# List with basic info
./scripts/list-instances.sh

# Show gateway tokens (secure)
./scripts/list-instances.sh --show-tokens
```

### Access Instance Web UI

```bash
# Get access URL and token
INSTANCE_NAME="openclaw-prod-1"
TOKEN=$(aws ssm get-parameter \
  --region us-west-2 \
  --name /openclaw/$INSTANCE_NAME/token \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

ALB_URL=$(aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-shared \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

echo "${ALB_URL}/${INSTANCE_NAME}/?token=${TOKEN}"
```

Open the URL in your browser!

### Connect to Instance via SSM

```bash
# Get instance ID
INSTANCE_NAME="openclaw-prod-1"
ASG_NAME=$(aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-$INSTANCE_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text)

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --region us-west-2 \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

# Start SSM session
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Once connected, switch to ec2-user
sudo su - ec2-user

# Check OpenClaw status
systemctl status openclaw

# View logs
journalctl -u openclaw -f
```

## Scaling Operations

### Scale Single Instance

```bash
# Scale to 3 instances
./scripts/scale-instances.sh \
  --instance openclaw-prod-1 \
  --desired 3

# Update capacity limits
./scripts/scale-instances.sh \
  --instance openclaw-prod-1 \
  --min 2 \
  --desired 5 \
  --max 10
```

### Scale Down (Cost Savings)

```bash
# Scale to minimum (1 instance)
./scripts/scale-instances.sh \
  --instance openclaw-prod-1 \
  --desired 1

# Scale to zero (stop without deleting)
./scripts/scale-instances.sh \
  --instance openclaw-prod-1 \
  --min 0 \
  --desired 0 \
  --max 3
```

**Note:** Setting desired to 0 stops the instance but keeps the infrastructure. Useful for dev/test environments.

## Configuration Management

### Update Bedrock Model

```bash
# Update global default model
aws ssm put-parameter \
  --region us-west-2 \
  --name /openclaw/global/default-model \
  --value "global.anthropic.claude-sonnet-4-5-20250929-v1:0" \
  --type String \
  --overwrite

# Instances will reload config within 30 seconds
```

### Update Instance-Specific Configuration

```bash
# Set custom model for specific instance
aws ssm put-parameter \
  --region us-west-2 \
  --name /openclaw/openclaw-prod-1/model \
  --value "us.amazon.nova-pro-v1:0" \
  --type String \
  --overwrite

# Restart instance to apply
INSTANCE_ID=$(...)  # Get instance ID as shown above
aws ssm send-command \
  --region us-west-2 \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo systemctl restart openclaw"]'
```

### Rotate Gateway Token

```bash
INSTANCE_NAME="openclaw-prod-1"

# Generate new token
NEW_TOKEN=$(openssl rand -hex 32)

# Update SSM Parameter
aws ssm put-parameter \
  --region us-west-2 \
  --name /openclaw/$INSTANCE_NAME/token \
  --value "$NEW_TOKEN" \
  --type SecureString \
  --overwrite

# Update config file on instance (via SSM)
# ... (connect and update /home/ec2-user/openclaw/config.yaml)

# Restart OpenClaw
# ... (sudo systemctl restart openclaw)
```

## Monitoring

### CloudWatch Dashboard

Visit: https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=OpenClaw-Multi

**Key Metrics:**
- CPU Utilization (by instance)
- Memory Utilization
- Network In/Out
- Bedrock API Calls
- ALB Request Count
- ALB Target Health

### View Logs

```bash
# Tail logs from CloudWatch
aws logs tail /openclaw/openclaw-shared \
  --follow \
  --region us-west-2 \
  --filter-pattern "ERROR"

# View specific instance logs
aws logs tail /openclaw/openclaw-prod-1 \
  --follow \
  --region us-west-2
```

### Set Up Email Alerts

```bash
# Subscribe to SNS topic
SNS_TOPIC=$(aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-shared \
  --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
  --output text)

aws sns subscribe \
  --region us-west-2 \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint your-email@example.com

# Confirm subscription in email
```

## Backup and Restore

### Backup Configuration

```bash
# Export all SSM parameters
aws ssm get-parameters-by-path \
  --region us-west-2 \
  --path /openclaw/ \
  --recursive \
  --with-decryption \
  --query 'Parameters[*].[Name,Value]' \
  --output json > backup-config-$(date +%Y%m%d).json

# Backup CloudFormation templates
aws cloudformation get-template \
  --region us-west-2 \
  --stack-name openclaw-foundation \
  --query 'TemplateBody' > backup-foundation-$(date +%Y%m%d).yaml

aws cloudformation get-template \
  --region us-west-2 \
  --stack-name openclaw-shared \
  --query 'TemplateBody' > backup-shared-$(date +%Y%m%d).yaml
```

### Restore Configuration

```bash
# Restore SSM parameters from backup
cat backup-config-20260226.json | jq -r '.[] | @json' | while read param; do
  NAME=$(echo $param | jq -r '.[0]')
  VALUE=$(echo $param | jq -r '.[1]')
  
  aws ssm put-parameter \
    --region us-west-2 \
    --name "$NAME" \
    --value "$VALUE" \
    --type SecureString \
    --overwrite
done
```

## Cost Optimization

### View Current Costs

```bash
# Get current month cost by service
aws ce get-cost-and-usage \
  --region us-west-2 \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{
    "Tags": {
      "Key": "Project",
      "Values": ["OpenClaw-Multi"]
    }
  }'
```

### Switch to Spot Instances

```bash
# Update Launch Template to use Spot
# (requires CloudFormation update)
aws cloudformation update-stack \
  --region us-west-2 \
  --stack-name openclaw-prod-1 \
  --use-previous-template \
  --parameters \
    ParameterKey=UseSpotInstances,ParameterValue=true \
    ParameterKey=InstanceName,UsePreviousValue=true \
    [... other parameters ...]
```

### Schedule Scaling (Dev/Test Only)

```bash
# Scale down at night (save costs)
# Create EventBridge rule to trigger Lambda

# Scale down at 6 PM
# Scale up at 8 AM
```

## Troubleshooting

### Instance Won't Start

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --region us-west-2 \
  --stack-name openclaw-prod-1 \
  --max-items 10

# Check ASG activity
ASG_NAME=$(...)
aws autoscaling describe-scaling-activities \
  --region us-west-2 \
  --auto-scaling-group-name $ASG_NAME \
  --max-records 10
```

### High CPU Usage

```bash
# Check what's consuming CPU
# (connect via SSM first)
top
htop  # if installed

# Check OpenClaw logs
journalctl -u openclaw -n 100

# Restart OpenClaw
sudo systemctl restart openclaw
```

### ALB Health Check Failing

```bash
# Check target health
TG_ARN=$(aws cloudformation describe-stacks \
  --region us-west-2 \
  --stack-name openclaw-prod-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' \
  --output text)

aws elbv2 describe-target-health \
  --region us-west-2 \
  --target-group-arn $TG_ARN

# Common issues:
# 1. Security group blocking ALB → Instance traffic
# 2. OpenClaw not listening on port 18789
# 3. Health check path wrong (/health)
```

### Out of Memory

```bash
# Check memory usage
free -h

# Check OpenClaw memory
ps aux | grep openclaw

# Increase instance type
./scripts/update-instance-type.sh \
  --instance openclaw-prod-1 \
  --instance-type t4g.large
```

## Maintenance Windows

### Update OpenClaw Version

```bash
# TODO: Create update script
# Rolling update to avoid downtime
```

### Update AMI (Security Patches)

```bash
# 1. Launch new version with latest AMI
# 2. Test
# 3. Switch traffic via ALB weights
# 4. Terminate old version
```

### Database Migrations

*OpenClaw doesn't use a database by default, but if you add one:*

```bash
# Use RDS Blue/Green deployments
# Or snapshot → test → restore
```

## Disaster Recovery

### Regional Failure

**Manual steps:**
1. Deploy foundation in another region
2. Deploy instances
3. Update DNS to point to new ALB

**Automated (TODO):**
- CloudFormation StackSets for multi-region
- Route 53 health checks + failover

### Data Loss

**Prevention:**
- Enable EBS snapshots
- Store important data in S3
- Backup SSM parameters regularly

**Recovery:**
- Restore from latest snapshot
- Redeploy instances
- Restore SSM parameters

---

**Next:** [Troubleshooting Guide](TROUBLESHOOTING.md) | [Cost Optimization](COST_OPTIMIZATION.md)
