#!/bin/bash
# Bank of Anthos EKS Cleanup Script
# This script removes all Bank of Anthos resources and the EKS cluster

set -e  # Exit on any error

# Configuration
CLUSTER_NAME="bank-of-anthos"
REGION="us-east-1"

echo "=========================================="
echo "Bank of Anthos EKS Cleanup"
echo "=========================================="
echo ""
echo "This will delete:"
echo "  - Bank of Anthos application"
echo "  - JWT secrets"
echo "  - CloudWatch Observability add-on"
echo "  - EKS cluster: $CLUSTER_NAME"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Step 1: Delete Bank of Anthos application
echo "[Step 1/4] Deleting Bank of Anthos application..."
kubectl delete -f . --ignore-not-found=true || true
kubectl delete -f ../extras/jwt/jwt-secret.yaml --ignore-not-found=true || true

echo ""
echo "✓ Application deleted"
echo ""

# Step 2: Wait for LoadBalancer to be deleted
echo "[Step 2/4] Waiting for LoadBalancer to be deleted..."
echo "This ensures AWS resources are cleaned up properly..."
sleep 30

echo ""
echo "✓ LoadBalancer cleanup complete"
echo ""

# Step 3: Delete CloudWatch Observability add-on
echo "[Step 3/4] Deleting CloudWatch Observability add-on..."
eksctl delete addon \
  --cluster "$CLUSTER_NAME" \
  --name amazon-cloudwatch-observability \
  --region "$REGION" || echo "Warning: Add-on may already be deleted"

echo ""
echo "✓ CloudWatch add-on deleted"
echo ""

# Step 4: Delete EKS cluster
echo "[Step 4/4] Deleting EKS cluster: $CLUSTER_NAME"
echo "This will take approximately 10-15 minutes..."
eksctl delete cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION"

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "All resources have been deleted."
echo "Please verify in AWS Console:"
echo "  - EKS: No cluster named '$CLUSTER_NAME'"
echo "  - EC2: No instances/load balancers from the cluster"
echo "  - CloudWatch: Log groups can be manually deleted if desired"
echo ""
