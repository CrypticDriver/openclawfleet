#!/bin/bash
# OpenClaw Multi-Deployment - Scale Instances

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
REGION="us-west-2"
INSTANCE_NAME=""
DESIRED_COUNT=""
MIN_SIZE=""
MAX_SIZE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --instance)
      INSTANCE_NAME="$2"
      shift 2
      ;;
    --desired)
      DESIRED_COUNT="$2"
      shift 2
      ;;
    --min)
      MIN_SIZE="$2"
      shift 2
      ;;
    --max)
      MAX_SIZE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION      AWS region (default: us-west-2)"
      echo "  --instance NAME      Instance name (required)"
      echo "  --desired COUNT      Desired instance count"
      echo "  --min COUNT          Minimum instance count"
      echo "  --max COUNT          Maximum instance count"
      echo "  --help               Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Scale to 3 instances"
      echo "  $0 --instance openclaw-prod-1 --desired 3"
      echo ""
      echo "  # Update capacity limits"
      echo "  $0 --instance openclaw-prod-1 --min 2 --desired 5 --max 10"
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
  echo -e "${RED}Error: --instance is required${NC}"
  exit 1
fi

if [ -z "$DESIRED_COUNT" ] && [ -z "$MIN_SIZE" ] && [ -z "$MAX_SIZE" ]; then
  echo -e "${RED}Error: Specify at least one of --desired, --min, or --max${NC}"
  exit 1
fi

# Get ASG name
STACK_NAME="openclaw-${INSTANCE_NAME}"
ASG_NAME=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
  --output text 2>/dev/null)

if [ -z "$ASG_NAME" ]; then
  echo -e "${RED}Error: Instance '$INSTANCE_NAME' not found${NC}"
  exit 1
fi

# Get current configuration
CURRENT=$(aws autoscaling describe-auto-scaling-groups \
  --region $REGION \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize]' \
  --output text)

CURRENT_MIN=$(echo $CURRENT | awk '{print $1}')
CURRENT_DESIRED=$(echo $CURRENT | awk '{print $2}')
CURRENT_MAX=$(echo $CURRENT | awk '{print $3}')

# Use current values if not specified
MIN_SIZE=${MIN_SIZE:-$CURRENT_MIN}
DESIRED_COUNT=${DESIRED_COUNT:-$CURRENT_DESIRED}
MAX_SIZE=${MAX_SIZE:-$CURRENT_MAX}

# Validate values
if [ "$MIN_SIZE" -gt "$DESIRED_COUNT" ]; then
  echo -e "${RED}Error: Min ($MIN_SIZE) cannot be greater than Desired ($DESIRED_COUNT)${NC}"
  exit 1
fi

if [ "$DESIRED_COUNT" -gt "$MAX_SIZE" ]; then
  echo -e "${RED}Error: Desired ($DESIRED_COUNT) cannot be greater than Max ($MAX_SIZE)${NC}"
  exit 1
fi

echo ""
echo -e "${YELLOW}Scaling Instance: $INSTANCE_NAME${NC}"
echo ""
echo "Current:"
echo "  Min: $CURRENT_MIN"
echo "  Desired: $CURRENT_DESIRED"
echo "  Max: $CURRENT_MAX"
echo ""
echo "New:"
echo "  Min: $MIN_SIZE"
echo "  Desired: $DESIRED_COUNT"
echo "  Max: $MAX_SIZE"
echo ""

if [ "$CURRENT_MIN" = "$MIN_SIZE" ] && [ "$CURRENT_DESIRED" = "$DESIRED_COUNT" ] && [ "$CURRENT_MAX" = "$MAX_SIZE" ]; then
  echo -e "${YELLOW}No changes needed${NC}"
  exit 0
fi

read -p "Continue with scaling? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Scaling cancelled."
  exit 0
fi

# Update ASG
echo ""
echo -e "${YELLOW}Updating Auto Scaling Group...${NC}"

aws autoscaling update-auto-scaling-group \
  --region $REGION \
  --auto-scaling-group-name $ASG_NAME \
  --min-size $MIN_SIZE \
  --desired-capacity $DESIRED_COUNT \
  --max-size $MAX_SIZE

echo -e "${GREEN}✓ Auto Scaling Group updated${NC}"
echo ""

# Wait and show progress
echo "Waiting for desired capacity to be reached..."
echo ""

for i in {1..30}; do
  CURRENT_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --region $REGION \
    --auto-scaling-group-names $ASG_NAME \
    --query 'AutoScalingGroups[0].Instances | length(@)' \
    --output text)
  
  HEALTHY_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --region $REGION \
    --auto-scaling-group-names $ASG_NAME \
    --query 'AutoScalingGroups[0].Instances[?HealthStatus==`Healthy`] | length(@)' \
    --output text)
  
  echo -e "  [$i/30] Instances: $CURRENT_INSTANCES/$DESIRED_COUNT | Healthy: $HEALTHY_INSTANCES"
  
  if [ "$CURRENT_INSTANCES" = "$DESIRED_COUNT" ] && [ "$HEALTHY_INSTANCES" = "$DESIRED_COUNT" ]; then
    echo ""
    echo -e "${GREEN}✓ Scaling complete! All instances healthy.${NC}"
    break
  fi
  
  sleep 10
done

echo ""
echo -e "${GREEN}Instance scaled successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Check health: ./scripts/health-check.sh --instance $INSTANCE_NAME"
echo "  2. View instances: ./scripts/list-instances.sh"
echo ""
