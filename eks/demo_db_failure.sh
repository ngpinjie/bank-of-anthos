#!/bin/bash
# Database Failure Demo Script (Aggressive Version)
# Demonstrates cascading pod failures when database becomes unavailable
# Shows how Container Insights detects database-related outages
#
# This version actively kills pods to force restarts and generate more
# Container Insights metrics.

set -e

CLUSTER_NAME="bank-of-anthos"
REGION="us-west-2"

# Configuration - increase these for more dramatic demo
CHAOS_ROUNDS=3          # Number of times to kill pods while DB is down
CHAOS_INTERVAL=20       # Seconds between chaos rounds
MONITOR_DURATION=90     # Seconds to monitor after DB restore

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_chaos() { echo -e "${CYAN}[CHAOS]${NC} $1"; }

# Function to kill a pod and force restart
kill_pod() {
    local app=$1
    local pod_name=$(kubectl get pod -l app=$app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod_name" ]; then
        kubectl exec $pod_name -- sh -c 'kill 1' 2>/dev/null || true
        log_chaos "Killed $app ($pod_name)"
    fi
}

# Function to get restart count
get_restarts() {
    local app=$1
    kubectl get pod -l app=$app -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0"
}

echo "=========================================="
echo "Database Failure Demo (Aggressive)"
echo "=========================================="
echo ""
echo "This demo will:"
echo "  1. Show healthy state"
echo "  2. Kill the ledger-db (scale to 0)"
echo "  3. Repeatedly kill dependent pods to force restarts"
echo "  4. Generate multiple restart events for Container Insights"
echo "  5. Restore database and watch recovery"
echo ""
echo "Config: $CHAOS_ROUNDS chaos rounds, ${CHAOS_INTERVAL}s intervals"
echo ""

# Part 1: Show current state
echo "[Part 1] Current Cluster State"
echo "----------------------------"
echo ""
log_info "Database StatefulSets:"
kubectl get statefulsets
echo ""
log_info "Pods Status:"
kubectl get pods -o wide
echo ""
log_info "Services dependent on ledger-db:"
echo "  - ledgerwriter    (writes transactions)"
echo "  - balancereader   (reads balances)"
echo "  - transactionhistory (reads history)"
echo ""
log_success "All systems healthy"
echo ""
read -p "Press Enter to kill ledger-db..."
echo ""

# Part 2: Kill the database
echo "[Part 2] Simulating Database Failure"
echo "----------------------------"
echo ""
log_warning "Scaling ledger-db to 0 replicas..."
kubectl scale statefulset ledger-db --replicas=0
echo ""
log_info "Waiting for database pod to terminate..."
kubectl wait --for=delete pod/ledger-db-0 --timeout=60s 2>/dev/null || true
echo ""
log_error "ledger-db is now UNAVAILABLE"
echo ""

# Show the impact
log_info "Database StatefulSets (ledger-db should show 0/0):"
kubectl get statefulsets
echo ""

echo "=========================================="
echo "FAULT INJECTED: Database Unavailable"
echo "=========================================="
echo ""
echo "What's happening now:"
echo "  - ledgerwriter cannot write transactions"
echo "  - balancereader cannot read balances"
echo "  - transactionhistory cannot fetch history"
echo ""
echo "Container Insights URL:"
echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#container-insights:infrastructure/map/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'${CLUSTER_NAME}'))))"
echo ""
read -p "Press Enter to start chaos (kill pods repeatedly)..."
echo ""

# Part 3: Chaos - repeatedly kill pods to force restarts
echo "[Part 3] Chaos Engineering - Forcing Pod Restarts"
echo "----------------------------"
echo ""
log_warning "Database is DOWN. Now killing dependent pods repeatedly..."
log_warning "This will generate multiple restart events in Container Insights"
echo ""

AFFECTED_APPS=("ledgerwriter" "balancereader" "transactionhistory")

# Record initial restart counts
declare -A INITIAL_RESTARTS
for app in "${AFFECTED_APPS[@]}"; do
    INITIAL_RESTARTS[$app]=$(get_restarts $app)
done
log_info "Initial restart counts: ledgerwriter=${INITIAL_RESTARTS[ledgerwriter]}, balancereader=${INITIAL_RESTARTS[balancereader]}, transactionhistory=${INITIAL_RESTARTS[transactionhistory]}"
echo ""

# Chaos rounds - kill pods multiple times
for round in $(seq 1 $CHAOS_ROUNDS); do
    echo ""
    echo "========== CHAOS ROUND $round of $CHAOS_ROUNDS =========="
    echo ""

    # Kill all affected pods
    for app in "${AFFECTED_APPS[@]}"; do
        kill_pod $app
    done

    echo ""
    log_info "Waiting ${CHAOS_INTERVAL}s for pods to restart (and fail again because DB is down)..."

    # Monitor during wait
    for i in $(seq 1 $(($CHAOS_INTERVAL / 5))); do
        sleep 5
        echo ""
        echo "--- Status check (${i} of $(($CHAOS_INTERVAL / 5))) ---"
        for app in "${AFFECTED_APPS[@]}"; do
            RESTARTS=$(get_restarts $app)
            STATUS=$(kubectl get pod -l app=$app -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
            DELTA=$((RESTARTS - ${INITIAL_RESTARTS[$app]}))
            if [ $DELTA -gt 0 ]; then
                log_error "$app: Restarts=$RESTARTS (+$DELTA since start), Status=$STATUS"
            else
                log_info "$app: Restarts=$RESTARTS, Status=$STATUS"
            fi
        done
    done
done

echo ""
echo "=========================================="
echo "CHAOS COMPLETE"
echo "=========================================="
echo ""

# Show total restarts generated
TOTAL_RESTARTS=0
for app in "${AFFECTED_APPS[@]}"; do
    CURRENT=$(get_restarts $app)
    DELTA=$((CURRENT - ${INITIAL_RESTARTS[$app]}))
    TOTAL_RESTARTS=$((TOTAL_RESTARTS + DELTA))
    log_success "$app: $DELTA new restarts (was ${INITIAL_RESTARTS[$app]}, now $CURRENT)"
done
echo ""
log_success "Total new restarts generated: $TOTAL_RESTARTS"
echo ""

log_info "Current pod status:"
kubectl get pods
echo ""
read -p "Press Enter to restore the database..."
echo ""

# Part 4: Restore database
echo "[Part 4] Restoring Database"
echo "----------------------------"
echo ""
log_info "Scaling ledger-db back to 1 replica..."
kubectl scale statefulset ledger-db --replicas=1
echo ""
log_info "Waiting for database to become ready..."
kubectl wait --for=condition=ready pod/ledger-db-0 --timeout=120s
echo ""
log_success "ledger-db is back online!"
echo ""

# Part 5: Watch recovery
echo "[Part 5] Watching Recovery"
echo "----------------------------"
echo ""
log_info "Monitoring pod recovery for ${MONITOR_DURATION} seconds..."
echo ""

RECOVERY_POLLS=$((MONITOR_DURATION / 5))
for i in $(seq 1 $RECOVERY_POLLS); do
    echo "--- Recovery Poll $i/$RECOVERY_POLLS ($(($i * 5)) seconds) ---"
    HEALTHY_COUNT=0
    for app in "${AFFECTED_APPS[@]}"; do
        READY=$(kubectl get pod -l app=$app -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        RESTARTS=$(kubectl get pod -l app=$app -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

        if [ "$READY" = "true" ]; then
            log_success "$app: Ready=true, Restarts=$RESTARTS"
            ((HEALTHY_COUNT++)) || true
        else
            log_warning "$app: Ready=false, Restarts=$RESTARTS (recovering...)"
        fi
    done

    if [ $HEALTHY_COUNT -eq ${#AFFECTED_APPS[@]} ]; then
        echo ""
        log_success "All services recovered!"
        break
    fi

    if [ $i -lt $RECOVERY_POLLS ]; then
        sleep 5
    fi
done

echo ""
log_info "Final pod status:"
kubectl get pods
echo ""

# Calculate final stats
echo "=========================================="
echo "Demo Complete!"
echo "=========================================="
echo ""
echo "RESTART SUMMARY:"
echo "----------------------------"
TOTAL_FINAL=0
for app in "${AFFECTED_APPS[@]}"; do
    FINAL=$(get_restarts $app)
    DELTA=$((FINAL - ${INITIAL_RESTARTS[$app]}))
    TOTAL_FINAL=$((TOTAL_FINAL + DELTA))
    echo "  $app: ${INITIAL_RESTARTS[$app]} -> $FINAL (+$DELTA restarts)"
done
echo "  ----------------------------"
echo "  TOTAL NEW RESTARTS: $TOTAL_FINAL"
echo ""
echo "What you demonstrated:"
echo "  - Database failure causes cascading service failures"
echo "  - Multiple pod restarts visible in Container Insights"
echo "  - Services automatically recover when database returns"
echo "  - No manual intervention needed for recovery"
echo ""
echo "Metrics to check in Container Insights:"
echo "  - pod_number_of_container_restarts (should show $TOTAL_FINAL+ new restarts)"
echo "  - Pod container status waiting"
echo "  - Pod container status terminated"
echo ""
echo "Container Insights Dashboard:"
echo "https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~(~'${CLUSTER_NAME}'))))"
echo ""
