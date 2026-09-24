# Self-Testing Guide - Complete System Deployment & Validation

**This guide shows you how to test all components step-by-step with exact namespace configurations.**

---

## Namespaces Used

```
salt-master          → Master + Key Operator
salt                 → Minions (kubernetes & VCF)
```

---

## Prerequisites Checklist

Before starting, verify you have:

```bash
# 1. Kubernetes cluster running
kubectl cluster-info
# Expected: Kubernetes control plane is running

# 2. Helm 3+ installed
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}

# 3. kubectl authenticated
kubectl auth can-i create deployments --all-namespaces
# Expected: yes

# 4. Sufficient cluster resources
kubectl top nodes
# Expected: nodes with CPU/Memory available
```

---

## Complete Testing Workflow

### Phase 1: Setup (5 minutes)

#### Step 1: Create Namespaces

```bash
# Create namespaces
kubectl create namespace salt-master
kubectl create namespace salt

# Verify namespaces created
kubectl get namespaces | grep salt

# Expected output:
# NAME           STATUS   AGE
# salt           Active   10s
# salt-master    Active   10s
```

#### Step 2: Validate All Charts

```bash
# Navigate to project root
cd /Users/pt033548/CodeCrafters/open-source

# Run validation script
./validate-minion-charts.sh

# Expected: All 26 tests PASS ✅
```

---

### Phase 2: Deploy Salt Master & Operator (15 minutes)

#### Step 1: Deploy Salt Master

```bash
# Install Salt Master in salt-master namespace
helm install salt-master ./salt-kubernetes/helm/salt-master \
  --namespace salt-master \
  --set namespace=salt-master \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Watch deployment
kubectl rollout status statefulset/salt-master -n salt-master

# Verify pods are running
kubectl get pods -n salt-master

# Expected:
# NAME                 READY   STATUS    RESTARTS   AGE
# salt-master-0        2/2     Running   0          2m
```

#### Step 2: Verify Master is Healthy

```bash
# Check master logs
kubectl logs statefulset/salt-master -n salt-master --all-containers=true | head -30

# Expected: Salt Master starting up, listening on ports 4505/4506

# Test salt-run command
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-run test.arg testing

# Expected: "testing"

# List minions (should be empty)
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Expected: No accepted keys yet
```

#### Step 3: Deploy Salt Key Operator

```bash
# Install operator in same namespace
helm install salt-key-operator ./salt-kubernetes/helm/salt-key-operator \
  --namespace salt-master \
  --set image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Verify operator pod
kubectl get pods -n salt-master | grep operator

# Expected:
# salt-key-operator-xxxxx   1/1     Running   0          1m

# Check operator logs
kubectl logs deployment/salt-key-operator -n salt-master --tail 20

# Expected: No errors, operator ready
```

---

### Phase 3: Deploy Kubernetes Minion (15 minutes)

#### Step 1: Deploy Kubernetes Minion

```bash
# Install minion in salt namespace
helm install salt-minion ./salt-kubernetes/helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  --set agent.image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Watch pod startup
kubectl rollout status deployment/salt-minion -n salt -w

# Expected: deployment "salt-minion" successfully rolled out
```

#### Step 2: Verify Minion Pod Health

```bash
# Get minion pod name
MINION_POD=$(kubectl get pod -n salt -l app=salt-minion \
  -o jsonpath='{.items[0].metadata.name}')

echo "Minion pod: $MINION_POD"

# Check pod status
kubectl describe pod $MINION_POD -n salt | grep -A 10 "Conditions:"

# Expected: Ready = True, Status = Running

# Check health probes
kubectl describe pod $MINION_POD -n salt | grep -A 3 "Liveness:"
kubectl describe pod $MINION_POD -n salt | grep -A 3 "Readiness:"

# Expected: Both showing success counts > 0

# View minion startup logs
kubectl logs $MINION_POD -n salt --all-containers=true | head -50

# Expected: Salt minion starting, connecting to master
```

#### Step 3: Get Minion ID and Accept Key

```bash
# Get minion ID (usually pod name)
MINION_ID=$MINION_POD

echo "Accepting minion: $MINION_ID"

# Check pending keys on master
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Accept the minion
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a $MINION_ID -y

# Verify minion is accepted
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Expected: Minion ID appears under "Accepted Keys"
```

#### Step 4: Test Kubernetes Minion Connectivity

```bash
# Test from master to minion
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt "$MINION_ID" test.ping

# Expected: True

# Test minion local command
kubectl exec deployment/salt-minion -n salt \
  -- salt-call --local test.ping

# Expected: local: True

# Get minion info
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt "$MINION_ID" grains.items

# Expected: Shows minion grains (hostname, kernel, OS, etc.)
```

---

### Phase 4: Deploy VCF Minion (15 minutes)

#### Step 1: Deploy VCF Minion

```bash
# Install VCF minion in same namespace
helm install salt-minion-vcf ./salt-minion-vcf/helm/salt-minion-vcf \
  --namespace salt \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  --set workload.kind=Deployment \
  --set persistence.enabled=false \
  --set image.pullPolicy=IfNotPresent \
  --wait \
  --timeout 5m

# Watch deployment
kubectl rollout status deployment/salt-minion-vcf -n salt -w

# Expected: deployment "salt-minion-vcf" successfully rolled out
```

#### Step 2: Verify VCF Minion Health

```bash
# Get VCF minion pod name
VCF_POD=$(kubectl get pod -n salt -l app.kubernetes.io/name=salt-minion-vcf \
  -o jsonpath='{.items[0].metadata.name}')

echo "VCF minion pod: $VCF_POD"

# Check pod status
kubectl describe pod $VCF_POD -n salt | grep -A 10 "Conditions:"

# Expected: Ready = True

# Check health probes
kubectl describe pod $VCF_POD -n salt | grep -A 3 "Liveness:"

# View VCF minion logs
kubectl logs $VCF_POD -n salt | head -50

# Expected: Salt minion starting with VCF extensions
```

#### Step 3: Accept VCF Minion Key

```bash
# Get VCF minion ID
VCF_MINION_ID=$VCF_POD

echo "Accepting VCF minion: $VCF_MINION_ID"

# Accept the minion
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -a $VCF_MINION_ID -y

# List all accepted minions
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt-key -L

# Expected: Both K8s and VCF minions listed
```

#### Step 4: Test VCF Minion Connectivity

```bash
# Test VCF minion
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt "$VCF_MINION_ID" test.ping

# Expected: True

# Test VCF extensions (if installed)
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt "$VCF_MINION_ID" grains.items

# Expected: Shows minion info
```

---

### Phase 5: Full Integration Testing (20 minutes)

#### Test 1: Master-to-All-Minions

```bash
# Ping all minions
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' test.ping

# Expected:
# minion-1:
#   True
# minion-2:
#   True
```

#### Test 2: Execute Commands on All Minions

```bash
# Run command on all minions
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' cmd.run 'uname -a'

# Expected: Shows kernel info from all minions

# Get hostname from all minions
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' cmd.run 'hostname'

# Expected: Shows hostname of each minion
```

#### Test 3: Grain Information Collection

```bash
# Collect grains from all minions
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' grains.items | head -50

# Expected: Shows detailed grain data from all minions
```

#### Test 4: Module Execution

```bash
# Test pkg module (list installed packages)
kubectl exec statefulset/salt-master -n salt-master \
  --container salt-master \
  -- salt '*' pkg.list_pkgs | head -30

# Expected: Package information from minions
```

---

### Phase 6: Health Probe Validation (10 minutes)

#### Test 1: Verify Liveness Probes

```bash
# Get minion pod details
kubectl describe pod -n salt -l app=salt-minion

# Look for Liveness section
# Expected output should show:
# Liveness:   exec [salt-call --local test.ping] delay=30s timeout=10s period=60s #success=1 #failure=3

# Check events for any probe failures
kubectl get events -n salt --sort-by='.lastTimestamp' | grep -i "liveness"

# Expected: No failures listed
```

#### Test 2: Verify Readiness Probes

```bash
# Check readiness probe status
kubectl describe pod -n salt -l app=salt-minion | grep -A 3 "Readiness:"

# Expected:
# Readiness:  exec [salt-call --local test.ping] delay=15s timeout=10s period=30s #success=1 #failure=3

# Check pod is ready
kubectl get pod -n salt -l app=salt-minion -o jsonpath='{.items[0].status.containerStatuses[0].ready}'

# Expected: true
```

#### Test 3: Manual Health Check

```bash
# Manually test the health check command
MINION_POD=$(kubectl get pod -n salt -l app=salt-minion -o jsonpath='{.items[0].metadata.name}')

kubectl exec $MINION_POD -n salt -- salt-call --local test.ping

# Expected:
# local:
#     True
```

---

### Phase 7: Cleanup (5 minutes)

#### Option 1: Clean Everything

```bash
# Uninstall all releases
helm uninstall salt-minion-vcf -n salt
helm uninstall salt-minion -n salt
helm uninstall salt-key-operator -n salt-master
helm uninstall salt-master -n salt-master

# Wait for cleanup
sleep 10

# Delete namespaces
kubectl delete namespace salt salt-master

# Verify cleanup
kubectl get namespaces | grep salt

# Expected: No salt namespaces listed
```

#### Option 2: Keep for Further Testing

```bash
# Just scale down deployments (if needed)
kubectl scale deployment salt-minion --replicas=0 -n salt

# To bring back up:
kubectl scale deployment salt-minion --replicas=1 -n salt
```

---

## Complete Testing Checklist

### Master Deployment ✅
- [ ] Namespace created (salt-master)
- [ ] Helm install successful
- [ ] Pod status = Running
- [ ] Health check passing
- [ ] salt-run command works
- [ ] salt-key -L returns empty

### Operator Deployment ✅
- [ ] Helm install successful
- [ ] Operator pod running
- [ ] No errors in logs
- [ ] Ready to manage keys

### Kubernetes Minion ✅
- [ ] Helm install successful
- [ ] Pod reaches Running state
- [ ] Liveness probe passing
- [ ] Readiness probe passing
- [ ] Key appears on master (pending)
- [ ] Key accepted on master
- [ ] test.ping responds True
- [ ] Commands execute successfully

### VCF Minion ✅
- [ ] Helm install successful
- [ ] Pod reaches Running state
- [ ] Liveness probe passing
- [ ] Key accepted on master
- [ ] test.ping responds True
- [ ] Extensions available

### Integration ✅
- [ ] All minions visible on master
- [ ] Commands execute on all minions
- [ ] Grains collected from all minions
- [ ] No connection errors
- [ ] No probe failures

---

## Troubleshooting During Testing

### Pod Stuck in Pending

```bash
# Check what's preventing scheduling
kubectl describe pod <pod-name> -n <namespace>

# Common causes:
# - No nodes available (insufficient resources)
# - Image not found
# - PVC not bound
```

### Minion Not Connecting to Master

```bash
# Check network connectivity
kubectl exec <minion-pod> -n salt -- \
  nc -zv salt-master.salt-master.svc.cluster.local 4506

# Check minion logs
kubectl logs <minion-pod> -n salt --all-containers=true

# Common causes:
# - Wrong master hostname
# - Master not running
# - Network policy blocking traffic
```

### Health Check Failing

```bash
# Test manually
kubectl exec <pod> -n <namespace> -- salt-call --local test.ping

# View probe history in events
kubectl describe pod <pod> -n <namespace> | grep -A 10 "Events:"

# Common causes:
# - Salt minion crashed
# - Insufficient resources
# - Configuration issue
```

### Key Not Appearing on Master

```bash
# Check if secret was created
kubectl get secret -n salt | grep keys

# Check keygen job logs
kubectl logs job/<release>-keygen -n salt

# Verify master is running
kubectl get statefulset -n salt-master
```

---

## Sample Test Output (Expected Results)

### Successful Helm Install Output

```
NAME: salt-master
LAST DEPLOYED: [timestamp]
NAMESPACE: salt-master
STATUS: deployed
REVISION: 1
```

### Successful Pod Verification

```
$ kubectl get pods -n salt-master
NAME           READY   STATUS    RESTARTS   AGE
salt-master-0  2/2     Running   0          2m
```

### Successful Health Check

```
$ kubectl exec salt-minion-xxxxx -n salt -- salt-call --local test.ping
local:
    True
```

### Successful Master-Minion Communication

```
$ kubectl exec salt-master-0 -n salt-master -- salt 'salt-minion-xxxxx' test.ping
salt-minion-xxxxx:
    True
```

---

## Testing Timeline

| Phase | Duration | Status |
|-------|----------|--------|
| Setup | 5 min | ✅ Quick |
| Master Deploy | 5 min | ✅ Fast |
| Operator Deploy | 5 min | ✅ Fast |
| K8s Minion Deploy | 5 min | ✅ Fast |
| K8s Minion Testing | 10 min | ✅ Comprehensive |
| VCF Minion Deploy | 5 min | ✅ Fast |
| VCF Minion Testing | 10 min | ✅ Comprehensive |
| Integration Testing | 15 min | ✅ Thorough |
| Cleanup | 5 min | ✅ Quick |
| **TOTAL** | **60 min** | **✅ Complete** |

---

## Quick Test Commands (Copy-Paste)

### Deploy Everything

```bash
# Create namespaces
kubectl create namespace salt-master
kubectl create namespace salt

# Deploy master
helm install salt-master ./salt-kubernetes/helm/salt-master \
  --namespace salt-master --set namespace=salt-master --wait

# Deploy operator
helm install salt-key-operator ./salt-kubernetes/helm/salt-key-operator \
  --namespace salt-master --wait

# Deploy minions
helm install salt-minion ./salt-kubernetes/helm/salt-minion \
  --namespace salt \
  --set agent.saltMasterHost="salt-master.salt-master.svc.cluster.local" \
  --wait

helm install salt-minion-vcf ./salt-minion-vcf/helm/salt-minion-vcf \
  --namespace salt \
  --set salt.master="salt-master.salt-master.svc.cluster.local" \
  --wait

# Wait for everything to stabilize
sleep 30

# Check status
kubectl get pods -n salt-master
kubectl get pods -n salt
```

### Accept Minions and Test

```bash
# Get minion IDs
K8S_MINION=$(kubectl get pod -n salt -l app=salt-minion -o jsonpath='{.items[0].metadata.name}')
VCF_MINION=$(kubectl get pod -n salt -l app.kubernetes.io/name=salt-minion-vcf -o jsonpath='{.items[0].metadata.name}')

# Accept minions
kubectl exec statefulset/salt-master -n salt-master --container salt-master -- salt-key -a $K8S_MINION -y
kubectl exec statefulset/salt-master -n salt-master --container salt-master -- salt-key -a $VCF_MINION -y

# Test connectivity
kubectl exec statefulset/salt-master -n salt-master --container salt-master -- salt '*' test.ping
```

### Cleanup

```bash
helm uninstall salt-minion-vcf -n salt
helm uninstall salt-minion -n salt
helm uninstall salt-key-operator -n salt-master
helm uninstall salt-master -n salt-master
kubectl delete namespace salt salt-master
```

---

## Success Criteria

Your testing is successful when:

✅ All pods reach Running state  
✅ All health probes pass (Liveness & Readiness)  
✅ Minion keys appear on master  
✅ Master can ping all minions  
✅ Master can execute commands on minions  
✅ No errors in pod logs  
✅ No liveness/readiness probe failures  

---

## Resources

- **Master Documentation**: `./salt-kubernetes/src/master/README.md`
- **Minion Documentation**: `./salt-kubernetes/src/minion/README.md`
- **Helm Chart Docs**: `./salt-kubernetes/helm/*/README.md`
- **Test Guide**: `./salt-kubernetes/docs/complete-system-test.md`

---

**Ready to test?** Start with Phase 1 and work through each phase sequentially!

