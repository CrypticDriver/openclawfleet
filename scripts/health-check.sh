#!/bin/bash
# OpenClaw Multi-Deployment - Health Check Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
REGION="us-west-2"
INSTANCE_NAME=""
CHECK_ALL=false

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
    --all)
      CHECK_ALL=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION       AWS region (default: us-west-2)"
      echo "  --instance NAME       Check specific instance"
      echo "  --all                 Check all instances"
      echo "  --help                Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --instance openclaw-prod-1"
      echo "  $0 --all"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Find all OpenClaw stacks
get_openclaw_stacks() {
  aws cloudformation list-stacks \
    --region $REGION \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[?starts_with(StackName, `openclaw-`) && StackName != `openclaw-foundation` && StackName != `openclaw-shared`].StackName' \
    --output text
}

# Check single instance
check_instance() {
  local STACK_NAME=$1
  local INSTANCE_NAME=$(echo $STACK_NAME | sed 's/^openclaw-//')
  
  # Get stack outputs
  local OUTPUTS=$(aws cloudformation describe-stacks \
    --region $REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs' \
    --output json 2>/dev/null)
  
  if [ -z "$OUTPUTS" ]; then
    echo -e "${RED}✗ $INSTANCE_NAME - Stack not found${NC}"
    return 1
  fi
  
  # Get ASG name
  local ASG_NAME=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="AutoScalingGroupName") | .OutputValue')
  
  # Get ASG details
  local ASG_INFO=$(aws autoscaling describe-auto-scaling-groups \
    --region $REGION \
    --auto-scaling-group-names $ASG_NAME \
    --query 'AutoScalingGroups[0]' \
    --output json 2>/dev/null)
  
  if [ -z "$ASG_INFO" ] || [ "$ASG_INFO" = "null" ]; then
    echo -e "${YELLOW}⚠ $INSTANCE_NAME - ASG not found${NC}"
    return 1
  fi
  
  # Parse ASG info
  local DESIRED=$(echo $ASG_INFO | jq -r '.DesiredCapacity')
  local MIN=$(echo $ASG_INFO | jq -r '.MinSize')
  local MAX=$(echo $ASG_INFO | jq -r '.MaxSize')
  local INSTANCES=$(echo $ASG_INFO | jq -r '.Instances | length')
  local HEALTHY=$(echo $ASG_INFO | jq -r '[.Instances[] | select(.HealthStatus=="Healthy")] | length')
  
  # Get instance IDs
  local INSTANCE_IDS=$(echo $ASG_INFO | jq -r '.Instances[].InstanceId' | tr '\n' ' ')
  
  # Get instance metrics (if instances exist)
  local CPU="N/A"
  local MEMORY="N/A"
  local UPTIME="N/A"
  
  if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != " " ]; then
    local FIRST_INSTANCE=$(echo $INSTANCE_IDS | awk '{print $1}')
    
    # Get CPU utilization (last 5 minutes)
    CPU=$(aws cloudwatch get-metric-statistics \
      --region $REGION \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --dimensions Name=InstanceId,Value=$FIRST_INSTANCE \
      --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
      --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
      --period 300 \
      --statistics Average \
      --query 'Datapoints[0].Average' \
      --output text 2>/dev/null || echo "N/A")
    
    if [ "$CPU" != "N/A" ] && [ "$CPU" != "None" ]; then
      CPU=$(printf "%.1f%%" $CPU)
    else
      CPU="N/A"
    fi
    
    # Get uptime
    local LAUNCH_TIME=$(echo $ASG_INFO | jq -r '.Instances[0].LaunchTime')
    if [ -n "$LAUNCH_TIME" ] && [ "$LAUNCH_TIME" != "null" ]; then
      local NOW=$(date +%s)
      local LAUNCH=$(date -d "$LAUNCH_TIME" +%s)
      local DIFF=$((NOW - LAUNCH))
      local DAYS=$((DIFF / 86400))
      local HOURS=$(((DIFF % 86400) / 3600))
      UPTIME="${DAYS}d ${HOURS}h"
    fi
  fi
  
  # Get target group health
  local TG_ARN=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="TargetGroupArn") | .OutputValue')
  local TG_HEALTH="N/A"
  
  if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "null" ]; then
    local TG_HEALTHY=$(aws elbv2 describe-target-health \
      --region $REGION \
      --target-group-arn $TG_ARN \
      --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
      --output text 2>/dev/null || echo "0")
    local TG_TOTAL=$(aws elbv2 describe-target-health \
      --region $REGION \
      --target-group-arn $TG_ARN \
      --query 'length(TargetHealthDescriptions)' \
      --output text 2>/dev/null || echo "0")
    TG_HEALTH="${TG_HEALTHY}/${TG_TOTAL}"
  fi
  
  # Determine overall status
  local STATUS="unknown"
  local STATUS_COLOR=$YELLOW
  
  if [ "$HEALTHY" -eq "$DESIRED" ] && [ "$DESIRED" -gt 0 ]; then
    STATUS="healthy"
    STATUS_COLOR=$GREEN
  elif [ "$HEALTHY" -gt 0 ]; then
    STATUS="degraded"
    STATUS_COLOR=$YELLOW
  else
    STATUS="unhealthy"
    STATUS_COLOR=$RED
  fi
  
  # Print result
  printf "${STATUS_COLOR}%-20s %-10s %-6s %-8s %-12s %-15s${NC}\n" \
    "$INSTANCE_NAME" \
    "$STATUS" \
    "$CPU" \
    "$MEMORY" \
    "$UPTIME" \
    "ALB: $TG_HEALTH"
}

# Main execution
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  OpenClaw Multi-Deployment - Health Check${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
printf "%-20s %-10s %-6s %-8s %-12s %-15s\n" "Instance" "Status" "CPU" "Memory" "Uptime" "ALB Health"
echo "─────────────────────────────────────────────────────────────────────"

if [ "$CHECK_ALL" = true ]; then
  # Check all instances
  STACKS=$(get_openclaw_stacks)
  
  if [ -z "$STACKS" ]; then
    echo -e "${YELLOW}No OpenClaw instances found${NC}"
    exit 0
  fi
  
  for STACK in $STACKS; do
    check_instance $STACK
  done
  
elif [ -n "$INSTANCE_NAME" ]; then
  # Check specific instance
  STACK_NAME="openclaw-${INSTANCE_NAME}"
  check_instance $STACK_NAME
  
else
  echo -e "${RED}Error: Specify --instance NAME or --all${NC}"
  exit 1
fi

echo "─────────────────────────────────────────────────────────────────────"
echo ""

# Summary
if [ "$CHECK_ALL" = true ]; then
  TOTAL=$(echo "$STACKS" | wc -w)
  echo -e "${BLUE}Total Instances: $TOTAL${NC}"
  echo ""
fi

echo -e "${GREEN}Legend:${NC}"
echo "  healthy   - All instances running and healthy"
echo "  degraded  - Some instances unhealthy"
echo "  unhealthy - No healthy instances"
echo ""
