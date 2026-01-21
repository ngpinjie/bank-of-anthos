#!/bin/bash
# Bank of Anthos EKS Deployment Script with Container Insights
# This script automates the deployment of Bank of Anthos on Amazon EKS

set -e  # Exit on any error

# Configuration
CLUSTER_NAME="bank-of-anthos"
REGION="us-east-1"
NODE_TYPE="t3.medium"
NODE_COUNT=3

echo "=========================================="
echo "Bank of Anthos EKS Deployment"
echo "=========================================="
echo ""

# Step 1: Create EKS Cluster
echo "[Step 1/6] Creating EKS cluster: $CLUSTER_NAME"
echo "This will take approximately 15-20 minutes..."
eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --nodegroup-name standard-workers \
  --node-type "$NODE_TYPE" \
  --nodes "$NODE_COUNT" \
  --managed

echo ""
echo "✓ Cluster created successfully"
echo ""

# Step 2: Enable OIDC Provider
echo "[Step 2/6] Enabling OIDC provider for IAM integration..."
eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --approve

echo ""
echo "✓ OIDC provider enabled"
echo ""

# Step 3: Install CloudWatch Observability Add-on
echo "[Step 3/6] Installing Amazon CloudWatch Observability add-on..."
eksctl create addon \
  --name amazon-cloudwatch-observability \
  --cluster "$CLUSTER_NAME" \
  --region "$REGION" \
  --force

echo ""
echo "✓ CloudWatch Observability add-on installed"
echo ""

# Step 4: Verify CloudWatch agents
echo "[Step 4/6] Verifying CloudWatch agents are running..."
echo "Waiting for CloudWatch pods to be ready (this may take 1-2 minutes)..."
kubectl wait --for=condition=ready pod \
  -l name=cloudwatch-agent \
  -n amazon-cloudwatch \
  --timeout=120s || echo "Warning: CloudWatch agent may still be initializing"

kubectl wait --for=condition=ready pod \
  -l k8s-app=fluent-bit \
  -n amazon-cloudwatch \
  --timeout=120s || echo "Warning: Fluent Bit may still be initializing"

echo ""
echo "CloudWatch agents status:"
kubectl get pods -n amazon-cloudwatch
echo ""
echo "✓ CloudWatch agents deployed"
echo ""

# Step 5: Deploy JWT Secret
echo "[Step 5/6] Deploying JWT secret..."
kubectl apply -f ../extras/jwt/jwt-secret.yaml

echo ""
echo "✓ JWT secret created"
echo ""

# Step 6: Deploy Bank of Anthos
echo "[Step 6/6] Deploying Bank of Anthos application..."
kubectl apply -f .

echo ""
echo "✓ Application manifests applied"
echo ""

# Wait for pods to be ready
echo "Waiting for pods to be ready (this may take 3-5 minutes)..."
echo ""

# Wait for databases first
kubectl wait --for=condition=ready pod \
  -l app=accounts-db \
  --timeout=300s

kubectl wait --for=condition=ready pod \
  -l app=ledger-db \
  --timeout=300s

echo "✓ Databases are ready"
echo ""

# Wait for all other pods
kubectl wait --for=condition=ready pod \
  -l application=bank-of-anthos \
  --timeout=300s

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

# Get pod status
echo "Pod Status:"
kubectl get pods
echo ""

# Get frontend service
echo "Waiting for frontend LoadBalancer (this may take 2-3 minutes)..."
echo ""

# Wait for external IP
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
    EXTERNAL_IP=$(kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -z "$EXTERNAL_IP" ]; then
        echo "Waiting for LoadBalancer IP assignment..."
        sleep 10
    fi
done

echo ""
echo "=========================================="
echo "Access Bank of Anthos:"
echo "=========================================="
echo ""
echo "URL: http://$EXTERNAL_IP"
echo ""
echo "Demo Login Credentials:"
echo "  Username: testuser"
echo "  Password: bankofanthos"
echo ""
echo "=========================================="
echo "Access Container Insights:"
echo "=========================================="
echo ""
echo "1. Go to AWS Console → CloudWatch"
echo "2. Click 'Container Insights' → 'Performance monitoring'"
echo "3. Select cluster: $CLUSTER_NAME"
echo ""
echo "CloudWatch Log Groups:"
echo "  - /aws/containerinsights/$CLUSTER_NAME/application"
echo "  - /aws/containerinsights/$CLUSTER_NAME/dataplane"
echo "  - /aws/containerinsights/$CLUSTER_NAME/host"
echo ""
echo "=========================================="
echo ""
