# Custom OpenTelemetry Metrics Demo

Add custom business metrics to Bank of Anthos using OpenTelemetry, exported to CloudWatch.

## Files

```
eks/custom-metrics/
├── adot-collector.yaml     # ADOT Collector (receives OTLP, exports to CloudWatch)
├── instrumentation.yaml    # Configures Python metrics export
├── setup-iam.sh            # Creates IAM role for CloudWatch access
├── deploy.sh               # Deploys everything to EKS
├── generate-load.sh        # Generates test traffic
├── build-userservice.sh    # Builds userservice Docker image
└── README.md               # This file
```

## Architecture

```
┌─────────────────┐
│   userservice   │  (Python + custom OTEL metrics)
└────────┬────────┘
         │ OTLP/HTTP (port 4318)
         ▼
┌─────────────────┐
│ ADOT Collector  │  (dedicated, in default namespace)
└────────┬────────┘
         │ EMF format
         ▼
┌─────────────────┐
│   CloudWatch    │  (BankOfAnthos namespace)
└─────────────────┘
```

## Custom Metric

**Name:** `user.login.attempts`

**Dimensions:**
| Status | Failure Reason | Description |
|--------|----------------|-------------|
| success | none | Successful login |
| failure | user_not_found | Unknown username |
| failure | invalid_password | Wrong password |
| failure | database_error | DB connection issue |

## Quick Start

```bash
cd eks/custom-metrics

# 1. Setup IAM (one-time)
./setup-iam.sh

# 2. Build and push image
./build-userservice.sh
docker push 131676642557.dkr.ecr.us-west-2.amazonaws.com/bank-of-anthos:userservice-custom-metrics

# 3. Deploy
./deploy.sh

# 4. Generate traffic
./generate-load.sh

# 5. View in CloudWatch (wait 2-3 minutes)
#    CloudWatch → Metrics → BankOfAnthos → user.login.attempts
```

## Code Changes

Custom metric implementation in `src/accounts/userservice/userservice.py`:

```python
from opentelemetry import metrics

# Create meter and counter
meter = metrics.get_meter("userservice", "1.0.0")
login_counter = meter.create_counter(
    name="user.login.attempts",
    description="Number of user login attempts",
    unit="1"
)

# Record metric on login
login_counter.add(1, {"status": "success", "failure_reason": "none"})
```

## Troubleshooting

```bash
# Check ADOT collector
kubectl logs -l app=adot-collector

# Check userservice
kubectl logs -l app=userservice | grep -i metric

# Verify IAM role attached
kubectl get sa adot-collector -o yaml | grep eks.amazonaws.com
```

## Cleanup

```bash
kubectl delete -f adot-collector.yaml
kubectl delete -f instrumentation.yaml
kubectl set image deployment/userservice \
  userservice=us-central1-docker.pkg.dev/bank-of-anthos-ci/bank-of-anthos/userservice:v0.6.8
```
