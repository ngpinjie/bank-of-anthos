#!/bin/bash
# =============================================================================
# Deploy Custom Metrics Demo
# =============================================================================
# Deploys the ADOT collector and userservice with custom metrics support.
#
# Prerequisites:
#   1. Run ./setup-iam.sh first to create IAM role
#   2. Build and push userservice image (see README.md)
#
# Usage:
#   ./deploy.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ECR_REPO="${ECR_REPO:-131676642557.dkr.ecr.us-west-2.amazonaws.com/bank-of-anthos}"

echo "============================================="
echo "  Custom Metrics Demo - Deployment"
echo "============================================="
echo ""

# Step 1: Deploy ADOT Collector
echo "[1/4] Deploying ADOT Collector..."
kubectl apply -f "$SCRIPT_DIR/adot-collector.yaml"
kubectl rollout status deployment/adot-collector --timeout=60s
echo "      Done."

# Step 2: Deploy Instrumentation
echo ""
echo "[2/4] Deploying Instrumentation resource..."
kubectl apply -f "$SCRIPT_DIR/instrumentation.yaml"
echo "      Done."

# Step 3: Update userservice image
echo ""
echo "[3/4] Updating userservice image..."
echo "      Image: $ECR_REPO:userservice-custom-metrics"
kubectl set image deployment/userservice userservice="$ECR_REPO:userservice-custom-metrics"

# Step 4: Restart userservice to apply Instrumentation
echo ""
echo "[4/4] Restarting userservice..."
kubectl rollout restart deployment/userservice
kubectl rollout status deployment/userservice --timeout=120s
echo "      Done."

# Verify
echo ""
echo "============================================="
echo "  Verification"
echo "============================================="
echo ""
echo "ADOT Collector:"
kubectl get pods -l app=adot-collector --no-headers
echo ""
echo "Userservice:"
kubectl get pods -l app=userservice --no-headers
echo ""

# Check for custom metrics log
echo "Checking userservice logs..."
sleep 3
if kubectl logs -l app=userservice --tail=50 2>/dev/null | grep -q "Setting up custom OpenTelemetry metrics"; then
    echo "Custom metrics code is running."
else
    echo "Warning: Custom metrics log not found (may take a moment)."
fi

echo ""
echo "============================================="
echo "  Deployment Complete"
echo "============================================="
echo ""
echo "Next steps:"
echo "  1. Generate traffic:  ./generate-load.sh"
echo "  2. View metrics:      CloudWatch → Metrics → BankOfAnthos"
echo ""
