#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Salt Minion Helm Chart Validation${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to print test results
FAILED_TESTS=0
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED${NC}: $2"
    else
        echo -e "${RED}❌ FAILED${NC}: $2"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

print_info() {
    echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

print_section() {
    echo ""
    echo -e "${YELLOW}▸ $1${NC}"
}

# Check if helm is installed
print_section "Checking prerequisites"
command -v helm >/dev/null 2>&1
print_result $? "helm command available"

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_MINION_CHART="$SCRIPT_DIR/salt-kubernetes/helm/salt-minion"
VCF_MINION_CHART="$SCRIPT_DIR/salt-minion-vcf/helm/salt-minion-vcf"

# Test 1: Lint both charts
print_section "Linting Helm Charts"

if [ -d "$K8S_MINION_CHART" ]; then
    helm lint "$K8S_MINION_CHART" >/dev/null 2>&1
    print_result $? "salt-kubernetes minion chart lint"
else
    echo -e "${RED}❌ Chart not found${NC}: $K8S_MINION_CHART"
    exit 1
fi

if [ -d "$VCF_MINION_CHART" ]; then
    helm lint "$VCF_MINION_CHART" >/dev/null 2>&1
    print_result $? "salt-minion-vcf chart lint"
else
    echo -e "${RED}❌ Chart not found${NC}: $VCF_MINION_CHART"
    exit 1
fi

# Test 2: Render templates and validate output
print_section "Rendering Templates"

# Kubernetes minion
K8S_OUTPUT=$(helm template test-minion "$K8S_MINION_CHART" \
    --set agent.saltMasterHost="salt-master.example.com" 2>&1)

[ ! -z "$K8S_OUTPUT" ]
print_result $? "salt-kubernetes minion template renders"

# VCF minion
VCF_OUTPUT=$(helm template test-vcf "$VCF_MINION_CHART" \
    --set salt.master="salt-master.example.com" 2>&1)

[ ! -z "$VCF_OUTPUT" ]
print_result $? "salt-minion-vcf template renders"

# Test 3: Verify critical resources exist
print_section "Verifying Resource Definitions"

# Check for ServiceAccount in K8S minion
echo "$K8S_OUTPUT" | grep -q "kind: ServiceAccount"
print_result $? "ServiceAccount defined in kubernetes minion"

# Check for Deployment in K8S minion
echo "$K8S_OUTPUT" | grep -q "kind: Deployment"
print_result $? "Deployment defined in kubernetes minion"

# Check for RBAC resources
echo "$K8S_OUTPUT" | grep -q "kind: ClusterRole"
print_result $? "ClusterRole defined in kubernetes minion"

echo "$K8S_OUTPUT" | grep -q "kind: Role"
print_result $? "Role defined in kubernetes minion"

# Check for keygen job (creates secret dynamically)
echo "$K8S_OUTPUT" | grep -q "kind: Job"
print_result $? "Key generation Job defined in kubernetes minion"

echo "$K8S_OUTPUT" | grep -q "keygen"
print_result $? "Key generation job properly named"

echo "$K8S_OUTPUT" | grep -q "openssl genpkey"
print_result $? "Key generation uses OpenSSL for RSA keypair"

# Test 4: Verify health checks
print_section "Verifying Health Checks"

echo "$K8S_OUTPUT" | grep -q "livenessProbe:"
print_result $? "Liveness probe defined in kubernetes minion"

echo "$K8S_OUTPUT" | grep -q "readinessProbe:"
print_result $? "Readiness probe defined in kubernetes minion"

echo "$K8S_OUTPUT" | grep -q "salt-call"
print_result $? "Health check command defined correctly"

# Test 5: Verify environment variables
print_section "Verifying Environment Variables"

echo "$K8S_OUTPUT" | grep -q "name: SALT_MASTER"
print_result $? "SALT_MASTER environment variable set"

echo "$K8S_OUTPUT" | grep -q "name: SALT_LOG_LEVEL"
print_result $? "SALT_LOG_LEVEL environment variable set"

echo "$K8S_OUTPUT" | grep -q "name: VAULT_ADDR"
print_result $? "Vault integration environment variables available"

# Test 6: Verify volumes and mounts
print_section "Verifying Volumes and Mounts"

echo "$K8S_OUTPUT" | grep -q "name: minion-keys"
print_result $? "minion-keys volume defined"

echo "$K8S_OUTPUT" | grep -q "/etc/salt/pki"
print_result $? "PKI volume mount configured"

# Secret is created dynamically by keygen job, not as static template
echo "$K8S_OUTPUT" | grep -q "kubectl create secret"
print_result $? "Secret creation command in keygen job"

# Test 7: Verify VCF specific features
print_section "Verifying VCF Chart Features"

echo "$VCF_OUTPUT" | grep -q "kind: StatefulSet"
print_result $? "StatefulSet defined in VCF chart"

echo "$VCF_OUTPUT" | grep -q "livenessProbe:"
print_result $? "VCF chart has liveness probe"

echo "$VCF_OUTPUT" | grep -q "readinessProbe:"
print_result $? "VCF chart has readiness probe"

# Test 8: Verify security context
print_section "Verifying Security Configuration"

echo "$K8S_OUTPUT" | grep -q "runAsNonRoot: true"
print_result $? "Non-root user enforced in kubernetes minion"

echo "$VCF_OUTPUT" | grep -q "runAsNonRoot: true"
print_result $? "Non-root user enforced in VCF minion"

echo "$K8S_OUTPUT" | grep -q "allowPrivilegeEscalation: false"
print_result $? "Privilege escalation prevented in kubernetes minion"

echo "$VCF_OUTPUT" | grep -q "allowPrivilegeEscalation: false"
print_result $? "Privilege escalation prevented in VCF minion"

# Test 9: Check for deprecated/unused resources
print_section "Checking for Issues"

# Count minion-config references - should be none now
MINION_CONFIG_COUNT=$(echo "$K8S_OUTPUT" | grep -c "minion-config" || true)
if [ "$MINION_CONFIG_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ PASSED${NC}: No unused minion-config volume references"
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: Found $MINION_CONFIG_COUNT minion-config references (should be 0)"
fi

# Test 10: Verify key handling (keygen job creates the secret dynamically)
print_section "Verifying Key Handling"

# Check that keygen job is defined and uses correct key file names
echo "$K8S_OUTPUT" | grep -q "minion.pem"
print_result $? "Private key file (minion.pem) referenced in keygen job"

echo "$K8S_OUTPUT" | grep -q "minion.pub"
print_result $? "Public key file (minion.pub) referenced in keygen job"

# Verify secret reference in deployment (keygen job creates it)
echo "$K8S_OUTPUT" | grep -q "secretName:"
print_result $? "Secret reference present in deployment"

# Summary
print_section "Validation Summary"
if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}✅ All validation tests passed!${NC}"
    echo -e "${GREEN}================================================${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}================================================${NC}"
    echo -e "${RED}❌ $FAILED_TESTS validation test(s) failed!${NC}"
    echo -e "${RED}================================================${NC}"
    EXIT_CODE=1
fi
echo ""

print_info "Next steps:"
echo "  1. Create a Kubernetes cluster if not present"
echo "  2. Create salt namespace: kubectl create namespace salt"
echo "  3. Deploy salt-master first (if not already running)"
echo "  4. Deploy minion:"
echo "     helm install salt-minion ./salt-kubernetes/helm/salt-minion \\"
echo "       -f ./test-values-k8s-minion.yaml -n salt"
echo "  5. Or for VCF minion:"
echo "     helm install salt-minion-vcf ./salt-minion-vcf/helm/salt-minion-vcf \\"
echo "       -f ./test-values-vcf-minion.yaml -n salt"
echo "  6. Monitor deployment:"
echo "     kubectl rollout status deployment/salt-minion -n salt"
echo "     kubectl logs -f deployment/salt-minion -n salt"
echo ""

exit $EXIT_CODE
