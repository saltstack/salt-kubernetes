# Salt Minion Helm Chart Validation Report

**Date**: 2026-09-23  
**Status**: ✅ FIXED - All critical issues resolved

## Issues Found and Fixed

### salt-kubernetes/helm/salt-minion

#### ✅ Issue 1: Empty Secret Template (FIXED)
- **File**: `templates/minion-secret.yaml`
- **Problem**: Template was creating an empty secret conflicting with keygen-job
- **Fix**: Made template conditional - only creates secret if private/public keys are provided via values
- **Impact**: Eliminates secret creation conflicts

#### ✅ Issue 2: Unused Volume (FIXED)
- **File**: `templates/deployment.yaml`
- **Problem**: minion-config volume was defined but never mounted
- **Fix**: Removed unused volume definition (not needed as config is generated from env vars)
- **Impact**: Cleaner manifest, no confusing unused volumes

#### ✅ Issue 3: Secret Name Mismatch (FIXED)
- **File**: `templates/deployment.yaml` line 23
- **Problem**: Deployment used default name `salt-minion-${RELEASE_NAME}-key` but keygen creates `${RELEASE_NAME}-keys`
- **Fix**: Changed default to match: `${RELEASE_NAME}-keys`
- **Impact**: Correct secret references, no deployment failures

#### ✅ Issue 4: Missing Health Checks (FIXED)
- **File**: `templates/deployment.yaml`
- **Problem**: No liveness or readiness probes defined
- **Fix**: Added both probes using `salt-call --local test.ping`
  - Liveness: 30s initial delay, 60s period
  - Readiness: 15s initial delay, 30s period
- **Impact**: Kubernetes can properly manage minion lifecycle

### salt-minion-vcf/helm/salt-minion-vcf

**Status**: ✅ NO ISSUES FOUND
- Chart is well-structured with proper health checks
- Includes StatefulSet support with persistence
- Vault integration properly configured
- All volumes and mounts correctly defined

## Deployment Configuration Examples

### Kubernetes Minion (in_cluster mode)

```bash
helm install salt-minion ./helm/salt-minion \
  --namespace salt \
  --create-namespace \
  --set agent.saltMasterHost="salt-master.example.com" \
  --set agent.saltMasterPort=4506 \
  --set agent.image.repository="ghcr.io/saltstack/salt-kubernetes/salt-minion" \
  --set agent.image.tag="0.1.0"
```

### VCF Minion (StatefulSet)

```bash
helm install salt-minion-vcf ./helm/salt-minion-vcf \
  --namespace salt \
  --create-namespace \
  --set salt.master="salt-master.example.com" \
  --set salt.masterPort=4506 \
  --set image.repository="ghcr.io/saltstack/salt-kubernetes/salt-minion-vcf" \
  --set image.tag="0.1.0" \
  --set workload.kind="StatefulSet" \
  --set persistence.enabled=true
```

## Validation Steps Completed

### Helm Lint
```
salt-kubernetes/helm/salt-minion: ✅ PASSED
salt-minion-vcf/helm/salt-minion-vcf: ✅ PASSED
```

### Template Rendering
- ✅ Templates render without errors
- ✅ All environment variables correctly set
- ✅ Volume mounts properly defined
- ✅ Health probes correctly configured
- ✅ RBAC resources properly created
- ✅ Service account properly configured

### Key Features Verified
- ✅ Secret name consistency between deployment and keygen-job
- ✅ PKI volume mounting for minion keys
- ✅ Environment variable configuration
- ✅ Health check probes (liveness and readiness)
- ✅ RBAC configuration (ClusterRole, Role, bindings)
- ✅ Security context properly set
- ✅ Vault integration available (optional)

## Known Limitations

### salt-kubernetes/helm/salt-minion
1. Requires external salt-master - minion won't operate standalone
2. Keys must be pre-generated (see keygen-job for automatic generation)
3. Minion ID defaults to pod hostname if not explicitly set
4. In-cluster Deployment mode requires persistent PKI volume for key persistence across restarts

### salt-minion-vcf/helm/salt-minion-vcf
1. StatefulSet recommended for stable identity
2. Requires pillar Secret for VCF credentials (optional but recommended)
3. Vault integration requires valid Vault installation

## Deployment Readiness

### Prerequisites Met
- ✅ Helm 3+ compatible
- ✅ Kubernetes 1.24+ compatible
- ✅ RBAC properly configured
- ✅ Health checks in place
- ✅ Security hardened (non-root, capabilities dropped)

### Ready for Production
Both helm charts are now production-ready with proper error handling, health checks, and security configuration.

## Recommendations

1. **Key Management**: For production, use a secure key store instead of environment variables
2. **Vault Integration**: Enable Vault integration for secrets management
3. **Persistence**: Enable persistence for stable minion identity
4. **Monitoring**: Monitor liveness/readiness probe metrics for pod health
5. **Resource Limits**: Set appropriate resource requests/limits based on workload

## Testing Instructions

See `helm-deployment-test.yaml` for comprehensive test scenarios.

