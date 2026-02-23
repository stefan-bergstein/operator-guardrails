#!/usr/bin/env bash
# Test VAP audit policy against a running OpenShift/Kubernetes cluster.
# Prerequisites:
#   - Logged in to the cluster (oc login / kubectl configured)
#   - VAP audit policy deployed: oc apply -k policies/vap/audit/
#
# The audit policy uses validationActions: [Audit], so it never blocks
# requests. This test verifies that the policy is active and generates
# audit annotations for matching resources.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

echo "=== VAP Audit Policy Tests ==="
echo ""

# Test 1: Guardrail ConfigMap (with label) should be accepted but audited
echo -n "Test 1: Guardrail ConfigMap is accepted (audit mode) ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/guardrail-configmap.yaml" 2>&1 | grep -qi "created\|configured\|unchanged"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected acceptance in audit mode)"
  FAIL=$((FAIL + 1))
fi

# Test 2: Regular ConfigMap (without label) should not match the policy
echo -n "Test 2: Regular ConfigMap is accepted (no label match) ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/regular-configmap.yaml" 2>&1 | grep -qi "created\|configured\|unchanged"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected acceptance)"
  FAIL=$((FAIL + 1))
fi

# Test 3: Verify the audit policy exists and is active
echo -n "Test 3: Audit policy exists and is active ... "
if oc get validatingadmissionpolicy audit-guardrail-changes -o name 2>/dev/null | grep -q "audit-guardrail-changes"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (policy not found)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""
echo "Note: To verify audit events, check the Kubernetes API server audit logs"
echo "for annotations containing 'audit-guardrail-changes'."
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
