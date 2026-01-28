#!/bin/bash
# Deploy self-hosted Grafana on EKS with CloudWatch/Container Insights data source

set -e

CLUSTER_NAME="${CLUSTER_NAME:-bank-of-anthos}"
REGION="${REGION:-us-west-2}"
NAMESPACE="grafana"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Deploying Grafana to EKS"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Region:  $REGION"
echo ""

# Step 1: Get AWS Account ID
echo "[1/6] Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  Account ID: $ACCOUNT_ID"

# Step 2: Create IAM policy for Grafana
echo ""
echo "[2/6] Creating IAM policy for CloudWatch access..."
POLICY_NAME="GrafanaCloudWatchPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

# Check if policy exists
if aws iam get-policy --policy-arn "$POLICY_ARN" 2>/dev/null; then
    echo "  Policy already exists: $POLICY_ARN"
else
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://${SCRIPT_DIR}/iam-policy.json \
        --description "Allows Grafana to read CloudWatch metrics and logs"
    echo "  Created policy: $POLICY_ARN"
fi

# Step 3: Create IRSA role for Grafana
echo ""
echo "[3/6] Creating IRSA role for Grafana service account..."
ROLE_NAME="GrafanaCloudWatchRole"

# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
    --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

if [ -z "$OIDC_PROVIDER" ]; then
    echo "ERROR: Could not get OIDC provider. Make sure OIDC is associated with the cluster."
    echo "Run: eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve"
    exit 1
fi

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:grafana"
        }
      }
    }
  ]
}
EOF
)

# Create or update role
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo "  Role already exists, updating trust policy..."
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document "$TRUST_POLICY"
else
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "IRSA role for Grafana to access CloudWatch"
    echo "  Created role: $ROLE_NAME"
fi

# Attach policy to role
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
echo "  Attached policy to role"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "  Role ARN: $ROLE_ARN"

# Step 4: Create namespace and ConfigMap for dashboards
echo ""
echo "[4/6] Creating Kubernetes namespace and dashboard ConfigMap..."
kubectl create namespace "$NAMESPACE" 2>/dev/null || echo "  Namespace already exists"

# Create ConfigMap from dashboard JSON
kubectl create configmap grafana-dashboards \
    --from-file=container-insights.json=${SCRIPT_DIR}/dashboards/container-insights.json \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "  Dashboard ConfigMap created"

# Step 5: Add Helm repo and install Grafana
echo ""
echo "[5/6] Installing Grafana via Helm..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Create temporary values file with IRSA annotation
TEMP_VALUES=$(mktemp)
cat ${SCRIPT_DIR}/values.yaml > "$TEMP_VALUES"

# Update region in values
sed -i "s/defaultRegion: us-west-2/defaultRegion: $REGION/g" "$TEMP_VALUES"

helm upgrade --install grafana grafana/grafana \
    --namespace "$NAMESPACE" \
    --values "$TEMP_VALUES" \
    --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=$ROLE_ARN" \
    --wait

rm -f "$TEMP_VALUES"
echo "  Grafana installed"

# Step 6: Get access info
echo ""
echo "[6/6] Getting Grafana access information..."
echo ""
echo "Waiting for LoadBalancer IP..."
sleep 10

GRAFANA_URL=""
for i in {1..30}; do
    GRAFANA_URL=$(kubectl get svc grafana -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -n "$GRAFANA_URL" ]; then
        break
    fi
    echo "  Waiting for LoadBalancer... ($i/30)"
    sleep 5
done

echo ""
echo "=========================================="
echo "Grafana Deployment Complete!"
echo "=========================================="
echo ""
if [ -n "$GRAFANA_URL" ]; then
    echo "Grafana URL: http://${GRAFANA_URL}"
else
    echo "Grafana URL: (pending - run: kubectl get svc grafana -n $NAMESPACE)"
fi
echo ""
echo "Credentials:"
echo "  Username: admin"
echo "  Password: grafana-admin"
echo ""
echo "The Container Insights dashboard is pre-loaded at:"
echo "  Dashboards > Container Insights > EKS Container Insights"
echo ""
echo "Dashboard shows:"
echo "  - Cluster CPU/Memory utilization"
echo "  - Pod restart counts (from your demo!)"
echo "  - Pod CPU/Memory by pod"
echo "  - Node health metrics"
echo ""
