#!/bin/bash
# OpenClaw Multi-Deployment - List All Instances

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
REGION="us-west-2"
SHOW_TOKENS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --show-tokens)
      SHOW_TOKENS=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION     AWS region (default: us-west-2)"
      echo "  --show-tokens       Show gateway tokens (secure)"
      echo "  --help              Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Get ALB URL
ALB_URL=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name openclaw-shared \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text 2>/dev/null)

if [ -z "$ALB_URL" ]; then
  echo -e "${RED}Error: Shared stack not found or ALB not deployed${NC}"
  exit 1
fi

# Get all OpenClaw stacks
STACKS=$(aws cloudformation list-stacks \
  --region $REGION \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query 'StackSummaries[?starts_with(StackName, `openclaw-`) && StackName != `openclaw-foundation` && StackName != `openclaw-shared`].StackName' \
  --output text)

if [ -z "$STACKS" ]; then
  echo -e "${YELLOW}No OpenClaw instances found${NC}"
  exit 0
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  OpenClaw Multi-Deployment - Instance List${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "ALB URL: $ALB_URL"
echo "Region: $REGION"
echo ""

COUNT=0

for STACK in $STACKS; do
  COUNT=$((COUNT + 1))
  INSTANCE_NAME=$(echo $STACK | sed 's/^openclaw-//')
  
  # Get token if requested
  if [ "$SHOW_TOKENS" = true ]; then
    TOKEN=$(aws ssm get-parameter \
      --region $REGION \
      --name /openclaw/$INSTANCE_NAME/token \
      --with-decryption \
      --query 'Parameter.Value' \
      --output text 2>/dev/null || echo "N/A")
  fi
  
  # Get instance count
  ASG_NAME=$(aws cloudformation describe-stacks \
    --region $REGION \
    --stack-name $STACK \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text 2>/dev/null)
  
  INSTANCE_COUNT=0
  if [ -n "$ASG_NAME" ]; then
    INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
      --region $REGION \
      --auto-scaling-group-names $ASG_NAME \
      --query 'AutoScalingGroups[0].Instances | length(@)' \
      --output text 2>/dev/null || echo "0")
  fi
  
  echo -e "${GREEN}[$COUNT] $INSTANCE_NAME${NC}"
  echo "    URL: ${ALB_URL}/${INSTANCE_NAME}/"
  
  if [ "$SHOW_TOKENS" = true ]; then
    echo "    Full URL: ${ALB_URL}/${INSTANCE_NAME}/?token=$TOKEN"
  else
    echo "    Get token: aws ssm get-parameter --region $REGION --name /openclaw/$INSTANCE_NAME/token --with-decryption --query 'Parameter.Value' --output text"
  fi
  
  echo "    Instances: $INSTANCE_COUNT"
  echo "    Stack: $STACK"
  echo ""
done

echo -e "${BLUE}Total: $COUNT instances${NC}"
echo ""

if [ "$SHOW_TOKENS" = false ]; then
  echo -e "${YELLOW}Tip: Use --show-tokens to display gateway tokens${NC}"
  echo ""
fi

# Generate quick access script
ACCESS_SCRIPT="access-instances.sh"
cat > $ACCESS_SCRIPT << 'EOF'
#!/bin/bash
# Auto-generated instance access script
# Generated: $(date)

REGION="us-west-2"

EOF

for STACK in $STACKS; do
  INSTANCE_NAME=$(echo $STACK | sed 's/^openclaw-//')
  cat >> $ACCESS_SCRIPT << EOF
echo "$INSTANCE_NAME:"
TOKEN=\$(aws ssm get-parameter --region $REGION --name /openclaw/$INSTANCE_NAME/token --with-decryption --query 'Parameter.Value' --output text)
echo "  ${ALB_URL}/${INSTANCE_NAME}/?token=\$TOKEN"
echo ""

EOF
done

chmod +x $ACCESS_SCRIPT

echo -e "${GREEN}✓ Quick access script generated: $ACCESS_SCRIPT${NC}"
echo "  Run: ./$ACCESS_SCRIPT"
echo ""
