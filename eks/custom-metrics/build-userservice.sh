#!/bin/bash
# =============================================================================
# Build Userservice with Custom Metrics
# =============================================================================
# Builds the userservice Docker image with custom OpenTelemetry metrics code.
#
# Usage:
#   ./build-userservice.sh
#   docker push $ECR_REPO:userservice-custom-metrics
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVICE_DIR="$PROJECT_ROOT/src/accounts/userservice"

ECR_REPO="${ECR_REPO:-131676642557.dkr.ecr.us-west-2.amazonaws.com/bank-of-anthos}"
IMAGE_TAG="userservice-custom-metrics"

echo "============================================="
echo "  Build Userservice with Custom Metrics"
echo "============================================="
echo ""
echo "Source:  $SERVICE_DIR"
echo "Image:   $ECR_REPO:$IMAGE_TAG"
echo ""

cd "$SERVICE_DIR"

echo "Building Docker image..."
docker build -t "userservice:custom-metrics" .

echo "Tagging for ECR..."
docker tag "userservice:custom-metrics" "$ECR_REPO:$IMAGE_TAG"

echo ""
echo "============================================="
echo "  Build Complete"
echo "============================================="
echo ""
echo "Next step - push to ECR:"
echo "  docker push $ECR_REPO:$IMAGE_TAG"
echo ""
