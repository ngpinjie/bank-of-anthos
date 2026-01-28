#!/bin/bash
# =============================================================================
# Generate Load for Custom Metrics Testing
# =============================================================================
# Creates login attempts against userservice to generate custom metrics.
# Uses kubectl port-forward to call userservice directly.
#
# Usage:
#   ./generate-load.sh
# =============================================================================

echo "============================================="
echo "  Custom Metrics - Load Generator"
echo "============================================="
echo ""

# Setup port-forward
echo "Setting up port-forward to userservice..."
pkill -f "port-forward.*userservice" 2>/dev/null || true
sleep 1

kubectl port-forward svc/userservice 8080:8080 &
PF_PID=$!
sleep 3

if ! kill -0 $PF_PID 2>/dev/null; then
    echo "Error: Failed to start port-forward"
    exit 1
fi

trap "kill $PF_PID 2>/dev/null" EXIT

URL="http://localhost:8080"
echo "Port-forward active: $URL"
echo ""

# Test credentials
VALID_USER="testuser"
VALID_PASS="bankofanthos"

echo "Generating 30 login attempts..."
echo ""

for i in {1..30}; do
    case $((i % 3)) in
        0)
            # Successful login
            printf "  [%02d] Success........" "$i"
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL/login?username=$VALID_USER&password=$VALID_PASS" || echo "ERR")
            echo " $CODE"
            ;;
        1)
            # Invalid user
            printf "  [%02d] User not found." "$i"
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL/login?username=unknown&password=test" || echo "ERR")
            echo " $CODE"
            ;;
        2)
            # Invalid password
            printf "  [%02d] Wrong password." "$i"
            CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL/login?username=$VALID_USER&password=wrong" || echo "ERR")
            echo " $CODE"
            ;;
    esac
    sleep 0.3
done

echo ""
echo "============================================="
echo "  Load Generation Complete"
echo "============================================="
echo ""
echo "Expected HTTP codes:"
echo "  - 200: Successful login"
echo "  - 404: User not found"
echo "  - 401: Invalid password"
echo ""
echo "View metrics in CloudWatch (wait 2-3 minutes):"
echo "  https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#metricsV2:namespace=BankOfAnthos"
echo ""
