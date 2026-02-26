#!/bin/bash
# OpenClaw Multi-Deployment - Batch Deployment Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
COUNT=5
PREFIX="openclaw-prod"
REGION="us-west-2"
INSTANCE_TYPE="t4g.medium"
BEDROCK_MODEL="global.amazon.nova-2-lite-v1:0"
KEY_PAIR=""
PARALLEL_DEPLOYMENTS=3

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --count)
      COUNT="$2"
      shift 2
      ;;
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
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
    --parallel)
      PARALLEL_DEPLOYMENTS="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --count NUM               Number of instances to deploy (default: 5)"
      echo "  --prefix PREFIX           Instance name prefix (default: openclaw-prod)"
      echo "  --region REGION           AWS region (default: us-west-2)"
      echo "  --instance-type TYPE      EC2 instance type (default: t4g.medium)"
      echo "  --model MODEL_ID          Bedrock model ID (default: nova-2-lite)"
      echo "  --key-pair NAME           EC2 key pair name (required)"
      echo "  --parallel NUM            Max parallel deployments (default: 3)"
      echo "  --help                    Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --count 5 --prefix openclaw-prod --key-pair my-key"
      echo ""
      echo "This will create:"
      echo "  openclaw-prod-1"
      echo "  openclaw-prod-2"
      echo "  openclaw-prod-3"
      echo "  openclaw-prod-4"
      echo "  openclaw-prod-5"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Validate inputs
if [ -z "$KEY_PAIR" ]; then
  echo -e "${RED}Error: --key-pair is required${NC}"
  exit 1
fi

if [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 50 ]; then
  echo -e "${RED}Error: Count must be between 1 and 50${NC}"
  exit 1
fi

# Calculate total cost
COST_PER_INSTANCE=31
FOUNDATION_COST=70
TOTAL_COST=$(echo "$FOUNDATION_COST + ($COUNT * $COST_PER_INSTANCE)" | bc)

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  OpenClaw Batch Deployment${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Configuration:"
echo "  Count: $COUNT instances"
echo "  Prefix: $PREFIX"
echo "  Names: ${PREFIX}-1 to ${PREFIX}-${COUNT}"
echo "  Region: $REGION"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Bedrock Model: $BEDROCK_MODEL"
echo "  Key Pair: $KEY_PAIR"
echo "  Parallel Deployments: $PARALLEL_DEPLOYMENTS"
echo ""
echo -e "${GREEN}Monthly Cost Estimate:${NC}"
echo "  Foundation (shared): \$$FOUNDATION_COST"
echo "  $COUNT instances @ \$$COST_PER_INSTANCE each: \$$(echo "$COUNT * $COST_PER_INSTANCE" | bc)"
echo -e "${GREEN}  Total: ~\$$TOTAL_COST/month${NC}"
echo ""
read -p "Continue with batch deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Deployment cancelled."
  exit 0
fi

# Create deployment log directory
LOG_DIR="logs/batch-deployment-$(date +%Y%m%d-%H%M%S)"
mkdir -p $LOG_DIR

echo ""
echo -e "${YELLOW}Starting batch deployment...${NC}"
echo "Logs will be saved to: $LOG_DIR"
echo ""

# Track deployments
declare -a PIDS=()
declare -a NAMES=()
FAILED_COUNT=0
SUCCESS_COUNT=0

# Deploy instances
for i in $(seq 1 $COUNT); do
  INSTANCE_NAME="${PREFIX}-${i}"
  LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.log"
  
  echo -e "${YELLOW}[$i/$COUNT] Deploying $INSTANCE_NAME...${NC}"
  
  # Deploy in background
  (
    ./scripts/deploy-instance.sh \
      --name $INSTANCE_NAME \
      --region $REGION \
      --instance-type $INSTANCE_TYPE \
      --model $BEDROCK_MODEL \
      --key-pair $KEY_PAIR \
      > $LOG_FILE 2>&1
    
    if [ $? -eq 0 ]; then
      echo "SUCCESS" >> $LOG_FILE
    else
      echo "FAILED" >> $LOG_FILE
    fi
  ) &
  
  PID=$!
  PIDS+=($PID)
  NAMES+=($INSTANCE_NAME)
  
  # Wait if we hit max parallel deployments
  if [ ${#PIDS[@]} -ge $PARALLEL_DEPLOYMENTS ]; then
    echo "  Waiting for parallel deployments to complete..."
    wait ${PIDS[0]}
    PIDS=("${PIDS[@]:1}")
  fi
  
  sleep 2  # Small delay between deployments
done

# Wait for all remaining deployments
echo ""
echo -e "${YELLOW}Waiting for all deployments to complete...${NC}"
for PID in "${PIDS[@]}"; do
  wait $PID
done

# Check results
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Deployment Results${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

for i in $(seq 0 $((COUNT-1))); do
  INSTANCE_NAME="${NAMES[$i]}"
  LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.log"
  
  if grep -q "SUCCESS" $LOG_FILE 2>/dev/null; then
    echo -e "${GREEN}✓ $INSTANCE_NAME - SUCCESS${NC}"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo -e "${RED}✗ $INSTANCE_NAME - FAILED${NC}"
    echo "  Log: $LOG_FILE"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo ""
echo -e "${GREEN}Success: $SUCCESS_COUNT${NC}"
echo -e "${RED}Failed: $FAILED_COUNT${NC}"
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
  echo -e "${GREEN}All instances deployed successfully! 🎉${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Check health: ./scripts/health-check.sh --all"
  echo "  2. Get access URLs: ./scripts/list-instances.sh"
  echo ""
else
  echo -e "${YELLOW}Some deployments failed. Check logs in: $LOG_DIR${NC}"
  echo ""
  echo "To retry failed deployments:"
  for i in $(seq 0 $((COUNT-1))); do
    INSTANCE_NAME="${NAMES[$i]}"
    LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.log"
    if ! grep -q "SUCCESS" $LOG_FILE 2>/dev/null; then
      echo "  ./scripts/deploy-instance.sh --name $INSTANCE_NAME --key-pair $KEY_PAIR"
    fi
  done
  echo ""
fi

# Save deployment summary
SUMMARY_FILE="$LOG_DIR/summary.txt"
cat > $SUMMARY_FILE << EOF
Batch Deployment Summary
========================
Date: $(date)
Count: $COUNT
Prefix: $PREFIX
Region: $REGION
Instance Type: $INSTANCE_TYPE
Bedrock Model: $BEDROCK_MODEL

Results:
Success: $SUCCESS_COUNT
Failed: $FAILED_COUNT

Instance List:
EOF

for i in $(seq 1 $COUNT); do
  INSTANCE_NAME="${PREFIX}-${i}"
  LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.log"
  if grep -q "SUCCESS" $LOG_FILE 2>/dev/null; then
    echo "✓ $INSTANCE_NAME" >> $SUMMARY_FILE
  else
    echo "✗ $INSTANCE_NAME" >> $SUMMARY_FILE
  fi
done

echo "Summary saved to: $SUMMARY_FILE"
