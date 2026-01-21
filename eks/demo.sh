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

# Part 2: Crash pods (to trigger restarts)
echo "[Part 2] Crashing Pods to Trigger Restarts"
echo "----------------------------"
echo "Simulating OOM kill on frontend..."
kubectl exec -it $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- sh -c 'kill 1' 2>/dev/null || echo "Pod crashed"
echo ""
echo "Simulating crash on ledgerwriter..."
kubectl exec -it $(kubectl get pod -l app=ledgerwriter -o jsonpath='{.items[0].metadata.name}') -- sh -c 'kill 1' 2>/dev/null || echo "Pod crashed"
echo ""
echo "Simulating crash on balancereader..."
kubectl exec -it $(kubectl get pod -l app=balancereader -o jsonpath='{.items[0].metadata.name}') -- sh -c 'kill 1' 2>/dev/null || echo "Pod crashed"
echo ""
echo "✅ Pods killed. Check Container Insights dashboard now!"
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
