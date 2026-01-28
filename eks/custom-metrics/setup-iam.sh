#!/bin/bash
# =============================================================================
# Setup IAM Role for ADOT Collector
# =============================================================================
# Creates an IAM role with IRSA (IAM Roles for Service Accounts) that allows
# the ADOT collector to write metrics to CloudWatch.
#
# Prerequisites:
#   - AWS CLI configured
#   - kubectl configured for EKS cluster
#   - OIDC provider associated with cluster
#
# Usage:
#   ./setup-iam.sh
# =============================================================================

set -e

AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-bank-of-anthos}"
ROLE_NAME="adot-collector-cloudwatch-role"
NAMESPACE="default"
SERVICE_ACCOUNT="adot-collector"

echo "============================================="
echo "  ADOT Collector IAM Setup"
echo "============================================="
echo ""

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account:  $ACCOUNT_ID"
echo "Region:   $AWS_REGION"
echo "Cluster:  $CLUSTER_NAME"
echo ""

# Get OIDC provider
OIDC_PROVIDER=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --query "cluster.identity.oidc.issuer" \
    --output text | sed 's|https://||')

if [ -z "$OIDC_PROVIDER" ]; then
    echo "Error: Could not get OIDC provider for cluster $CLUSTER_NAME"
    exit 1
fi

echo "OIDC:     $OIDC_PROVIDER"
echo ""

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
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}"
        }
      }
    }
  ]
}
EOF
)

# Create or update IAM role
echo "Creating IAM role: $ROLE_NAME"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "  Role exists, updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY"
else
    echo "  Creating new role..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "ADOT Collector role for CloudWatch access" \
        --output text --query 'Role.Arn'
fi

# Attach CloudWatch policy
echo "Attaching CloudWatchAgentServerPolicy..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "============================================="
echo "  IAM Role Created"
echo "============================================="
echo ""
echo "Role ARN: $ROLE_ARN"
echo ""

# Annotate ServiceAccount
echo "Annotating ServiceAccount..."
kubectl annotate serviceaccount "$SERVICE_ACCOUNT" \
    --namespace="$NAMESPACE" \
    "eks.amazonaws.com/role-arn=$ROLE_ARN" \
    --overwrite 2>/dev/null || echo "  ServiceAccount not found yet (will be created by deploy.sh)"

echo ""
echo "Done. Run ./deploy.sh to deploy the ADOT collector."
echo ""
