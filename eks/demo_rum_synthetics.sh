#!/bin/bash
# CloudWatch RUM and Synthetics Demo Script
# Sets up Real User Monitoring and Synthetic Canaries for Bank of Anthos
#
# Prerequisites:
#   - AWS CLI configured
#   - EKS cluster with Bank of Anthos deployed
#   - Frontend accessible via LoadBalancer

set -e

CLUSTER_NAME="bank-of-anthos"
REGION="us-west-2"
APP_NAME="bank-of-anthos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1" >&2; }

# Get AWS Account ID
get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

# Get frontend URL
get_frontend_url() {
    local url=$(kubectl get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    if [ -z "$url" ]; then
        url=$(kubectl get svc frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    fi
    echo "http://${url}"
}

# Create S3 bucket for Synthetics artifacts
create_synthetics_bucket() {
    local bucket_name="cw-syn-results-${ACCOUNT_ID}-${REGION}"

    log_info "Creating S3 bucket for Synthetics: ${bucket_name}"

    if aws s3api head-bucket --bucket "$bucket_name" --region "$REGION" 2>/dev/null 1>&2; then
        log_info "Bucket already exists"
    else
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$bucket_name" --region "$REGION" 2>&1 1>&2
        else
            aws s3api create-bucket --bucket "$bucket_name" --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION" 2>&1 1>&2
        fi
        log_success "Bucket created: ${bucket_name}"
    fi

    echo "$bucket_name"
}

# Create IAM role for Synthetics
create_synthetics_role() {
    local role_name="CloudWatchSyntheticsRole-${APP_NAME}"

    log_info "Creating IAM role for Synthetics: ${role_name}"

    # Check if role exists
    if aws iam get-role --role-name "$role_name" 2>/dev/null 1>&2; then
        log_info "Role already exists"
        echo "$role_name"
        return
    fi

    # Create trust policy
    cat > /tmp/synthetics-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document file:///tmp/synthetics-trust-policy.json \
        --description "Role for CloudWatch Synthetics canaries" 2>&1 1>&2

    # Attach policies
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchSyntheticsFullAccess" 2>&1 1>&2

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>&1 1>&2

    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess" 2>&1 1>&2

    log_success "Role created: ${role_name}"

    # Wait for role to propagate
    sleep 10

    echo "$role_name"
}

# Create a Synthetics canary
create_canary() {
    local canary_name=$1
    local script_file=$2
    local runtime="syn-nodejs-puppeteer-9.1"

    log_info "Creating canary: ${canary_name}"

    # Check if canary exists
    if aws synthetics get-canary --name "$canary_name" --region "$REGION" 2>/dev/null; then
        log_info "Canary ${canary_name} already exists, updating..."
        aws synthetics delete-canary --name "$canary_name" --region "$REGION" 2>/dev/null || true
        sleep 10
    fi

    # Create zip file for canary (cross-platform: works on Windows and Linux)
    local zip_dir="${SCRIPT_DIR}/observability/.tmp/${canary_name}"
    local zip_file="${SCRIPT_DIR}/observability/.tmp/${canary_name}.zip"

    # Clean up and create directory structure
    rm -rf "$zip_dir" "$zip_file" 2>/dev/null || true
    mkdir -p "$zip_dir/nodejs/node_modules"
    
    # Copy script to node_modules directory (required by Synthetics)
    cp "${SCRIPT_DIR}/observability/canaries/${script_file}" "$zip_dir/nodejs/node_modules/${script_file}"

    # Create zip (try multiple methods for cross-platform support)
    if command -v zip &> /dev/null; then
        # Linux/Mac with zip
        cd "$zip_dir" && zip -r "$zip_file" nodejs/
        cd - > /dev/null
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]; then
        # Windows - convert paths and use PowerShell
        local win_zip_dir=$(cygpath -w "$zip_dir" 2>/dev/null || echo "$zip_dir" | sed 's|/|\\|g')
        local win_zip_file=$(cygpath -w "$zip_file" 2>/dev/null || echo "$zip_file" | sed 's|/|\\|g')
        powershell.exe -Command "Compress-Archive -Path '${win_zip_dir}\\nodejs' -DestinationPath '${win_zip_file}' -Force"
    elif command -v powershell &> /dev/null; then
        powershell -Command "Compress-Archive -Path '$zip_dir/nodejs' -DestinationPath '$zip_file' -Force"
    elif command -v pwsh &> /dev/null; then
        pwsh -Command "Compress-Archive -Path '$zip_dir/nodejs' -DestinationPath '$zip_file' -Force"
    else
        log_error "No zip tool available. Install 'zip' or use PowerShell."
        return 1
    fi

    # Upload to S3
    aws s3 cp "$zip_file" "s3://${SYNTHETICS_BUCKET}/canary-scripts/${canary_name}.zip"

    # Cleanup temp files
    rm -rf "$zip_dir" "$zip_file" 2>/dev/null || true

    # Create canary
    aws synthetics create-canary \
        --name "$canary_name" \
        --artifact-s3-location "s3://${SYNTHETICS_BUCKET}/canary-artifacts/${canary_name}" \
        --execution-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${SYNTHETICS_ROLE}" \
        --schedule "Expression=rate(5 minutes)" \
        --runtime-version "$runtime" \
        --code "S3Bucket=${SYNTHETICS_BUCKET},S3Key=canary-scripts/${canary_name}.zip,Handler=${script_file%.js}.handler" \
        --run-config "TimeoutInSeconds=120,EnvironmentVariables={FRONTEND_URL=${FRONTEND_URL},TEST_USERNAME=testuser,TEST_PASSWORD=bankofanthos}" \
        --region "$REGION"

    log_success "Canary created: ${canary_name}"

    # Start the canary (wait longer for creation to complete)
    log_info "Waiting for canary to be ready..."
    sleep 15
    aws synthetics start-canary --name "$canary_name" --region "$REGION"
    log_success "Canary started: ${canary_name}"
}

# Create CloudWatch RUM App Monitor
create_rum_monitor() {
    local app_name="${APP_NAME}-rum"

    log_info "Creating CloudWatch RUM App Monitor: ${app_name}"

    # Check if exists
    if aws rum get-app-monitor --name "$app_name" --region "$REGION" 2>/dev/null; then
        log_info "RUM App Monitor already exists"
        RUM_APP_ID=$(aws rum get-app-monitor --name "$app_name" --region "$REGION" --query 'AppMonitor.Id' --output text)
        return
    fi

    # Create RUM app monitor
    local result=$(aws rum create-app-monitor \
        --name "$app_name" \
        --domain "${FRONTEND_URL#http://}" \
        --region "$REGION" \
        --app-monitor-configuration '{
            "AllowCookies": true,
            "EnableXRay": false,
            "SessionSampleRate": 1.0,
            "Telemetries": ["errors", "performance", "http"]
        }' \
        --output json)

    RUM_APP_ID=$(echo "$result" | jq -r '.Id')
    log_success "RUM App Monitor created: ${app_name} (ID: ${RUM_APP_ID})"

    # Get the JavaScript snippet
    log_info "Fetching RUM JavaScript snippet..."
    local snippet_info=$(aws rum get-app-monitor --name "$app_name" --region "$REGION" --output json)

    echo ""
    log_warning "==========================================="
    log_warning "RUM JAVASCRIPT SNIPPET"
    log_warning "==========================================="
    echo ""
    echo "Add this script tag to your HTML <head> section:"
    echo "(src/frontend/templates/shared/html_head.html)"
    echo ""
    cat << EOF
<script>
(function(n,i,v,r,s,c,x,z){x=window.AwsRumClient={q:[],n:n,i:i,v:v,r:r,c:c};window[n]=function(c,p){x.q.push({c:c,p:p});};z=document.createElement('script');z.async=true;z.src=s;document.head.insertBefore(z,document.head.getElementsByTagName('script')[0]);})('cwr','${RUM_APP_ID}','1.0.0','${REGION}','https://client.rum.us-east-1.amazonaws.com/1.18.0/cwr.js',{sessionSampleRate:1,identityPoolId:'${REGION}:00000000-0000-0000-0000-000000000000',endpoint:'https://dataplane.rum.${REGION}.amazonaws.com',telemetries:['performance','errors','http'],allowCookies:true,enableXRay:false});
</script>
EOF
    echo ""
    log_warning "==========================================="
}

# Display setup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "RUM & Synthetics Setup Complete!"
    echo "=========================================="
    echo ""
    echo "FRONTEND URL: ${FRONTEND_URL}"
    echo ""
    echo "SYNTHETICS CANARIES:"
    echo "  - heartbeat-boa        : Simple HTTP check (every 5 min)"
    echo "  - api-health-boa       : API endpoint checks (every 5 min)"
    echo "  - login-flow-boa       : Login workflow test (every 5 min)"
    echo "  - transaction-flow-boa : Transaction workflow test (every 5 min)"
    echo ""
    echo "CLOUDWATCH DASHBOARDS:"
    echo ""
    echo "Synthetics Dashboard:"
    echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#synthetics:canary/list"
    echo ""
    echo "RUM Dashboard:"
    echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#rum:dashboard/application/${RUM_APP_ID:-'check-console'}"
    echo ""
    echo "Container Insights:"
    echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'${CLUSTER_NAME}'))))"
    echo ""
}

# Cleanup function
cleanup_resources() {
    log_warning "Cleaning up RUM and Synthetics resources..."

    # Delete canaries
    for canary in "heartbeat-boa" "login-flow-boa" "api-health-boa" "transaction-flow-boa"; do
        log_info "Deleting canary: ${canary}"
        aws synthetics stop-canary --name "$canary" --region "$REGION" 2>/dev/null || true
        sleep 5
        aws synthetics delete-canary --name "$canary" --region "$REGION" 2>/dev/null || true
    done

    # Delete RUM app monitor
    log_info "Deleting RUM app monitor..."
    aws rum delete-app-monitor --name "${APP_NAME}-rum" --region "$REGION" 2>/dev/null || true

    log_success "Cleanup complete"
}

# Show help
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  setup     - Set up RUM and Synthetics (default)"
    echo "  cleanup   - Remove all RUM and Synthetics resources"
    echo "  status    - Show status of canaries"
    echo "  help      - Show this help message"
    echo ""
}

# Show canary status
show_status() {
    echo ""
    log_info "Synthetics Canary Status:"
    echo ""

    for canary in "heartbeat-boa" "login-flow-boa" "api-health-boa" "transaction-flow-boa"; do
        local status=$(aws synthetics get-canary --name "$canary" --region "$REGION" --query 'Canary.Status.State' --output text 2>/dev/null || echo "NOT_FOUND")
        local last_run=$(aws synthetics get-canary --name "$canary" --region "$REGION" --query 'Canary.Status.StateReason' --output text 2>/dev/null || echo "N/A")

        if [ "$status" = "RUNNING" ]; then
            log_success "${canary}: ${status}"
        elif [ "$status" = "NOT_FOUND" ]; then
            log_error "${canary}: NOT FOUND"
        else
            log_warning "${canary}: ${status}"
        fi
    done

    echo ""
    echo "View details at:"
    echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#synthetics:canary/list"
    echo ""
}

# Main execution
main() {
    local command=${1:-setup}

    case $command in
        setup)
            echo "=========================================="
            echo "CloudWatch RUM & Synthetics Setup"
            echo "=========================================="
            echo ""

            # Get account ID
            log_step "Getting AWS Account ID..."
            ACCOUNT_ID=$(get_account_id)
            log_info "Account ID: ${ACCOUNT_ID}"

            # Get frontend URL
            log_step "Getting frontend URL..."
            FRONTEND_URL=$(get_frontend_url)
            if [ -z "$FRONTEND_URL" ] || [ "$FRONTEND_URL" = "http://" ]; then
                log_error "Could not get frontend URL. Is the frontend service running?"
                log_info "Trying to get service info..."
                kubectl get svc frontend
                exit 1
            fi
            log_info "Frontend URL: ${FRONTEND_URL}"

            echo ""
            read -p "Press Enter to continue with setup..."
            echo ""

            # Create S3 bucket
            log_step "[1/5] Creating S3 bucket for Synthetics..."
            SYNTHETICS_BUCKET=$(create_synthetics_bucket)

            # Create IAM role
            log_step "[2/5] Creating IAM role for Synthetics..."
            SYNTHETICS_ROLE=$(create_synthetics_role)

            # Create RUM monitor
            log_step "[3/5] Creating CloudWatch RUM App Monitor..."
            create_rum_monitor

            echo ""
            read -p "Press Enter to create Synthetics canaries..."
            echo ""

            # Create canaries
            log_step "[4/5] Creating Synthetics Canaries..."
            create_canary "heartbeat-boa" "heartbeat-frontend.js"
            create_canary "api-health-boa" "api-health.js"
            create_canary "login-flow-boa" "login-flow.js"
            create_canary "transaction-flow-boa" "transaction-flow.js"

            log_step "[5/5] Setup complete!"
            display_summary

            echo ""
            log_info "Waiting 60 seconds for first canary runs..."
            log_info "Check the Synthetics dashboard to see results"
            echo ""
            ;;

        cleanup)
            cleanup_resources
            ;;

        status)
            show_status
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
