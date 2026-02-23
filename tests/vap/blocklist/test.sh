#!/usr/bin/env bash
# Test VAP blocklist policy against a running OpenShift/Kubernetes cluster.
# Prerequisites:
#   - Logged in to the cluster (oc login / kubectl configured)
#   - OLM installed (Subscription CRD must exist)
#   - VAP blocklist policies deployed: oc apply -k policies/vap/blocklist/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

echo "=== VAP Blocklist Policy Tests ==="
echo ""

# Test 1: Blocked operator should be denied
echo -n "Test 1: Blocked operator (ansible-automation-platform-operator) is denied ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/blocked-subscription.yaml" 2>&1 | grep -qi "blocked by policy\|denied\|forbidden"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected denial)"
  FAIL=$((FAIL + 1))
fi

# Test 2: Allowed operator should be accepted
echo -n "Test 2: Non-blocked operator (web-terminal) is allowed ... "
if oc apply --dry-run=server -f "$SCRIPT_DIR/resources/allowed-subscription.yaml" 2>&1 | grep -qi "created\|configured\|unchanged"; then
  echo "PASS"
  PASS=$((PASS + 1))
else
  echo "FAIL (expected acceptance)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
