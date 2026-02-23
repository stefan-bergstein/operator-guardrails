#!/usr/bin/env bash
# Test VAP allowlist policy against a running OpenShift/Kubernetes cluster.
# Prerequisites:
#   - Logged in to the cluster (oc login / kubectl configured)
#   - OLM installed (Subscription CRD must exist)
#   - VAP allowlist policies deployed: oc apply -k policies/vap/allowlist/
# set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

echo "=== VAP Allowlist Policy Tests ==="
echo ""

# Test 1: Allowed operator should be accepted
echo -n "Test 1: Allowed operator (web-terminal) is accepted ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/whitelisted-subscription.yaml" 2>&1 | grep -qi "created\|configured\|unchanged"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected acceptance)"
  FAIL=$((FAIL + 1))
fi

# Test 2: Non-allowed operator should be denied
echo -n "Test 2: Non-allowed operator (ansible-automation-platform-operator) is denied ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/non-whitelisted-subscription.yaml" 2>&1 | grep -qi "not on the approved list\|denied\|forbidden"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected denial)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
