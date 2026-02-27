#!/usr/bin/env bash
# ==============================================================================
# Operator Guardrails — End-to-End Tutorial Runner
#
# Runs the full step-by-step tutorial automatically:
#   Part 1: Kyverno  (allowlist + blocklist)
#   Part 2: VAP      (allowlist + blocklist)
#
# Prerequisites:
#   - OpenShift 4.17+ cluster with cluster-admin access
#   - oc CLI logged in
#   - helm CLI installed
#   - This repository cloned locally
#
# Usage:
#   ./run-tutorial.sh            # Run full tutorial (Kyverno + VAP)
#   ./run-tutorial.sh --kyverno  # Run only Part 1 (Kyverno)
#   ./run-tutorial.sh --vap      # Run only Part 2 (VAP)
# ==============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KYVERNO_VERSION="3.5.2"
KYVERNO_NAMESPACE="kyverno"
KYVERNO_VALUES="$SCRIPT_DIR/bootstrap/kyverno/kyverno-openshift-values.yaml"
KYVERNO_WAIT_TIMEOUT=300   # seconds to wait for Kyverno pods

# ---------------------------------------------------------------------------
# Colors and symbols
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'  # No Color

PASS_ICON="${GREEN}[PASS]${NC}"
FAIL_ICON="${RED}[FAIL]${NC}"
SKIP_ICON="${YELLOW}[SKIP]${NC}"
INFO_ICON="${BLUE}[INFO]${NC}"
RUN_ICON="${CYAN}[RUN ]${NC}"
WAIT_ICON="${YELLOW}[WAIT]${NC}"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TOTAL_STEPS=0
PASSED_STEPS=0
FAILED_STEPS=0
SKIPPED_STEPS=0

# Per-part results for summary table
KYVERNO_ALLOWLIST_RESULT=""
KYVERNO_BLOCKLIST_RESULT=""
VAP_ALLOWLIST_RESULT=""
VAP_BLOCKLIST_RESULT=""

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
separator() {
  echo ""
  echo -e "${DIM}$(printf '%.0s─' {1..70})${NC}"
  echo ""
}

banner() {
  local title="$1"
  echo ""
  echo -e "${DIM}$(printf '%.0s═' {1..70})${NC}"
  echo -e "${BOLD}  $title${NC}"
  echo -e "${DIM}$(printf '%.0s═' {1..70})${NC}"
  echo ""
}

section() {
  local number="$1"
  local title="$2"
  echo ""
  echo -e "${BOLD}${BLUE}Step $number: $title${NC}"
  separator
}

show_cmd() {
  echo -e "  ${RUN_ICON} ${DIM}\$${NC} $1"
}

show_info() {
  echo -e "  ${INFO_ICON} $1"
}

show_pass() {
  echo -e "  ${PASS_ICON} $1"
  TOTAL_STEPS=$((TOTAL_STEPS + 1))
  PASSED_STEPS=$((PASSED_STEPS + 1))
}

show_fail() {
  echo -e "  ${FAIL_ICON} $1"
  TOTAL_STEPS=$((TOTAL_STEPS + 1))
  FAILED_STEPS=$((FAILED_STEPS + 1))
}

show_skip() {
  echo -e "  ${SKIP_ICON} $1"
  TOTAL_STEPS=$((TOTAL_STEPS + 1))
  SKIPPED_STEPS=$((SKIPPED_STEPS + 1))
}

show_wait() {
  echo -e "  ${WAIT_ICON} $1"
}

# Run a command, show it, capture output, and check exit code.
# Usage: run_cmd "description" "command" [expect_fail]
#   expect_fail: if "true", success means the command fails (non-zero exit or error output)
run_cmd() {
  local desc="$1"
  local cmd="$2"
  local expect_fail="${3:-false}"
  local output
  local rc=0

  show_cmd "$cmd"
  output=$(eval "$cmd" 2>&1) || rc=$?

  if [ "$expect_fail" = "true" ]; then
    if [ $rc -ne 0 ] || echo "$output" | grep -qi "denied\|forbidden\|blocked\|not on the approved"; then
      show_pass "$desc"
      if [ -n "$output" ]; then
        echo -e "         ${DIM}$(echo "$output" | head -3 | sed 's/^/         /')${NC}"
      fi
      return 0
    else
      show_fail "$desc (expected denial, but command succeeded)"
      if [ -n "$output" ]; then
        echo -e "         ${DIM}$(echo "$output" | head -3 | sed 's/^/         /')${NC}"
      fi
      return 1
    fi
  else
    if [ $rc -eq 0 ]; then
      show_pass "$desc"
      if [ -n "$output" ]; then
        echo -e "         ${DIM}$(echo "$output" | head -5 | sed 's/^/         /')${NC}"
      fi
      return 0
    else
      show_fail "$desc"
      if [ -n "$output" ]; then
        echo -e "         ${DIM}$(echo "$output" | head -5 | sed 's/^/         /')${NC}"
      fi
      return 1
    fi
  fi
}

# Run a command silently, only show status
run_quiet() {
  local desc="$1"
  local cmd="$2"
  local output
  local rc=0

  show_cmd "$cmd"
  output=$(eval "$cmd" 2>&1) || rc=$?

  if [ $rc -eq 0 ]; then
    show_pass "$desc"
  else
    show_fail "$desc"
    echo -e "         ${DIM}$(echo "$output" | head -3 | sed 's/^/         /')${NC}"
  fi
  return $rc
}

# ---------------------------------------------------------------------------
# Prerequisites check
# ---------------------------------------------------------------------------
check_prerequisites() {
  banner "Checking Prerequisites"

  local ok=true

  # Check oc CLI
  if command -v oc &>/dev/null; then
    show_pass "oc CLI found: $(oc version --client 2>/dev/null | head -1)"
  else
    show_fail "oc CLI not found"
    ok=false
  fi

  # Check helm CLI
  if command -v helm &>/dev/null; then
    show_pass "helm CLI found: $(helm version --short 2>/dev/null)"
  else
    show_fail "helm CLI not found"
    ok=false
  fi

  # Check cluster connectivity
  local whoami
  if whoami=$(oc whoami 2>/dev/null); then
    show_pass "Logged into cluster as: $whoami"
  else
    show_fail "Not logged into a cluster (run 'oc login' first)"
    ok=false
  fi

  # Check cluster-admin access
  if oc auth can-i create clusterrole &>/dev/null; then
    show_pass "Cluster-admin access confirmed"
  else
    show_fail "Cluster-admin access required"
    ok=false
  fi

  # Check cluster version
  local version
  if version=$(oc version 2>/dev/null | grep "Server" | head -1); then
    show_info "Cluster version: $version"
  fi

  # Check required files exist
  if [ -f "$KYVERNO_VALUES" ]; then
    show_pass "Kyverno Helm values file found"
  else
    show_fail "Missing: $KYVERNO_VALUES"
    ok=false
  fi

  if [ -d "$SCRIPT_DIR/policies/kyverno" ] && [ -d "$SCRIPT_DIR/policies/vap" ]; then
    show_pass "Policy directories found (kyverno + vap)"
  else
    show_fail "Missing policy directories"
    ok=false
  fi

  if [ "$ok" = false ]; then
    echo ""
    echo -e "${RED}Prerequisites check failed. Please fix the issues above and try again.${NC}"
    exit 1
  fi

  echo ""
  show_info "All prerequisites met."
}

# ---------------------------------------------------------------------------
# Part 1: Kyverno
# ---------------------------------------------------------------------------

kyverno_install() {
  section "1.1" "Install Kyverno using Helm"

  show_info "Adding Kyverno Helm repository..."
  run_cmd "Helm repo added" \
    "helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true" || true

  run_quiet "Helm repo updated" \
    "helm repo update" || true

  show_info "Installing Kyverno $KYVERNO_VERSION into namespace '$KYVERNO_NAMESPACE'..."
  local install_output
  local rc=0
  show_cmd "helm install kyverno kyverno/kyverno --namespace $KYVERNO_NAMESPACE --create-namespace --version $KYVERNO_VERSION -f $KYVERNO_VALUES"
  install_output=$(helm install kyverno kyverno/kyverno \
    --namespace "$KYVERNO_NAMESPACE" \
    --create-namespace \
    --version "$KYVERNO_VERSION" \
    -f "$KYVERNO_VALUES" 2>&1) || rc=$?

  if [ $rc -eq 0 ]; then
    show_pass "Kyverno Helm release installed"
  else
    # Check if already installed
    if echo "$install_output" | grep -qi "already exists"; then
      show_info "Kyverno already installed, continuing..."
    else
      show_fail "Kyverno installation failed"
      echo -e "         ${DIM}$install_output${NC}"
      return 1
    fi
  fi

  # Wait for pods to be ready
  show_wait "Waiting for Kyverno pods to become ready (timeout: ${KYVERNO_WAIT_TIMEOUT}s)..."
  show_cmd "oc rollout status deployment -n $KYVERNO_NAMESPACE --timeout=${KYVERNO_WAIT_TIMEOUT}s"

  local deployments
  deployments=$(oc get deployments -n "$KYVERNO_NAMESPACE" -o name 2>/dev/null)
  local all_ready=true
  for dep in $deployments; do
    if oc rollout status "$dep" -n "$KYVERNO_NAMESPACE" --timeout="${KYVERNO_WAIT_TIMEOUT}s" &>/dev/null; then
      show_pass "$(basename "$dep") is ready"
    else
      show_fail "$(basename "$dep") failed to become ready"
      all_ready=false
    fi
  done

  if [ "$all_ready" = true ]; then
    show_info "All Kyverno components are running."
    echo ""
    show_cmd "oc get pods -n $KYVERNO_NAMESPACE"
    oc get pods -n "$KYVERNO_NAMESPACE" 2>/dev/null | sed 's/^/         /'
  fi
}

kyverno_allowlist_deploy() {
  section "1.2" "Deploy the Kyverno Allowlist Policy"

  show_info "Allowed operators: web-terminal, openshift-gitops-operator"
  show_info "AAP operator is NOT on this list and will be denied."
  echo ""

  run_cmd "Allowlist policy and ConfigMap deployed" \
    "oc apply -k $SCRIPT_DIR/policies/kyverno/allowlist/" || return 1

  echo ""
  run_cmd "Policy is active and enforcing" \
    "oc get clusterpolicy allow-operator-subscriptions" || return 1
}

kyverno_allowlist_test() {
  section "1.3" "Test the Kyverno Allowlist"

  show_info "Testing: AAP operator should be DENIED (not on allowlist)"
  run_cmd "AAP operator denied by allowlist" \
    "oc apply -f $SCRIPT_DIR/tests/kyverno/allowlist/resources/non-whitelisted-subscription.yaml" \
    "true"

  local test1=$?

  echo ""
  show_info "Testing: web-terminal operator should be ALLOWED (on allowlist)"
  run_cmd "web-terminal operator allowed by allowlist" \
    "oc apply --dry-run=server -f $SCRIPT_DIR/tests/kyverno/allowlist/resources/whitelisted-subscription.yaml"

  local test2=$?

  if [ $test1 -eq 0 ] && [ $test2 -eq 0 ]; then
    KYVERNO_ALLOWLIST_RESULT="PASS"
  else
    KYVERNO_ALLOWLIST_RESULT="FAIL"
  fi
}

kyverno_allowlist_remove() {
  section "1.4" "Remove the Kyverno Allowlist Policy"

  run_cmd "Allowlist policy removed" \
    "oc delete -k $SCRIPT_DIR/policies/kyverno/allowlist/" || true

  echo ""
  show_info "Verifying policy is gone..."
  if oc get clusterpolicy allow-operator-subscriptions &>/dev/null; then
    show_fail "Policy still exists"
  else
    show_pass "Policy successfully removed"
  fi
}

kyverno_blocklist_deploy() {
  section "1.5" "Deploy the Kyverno Blocklist Policy"

  show_info "Blocked operators: ansible-automation-platform-operator,"
  show_info "  serverless-operator, openshift-pipelines-operator-rh,"
  show_info "  servicemeshoperator, cluster-logging, compliance-operator"
  echo ""

  run_cmd "Blocklist policy and ConfigMap deployed" \
    "oc apply -k $SCRIPT_DIR/policies/kyverno/blocklist/" || return 1

  echo ""
  run_cmd "Policy is active and enforcing" \
    "oc get clusterpolicy block-operator-subscriptions" || return 1
}

kyverno_blocklist_test() {
  section "1.6" "Test the Kyverno Blocklist"

  show_info "Testing: AAP operator should be DENIED (on blocklist)"
  run_cmd "AAP operator denied by blocklist" \
    "oc apply -f $SCRIPT_DIR/tests/kyverno/blocklist/resources/blocked-subscription.yaml" \
    "true"

  local test1=$?

  echo ""
  show_info "Testing: web-terminal operator should be ALLOWED (not on blocklist)"
  run_cmd "web-terminal operator allowed (not blocked)" \
    "oc apply --dry-run=server -f $SCRIPT_DIR/tests/kyverno/blocklist/resources/allowed-subscription.yaml"

  local test2=$?

  if [ $test1 -eq 0 ] && [ $test2 -eq 0 ]; then
    KYVERNO_BLOCKLIST_RESULT="PASS"
  else
    KYVERNO_BLOCKLIST_RESULT="FAIL"
  fi
}

kyverno_blocklist_remove() {
  section "1.7" "Remove the Kyverno Blocklist Policy"

  run_cmd "Blocklist policy removed" \
    "oc delete -k $SCRIPT_DIR/policies/kyverno/blocklist/" || true
}

kyverno_uninstall() {
  section "1.8" "Uninstall Kyverno"

  show_info "Removing Kyverno Helm release..."
  run_cmd "Kyverno Helm release removed" \
    "helm uninstall kyverno --namespace $KYVERNO_NAMESPACE" || true

  echo ""
  show_info "Deleting Kyverno namespace..."
  run_cmd "Kyverno namespace deleted" \
    "oc delete namespace $KYVERNO_NAMESPACE --timeout=60s" || true

  echo ""
  show_info "Verifying Kyverno is fully removed..."
  if oc get namespace "$KYVERNO_NAMESPACE" &>/dev/null; then
    show_info "Namespace still terminating (this is normal, it will be cleaned up)"
  else
    show_pass "Kyverno fully removed"
  fi
}

run_part1() {
  banner "Part 1: Kyverno"
  show_info "Kyverno is an external policy engine that runs as a set of controllers"
  show_info "in your cluster. Policies are defined as ClusterPolicy resources."
  echo ""

  kyverno_install
  kyverno_allowlist_deploy
  kyverno_allowlist_test
  kyverno_allowlist_remove
  kyverno_blocklist_deploy
  kyverno_blocklist_test
  kyverno_blocklist_remove
  kyverno_uninstall
}

# ---------------------------------------------------------------------------
# Part 2: VAP (Validating Admission Policy)
# ---------------------------------------------------------------------------

vap_namespace_create() {
  show_info "Creating operator-guardrails namespace for VAP ConfigMaps..."
  run_cmd "Namespace created" \
    "oc apply -f $SCRIPT_DIR/policies/vap/namespace.yaml" || true
}

vap_allowlist_deploy() {
  section "2.1" "Deploy the VAP Allowlist Policy"

  show_info "VAP is built into Kubernetes — no external controller needed."
  show_info "Allowed operators: web-terminal, openshift-gitops-operator"
  show_info "AAP operator is NOT on this list and will be denied."
  echo ""

  vap_namespace_create
  echo ""

  run_cmd "Allowlist policy, binding, and ConfigMap deployed" \
    "oc apply -k $SCRIPT_DIR/policies/vap/allowlist/" || return 1

  echo ""
  run_cmd "ValidatingAdmissionPolicy exists" \
    "oc get validatingadmissionpolicy allow-operator-subscriptions" || return 1

  echo ""
  run_cmd "ValidatingAdmissionPolicyBinding exists" \
    "oc get validatingadmissionpolicybinding allow-operator-subscriptions" || return 1
}

vap_allowlist_test() {
  section "2.2" "Test the VAP Allowlist"

  show_info "Testing: AAP operator should be DENIED (not on allowlist)"
  run_cmd "AAP operator denied by allowlist" \
    "oc apply -f $SCRIPT_DIR/tests/vap/allowlist/resources/non-whitelisted-subscription.yaml" \
    "true"

  local test1=$?

  echo ""
  show_info "Testing: web-terminal operator should be ALLOWED (on allowlist)"
  run_cmd "web-terminal operator allowed by allowlist" \
    "oc apply --dry-run=server -f $SCRIPT_DIR/tests/vap/allowlist/resources/whitelisted-subscription.yaml"

  local test2=$?

  if [ $test1 -eq 0 ] && [ $test2 -eq 0 ]; then
    VAP_ALLOWLIST_RESULT="PASS"
  else
    VAP_ALLOWLIST_RESULT="FAIL"
  fi
}

vap_allowlist_remove() {
  section "2.3" "Remove the VAP Allowlist Policy"

  run_cmd "Allowlist policy, binding, and ConfigMap removed" \
    "oc delete -k $SCRIPT_DIR/policies/vap/allowlist/" || true

  echo ""
  show_info "Verifying policy is gone..."
  if oc get validatingadmissionpolicy allow-operator-subscriptions &>/dev/null; then
    show_fail "Policy still exists"
  else
    show_pass "Policy successfully removed"
  fi
}

vap_blocklist_deploy() {
  section "2.4" "Deploy the VAP Blocklist Policy"

  show_info "Blocked operators: ansible-automation-platform-operator,"
  show_info "  serverless-operator, openshift-pipelines-operator-rh,"
  show_info "  servicemeshoperator, cluster-logging, compliance-operator"
  echo ""

  run_cmd "Blocklist policy, binding, and ConfigMap deployed" \
    "oc apply -k $SCRIPT_DIR/policies/vap/blocklist/" || return 1

  echo ""
  run_cmd "ValidatingAdmissionPolicy exists" \
    "oc get validatingadmissionpolicy block-operator-subscriptions" || return 1
}

vap_blocklist_test() {
  section "2.5" "Test the VAP Blocklist"

  show_info "Testing: AAP operator should be DENIED (on blocklist)"
  run_cmd "AAP operator denied by blocklist" \
    "oc apply -f $SCRIPT_DIR/tests/vap/blocklist/resources/blocked-subscription.yaml" \
    "true"

  local test1=$?

  echo ""
  show_info "Testing: web-terminal operator should be ALLOWED (not on blocklist)"
  run_cmd "web-terminal operator allowed (not blocked)" \
    "oc apply --dry-run=server -f $SCRIPT_DIR/tests/vap/blocklist/resources/allowed-subscription.yaml"

  local test2=$?

  if [ $test1 -eq 0 ] && [ $test2 -eq 0 ]; then
    VAP_BLOCKLIST_RESULT="PASS"
  else
    VAP_BLOCKLIST_RESULT="FAIL"
  fi
}

vap_blocklist_remove() {
  section "2.6" "Remove the VAP Blocklist Policy"

  run_cmd "Blocklist policy, binding, and ConfigMap removed" \
    "oc delete -k $SCRIPT_DIR/policies/vap/blocklist/" || true

  echo ""
  show_info "Optionally removing operator-guardrails namespace..."
  run_cmd "Namespace removed" \
    "oc delete -f $SCRIPT_DIR/policies/vap/namespace.yaml --timeout=60s" || true
}

run_part2() {
  banner "Part 2: Validating Admission Policy (VAP)"
  show_info "VAP is built into the Kubernetes API server (OpenShift 4.17+)."
  show_info "No external controller is needed — policies use CEL expressions."
  echo ""

  vap_allowlist_deploy
  vap_allowlist_test
  vap_allowlist_remove
  vap_blocklist_deploy
  vap_blocklist_test
  vap_blocklist_remove
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  banner "Tutorial Summary"

  # Format result with color
  format_result() {
    local result="$1"
    case "$result" in
      PASS) echo -e "${GREEN}PASS${NC}" ;;
      FAIL) echo -e "${RED}FAIL${NC}" ;;
      *)    echo -e "${DIM}---${NC}" ;;
    esac
  }

  echo -e "  ${BOLD}Test Results:${NC}"
  echo ""
  printf "  %-35s  %-12s  %-12s\n" "" "Kyverno" "VAP"
  echo -e "  ${DIM}$(printf '%.0s─' {1..62})${NC}"
  printf "  %-35s  %-22b  %-22b\n" "Allowlist (deny unlisted)" "$(format_result "$KYVERNO_ALLOWLIST_RESULT")" "$(format_result "$VAP_ALLOWLIST_RESULT")"
  printf "  %-35s  %-22b  %-22b\n" "Blocklist (deny listed)" "$(format_result "$KYVERNO_BLOCKLIST_RESULT")" "$(format_result "$VAP_BLOCKLIST_RESULT")"
  echo -e "  ${DIM}$(printf '%.0s─' {1..62})${NC}"
  echo ""

  echo -e "  ${BOLD}Overall:${NC}"
  echo -e "    Total checks:  $TOTAL_STEPS"
  echo -e "    Passed:        ${GREEN}$PASSED_STEPS${NC}"
  if [ "$FAILED_STEPS" -gt 0 ]; then
    echo -e "    Failed:        ${RED}$FAILED_STEPS${NC}"
  else
    echo -e "    Failed:        $FAILED_STEPS"
  fi
  if [ "$SKIPPED_STEPS" -gt 0 ]; then
    echo -e "    Skipped:       ${YELLOW}$SKIPPED_STEPS${NC}"
  fi
  echo ""

  echo -e "  ${BOLD}Key Differences:${NC}"
  echo -e "    Kyverno  — External controller, supports offline CLI testing, mutation, generation"
  echo -e "    VAP      — Built-in (OpenShift 4.17+), CEL expressions, no install, lower latency"
  echo ""

  if [ "$FAILED_STEPS" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All checks passed. Tutorial completed successfully.${NC}"
  else
    echo -e "  ${RED}${BOLD}Some checks failed. Review the output above for details.${NC}"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local run_kyverno=true
  local run_vap=true

  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --kyverno)
        run_kyverno=true
        run_vap=false
        ;;
      --vap)
        run_kyverno=false
        run_vap=true
        ;;
      --help|-h)
        echo "Usage: $0 [--kyverno] [--vap] [--help]"
        echo ""
        echo "  --kyverno   Run only Part 1 (Kyverno)"
        echo "  --vap       Run only Part 2 (VAP)"
        echo "  --help      Show this help message"
        echo ""
        echo "With no arguments, both parts are run."
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        echo "Run '$0 --help' for usage."
        exit 1
        ;;
    esac
  done

  echo ""
  echo -e "${BOLD}${CYAN}"
  echo "   ___                       _              ____                     _           _ _"
  echo "  / _ \ _ __   ___ _ __ __ _| |_ ___  _ __ / ___|_   _  __ _ _ __ __| |_ __ __ _(_) |___"
  echo " | | | | '_ \ / _ \ '__/ _\` | __/ _ \| '__| |  _| | | |/ _\` | '__/ _\` | '__/ _\` | | / __|"
  echo " | |_| | |_) |  __/ | | (_| | || (_) | |  | |_| | |_| | (_| | | | (_| | | | (_| | | \__ \\"
  echo "  \___/| .__/ \___|_|  \__,_|\__\___/|_|   \____|\__,_|\__,_|_|  \__,_|_|  \__,_|_|_|___/"
  echo "       |_|"
  echo -e "${NC}"
  echo -e "  ${DIM}End-to-End Tutorial Runner${NC}"
  echo ""

  check_prerequisites

  if [ "$run_kyverno" = true ]; then
    run_part1
  fi

  if [ "$run_vap" = true ]; then
    run_part2
  fi

  print_summary

  [ "$FAILED_STEPS" -eq 0 ] && exit 0 || exit 1
}

main "$@"
