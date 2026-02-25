#!/bin/bash
# OpenClaw Multi-Deployment - Foundation Deployment Script
# This script deploys the VPC and shared resources (one-time setup)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
REGION="us-west-2"
STACK_NAME="openclaw-foundation"
SHARED_STACK_NAME="openclaw-shared"
KEY_PAIR=""
ENABLE_NAT_REDUNDANCY="false"
ENABLE_VPC_FLOW_LOGS="true"
ENABLE_VPC_ENDPOINTS="true"
CERTIFICATE_ARN=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      REGION="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --key-pair)
      KEY_PAIR="$2"
      shift 2
      ;;
    --nat-redundancy)
      ENABLE_NAT_REDUNDANCY="true"
      shift
      ;;
    --no-flow-logs)
      ENABLE_VPC_FLOW_LOGS="false"
      shift
      ;;
    --no-vpc-endpoints)
      ENABLE_VPC_ENDPOINTS="false"
      shift
      ;;
    --certificate-arn)
      CERTIFICATE_ARN="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --region REGION             AWS region (default: us-west-2)"
      echo "  --stack-name NAME           CloudFormation stack name (default: openclaw-foundation)"
      echo "  --key-pair NAME             EC2 key pair name (required)"
      echo "  --nat-redundancy            Enable NAT Gateway in both AZs (costs 2x)"
      echo "  --no-flow-logs              Disable VPC Flow Logs (saves ~$10/mo)"
      echo "  --no-vpc-endpoints          Disable VPC Endpoints (saves $21.60/mo)"
      echo "  --certificate-arn ARN       ACM certificate ARN for HTTPS"
      echo "  --help                      Show this help message"
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

# Get availability zones
echo -e "${YELLOW}Fetching availability zones in ${REGION}...${NC}"
AZ1=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[0].ZoneName' --output text)
AZ2=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[1].ZoneName' --output text)

echo -e "${GREEN}✓ Using AZ1: ${AZ1}, AZ2: ${AZ2}${NC}"

# Calculate cost estimate
NAT_COST=$([ "$ENABLE_NAT_REDUNDANCY" = "true" ] && echo "64.80" || echo "32.40")
FLOW_LOG_COST=$([ "$ENABLE_VPC_FLOW_LOGS" = "true" ] && echo "10" || echo "0")
VPC_ENDPOINT_COST=$([ "$ENABLE_VPC_ENDPOINTS" = "true" ] && echo "21.60" || echo "0")
TOTAL_COST=$(echo "$NAT_COST + $FLOW_LOG_COST + $VPC_ENDPOINT_COST + 16.20" | bc)

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  OpenClaw Multi-Deployment - Foundation Setup${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Configuration:"
echo "  Region: $REGION"
echo "  Stack Name: $STACK_NAME"
echo "  Key Pair: $KEY_PAIR"
echo "  NAT Redundancy: $ENABLE_NAT_REDUNDANCY"
echo "  VPC Flow Logs: $ENABLE_VPC_FLOW_LOGS"
echo "  VPC Endpoints: $ENABLE_VPC_ENDPOINTS"
echo "  Certificate: ${CERTIFICATE_ARN:-None (HTTP only)}"
echo ""
echo -e "${GREEN}Monthly Cost Estimate:${NC}"
echo "  NAT Gateway: \$$NAT_COST"
echo "  VPC Flow Logs: \$$FLOW_LOG_COST"
echo "  VPC Endpoints: \$$VPC_ENDPOINT_COST"
echo "  ALB: \$16.20"
echo -e "${GREEN}  Total: \$$TOTAL_COST/month${NC}"
echo ""
read -p "Continue with deployment? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Deployment cancelled."
  exit 0
fi

# Step 1: Deploy VPC Foundation
echo ""
echo -e "${YELLOW}Step 1/2: Deploying VPC Foundation...${NC}"

aws cloudformation create-stack \
  --region $REGION \
  --stack-name $STACK_NAME \
  --template-body file://cloudformation/01-vpc-foundation.yaml \
  --parameters \
    ParameterKey=AvailabilityZone1,ParameterValue=$AZ1 \
    ParameterKey=AvailabilityZone2,ParameterValue=$AZ2 \
    ParameterKey=EnableNATGatewayRedundancy,ParameterValue=$ENABLE_NAT_REDUNDANCY \
    ParameterKey=EnableVPCFlowLogs,ParameterValue=$ENABLE_VPC_FLOW_LOGS \
  --capabilities CAPABILITY_IAM \
  --tags Key=Project,Value=OpenClaw-Multi

echo -e "${GREEN}✓ VPC stack creation initiated${NC}"
echo "Waiting for VPC stack to complete (this may take 5-10 minutes)..."

aws cloudformation wait stack-create-complete \
  --region $REGION \
  --stack-name $STACK_NAME

echo -e "${GREEN}✓ VPC Foundation deployed successfully!${NC}"

# Step 2: Deploy Shared Resources
echo ""
echo -e "${YELLOW}Step 2/2: Deploying Shared Resources (ALB, VPC Endpoints)...${NC}"

SHARED_PARAMS="ParameterKey=FoundationStackName,ParameterValue=$STACK_NAME ParameterKey=EnableVPCEndpoints,ParameterValue=$ENABLE_VPC_ENDPOINTS"

if [ -n "$CERTIFICATE_ARN" ]; then
  SHARED_PARAMS="$SHARED_PARAMS ParameterKey=CertificateArn,ParameterValue=$CERTIFICATE_ARN"
fi

aws cloudformation create-stack \
  --region $REGION \
  --stack-name $SHARED_STACK_NAME \
  --template-body file://cloudformation/02-shared-resources.yaml \
  --parameters $SHARED_PARAMS \
  --capabilities CAPABILITY_IAM \
  --tags Key=Project,Value=OpenClaw-Multi

echo -e "${GREEN}✓ Shared resources stack creation initiated${NC}"
echo "Waiting for shared resources stack to complete (this may take 3-5 minutes)..."

aws cloudformation wait stack-create-complete \
  --region $REGION \
  --stack-name $SHARED_STACK_NAME

echo -e "${GREEN}✓ Shared Resources deployed successfully!${NC}"

# Get outputs
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deployment Complete! 🎉${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""

ALB_URL=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name $SHARED_STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
  --output text)

VPC_ID=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' \
  --output text)

echo "Foundation Details:"
echo "  VPC ID: $VPC_ID"
echo "  ALB URL: $ALB_URL"
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "  1. Deploy OpenClaw instances:"
echo "     ./scripts/deploy-instance.sh --name openclaw-prod-1"
echo ""
echo "  2. Or deploy multiple instances at once:"
echo "     ./scripts/deploy-batch.sh --count 5 --prefix openclaw-prod"
echo ""
echo "  3. Access the management dashboard:"
echo "     aws cloudformation describe-stacks --region $REGION --stack-name $SHARED_STACK_NAME"
echo ""
echo -e "${YELLOW}Foundation is ready for OpenClaw deployments!${NC}"
