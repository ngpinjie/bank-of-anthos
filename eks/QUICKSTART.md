# Quick Start - Bank of Anthos on EKS with Container Insights + Application Signals

## Fast Track Deployment (3 Commands)

### Option 1: Automated Script

```bash
cd eks/
./deploy.sh
```

Wait ~20 minutes, then access the app at the URL shown.

---

### Option 2: Manual Commands

```bash
# 1. Create cluster (~15-20 min)
eksctl create cluster \
  --name bank-of-anthos \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --managed

# 2. Enable Container Insights (~2 min)
eksctl utils associate-iam-oidc-provider \
  --cluster bank-of-anthos \
  --region us-east-1 \
  --approve

eksctl create addon \
  --name amazon-cloudwatch-observability \
  --cluster bank-of-anthos \
  --region us-east-1 \
  --force

# 3. Deploy app (~5 min)
kubectl apply -f ../extras/jwt/jwt-secret.yaml
kubectl apply -f .
```

---

## Access the Application

### Get Frontend URL

```bash
kubectl get service frontend

# Access at: http://<EXTERNAL-IP>
```

### Demo Login

- **Username**: `testuser`
- **Password**: `bankofanthos`

---

## View Observability Data

### Container Insights (Infrastructure)

1. Navigate to **CloudWatch** → **Container Insights**
2. Select **Performance monitoring**
3. Choose cluster: `bank-of-anthos`

**Views:**
- **Cluster** - Overall metrics (CPU, memory, network)
- **Nodes** - Per-node performance
- **Pods** - Individual pod metrics
- **Services** - Service-level aggregations

### Application Signals (Application Metrics) 🆕

**IMPORTANT:** Data appears **5-10 minutes** after deployment.

1. Navigate to **CloudWatch** → **Application Signals**
2. Click **Services** tab

**What You'll See:**
- **Service Map** - Visual topology of all microservices
- **Distributed Traces** - End-to-end request waterfall
- **JVM Metrics** - Heap, GC, threads for Java services
- **Database Metrics** - Query latency to PostgreSQL
- **SLO Monitoring** - Create and track service level objectives

**All Services Instrumented:**
- ✅ `frontend` (Python) - Web UI
- ✅ `userservice` (Python) - Authentication
- ✅ `contacts` (Python) - Contact management
- ✅ `balancereader` (Java) - Balance cache service
- ✅ `ledgerwriter` (Java) - Transaction validation
- ✅ `transactionhistory` (Java) - Transaction history cache

### Logs

**CloudWatch** → **Log groups** → `/aws/containerinsights/bank-of-anthos/`

---

## Cleanup

### Option 1: Automated

```bash
cd eks/
./cleanup.sh
```

### Option 2: Manual

```bash
kubectl delete -f .
kubectl delete -f ../extras/jwt/jwt-secret.yaml

eksctl delete cluster \
  --name bank-of-anthos \
  --region us-east-1
```

---

## What Was Changed from GKE Version?

### Critical Changes (Prevents Crashes)

1. **Disabled Google Cloud Dependencies**
   - Set `ENABLE_METRICS=false` and `ENABLE_TRACING=false` in Java services
   - Set `SPRING_CLOUD_GCP_*_ENABLED=false` to prevent metadata service calls
   - Eliminates 245ms timeout penalty per request
   - Files: `balance-reader.yaml`, `ledger-writer.yaml`, `transaction-history.yaml`

2. **Removed GCP Workload Identity**
   - Deleted `iam.gke.io/gcp-service-account` annotation
   - File: `config.yaml`

3. **Enabled AWS Application Signals** 🆕
   - Added `instrumentation.opentelemetry.io/inject-java: "true"` for Java services
   - Added `instrumentation.opentelemetry.io/inject-python: "true"` for Python services
   - Provides **100% feature parity** with GKE Stackdriver + Cloud Trace
   - **All 6 application services** are now fully instrumented

### What We Kept

- Container images from GCP Artifact Registry (they're public)
- All application configuration
- Service mesh annotations (harmless if not using Istio)

### Observability Comparison

| Feature | GKE | EKS | Status |
|---------|-----|-----|--------|
| Infrastructure Metrics | ✅ | ✅ | Equal |
| Distributed Tracing | ✅ | ✅ | Equal |
| Service Maps | ✅ | ✅ | Equal |
| JVM Metrics | ✅ | ✅ | Equal |
| HTTP Request Metrics | ✅ | ✅ | Equal |
| Database Query Metrics | ✅ | ✅ | Equal |
| SLO Management UI | ⚠️ Manual | ✅ Built-in | **Better!** |
| Anomaly Detection | ⚠️ Separate | ✅ Built-in | **Better!** |

---

## Troubleshooting

### Pods CrashLooping or Slow?

Check Java services have ALL GCP environment variables set to `false`:

```bash
kubectl get pod <pod-name> -o yaml | grep ENABLE_METRICS
# Should show: value: "false"
```

### No Container Insights Data?

Verify CloudWatch agents are running:

```bash
kubectl get pods -n amazon-cloudwatch
```

Expected pods:
- `cloudwatch-agent-xxxxx`
- `fluent-bit-xxxxx`

### LoadBalancer Stuck on Pending?

Wait 2-5 minutes. AWS takes time to provision Classic ELB.

```bash
kubectl describe service frontend
# Check Events section for errors
```

---

## Cost Warning

**Running 24/7**: ~$193/month

- EKS control plane: $73/month
- 3x t3.medium nodes: $90/month
- Classic Load Balancer: $18/month
- Container Insights: $10-20/month

**Demo Tip**: Delete cluster after demo to avoid charges.

---

## Next Steps

See [README.md](README.md) for:
- Detailed architecture
- Advanced troubleshooting
- Container Insights features
- Cost optimization tips
