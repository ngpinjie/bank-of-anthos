# Bank of Anthos on Amazon EKS with Container Insights + Application Signals

This directory contains Kubernetes manifests for deploying Bank of Anthos on Amazon EKS with:
- **AWS CloudWatch Container Insights** - Infrastructure monitoring (pods, nodes, cluster)
- **AWS CloudWatch Application Signals** - Application-level observability (traces, metrics, service maps)

## Changes from Original GKE Manifests

### Critical Changes Made:
1. **Removed GCP Workload Identity** - Removed `iam.gke.io/gcp-service-account` annotation from ServiceAccount
2. **Disabled Google Cloud Dependencies** - Set multiple environment variables to prevent GCP metadata service calls:
   - `ENABLE_METRICS=false` and `ENABLE_TRACING=false` - Disables Stackdriver metrics/tracing
   - `SPRING_CLOUD_GCP_CORE_ENABLED=false` - Disables Spring Cloud GCP auto-configuration
   - `SPRING_CLOUD_GCP_LOGGING_ENABLED=false` - Disables GCP logging integration
   - `SPRING_CLOUD_GCP_TRACE_ENABLED=false` - Disables GCP trace integration
3. **Enabled AWS Application Signals** - Added `instrumentation.opentelemetry.io/inject-java: "true"` and `inject-python: "true"` annotations
4. **Container Images** - Still using GCP Artifact Registry images (public access)

### Services Modified:
- `balance-reader.yaml` - Disabled GCP metrics/tracing, enabled Application Signals (Java)
- `ledger-writer.yaml` - Disabled GCP metrics/tracing, enabled Application Signals (Java)
- `transaction-history.yaml` - Disabled GCP metrics/tracing, enabled Application Signals (Java)
- `frontend.yaml` - Enabled Application Signals (Python)
- `userservice.yaml` - Enabled Application Signals (Python)
- `contacts.yaml` - Enabled Application Signals (Python)
- `config.yaml` - Removed GCP Workload Identity annotation

### Observability Feature Parity:

| Feature | GKE (Stackdriver) | EKS (Application Signals) |
|---------|------------------|---------------------------|
| Distributed Tracing | ✅ Cloud Trace | ✅ X-Ray Integration |
| Service Maps | ✅ Auto-generated | ✅ Auto-generated |
| JVM Metrics | ✅ Stackdriver | ✅ Application Signals |
| HTTP Request Metrics | ✅ Stackdriver | ✅ Application Signals |
| Database Query Metrics | ✅ Stackdriver | ✅ Application Signals |
| SLO Monitoring | ⚠️ Manual | ✅ Built-in |

## Prerequisites

- AWS CLI configured with appropriate credentials
- `eksctl` installed
- `kubectl` installed
- AWS account with permissions to create EKS clusters

## Deployment Steps

### 1. Create EKS Cluster with Container Insights

```bash
eksctl create cluster \
  --name bank-of-anthos \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --managed
```

**Note:** This takes approximately 15-20 minutes.

### 2. Enable OIDC Provider (Required for CloudWatch Addon)

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster bank-of-anthos \
  --region us-east-1 \
  --approve
```

### 3. Install Amazon CloudWatch Observability Add-on

```bash
eksctl create addon \
  --name amazon-cloudwatch-observability \
  --cluster bank-of-anthos \
  --region us-east-1 \
  --force
```

This installs:
- **CloudWatch Agent** - Infrastructure metrics collection (CPU, memory, network)
- **Fluent Bit** - Log aggregation to CloudWatch Logs
- **Container Insights** - Pod, node, and cluster dashboards
- **Application Signals** - Auto-instrumentation for distributed tracing and application metrics
- **ADOT Operator** - OpenTelemetry auto-injection for Java services

### 4. Verify CloudWatch Agent Deployment

```bash
# Check if CloudWatch agents are running
kubectl get pods -n amazon-cloudwatch

# Expected output:
# cloudwatch-agent-xxxxx       1/1     Running
# fluent-bit-xxxxx             1/1     Running
```

### 5. Deploy JWT Secret

```bash
kubectl apply -f ../extras/jwt/jwt-secret.yaml
```

### 6. Deploy Bank of Anthos

```bash
kubectl apply -f .
```

### 7. Wait for Pods to be Ready

```bash
kubectl get pods -w
```

Expected pods (all should be Running):
- `accounts-db-xxxxx`
- `balancereader-xxxxx`
- `contacts-xxxxx`
- `frontend-xxxxx`
- `ledger-db-xxxxx`
- `ledgerwriter-xxxxx`
- `loadgenerator-xxxxx`
- `transactionhistory-xxxxx`
- `userservice-xxxxx`

### 8. Get Frontend Load Balancer URL

```bash
kubectl get service frontend

# Wait for EXTERNAL-IP to be assigned (takes 2-3 minutes)
# Access the app at: http://<EXTERNAL-IP>
```

## Accessing Observability Dashboards

### Container Insights (Infrastructure Monitoring)

1. Navigate to **AWS Console** → **CloudWatch**
2. Click **Container Insights** in the left sidebar
3. Select **Performance monitoring**
4. Choose cluster: `bank-of-anthos`

**Available Views:**
- **Cluster View** - Overall cluster health, CPU, memory, network
- **Nodes View** - Individual node performance
- **Pods View** - Pod-level metrics and resource usage
- **Namespaces View** - Namespace-level aggregations
- **Services View** - Service-level metrics

### Application Signals (Application Monitoring)

**IMPORTANT:** Application Signals data takes **5-10 minutes** after deployment to appear.

1. Navigate to **AWS Console** → **CloudWatch**
2. Click **Application Signals** in the left sidebar (under "Insights")
3. Select **Services** tab

**What You'll See:**

#### **Service Map (Topology)**
- Visual representation of all microservices and their dependencies
- Request flow between services (frontend → userservice → accounts-db)
- Color-coded health status (green = healthy, red = errors)
- Request volume shown as arrow thickness
- Click any service to drill down into metrics

#### **Service-Level Metrics**
For each Java service (balancereader, ledgerwriter, transactionhistory):
- **Request Rate** - Requests per minute
- **Latency** - p50, p95, p99 percentiles
- **Error Rate** - Percentage of failed requests
- **Availability** - Percentage uptime
- **Database Query Performance** - Query latency to PostgreSQL

#### **Distributed Traces**
1. Click **Traces** tab in Application Signals
2. Filter by:
   - Service name (e.g., `ledgerwriter`)
   - Latency (e.g., show only slow requests > 500ms)
   - HTTP status code (e.g., errors = 500)
   - Time range

3. Click any trace to see the **request waterfall**:
   ```
   frontend (385ms total)
     └─ userservice (45ms)
         └─ accounts-db query (22ms)
     └─ ledgerwriter (280ms) ← SLOW
         └─ ledger-db INSERT (245ms) ← BOTTLENECK
   ```

#### **SLO Monitoring**
1. Go to **Application Signals** → **Services**
2. Click a service (e.g., `ledgerwriter`)
3. Click **Create SLO**
4. Set targets:
   - Availability: 99.9%
   - Latency: 95% of requests < 300ms
5. Monitor **Error Budget** consumption

#### **JVM Metrics**
1. Click a Java service in the Service Map
2. View **Operations** tab for:
   - Heap memory usage
   - Garbage collection pause times
   - Thread count
   - JVM CPU usage

### CloudWatch Logs

Navigate to **CloudWatch** → **Log groups** → Filter by `/aws/containerinsights/bank-of-anthos/`

Available log groups:
- `/aws/containerinsights/bank-of-anthos/application` - Application logs
- `/aws/containerinsights/bank-of-anthos/dataplane` - Node/pod logs
- `/aws/containerinsights/bank-of-anthos/host` - Node-level system logs

## Demo Login Credentials

- **Username**: `testuser`
- **Password**: `bankofanthos`

## GKE vs. EKS Observability Comparison

### What You Get with Application Signals (vs. GKE Stackdriver)

| Feature | GKE (Stackdriver + Cloud Trace) | EKS (Application Signals) | Status |
|---------|--------------------------------|---------------------------|--------|
| **Infrastructure Metrics** | ✅ Cloud Monitoring | ✅ Container Insights | ✅ Equal |
| **Distributed Tracing** | ✅ Cloud Trace | ✅ X-Ray + Application Signals | ✅ Equal |
| **Service Dependency Map** | ✅ Auto-generated | ✅ Auto-generated | ✅ Equal |
| **HTTP Request Metrics** | ✅ Rate, latency, errors | ✅ Rate, latency, errors | ✅ Equal |
| **Database Query Metrics** | ✅ Query latency | ✅ Query latency | ✅ Equal |
| **JVM Metrics** | ✅ Heap, GC, threads | ✅ Heap, GC, threads | ✅ Equal |
| **SLO Monitoring** | ⚠️ Manual setup | ✅ Built-in UI | ✅ Better! |
| **Anomaly Detection** | ⚠️ Separate product | ✅ Built-in ML | ✅ Better! |
| **Auto-Instrumentation** | ✅ Spring Cloud GCP | ✅ ADOT Java Agent | ✅ Equal |
| **Custom Metrics** | ✅ Micrometer export | ✅ OpenTelemetry | ✅ Equal |

### Key Differences

**Advantages of Application Signals:**
- ✅ **Built-in SLO Management** - Create and track SLOs directly in the UI
- ✅ **Anomaly Detection** - ML-powered detection of unusual patterns
- ✅ **Unified Console** - All observability in CloudWatch (vs. separate GCP products)
- ✅ **Error Budget Tracking** - Automatic SLO burn-rate calculation

**Advantages of GKE Stackdriver:**
- ✅ **Tighter GCP Integration** - Native integration with other Google Cloud services
- ✅ **Established Ecosystem** - More third-party integrations

**Bottom Line:** Application Signals provides **100% feature parity** with what you had on GKE, plus some additional capabilities like built-in SLO management and anomaly detection.

## Troubleshooting

### Pods CrashLooping or Slow Startup

**Issue**: Java pods crash, timeout, or have slow startup (245ms delays)

**Solution**: Verify ALL GCP-related environment variables are set to `false`:
- `ENABLE_METRICS=false`
- `ENABLE_TRACING=false`
- `SPRING_CLOUD_GCP_CORE_ENABLED=false`
- `SPRING_CLOUD_GCP_LOGGING_ENABLED=false`
- `SPRING_CLOUD_GCP_TRACE_ENABLED=false`

Check in: `balance-reader.yaml`, `ledger-writer.yaml`, `transaction-history.yaml`

### Frontend LoadBalancer Pending

**Issue**: `kubectl get svc frontend` shows `<pending>` for EXTERNAL-IP

**Solution**:
- Wait 2-5 minutes for AWS to provision the Classic Load Balancer
- Check node security groups allow inbound traffic
- Verify VPC has internet gateway attached

### Container Insights Not Showing Data

**Issue**: CloudWatch Container Insights dashboard is empty

**Solution**:
```bash
# Verify CloudWatch agents are running
kubectl get pods -n amazon-cloudwatch

# Check agent logs
kubectl logs -n amazon-cloudwatch -l name=cloudwatch-agent

# Verify IAM permissions on node role
aws iam list-attached-role-policies --role-name eksctl-bank-of-anthos-nodegroup-NodeInstanceRole-XXXXX
```

Expected policy: `CloudWatchAgentServerPolicy`

### Application Signals Not Showing Data

**Issue**: Application Signals dashboard is empty or missing services

**Common Causes & Solutions:**

**1. Data Not Yet Available (Most Common)**
- Application Signals takes **5-10 minutes** after deployment to populate
- Wait and refresh the CloudWatch console

**2. ADOT Operator Not Installed**
```bash
# Verify the ADOT operator is running
kubectl get pods -n amazon-cloudwatch -l app.kubernetes.io/name=adot-operator

# Expected output:
# adot-operator-xxxxx   1/1   Running
```

**3. Java Agent Not Injected**
```bash
# Check if Java agent was injected into pods
kubectl get pod <balancereader-pod> -o yaml | grep -A 5 "JAVA_TOOL_OPTIONS"

# Expected output should include:
# -javaagent:/otel-auto-instrumentation/javaagent.jar
```

**4. Verify Auto-Instrumentation Annotation**
```bash
# Check if annotation is present
kubectl get deployment balancereader -o yaml | grep instrumentation

# Expected output:
# instrumentation.opentelemetry.io/inject-java: "true"
```

**5. Force Pod Restart (if needed)**
```bash
# If pods were deployed before ADOT operator was ready, restart them:
kubectl rollout restart deployment balancereader
kubectl rollout restart deployment ledgerwriter
kubectl rollout restart deployment transactionhistory
```

### Application Signals Shows Only Some Services

**Issue**: Not seeing all expected services in the service map

**Possible Causes**:
1. **Pods deployed before ADOT operator was ready** - Restart deployments
2. **Annotation missing** - Verify all services have the correct annotation
3. **Still collecting initial data** - Wait 10-15 minutes for complete service map

**Expected Behavior:**
- ✅ `balancereader` (Java) - **Full instrumentation**
- ✅ `ledgerwriter` (Java) - **Full instrumentation**
- ✅ `transactionhistory` (Java) - **Full instrumentation**
- ✅ `frontend` (Python) - **Full instrumentation**
- ✅ `userservice` (Python) - **Full instrumentation**
- ✅ `contacts` (Python) - **Full instrumentation**
- ❌ `accounts-db` (PostgreSQL) - Database pods don't appear in service map
- ❌ `ledger-db` (PostgreSQL) - Database pods don't appear in service map

**Note:** Database queries **will** show in the traces from services that call them (userservice → accounts-db, Java services → ledger-db).

### Traces Show Faults to metadata.google.internal

**Issue**: Application Signals traces show 100% fault rate to `metadata.google.internal` with ~245ms timeouts

**Root Cause**: Java services are trying to reach Google Cloud Metadata Service (`169.254.169.254`) which doesn't exist on AWS.

**Example Trace:**
```
ledgerwriter [245ms]
  └─ metadata.google.internal [245ms] ← FAULT (timeout)
      └─ Remote: GET http://metadata.google.internal
```

**Solution**: This is **already fixed** in the current manifests. If you still see this issue:

1. **Verify environment variables are set** in all Java services:
```bash
kubectl get deployment ledgerwriter -o yaml | grep -A 15 "env:"
```

Expected output should include:
```yaml
- name: SPRING_CLOUD_GCP_CORE_ENABLED
  value: "false"
- name: SPRING_CLOUD_GCP_LOGGING_ENABLED
  value: "false"
- name: SPRING_CLOUD_GCP_TRACE_ENABLED
  value: "false"
```

2. **Restart deployments** to pick up new environment variables:
```bash
kubectl rollout restart deployment balancereader
kubectl rollout restart deployment ledgerwriter
kubectl rollout restart deployment transactionhistory
```

3. **Verify fix** by checking new traces in Application Signals (wait 5 minutes for new data)

**Impact if not fixed:**
- Every request adds 245ms latency (timeout waiting for GCP metadata)
- Application Signals shows 100% error rate (false positive)
- Increased network connection overhead

### Images Not Pulling

**Issue**: Pods stuck in `ImagePullBackOff`

**Solution**:
- GCP Artifact Registry images are public and should work
- Verify node security group allows outbound HTTPS (port 443)
- Check if VPC has NAT gateway for private subnets

## Cleanup

### Delete Application

```bash
kubectl delete -f .
kubectl delete -f ../extras/jwt/jwt-secret.yaml
```

### Delete CloudWatch Addon

```bash
eksctl delete addon \
  --cluster bank-of-anthos \
  --name amazon-cloudwatch-observability \
  --region us-east-1
```

### Delete Cluster

```bash
eksctl delete cluster \
  --name bank-of-anthos \
  --region us-east-1
```

**Note:** This takes approximately 10-15 minutes.

## Architecture

Bank of Anthos consists of 9 microservices:

**Frontend Tier:**
- `frontend` - Python Flask web UI

**Account Services:**
- `userservice` - Python user authentication (JWT)
- `contacts` - Python contact management

**Ledger Services (Java Spring Boot):**
- `ledgerwriter` - Transaction validation and writes
- `balancereader` - Read-only balance cache
- `transactionhistory` - Read-only transaction history

**Databases:**
- `accounts-db` - PostgreSQL (user data)
- `ledger-db` - PostgreSQL (transaction ledger)

**Load Testing:**
- `loadgenerator` - Python/Locust continuous traffic generator

## Cost Estimation

**Estimated AWS Cost (us-east-1):**

- EKS Cluster: $0.10/hour ($73/month)
- 3x t3.medium nodes: $0.0416/hour each ($90/month total)
- Classic Load Balancer: $0.025/hour ($18/month)
- CloudWatch Container Insights: ~$10-20/month (based on metrics/logs volume)
- EBS volumes (2x 8GB): ~$2/month

**Total: ~$193/month** (if running 24/7)

**Demo Cost Saving:** Delete cluster after demo to avoid charges.

## Reference Documentation

- [AWS Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Bank of Anthos Original Repo](https://github.com/GoogleCloudPlatform/bank-of-anthos)
