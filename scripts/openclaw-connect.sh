#!/bin/bash
# openclaw-connect.sh - Connect to OpenClaw instances via SSM

REGION="us-west-2"

# Instance configuration
declare -A INSTANCES=(
  ["i-0773b8764b3191320"]="18789:Instance-1:fc48b4da71da72bda6f3203c886d3c0d1480b002fe94f1423a19cc0a6a3861ea"
  ["i-034442ecf0a8c479e"]="18790:Instance-2:PENDING"
  ["i-034409e958a306fed"]="18791:Instance-3:a4414709e22799c42a83a6b530bf0fe2e3e4a731511ba25ccb2e089debf423d0"
)

echo "🚢 OpenClaw Fleet - SSM Connection"
echo ""
echo "Select instance to connect:"
echo ""

# Create menu
PS3="Enter number: "
select CHOICE in "Instance 1 (localhost:18789)" "Instance 2 (localhost:18790)" "Instance 3 (localhost:18791)" "Connect ALL" "Quit"; do
  case $CHOICE in
    "Instance 1 (localhost:18789)")
      IID="i-0773b8764b3191320"
      PORT="18789"
      TOKEN="fc48b4da71da72bda6f3203c886d3c0d1480b002fe94f1423a19cc0a6a3861ea"
      echo ""
      echo "🔌 Connecting to Instance 1..."
      echo "📋 Access URL: http://localhost:$PORT/?token=$TOKEN"
      echo ""
      aws ssm start-session \
        --region $REGION \
        --target $IID \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"$PORT\"]}"
      break
      ;;
    "Instance 2 (localhost:18790)")
      IID="i-034442ecf0a8c479e"
      PORT="18790"
      TOKEN="PENDING"
      echo ""
      echo "⚠️  Instance 2 token is still initializing"
      echo "🔌 Connecting anyway..."
      echo "📋 Access URL: http://localhost:$PORT/ (enter token manually)"
      echo ""
      aws ssm start-session \
        --region $REGION \
        --target $IID \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"$PORT\"]}"
      break
      ;;
    "Instance 3 (localhost:18791)")
      IID="i-034409e958a306fed"
      PORT="18791"
      TOKEN="a4414709e22799c42a83a6b530bf0fe2e3e4a731511ba25ccb2e089debf423d0"
      echo ""
      echo "🔌 Connecting to Instance 3..."
      echo "📋 Access URL: http://localhost:$PORT/?token=$TOKEN"
      echo ""
      aws ssm start-session \
        --region $REGION \
        --target $IID \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"$PORT\"]}"
      break
      ;;
    "Connect ALL")
      echo ""
      echo "🔌 Connecting to all instances..."
      echo ""
      
      # Instance 1
      echo "Starting Instance 1..."
      aws ssm start-session \
        --region $REGION \
        --target i-0773b8764b3191320 \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}' \
        > /tmp/openclaw-1.log 2>&1 &
      
      # Instance 2
      echo "Starting Instance 2..."
      aws ssm start-session \
        --region $REGION \
        --target i-034442ecf0a8c479e \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["18789"],"localPortNumber":["18790"]}' \
        > /tmp/openclaw-2.log 2>&1 &
      
      # Instance 3
      echo "Starting Instance 3..."
      aws ssm start-session \
        --region $REGION \
        --target i-034409e958a306fed \
        --document-name AWS-StartPortForwardingSession \
        --parameters '{"portNumber":["18789"],"localPortNumber":["18791"]}' \
        > /tmp/openclaw-3.log 2>&1 &
      
      echo ""
      echo "✅ All tunnels started in background!"
      echo ""
      echo "📋 Access URLs:"
      echo "  Instance 1: http://localhost:18789/?token=fc48b4da71da72bda6f3203c886d3c0d1480b002fe94f1423a19cc0a6a3861ea"
      echo "  Instance 2: http://localhost:18790/ (token pending)"
      echo "  Instance 3: http://localhost:18791/?token=a4414709e22799c42a83a6b530bf0fe2e3e4a731511ba25ccb2e089debf423d0"
      echo ""
      echo "Press Ctrl+C to stop all tunnels"
      trap "pkill -f 'AWS-StartPortForwardingSession'; exit" SIGINT SIGTERM
      wait
      break
      ;;
    "Quit")
      echo "Bye!"
      break
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
done
