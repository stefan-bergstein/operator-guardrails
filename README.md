# Operator Guardrails for OpenShift

Kyverno-based policies that control which OLM operators can be installed on OpenShift clusters. Two independent approaches are available:

- **Blocklist** — deny operators listed in a ConfigMap; allow everything else.
- **Allowlist** — allow only operators listed in a ConfigMap; deny everything else.

Each approach is deployed independently. Choose the one that fits your security model.

## How It Works

Both policies intercept `Subscription` resources (the OLM mechanism for installing operators) using a Kyverno `ClusterPolicy` admission webhook.

### Blocklist

```
User creates Subscription
        |
        v
Policy loads blocked-operators ConfigMap
        |
        v
Is spec.name in the blocked packages list?
       / \
     yes   no
      |     |
   DENY   ALLOW
```

### Allowlist

```
User creates Subscription
        |
        v
Policy loads allowed-operators ConfigMap
        |
        v
Is spec.name in the allowed packages list?
       / \
     yes   no
      |     |
  ALLOW   DENY
```

## Prerequisites

- OpenShift cluster (tested on 4.x)
- Kyverno installed on the cluster ([installation guide](docs/tutorial.md#installing-kyverno-on-openshift))
- `oc` CLI authenticated to the cluster
- Kyverno CLI for local testing (`brew install kyverno`)

## Quick Start

### Option A — Blocklist (deny specific operators)

```bash
# Deploy the blocklist policy and ConfigMap
oc apply -k policies/blocklist/

# Verify the policy is active
oc get clusterpolicies block-operator-subscriptions
```

Edit `policies/blocklist/blocked-operators-configmap.yaml` to change which operators are blocked.

### Option B — Allowlist (allow only approved operators)

```bash
# Deploy the allowlist policy and ConfigMap
oc apply -k policies/allowlist/

# Verify the policy is active
oc get clusterpolicies allow-operator-subscriptions
```

Edit `policies/allowlist/allowed-operators-configmap.yaml` to change which operators are approved.

## Project Structure

```
policies/
  blocklist/
    blocked-operators-configmap.yaml   # List of blocked OLM package names
    block-operator-subscriptions.yaml  # ClusterPolicy that enforces the block list
    kustomization.yaml                 # Deploys both resources together
  allowlist/
    allowed-operators-configmap.yaml   # List of allowed OLM package names
    allow-operator-subscriptions.yaml  # ClusterPolicy that enforces the allow list
    kustomization.yaml                 # Deploys both resources together
tests/
  blocklist/
    kyverno-test.yaml                  # Test manifest for blocklist policy
    values.yaml                        # ConfigMap context values for offline testing
    resources/
      blocked-subscription.yaml        # Sample blocked Subscription (expects deny)
      allowed-subscription.yaml        # Sample allowed Subscription (expects allow)
  allowlist/
    kyverno-test.yaml                  # Test manifest for allowlist policy
    values.yaml                        # ConfigMap context values for offline testing
    resources/
      whitelisted-subscription.yaml    # Sample approved Subscription (expects allow)
      non-whitelisted-subscription.yaml # Sample unapproved Subscription (expects deny)
docs/
  tutorial.md                          # Kyverno tutorial with OpenShift-specific guidance
```

## Default Blocked Operators (Blocklist)

| OLM Package Name | Operator |
|---|---|
| `ansible-automation-platform-operator` | Ansible Automation Platform |
| `serverless-operator` | OpenShift Serverless |
| `openshift-pipelines-operator-rh` | OpenShift Pipelines |
| `servicemeshoperator` | OpenShift Service Mesh |
| `cluster-logging` | Cluster Logging |
| `compliance-operator` | Compliance Operator |

## Default Allowed Operators (Allowlist)

| OLM Package Name | Operator |
|---|---|
| `web-terminal` | Web Terminal |
| `openshift-gitops-operator` | OpenShift GitOps |

## Managing the Operator Lists

### Blocklist

Edit `policies/blocklist/blocked-operators-configmap.yaml` to add or remove operator package names, then re-apply:

```bash
oc apply -f policies/blocklist/blocked-operators-configmap.yaml
```

### Allowlist

Edit `policies/allowlist/allowed-operators-configmap.yaml` to add or remove approved operator package names, then re-apply:

```bash
oc apply -f policies/allowlist/allowed-operators-configmap.yaml
```

Kyverno detects ConfigMap changes automatically. No policy redeployment is needed.

To find the correct OLM package name for an operator:

```bash
oc get packagemanifests -n openshift-marketplace | grep <keyword>
```

## Enforcement Modes

Both policies default to `Enforce`, which blocks non-compliant requests. To switch to `Audit` mode (log violations without blocking), change `validationFailureAction` in the respective policy YAML:

```yaml
spec:
  validationFailureAction: Audit
```

View audit violations with:

```bash
oc get policyreport -A
```

## Testing

Run the Kyverno CLI tests offline (no cluster required):

```bash
# Run blocklist tests
kyverno test tests/blocklist/

# Run allowlist tests
kyverno test tests/allowlist/
```

Expected output for each:

```
Test Summary: 2 tests passed and 0 tests failed
```

## Further Reading

- [docs/tutorial.md](docs/tutorial.md) -- step-by-step Kyverno tutorial covering installation, core concepts, deployment, and troubleshooting
- [Kyverno documentation](https://kyverno.io/docs/)
- [OpenShift OLM documentation](https://docs.openshift.com/container-platform/latest/operators/understanding/olm/olm-understanding-olm.html)
