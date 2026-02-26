#!/bin/bash
# setup-dashboard.sh
# Automatically configure dashboard and connection script after deployment

set -e

REGION="us-west-2"
STACK_NAME="openClawFleet"

echo "🔧 Configuring OpenClaw Fleet Dashboard..."
echo ""

# Get instance IDs from CloudFormation outputs
echo "📋 Fetching instance information..."
INSTANCES=$(aws cloudformation describe-stacks \
  --region $REGION \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?contains(OutputKey, `InstanceId`)].OutputValue' \
  --output text)

if [ -z "$INSTANCES" ]; then
  echo "❌ No instances found! Make sure the stack is deployed."
  exit 1
fi

# Convert to array
IFS=' ' read -ra INSTANCE_ARRAY <<< "$INSTANCES"
INSTANCE_COUNT=${#INSTANCE_ARRAY[@]}

echo "✅ Found $INSTANCE_COUNT instances"
echo ""

# Fetch tokens from SSM
echo "🔑 Fetching auth tokens..."
declare -A TOKENS
declare -A ICONS=( [0]="🦞" [1]="🦀" [2]="🦐" [3]="🦑" [4]="🐙" )

for i in "${!INSTANCE_ARRAY[@]}"; do
  INSTANCE_ID="${INSTANCE_ARRAY[$i]}"
  INSTANCE_NUM=$((i+1))
  LOCAL_PORT=$((18789+i))
  
  echo "  Instance $INSTANCE_NUM: $INSTANCE_ID"
  
  TOKEN=$(aws ssm get-parameter \
    --region $REGION \
    --name /openclaw/openclaw-$INSTANCE_NUM/token \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")
  
  if [ -z "$TOKEN" ]; then
    echo "    ⚠️  Token not found yet (instance may still be initializing)"
    TOKEN="Token not ready yet"
  else
    echo "    ✅ Token retrieved"
  fi
  
  TOKENS[$i]="$TOKEN"
done

echo ""
echo "📝 Generating dashboard..."

# Generate JavaScript instances array
INSTANCES_JS="    const instances = [\n"
for i in "${!INSTANCE_ARRAY[@]}"; do
  INSTANCE_ID="${INSTANCE_ARRAY[$i]}"
  INSTANCE_NUM=$((i+1))
  LOCAL_PORT=$((18789+i))
  TOKEN="${TOKENS[$i]}"
  ICON="${ICONS[$i]}"
  
  INSTANCES_JS+="      {\n"
  INSTANCES_JS+="        name: 'Instance $INSTANCE_NUM',\n"
  INSTANCES_JS+="        icon: '$ICON',\n"
  INSTANCES_JS+="        id: '$INSTANCE_ID',\n"
  INSTANCES_JS+="        port: $LOCAL_PORT,\n"
  INSTANCES_JS+="        token: '$TOKEN'\n"
  INSTANCES_JS+="      }"
  
  if [ $i -lt $((INSTANCE_COUNT-1)) ]; then
    INSTANCES_JS+=","
  fi
  INSTANCES_JS+="\n"
done
INSTANCES_JS+="    ];"

# Update dashboard HTML
sed -i.bak "/const instances = \[/,/\];/c\\
$INSTANCES_JS" dashboard/openclaw-dashboard.html

echo "✅ Dashboard updated: dashboard/openclaw-dashboard.html"
echo ""

# Update connection script
echo "📝 Generating connection script..."

SCRIPT_INSTANCES="declare -A INSTANCES=(\n"
for i in "${!INSTANCE_ARRAY[@]}"; do
  INSTANCE_ID="${INSTANCE_ARRAY[$i]}"
  INSTANCE_NUM=$((i+1))
  LOCAL_PORT=$((18789+i))
  
  SCRIPT_INSTANCES+="  [\"$INSTANCE_ID\"]=\"$LOCAL_PORT:Instance-$INSTANCE_NUM\"\n"
done
SCRIPT_INSTANCES+=")"

sed -i.bak "/declare -A INSTANCES=(/,/)/c\\
$SCRIPT_INSTANCES" scripts/openclaw-connect-all.sh

echo "✅ Connection script updated: scripts/openclaw-connect-all.sh"
echo ""
echo "🎉 Setup complete!"
echo ""
echo "📖 Next steps:"
echo "  1. Run: ./scripts/openclaw-connect-all.sh"
echo "  2. Open: dashboard/openclaw-dashboard.html"
echo "  3. Click on any instance to access OpenClaw!"
echo ""
