#!/bin/bash
# openclaw-connect-all.sh
# Connect to all OpenClaw instances via SSM port forwarding

set -e

REGION="us-west-2"

# Instance configuration (will be auto-populated)
declare -A INSTANCES=(
  ["INSTANCE_1_ID"]="18789:Instance-1"
  ["INSTANCE_2_ID"]="18790:Instance-2"
  ["INSTANCE_3_ID"]="18791:Instance-3"
)

echo "🚢 OpenClaw Fleet - Starting SSM Tunnels"
echo ""

# Kill existing port forwards
echo "Cleaning up existing tunnels..."
pkill -f "AWS-StartPortForwardingSession" 2>/dev/null || true
sleep 2

# Start tunnels in background
for IID in "${!INSTANCES[@]}"; do
  LOCAL_PORT=$(echo ${INSTANCES[$IID]} | cut -d: -f1)
  NAME=$(echo ${INSTANCES[$IID]} | cut -d: -f2)
  
  # Skip if instance ID is placeholder
  if [[ "$IID" == "INSTANCE_"*"_ID" ]]; then
    echo "⏭️  Skipping $NAME (not configured yet)"
    continue
  fi
  
  echo "🔌 Starting tunnel: $NAME → localhost:$LOCAL_PORT"
  
  aws ssm start-session \
    --region $REGION \
    --target $IID \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
    > /tmp/openclaw-$NAME.log 2>&1 &
  
  echo "   PID: $!"
done

echo ""
echo "✅ All tunnels started!"
echo ""
echo "📋 Access URLs:"
for IID in "${!INSTANCES[@]}"; do
  LOCAL_PORT=$(echo ${INSTANCES[$IID]} | cut -d: -f1)
  NAME=$(echo ${INSTANCES[$IID]} | cut -d: -f2)
  
  if [[ "$IID" != "INSTANCE_"*"_ID" ]]; then
    echo "   $NAME: http://localhost:$LOCAL_PORT/"
  fi
done
echo ""
echo "🌐 Dashboard: open dashboard/openclaw-dashboard.html"
echo ""
echo "Press Ctrl+C to stop all tunnels"

# Keep script running
trap "echo ''; echo 'Stopping all tunnels...'; pkill -f 'AWS-StartPortForwardingSession'; exit 0" SIGINT SIGTERM

# Wait for all background jobs
wait
