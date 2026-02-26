#!/bin/bash
# OpenClaw Multi-Deployment - Single Instance Deployment Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REGION="us-west-2"
FOUNDATION_STACK="openclaw-foundation"
SHARED_STACK="openclaw-shared"
INSTANCE_NAME=""
INSTANCE_TYPE="t4g.medium"
BEDROCK_MODEL="global.amazon.nova-2-lite-v1:0"
KEY_PAIR=""
MIN_SIZE=1
DESIRED_CAPACITY=1
MAX_SIZE=3
VOLUME_SIZE=30
USE_SPOT="false"
ENABLE_MONITORING="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --foundation-stack)
      FOUNDATION_STACK="$2"
      shift 2
      ;;
    --shared-stack)
      SHARED_STACK="$2"
      shift 2
      ;;
    --name)
      INSTANCE_NAME="$2"
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --model)
      BEDROCK_MODEL="$2"
      shift 2
      ;;
    --key-pair)
      KEY_PAIR="$2"
      shift 2
      ;;
    --min-size)
      MIN_SIZE="$2"
      shift 2
      ;;
    --desired)
      DESIRED_CAPACITY="$2"
      shift 2
      ;;
    --max-size)
      MAX_SIZE="$2"
      shift 2
      ;;
    --volume-size)
      VOLUME_SIZE="$2"
      shift 2
      ;;
    --spot)
      USE_SPOT="true"
      shift
      ;;
    --monitoring)
      ENABLE_MONITORING="true"
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION              AWS region (default: us-west-2)"
      echo "  --foundation-stack NAME      Foundation stack name (default: openclaw-foundation)"
      echo "  --shared-stack NAME          Shared stack name (default: openclaw-shared)"
      echo "  --name NAME                  Instance name (required, e.g., openclaw-prod-1)"
      echo "  --instance-type TYPE         EC2 instance type (default: t4g.medium)"
      echo "  --model MODEL_ID             Bedrock model ID (default: nova-2-lite)"
      echo "  --key-pair NAME              EC2 key pair name (required)"
      echo "  --min-size NUM               Min instances (default: 1)"
      echo "  --desired NUM                Desired instances (default: 1)"
      echo "  --max-size NUM               Max instances (default: 3)"
      echo "  --volume-size GB             EBS volume size (default: 30GB)"
      echo "  --spot                       Use Spot Instances (70% savings)"
      echo "  --monitoring                 Enable detailed CloudWatch monitoring"
      echo "  --help                       Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validate inputs
if [ -z "$INSTANCE_NAME" ]; then
  echo -e "${RED}Error: --name is required${NC}"
  echo "Example: $0 --name openclaw-prod-1 --key-pair my-key"
  exit 1
fi

if [ -z "$KEY_PAIR" ]; then
  echo -e "${RED}Error: --key-pair is required${NC}"
  exit 1
fi

# Validate instance name format
if [[ ! "$INSTANCE_NAME" =~ ^[a-z0-9-]+$ ]]; then
  echo -e "${RED}Error: Instance name must contain only lowercase letters, numbers, and hyphens${NC}"
  exit 1
fi

# Check if foundation stacks exist
echo -e "${YELLOW}Validating foundation stacks...${NC}"

if ! aws cloudformation describe-stacks --region $REGION --stack-name $FOUNDATION_STACK &>/dev/null; then
  echo -e "${RED}Error: Foundation stack '$FOUNDATION_STACK' not found${NC}"
  echo "Run: ./scripts/deploy-foundation.sh first"
  exit 1
fi

if ! aws cloudformation describe-stacks --region $REGION --stack-name $SHARED_STACK &>/dev/null; then
  echo -e "${RED}Error: Shared stack '$SHARED_STACK' not found${NC}"
  echo "Run: ./scripts/deploy-foundation.sh first"
  exit 1
fi

echo -e "${GREEN}✓ Foundation stacks validated${NC}"

# Calculate cost estimate
if [ "$USE_SPOT" = "true" ]; then
  EC2_COST="7.20"
else
  case "$INSTANCE_TYPE" in
    t4g.small) EC2_COST="12.00" ;;
    t4g.medium) EC2_COST="24.00" ;;
    t4g.large) EC2_COST="48.00" ;;
    t4g.xlarge) EC2_COST="96.00" ;;
    c7g.large) EC2_COST="54.00" ;;
    c7g.xlarge) EC2_COST="108.00" ;;
    *) EC2_COST="24.00" ;;
  esac
fi

EBS_COST=$(echo "$VOLUME_SIZE * 0.08" | bc)
BEDROCK_COST="5-8"
TOTAL_COST=$(echo "$EC2_COST + $EBS_COST + 6.5" | bc)

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  OpenClaw Instance Deployment${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Configuration:"
echo "  Instance Name: $INSTANCE_NAME"
echo "  Region: $REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Bedrock Model: $BEDROCK_MODEL"
echo "  Key Pair: $KEY_PAIR"
echo "  Auto Scaling: Min=$MIN_SIZE, Desired=$DESIRED_CAPACITY, Max=$MAX_SIZE"
echo "  Volume Size: ${VOLUME_SIZE}GB"
echo "  Use Spot: $USE_SPOT"
echo "  Detailed Monitoring: $ENABLE_MONITORING"
echo ""
echo -e "${GREEN}Monthly Cost Estimate:${NC}"
echo "  EC2: \$$EC2_COST"
echo "  EBS: \$$EBS_COST"
echo "  Bedrock: \$$BEDROCK_COST"
echo -e "${GREEN}  Total: ~\$$TOTAL_COST/month${NC}"
echo ""
read -p "Continue with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Deployment cancelled."
  exit 0
fi

# Deploy CloudFormation stack
echo ""
echo -e "${YELLOW}Deploying OpenClaw instance: $INSTANCE_NAME${NC}"

STACK_NAME="openclaw-${INSTANCE_NAME}"

aws cloudformation create-stack \
  --region $REGION \
  --stack-name $STACK_NAME \
  --template-body file://cloudformation/03-openclaw-instance.yaml \
  --parameters \
    ParameterKey=FoundationStackName,ParameterValue=$FOUNDATION_STACK \
    ParameterKey=SharedStackName,ParameterValue=$SHARED_STACK \
    ParameterKey=InstanceName,ParameterValue=$INSTANCE_NAME \
    ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE \
    ParameterKey=BedrockModel,ParameterValue=$BEDROCK_MODEL \
    ParameterKey=KeyPairName,ParameterValue=$KEY_PAIR \
    ParameterKey=MinSize,ParameterValue=$MIN_SIZE \
    ParameterKey=DesiredCapacity,ParameterValue=$DESIRED_CAPACITY \
    ParameterKey=MaxSize,ParameterValue=$MAX_SIZE \
    ParameterKey=VolumeSize,ParameterValue=$VOLUME_SIZE \
    ParameterKey=EnableDetailedMonitoring,ParameterValue=$ENABLE_MONITORING \
    ParameterKey=UseSpotInstances,ParameterValue=$USE_SPOT \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Key=Project,Value=OpenClaw-Multi Key=InstanceName,Value=$INSTANCE_NAME

echo -e "${GREEN}✓ Stack creation initiated${NC}"
echo "Waiting for stack to complete (this may take 3-5 minutes)..."

aws cloudformation wait stack-create-complete \
  --region $REGION \
  --stack-name $STACK_NAME

echo -e "${GREEN}✓ OpenClaw instance deployed successfully!${NC}"

# Get outputs
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment Complete! 🎉${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

ACCESS_URL=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`AccessURL`].OutputValue' \
  --output text)

echo "Instance Details:"
echo "  Name: $INSTANCE_NAME"
echo "  Stack: $STACK_NAME"
echo "  Region: $REGION"
echo ""
echo -e "${GREEN}Access Information:${NC}"
echo "  Base URL: $ACCESS_URL"
echo ""
echo "To get full access URL with token:"
echo -e "${BLUE}TOKEN=\$(aws ssm get-parameter --region $REGION --name /openclaw/$INSTANCE_NAME/token --with-decryption --query 'Parameter.Value' --output text)${NC}"
echo -e "${BLUE}echo \"${ACCESS_URL}?token=\$TOKEN\"${NC}"
echo ""
echo "Or use this one-liner:"
echo -e "${BLUE}TOKEN=\$(aws ssm get-parameter --region $REGION --name /openclaw/$INSTANCE_NAME/token --with-decryption --query 'Parameter.Value' --output text) && echo \"${ACCESS_URL}?token=\$TOKEN\"${NC}"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Wait ~2 minutes for OpenClaw to fully start"
echo "  2. Access the URL above in your browser"
echo "  3. Connect messaging channels (WhatsApp/Telegram/Discord)"
echo "  4. Check health: ./scripts/health-check.sh --instance $INSTANCE_NAME"
echo ""
echo -e "${YELLOW}Instance deployed successfully!${NC}"
