# Operator Guardrails with Kyverno

## Purpose

This project uses Kyverno policies to control which operators can be installed on OpenShift. Two independent approaches are available:

- **Blocklist** — deny operators listed in a ConfigMap; allow everything else.
- **Allowlist** — allow only operators listed in a ConfigMap; deny everything else.

Each approach is deployed independently. The admin chooses one or the other.

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
│   ├── blocklist/
│   │   ├── kustomization.yaml               # Kustomize overlay for blocklist
│   │   ├── blocked-operators-configmap.yaml  # ConfigMap with blocked operator list
│   │   └── block-operator-subscriptions.yaml # Policy blocking Subscription resources
│   ├── allowlist/
│   │   ├── kustomization.yaml               # Kustomize overlay for allowlist
│   │   ├── allowed-operators-configmap.yaml  # ConfigMap with allowed operator list
│   │   └── allow-operator-subscriptions.yaml # Policy allowing only listed Subscriptions
│   └── audit/
│       ├── kustomization.yaml               # Kustomize overlay for audit policy
│       └── audit-guardrail-changes.yaml     # Audit policy for guardrail resource changes
└── tests/
    ├── blocklist/
    │   ├── kyverno-test.yaml              # Kyverno CLI test manifest
    │   ├── values.yaml                    # Context variable values for CLI testing
    │   └── resources/
    │       ├── blocked-subscription.yaml
    │       └── allowed-subscription.yaml
    ├── allowlist/
    │   ├── kyverno-test.yaml              # Kyverno CLI test manifest
    │   ├── values.yaml                    # Context variable values for CLI testing
    │   └── resources/
    │       ├── whitelisted-subscription.yaml
    │       └── non-whitelisted-subscription.yaml
    └── audit/
        ├── kyverno-test.yaml              # Kyverno CLI test manifest
        └── resources/
            ├── guardrail-configmap.yaml
            └── regular-configmap.yaml
```

## Conventions

- All Kubernetes manifests use YAML.
- Blocklist and allowlist policies default to `Enforce` mode (not `Audit`). The audit policy uses `Audit` mode by design.
- The blocklist is driven by `policies/blocklist/blocked-operators-configmap.yaml`.
- The allowlist is driven by `policies/allowlist/allowed-operators-configmap.yaml`.

## Testing

Run Kyverno CLI tests locally (no cluster required):

```bash
# Blocklist tests
kyverno test tests/blocklist/

# Allowlist tests
kyverno test tests/allowlist/

# Audit policy tests
kyverno test tests/audit/
```

To install the Kyverno CLI:

```bash
# macOS
brew install kyverno

# or download from https://github.com/kyverno/kyverno/releases
```

## Deploying

```bash
# Bootstrap Kyverno via ArgoCD (prerequisite for all policies)
oc apply -f bootstrap/kyverno/namespace.yaml
oc apply -f bootstrap/kyverno/kyverno-application.yaml

# Deploy the blocklist approach
oc apply -k policies/blocklist/

# OR deploy the allowlist approach
oc apply -k policies/allowlist/

# Optionally, deploy the audit policy alongside either approach
oc apply -k policies/audit/
```
