# Operator Guardrails

## Purpose

This project controls which operators can be installed on OpenShift. Two independent approaches are available:

- **Blocklist** — deny operators listed in a ConfigMap; allow everything else.
- **Allowlist** — allow only operators listed in a ConfigMap; deny everything else.

Each approach is deployed independently. The admin chooses one or the other.

Two enforcement engines are provided — the admin picks one:

- **Kyverno** (`policies/blocklist/`, `policies/allowlist/`, `policies/audit/`) — uses Kyverno ClusterPolicy resources.
- **Validating Admission Policy** (`policies/vap/blocklist/`, `policies/vap/allowlist/`, `policies/vap/audit/`) — uses the built-in Kubernetes ValidatingAdmissionPolicy API (no external controller required).

## Project Structure

```
├── CLAUDE.md                            # This file
├── bootstrap/
│   └── kyverno/
│       ├── namespace.yaml                   # Namespace for Kyverno
│       ├── kyverno-application.yaml         # ArgoCD Application (Helm chart)
│       └── kyverno-openshift-values.yaml     # Helm values for OpenShift (shared)
├── docs/
│   └── tutorial.md                      # Beginner Kyverno tutorial
├── policies/
│   ├── blocklist/                           # Kyverno blocklist
│   │   ├── kustomization.yaml
│   │   ├── blocked-operators-configmap.yaml
│   │   └── block-operator-subscriptions.yaml
│   ├── allowlist/                           # Kyverno allowlist
│   │   ├── kustomization.yaml
│   │   ├── allowed-operators-configmap.yaml
│   │   └── allow-operator-subscriptions.yaml
│   ├── audit/                               # Kyverno audit
│   │   ├── kustomization.yaml
│   │   └── audit-guardrail-changes.yaml
│   └── vap/                                 # Validating Admission Policy (no Kyverno needed)
│       ├── namespace.yaml                       # operator-guardrails namespace
│       ├── blocklist/
│       │   ├── kustomization.yaml
│       │   ├── blocked-operators-configmap.yaml
│       │   ├── block-operator-subscriptions-policy.yaml
│       │   └── block-operator-subscriptions-binding.yaml
│       ├── allowlist/
│       │   ├── kustomization.yaml
│       │   ├── allowed-operators-configmap.yaml
│       │   ├── allowed-operators-configmap-stormshift-ocp5.yaml
│       │   ├── allow-operator-subscriptions-policy.yaml
│       │   └── allow-operator-subscriptions-binding.yaml
│       └── audit/
│           ├── kustomization.yaml
│           ├── audit-guardrail-changes-policy.yaml
│           └── audit-guardrail-changes-binding.yaml
└── tests/
    ├── blocklist/                           # Kyverno CLI tests
    │   ├── kyverno-test.yaml
    │   ├── values.yaml
    │   └── resources/
    │       ├── blocked-subscription.yaml
    │       └── allowed-subscription.yaml
    ├── allowlist/                           # Kyverno CLI tests
    │   ├── kyverno-test.yaml
    │   ├── values.yaml
    │   └── resources/
    │       ├── whitelisted-subscription.yaml
    │       └── non-whitelisted-subscription.yaml
    ├── audit/                               # Kyverno CLI tests
    │   ├── kyverno-test.yaml
    │   └── resources/
    │       ├── guardrail-configmap.yaml
    │       └── regular-configmap.yaml
    └── vap/                                 # VAP tests (require running cluster)
        ├── blocklist/
        │   ├── test.sh
        │   └── resources/
        │       ├── blocked-subscription.yaml
        │       └── allowed-subscription.yaml
        ├── allowlist/
        │   ├── test.sh
        │   └── resources/
        │       ├── whitelisted-subscription.yaml
        │       └── non-whitelisted-subscription.yaml
        └── audit/
            ├── test.sh
            └── resources/
                ├── guardrail-configmap.yaml
                └── regular-configmap.yaml
```

## Conventions

- All Kubernetes manifests use YAML.
- Blocklist and allowlist policies default to `Enforce` / `Deny` mode (not `Audit`). The audit policy uses `Audit` mode by design.
- **Kyverno:** blocklist driven by `policies/blocklist/blocked-operators-configmap.yaml`; allowlist driven by `policies/allowlist/allowed-operators-configmap.yaml`.
- **VAP:** blocklist driven by `policies/vap/blocklist/blocked-operators-configmap.yaml`; allowlist driven by `policies/vap/allowlist/allowed-operators-configmap.yaml`. ConfigMaps live in the `operator-guardrails` namespace.

## Testing

### Kyverno (offline, no cluster required)

```bash
kyverno test tests/blocklist/
kyverno test tests/allowlist/
kyverno test tests/audit/
```

To install the Kyverno CLI:

```bash
# macOS
brew install kyverno

# or download from https://github.com/kyverno/kyverno/releases
```

### VAP (requires a running cluster with OLM)

Deploy the policies first, then run the test scripts:

```bash
# Blocklist tests
tests/vap/blocklist/test.sh

# Allowlist tests
tests/vap/allowlist/test.sh

# Audit policy tests
tests/vap/audit/test.sh
```

## Deploying

### Option A: Kyverno

```bash
# Bootstrap Kyverno via ArgoCD (prerequisite for Kyverno policies)
oc apply -f bootstrap/kyverno/namespace.yaml
oc apply -f bootstrap/kyverno/kyverno-application.yaml

# Deploy the blocklist approach
oc apply -k policies/blocklist/

# OR deploy the allowlist approach
oc apply -k policies/allowlist/

# Optionally, deploy the audit policy alongside either approach
oc apply -k policies/audit/
```

### Option B: Validating Admission Policy (no external controller)

```bash
# Create the namespace for VAP ConfigMaps (prerequisite)
oc apply -f policies/vap/namespace.yaml

# Deploy the blocklist approach
oc apply -k policies/vap/blocklist/

# OR deploy the allowlist approach
oc apply -k policies/vap/allowlist/

# Optionally, deploy the audit policy alongside either approach
oc apply -k policies/vap/audit/
```
