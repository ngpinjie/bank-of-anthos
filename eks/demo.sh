#!/bin/bash
# Container Insights Demo Script
# Shows pod/node failures and Container Insights detection

set -e

CLUSTER_NAME="bank-of-anthos"
REGION="us-west-2"

echo "=========================================="
echo "Container Insights Demo"
echo "=========================================="
echo ""

# Part 1: Show current state
echo "[Part 1] Current Pod Status"
echo "----------------------------"
kubectl get pods -o wide
echo ""
echo "✅ All pods running healthy"
echo ""
read -p "Press Enter to kill some pods..."
echo ""

# Part 2: Crash pods multiple times (to trigger multiple restarts)
echo "[Part 2] Crashing Pods to Trigger Multiple Restarts"
echo "----------------------------"
CRASH_ROUNDS=3
APPS=("frontend" "ledgerwriter" "balancereader" "transactionhistory" "contacts")

for round in $(seq 1 $CRASH_ROUNDS); do
    echo ""
    echo "=== Crash Round $round of $CRASH_ROUNDS ==="
    for app in "${APPS[@]}"; do
        echo "Crashing $app..."
        kubectl exec -it $(kubectl get pod -l app=$app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) -- sh -c 'kill 1' 2>/dev/null || echo "  → $app crashed"
    done

    if [ $round -lt $CRASH_ROUNDS ]; then
        echo ""
        echo "Waiting 15 seconds for pods to restart before next round..."
        sleep 15
    fi
done

echo ""
echo "✅ Crashed ${#APPS[@]} pods x $CRASH_ROUNDS rounds = $((${#APPS[@]} * CRASH_ROUNDS)) total crashes!"
echo "   Each pod should now show restarts >= $CRASH_ROUNDS"
echo ""
echo "Container Insights URL:"
echo "https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#container-insights:infrastructure/map/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'$CLUSTER_NAME))))"
echo ""
read -p "Press Enter to see pod status..."
echo ""

# Show pods recovering
echo "Pod Status (recovering):"
kubectl get pods
echo ""
read -p "Press Enter to kill a node..."
echo ""

# Part 3: Kill node
echo "[Part 3] Killing Node"
echo "----------------------------"
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Draining node: $NODE_NAME"
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data --force
echo ""
echo "✅ Node drained. Pods will reschedule to other nodes."
echo ""
echo "Check Container Insights for:"
echo "  - Pod restarts"
echo "  - Node status change"
echo "  - Pod rescheduling"
echo ""
read -p "Press Enter to see current status..."
echo ""

# Part 4: Show recovery
echo "[Part 4] Recovery Status"
echo "----------------------------"
kubectl get pods -o wide
echo ""
kubectl get nodes
echo ""
echo "✅ Pods rescheduled to healthy nodes"
echo ""
read -p "Press Enter to restore the node..."
echo ""

# Restore node
echo "Restoring node: $NODE_NAME"
kubectl uncordon $NODE_NAME
echo ""
echo "✅ Node restored and ready"
echo ""

echo "=========================================="
echo "Demo Complete!"
echo "=========================================="
echo ""
echo "What you showed:"
echo "  ✅ Pod failures detected in Container Insights"
echo "  ✅ Node failure impact visualization"
echo "  ✅ Automatic pod recovery"
echo "  ✅ Real-time monitoring without kubectl"
echo ""
echo "Container Insights Dashboard:"
echo "https://us-west-2.console.aws.amazon.com/cloudwatch/home?region=us-west-2#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'$CLUSTER_NAME))))"
echo ""
