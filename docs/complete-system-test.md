# Complete Salt-Kubernetes System Test Guide

**Version**: 1.0.0  
**Last Updated**: 2026-09-23  
**Components**: Salt-Key-Operator, Salt-Master, Salt-Minion (Kubernetes & VCF)

---

## Overview

This guide provides comprehensive testing procedures for the complete salt-kubernetes system including:
- Salt Key Operator (declarative minion key management)
- Salt Master (multi-master capable)
- Salt Minion Kubernetes (in-cluster minion with kube-bench support)
- Salt Minion VCF (VMware Cloud Foundation extensions)

## Prerequisites

### Required Tools
```bash
# Verify all required tools are installed
helm version                          # Helm 3+
kubectl version --client              # Kubernetes 1.24+
docker --version                      # Docker for local image builds
go version                            # Go 1.21+ (for operator development)
```

### Kubernetes Cluster
- Kubernetes 1.24+ cluster running
- kubectl authenticated and configured
- Sufficient resources (4+ CPU, 8Gi RAM minimum)

```bash
# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Build Local Images (Optional)
For local testing without using published images:

```bash
# Build images from source
docker build --tag salt-master:local ./src/master
docker build --tag salt-minion:local ./src/minion/kubernetes
docker build --tag salt-minion-vcf:local ./src/minion/vcf
docker build --tag salt-key-operator:local ./src/salt-key-operator
```

---

## Test Scenarios

### Scenario 1: Basic Salt Master Deployment

**Objective**: Verify Salt Master starts correctly with persistent identity

#### 1.1 Lint and Validate

```bash
# Lint the master chart
helm lint ./helm/salt-master
helm lint ./helm/salt-key-operator

# Render and validate templates
helm template salt-master ./helm/salt-master \
  --namespace salt-master \
  --include-crds \
  > /tmp/salt-master.yaml

kubectl apply --dry-run=client --validate=true -f /tmp/salt-master.yaml
```

**Expected Result**: ✅ No lint errors, validation passes

#### 1.2 Install Salt Master

```bash
# Create namespace
kubectl create namespace salt-master

# Install without Salt Key Operator (basic test)
helm upgrade --install salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --set namespace=salt-master \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Or use published image:
helm upgrade --install salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --set namespace=salt-master \
  --set agent.image.repository=ghcr.io/saltstack/salt-kubernetes/salt-master \
  --set agent.image.tag=1.0.0 \
  --wait \
  --timeout 5m
```

#### 1.3 Verify Installation

```bash
# Check pod status
kubectl get pods -n salt-master
kubectl describe pod -n salt-master | grep -A 5 "Conditions:"

# Verify Health
kubectl get pod -n salt-master -o jsonpath='{.items[0].status.containerStatuses[0].ready}'
# Expected: true

# Check master is running
kubectl logs deployment/salt-master -n salt-master --container salt-master | head -20
```

**Expected Result**: ✅ Pod running, healthy, ports 4505/4506 listening

#### 1.4 Verify Master Key Persistence

```bash
# Get master public key from secret
kubectl get secret salt-master-master-keys -n salt-master \
  -o jsonpath='{.data.master\.pub}' | base64 --decode > /tmp/master-secret.pub

# Get master public key from running pod
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- cat /etc/salt/pki/master/master.pub > /tmp/master-pod.pub

# Compare (hashes should match)
sha256sum /tmp/master-secret.pub /tmp/master-pod.pub
```

**Expected Result**: ✅ Both hashes match (same key identity)

#### 1.5 Verify Salt Functionality

```bash
# Test salt-run
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-run test.arg testing

# List minions (empty for now)
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L
```

**Expected Result**: ✅ Command executes, shows empty minion list

---

### Scenario 2: Salt Key Operator Deployment

**Objective**: Verify operator can manage minion keys declaratively

#### 2.1 Install Salt Key Operator

```bash
# Install operator
helm upgrade --install salt-key-operator \
  ./helm/salt-key-operator \
  --namespace salt-master \
  --set image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Or use published:
helm upgrade --install salt-key-operator \
  ./helm/salt-key-operator \
  --namespace salt-master \
  --set image.repository=ghcr.io/saltstack/salt-kubernetes/salt-key-operator \
  --set image.tag=0.1.0 \
  --wait \
  --timeout 5m
```

#### 2.2 Verify Operator Installation

```bash
# Check operator pod
kubectl get pods -n salt-master | grep operator

# Check operator logs
kubectl logs deployment/salt-key-operator -n salt-master --tail 50
```

**Expected Result**: ✅ Operator pod running, no errors in logs

#### 2.3 Create Test Minion Key

```bash
# Generate test minion RSA key pair
openssl genrsa -out /tmp/test-minion-key.pem 2048
openssl rsa -in /tmp/test-minion-key.pem -pubout -out /tmp/test-minion-key.pub

# Get public key content
PUBLIC_KEY=$(cat /tmp/test-minion-key.pub)

# Create SaltMinionKey resource
cat <<EOF | kubectl apply -f -
apiVersion: salt.saltstack.io/v1alpha1
kind: SaltMinionKey
metadata:
  name: test-minion-1
  namespace: salt-master
spec:
  minionId: test-minion-1
  publicKey: |
    $(cat /tmp/test-minion-key.pub)
EOF
```

#### 2.4 Verify Key Acceptance

```bash
# Wait for ConfigMap to be created
sleep 2

# Check ConfigMap was created
kubectl get configmap salt-master-trusted-minions -n salt-master

# Verify key is in ConfigMap
kubectl get configmap salt-master-trusted-minions -n salt-master \
  -o jsonpath='{.data}' | grep test-minion-1

# Verify key propagated to Salt Master
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L
```

**Expected Result**: ✅ Key appears in salt-key -L output

#### 2.5 Test Key Deletion

```bash
# Delete the SaltMinionKey resource
kubectl delete saltminionkey test-minion-1 -n salt-master

# Wait for propagation
sleep 3

# Verify key is removed from Salt
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L
```

**Expected Result**: ✅ Key no longer appears in salt-key -L output

---

### Scenario 3: Kubernetes Minion Deployment (in_cluster)

**Objective**: Verify minion connects to master and passes health checks

#### 3.1 Lint and Validate Chart

```bash
# Lint minion chart
helm lint ./helm/salt-minion

# Render template
helm template test-minion ./helm/salt-minion \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  > /tmp/salt-minion.yaml

# Validate
kubectl apply --dry-run=client --validate=true -f /tmp/salt-minion.yaml
```

**Expected Result**: ✅ No lint errors, validation passes

#### 3.2 Create Minion Namespace and Install

```bash
# Create namespace
kubectl create namespace salt

# Install minion
helm upgrade --install salt-minion \
  ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Or use published:
helm upgrade --install salt-minion \
  ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  --set agent.image.repository=ghcr.io/saltstack/salt-kubernetes/salt-minion \
  --set agent.image.tag=0.1.0 \
  --wait \
  --timeout 5m
```

#### 3.3 Monitor Minion Startup

```bash
# Watch pod initialization
kubectl get pods -n salt -w

# Check init containers
kubectl describe pod -n salt -l app=salt-minion

# View minion startup logs
kubectl logs -n salt deployment/salt-minion --all-containers=true
```

**Expected Result**: ✅ Pod reaches Running state, container ready

#### 3.4 Verify Health Checks

```bash
# Check probe status
kubectl get pod -n salt -l app=salt-minion \
  -o jsonpath='{.items[0].status.containerStatuses[0]}'  | jq '.readinessProbes, .livenessProbes'

# Check probe history in events
kubectl describe pod -n salt -l app=salt-minion | grep -A 2 "Probe"
```

**Expected Result**: ✅ Both probes passing, ready status true

#### 3.5 Verify Minion Authentication to Master

```bash
# Get minion ID from pod
MINION_ID=$(kubectl get pod -n salt -l app=salt-minion -o jsonpath='{.items[0].metadata.name}')

# Check master's pending keys
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Accept the minion
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a $MINION_ID -y

# Verify minion is accepted
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L
```

**Expected Result**: ✅ Minion appears in accepted keys

#### 3.6 Test Minion Connectivity

```bash
# From master, ping minion
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt "$MINION_ID" test.ping

# From minion, test local connectivity
kubectl exec deployment/salt-minion -n salt \
  -- salt-call --local test.ping
```

**Expected Result**: ✅ Both commands return True

#### 3.7 Test kube-bench Integration

```bash
# Create test kube-bench job
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: test-kube-bench
  namespace: salt
spec:
  template:
    spec:
      serviceAccountName: salt-minion
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench", "run", "--targets", "node"]
      restartPolicy: Never
  backoffLimit: 1
EOF

# Monitor job
kubectl get job -n salt -w

# Get results
kubectl logs -n salt job/test-kube-bench
```

**Expected Result**: ✅ Job completes, kube-bench runs on node

---

### Scenario 4: VCF Minion Deployment (StatefulSet)

**Objective**: Verify VCF minion with StatefulSet and persistent PKI

#### 4.1 Lint and Validate

```bash
# Lint chart
helm lint ./helm/salt-minion-vcf

# Render template
helm template salt-minion-vcf ./helm/salt-minion-vcf \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  > /tmp/salt-minion-vcf.yaml

# Validate
kubectl apply --dry-run=client --validate=true -f /tmp/salt-minion-vcf.yaml
```

**Expected Result**: ✅ No lint errors, validation passes

#### 4.2 Create Storage Class (if needed)

```bash
# Check available storage classes
kubectl get storageclass

# Create local storage if not available
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

#### 4.3 Install VCF Minion

```bash
# Install StatefulSet minion with persistence
helm upgrade --install salt-minion-vcf \
  ./helm/salt-minion-vcf \
  --namespace salt \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  --set workload.kind=StatefulSet \
  --set workload.replicas=1 \
  --set persistence.enabled=true \
  --set persistence.storageClass=local-storage \
  --set image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Or use published:
helm upgrade --install salt-minion-vcf \
  ./helm/salt-minion-vcf \
  --namespace salt \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  --set image.repository=ghcr.io/saltstack/salt-kubernetes/salt-minion-vcf \
  --set image.tag=0.1.0 \
  --wait \
  --timeout 5m
```

#### 4.4 Verify StatefulSet and Persistence

```bash
# Check StatefulSet
kubectl get statefulset -n salt
kubectl get pods -n salt -l app.kubernetes.io/name=salt-minion-vcf

# Verify PVC created
kubectl get pvc -n salt

# Check PVC is bound
kubectl describe pvc -n salt
```

**Expected Result**: ✅ StatefulSet running, PVC bound and available

#### 4.5 Verify PKI Persistence

```bash
# Get minion pod name
MINION_POD=$(kubectl get pod -n salt -l app.kubernetes.io/name=salt-minion-vcf \
  -o jsonpath='{.items[0].metadata.name}')

# Get minion public key
kubectl exec -n salt $MINION_POD -- ls -la /etc/salt/pki/minion/

# Capture key hash
ORIGINAL_HASH=$(kubectl exec -n salt $MINION_POD -- \
  sha256sum /etc/salt/pki/minion/minion.pub | awk '{print $1}')

echo "Original minion.pub hash: $ORIGINAL_HASH"

# Delete pod (StatefulSet will recreate it)
kubectl delete pod -n salt $MINION_POD

# Wait for recreation
kubectl rollout status statefulset/salt-minion-vcf -n salt

# Get new pod name
NEW_POD=$(kubectl get pod -n salt -l app.kubernetes.io/name=salt-minion-vcf \
  -o jsonpath='{.items[0].metadata.name}')

# Compare key hash
NEW_HASH=$(kubectl exec -n salt $NEW_POD -- \
  sha256sum /etc/salt/pki/minion/minion.pub | awk '{print $1}')

echo "New minion.pub hash: $NEW_HASH"
```

**Expected Result**: ✅ Hashes match (persistent identity across restarts)

#### 4.6 Test VCF Extensions (if available)

```bash
# Check if VCF extensions are loaded
kubectl exec -n salt deployment/salt-minion-vcf \
  -- salt-call --local pillar.items

# Test with vcf grains
kubectl exec -n salt deployment/salt-minion-vcf \
  -- salt-call --local grains.items | grep -E "vcf|vmware"
```

**Expected Result**: ✅ Extensions loaded and available (if configured)

---

### Scenario 5: Multi-Master Deployment

**Objective**: Verify active-active multi-master setup with shared keypair

#### 5.1 Deploy Multi-Master

```bash
# Install with 3 replicas
helm upgrade --install salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --set agent.replicas=3 \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m
```

#### 5.2 Verify Master Identity Sharing

```bash
# All masters should share the same public key
for i in {0,1,2}; do
  echo "=== salt-master-$i ==="
  kubectl exec statefulset/salt-master -n salt-master --pod=$i \
    --container salt-master \
    -- sha256sum /etc/salt/pki/master/master.pub
done

# All hashes should be identical
```

**Expected Result**: ✅ All replicas share identical public key

#### 5.3 Verify Multi-Master Coordination

```bash
# Create a minion key via the first master
kubectl exec statefulset/salt-master -n salt-master --pod=0 \
  --container salt-master \
  -- salt-key -L

# Accept a test minion on the first master
MINION_ID="test-multimaster-minion"
cat <<EOF | kubectl apply -f -
apiVersion: salt.saltstack.io/v1alpha1
kind: SaltMinionKey
metadata:
  name: $MINION_ID
  namespace: salt-master
spec:
  minionId: $MINION_ID
  publicKey: |
    $(openssl rsa -in /tmp/test-minion-key.pem -pubout)
EOF

# Verify key is visible on all masters
for i in {0,1,2}; do
  echo "=== salt-master-$i ==="
  kubectl exec statefulset/salt-master -n salt-master --pod=$i \
    --container salt-master \
    -- salt-key -L | grep $MINION_ID
done
```

**Expected Result**: ✅ Minion key visible on all masters

---

### Scenario 6: Integration Test - Full Workflow

**Objective**: End-to-end workflow: deploy master → operator → minion → accept → command

#### 6.1 Clean Slate

```bash
# Delete previous releases
helm uninstall salt-minion-vcf -n salt || true
helm uninstall salt-minion -n salt || true
helm uninstall salt-key-operator -n salt-master || true
helm uninstall salt-master -n salt-master || true

kubectl delete namespace salt salt-master 2>/dev/null || true

# Wait for cleanup
sleep 10
```

#### 6.2 Deploy Complete Stack

```bash
# 1. Create namespaces
kubectl create namespace salt-master
kubectl create namespace salt

# 2. Deploy Salt Master
helm upgrade --install salt-master \
  ./helm/salt-master \
  --namespace salt-master \
  --set namespace=salt-master \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait --timeout 5m

# 3. Deploy Salt Key Operator
helm upgrade --install salt-key-operator \
  ./helm/salt-key-operator \
  --namespace salt-master \
  --set image.pullPolicy=IfNotPresent \
  --wait --timeout 5m

# 4. Deploy Kubernetes Minion
helm upgrade --install salt-minion \
  ./helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait --timeout 5m

# 5. Deploy VCF Minion
helm upgrade --install salt-minion-vcf \
  ./helm/salt-minion-vcf \
  --namespace salt \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  --set workload.kind=Deployment \
  --set persistence.enabled=false \
  --set image.pullPolicy=IfNotPresent \
  --wait --timeout 5m
```

#### 6.3 Accept Minions

```bash
# List all pending keys
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Get minion names
K8S_MINION=$(kubectl get pod -n salt -l app=salt-minion \
  -o jsonpath='{.items[0].metadata.name}')

VCF_MINION=$(kubectl get pod -n salt -l app.kubernetes.io/name=salt-minion-vcf \
  -o jsonpath='{.items[0].metadata.name}')

# Accept both minions
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a $K8S_MINION -y

kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a $VCF_MINION -y
```

#### 6.4 Verify Connectivity

```bash
# Ping all minions
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' test.ping

# Run a command on all minions
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' cmd.run 'uname -a'

# Gather grain data
kubectl exec deployment/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' grains.items
```

**Expected Result**: ✅ Both minions respond to master commands

#### 6.5 Cleanup

```bash
# Uninstall all releases
helm uninstall salt-minion-vcf -n salt
helm uninstall salt-minion -n salt
helm uninstall salt-key-operator -n salt-master
helm uninstall salt-master -n salt-master

# Delete namespaces
kubectl delete namespace salt salt-master

# Verify cleanup
kubectl get ns | grep salt
```

**Expected Result**: ✅ All resources cleaned up

---

## Automated Test Script

A shell script version of the complete integration test:

```bash
#!/bin/bash
set -e

echo "=== Complete Salt-Kubernetes Integration Test ==="

# Configuration
SALT_MASTER_NS="salt-master"
SALT_NS="salt"
TIMEOUT="5m"

# Cleanup function
cleanup() {
  echo "Cleaning up..."
  helm uninstall salt-minion-vcf -n $SALT_NS || true
  helm uninstall salt-minion -n $SALT_NS || true
  helm uninstall salt-key-operator -n $SALT_MASTER_NS || true
  helm uninstall salt-master -n $SALT_MASTER_NS || true
  kubectl delete namespace $SALT_NS $SALT_MASTER_NS || true
  sleep 10
}

# Test functions
test_master_install() {
  echo "Testing master installation..."
  kubectl create namespace $SALT_MASTER_NS
  
  helm upgrade --install salt-master \
    ./helm/salt-master \
    --namespace $SALT_MASTER_NS \
    --set agent.image.pullPolicy=IfNotPresent \
    --wait --timeout $TIMEOUT
  
  echo "✅ Master installed"
}

test_operator_install() {
  echo "Testing operator installation..."
  helm upgrade --install salt-key-operator \
    ./helm/salt-key-operator \
    --namespace $SALT_MASTER_NS \
    --set image.pullPolicy=IfNotPresent \
    --wait --timeout $TIMEOUT
  
  echo "✅ Operator installed"
}

test_minion_kubernetes() {
  echo "Testing kubernetes minion..."
  kubectl create namespace $SALT_NS
  
  helm upgrade --install salt-minion \
    ./helm/salt-minion \
    --namespace $SALT_NS \
    --set agent.saltMasterHost="salt-master.$SALT_MASTER_NS.svc.cluster.local" \
    --set agent.image.pullPolicy=IfNotPresent \
    --wait --timeout $TIMEOUT
  
  echo "✅ Kubernetes minion installed"
}

test_minion_vcf() {
  echo "Testing VCF minion..."
  helm upgrade --install salt-minion-vcf \
    ./helm/salt-minion-vcf \
    --namespace $SALT_NS \
    --set salt.master="salt-master.$SALT_MASTER_NS.svc.cluster.local" \
    --set image.pullPolicy=IfNotPresent \
    --wait --timeout $TIMEOUT
  
  echo "✅ VCF minion installed"
}

# Main test flow
trap cleanup EXIT

cleanup
test_master_install
test_operator_install
test_minion_kubernetes
test_minion_vcf

echo ""
echo "=== All Tests Passed ✅ ==="
```

---

## Success Criteria

All tests are considered successful when:

- ✅ All Helm charts pass linting
- ✅ All templates render without errors
- ✅ All pods reach Running state
- ✅ All containers pass health checks
- ✅ Salt Master is accessible via salt-key and salt commands
- ✅ Minions appear in salt-key listing
- ✅ Master can execute commands on minions via salt
- ✅ Keys persist across pod restarts (VCF)
- ✅ Multi-master shares keypair and minion keys
- ✅ Operator can create/delete minion keys declaratively

## Troubleshooting

### Pod stuck in pending
```bash
kubectl describe pod <pod-name> -n <namespace>
# Check: resource requests, node selectors, node availability
```

### Minion not connecting to master
```bash
# Check minion logs
kubectl logs <minion-pod> -n salt --all-containers

# Verify master is accessible
kubectl exec <minion-pod> -n salt -- nc -zv salt-master.salt-master.svc.cluster.local 4506

# Check minion configuration
kubectl exec <minion-pod> -n salt -- cat /etc/salt/minion.d/*
```

### Health check failing
```bash
# Test manually
kubectl exec <minion-pod> -n salt -- salt-call --local test.ping

# Check probe configuration
kubectl describe pod <minion-pod> -n salt | grep -A 10 "Probe"
```

### Key not appearing in master
```bash
# Check ConfigMap
kubectl get configmap salt-master-trusted-minions -n salt-master

# Check sidecar logs
kubectl logs <master-pod> -n salt-master -c trusted-minions-sync
```

---

## Performance Metrics to Monitor

During testing, monitor:

- Pod startup time (target: < 30s)
- Time to first master connection (target: < 60s)
- Health probe response time (target: < 5s)
- Key propagation latency (target: < 2 minutes)
- Multi-master key sync consistency

