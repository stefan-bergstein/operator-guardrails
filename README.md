# Operator Guardrails for OpenShift

Policies that control which OLM operators can be installed on OpenShift clusters. Two independent approaches are available:

- **Blocklist** — deny operators listed in a ConfigMap; allow everything else.
- **Allowlist** — allow only operators listed in a ConfigMap; deny everything else.

Each approach is deployed independently. Choose the one that fits your security model.

Two enforcement engines are provided — pick the one that suits your cluster:

| Engine | Directory | Requires |
|--------|-----------|----------|
| **Kyverno** | `policies/kyverno/blocklist/`, `policies/kyverno/allowlist/`, `policies/kyverno/audit/` | Kyverno controller installed on the cluster |
| **Validating Admission Policy (VAP)** | `policies/vap/blocklist/`, `policies/vap/allowlist/`, `policies/vap/audit/` | Kubernetes 1.30+ / OpenShift 4.17+ (built-in, no extra controller) |

## How It Works

Both approaches intercept `Subscription` resources (the OLM mechanism for installing operators) at admission time. Kyverno uses a `ClusterPolicy` webhook; VAP uses the built-in `ValidatingAdmissionPolicy` API with CEL expressions.

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
- `oc` CLI authenticated to the cluster

**Kyverno engine only:**
- Kyverno installed on the cluster ([installation guide](docs/tutorial.md#installing-kyverno-on-openshift))
- Kyverno CLI for local testing (`brew install kyverno`)

**VAP engine only:**
- Kubernetes 1.30+ / OpenShift 4.17+ (ValidatingAdmissionPolicy GA)

## Installing Kyverno

### Option 1 — Helm CLI

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version 3.5.2 \
  -f bootstrap/kyverno/kyverno-openshift-values.yaml
```

### Option 2 — ArgoCD (OpenShift GitOps)

```bash
oc apply -f bootstrap/kyverno/namespace.yaml
oc apply -f bootstrap/kyverno/kyverno-application.yaml
```

Both options use the same OpenShift-compatible Helm values (`bootstrap/kyverno/kyverno-openshift-values.yaml`). Verify the deployment:

```bash
oc get pods -n kyverno
```

For more details, see [docs/tutorial.md](docs/tutorial.md#installing-kyverno-on-openshift).

## Quick Start

### Using Kyverno

#### Option A — Blocklist (deny specific operators)

```bash
# Deploy the blocklist policy and ConfigMap
oc apply -k policies/kyverno/blocklist/

# Verify the policy is active
oc get clusterpolicies block-operator-subscriptions
```

Edit `policies/kyverno/blocklist/blocked-operators-configmap.yaml` to change which operators are blocked.

#### Option B — Allowlist (allow only approved operators)

```bash
# Deploy the allowlist policy and ConfigMap
oc apply -k policies/kyverno/allowlist/

# Verify the policy is active
oc get clusterpolicies allow-operator-subscriptions
```

Edit `policies/kyverno/allowlist/allowed-operators-configmap.yaml` to change which operators are approved.

#### Optional — Audit policy (log changes to guardrail resources)

```bash
oc apply -k policies/kyverno/audit/
```

### Using Validating Admission Policy (no Kyverno required)

#### Option A — Blocklist

```bash
# Create the namespace for VAP ConfigMaps
oc apply -f policies/vap/namespace.yaml

# Deploy the blocklist policy, binding, and ConfigMap
oc apply -k policies/vap/blocklist/

# Verify the policy is active
oc get validatingadmissionpolicy block-operator-subscriptions
```

Edit `policies/vap/blocklist/blocked-operators-configmap.yaml` to change which operators are blocked.

#### Option B — Allowlist

```bash
oc apply -f policies/vap/namespace.yaml
oc apply -k policies/vap/allowlist/

# Verify the policy is active
oc get validatingadmissionpolicy allow-operator-subscriptions
```

Edit `policies/vap/allowlist/allowed-operators-configmap.yaml` to change which operators are approved.

#### Optional — Audit policy

```bash
oc apply -k policies/vap/audit/
```

This can be deployed alongside either the blocklist or allowlist policy (for both Kyverno and VAP).

## Project Structure

```
bootstrap/
  kyverno/
    namespace.yaml                       # Namespace for Kyverno
    kyverno-application.yaml             # ArgoCD Application (Helm chart)
    kyverno-openshift-values.yaml        # Helm values for OpenShift (shared)
policies/
  kyverno/                               # Kyverno policies
    blocklist/
      blocked-operators-configmap.yaml
      block-operator-subscriptions.yaml
      kustomization.yaml
    allowlist/
      allowed-operators-configmap.yaml
      allow-operator-subscriptions.yaml
      kustomization.yaml
    audit/
      audit-guardrail-changes.yaml
      kustomization.yaml
  vap/                                   # Validating Admission Policy (no Kyverno needed)
    namespace.yaml                         # operator-guardrails namespace
    blocklist/
      blocked-operators-configmap.yaml
      block-operator-subscriptions-policy.yaml
      block-operator-subscriptions-binding.yaml
      kustomization.yaml
    allowlist/
      allowed-operators-configmap.yaml
      allowed-operators-configmap-stormshift-ocp5.yaml
      allow-operator-subscriptions-policy.yaml
      allow-operator-subscriptions-binding.yaml
      kustomization.yaml
    audit/
      audit-guardrail-changes-policy.yaml
      audit-guardrail-changes-binding.yaml
      kustomization.yaml
tests/
  kyverno/                               # Kyverno CLI tests (offline)
    blocklist/
      kyverno-test.yaml
      values.yaml
      resources/
        blocked-subscription.yaml
        allowed-subscription.yaml
    allowlist/
      kyverno-test.yaml
      values.yaml
      resources/
        whitelisted-subscription.yaml
        non-whitelisted-subscription.yaml
    audit/
      kyverno-test.yaml
      resources/
        guardrail-configmap.yaml
        regular-configmap.yaml
  vap/                                   # VAP tests (require running cluster)
    blocklist/
      test.sh
      resources/
        blocked-subscription.yaml
        allowed-subscription.yaml
    allowlist/
      test.sh
      resources/
        whitelisted-subscription.yaml
        non-whitelisted-subscription.yaml
    audit/
      test.sh
      resources/
        guardrail-configmap.yaml
        regular-configmap.yaml
docs/
  tutorial.md                            # Tutorial covering Kyverno and VAP approaches
contrib/
  no-oke-ops.sh                          # Helper to list non-OKE operators for blocklist generation
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

### Kyverno

Edit the ConfigMap and re-apply. Kyverno detects changes automatically — no policy redeployment needed.

```bash
# Blocklist
oc apply -f policies/kyverno/blocklist/blocked-operators-configmap.yaml

# Allowlist
oc apply -f policies/kyverno/allowlist/allowed-operators-configmap.yaml
```

### VAP

Edit the ConfigMap in the `operator-guardrails` namespace and re-apply. The API server picks up changes automatically.

```bash
# Blocklist
oc apply -f policies/vap/blocklist/blocked-operators-configmap.yaml

# Allowlist
oc apply -f policies/vap/allowlist/allowed-operators-configmap.yaml
```

To find the correct OLM package name for an operator:

```bash
oc get packagemanifests -n openshift-marketplace | grep <keyword>
```

## Audit Policy

The optional audit policy logs a policy violation whenever any operator guardrail resource is created, updated, or deleted. It matches resources labelled `app.kubernetes.io/part-of: operator-guardrails`.

This policy runs in `Audit` mode — it never blocks changes, only records them. Deploy it alongside whichever approach (blocklist or allowlist) you use.

### Kyverno

Matches ConfigMaps (in the `kyverno` namespace) and ClusterPolicies with the guardrail label.

```bash
oc apply -k policies/kyverno/audit/
```

View the audit trail:

```bash
oc get policyreport -A
oc get clusterpolicyreport
```

### VAP

Matches ConfigMaps and ValidatingAdmissionPolicy/Binding resources with the guardrail label. Uses `validationActions: [Audit]`.

```bash
oc apply -k policies/vap/audit/
```

Audit events are recorded in the Kubernetes API server audit log.

## Enforcement Modes

### Kyverno

Both policies default to `Enforce`, which blocks non-compliant requests. To switch to `Audit` mode (log violations without blocking), change `validationFailureAction` in the respective policy YAML:

```yaml
spec:
  validationFailureAction: Audit
```

View audit violations with:

```bash
oc get policyreport -A
```

### VAP

Both policies use `validationActions: [Deny]` in their binding, which blocks non-compliant requests. To switch to audit mode, edit the binding YAML:

```yaml
spec:
  validationActions:
    - Audit
```

Audit events appear in the Kubernetes API server audit log.

## Testing

### Kyverno (offline, no cluster required)

```bash
kyverno test tests/kyverno/blocklist/
kyverno test tests/kyverno/allowlist/
kyverno test tests/kyverno/audit/
```

Expected output for each:

```
Test Summary: 2 tests passed and 0 tests failed
```

### VAP (requires a running cluster with OLM)

Deploy the VAP policies first, then run the test scripts:

```bash
tests/vap/blocklist/test.sh
tests/vap/allowlist/test.sh
tests/vap/audit/test.sh
```

The scripts use `oc apply --dry-run=server` to validate policy behavior without creating real resources.

## Helper Scripts

The `contrib/` directory contains helper scripts for generating operator lists. See [contrib/README.md](contrib/README.md) for details.

- **no-oke-ops.sh** — queries a live cluster to list all operators not included in an OpenShift Kubernetes Engine (OKE) subscription. The output can be piped directly into the blocklist ConfigMap.

## Disclaimer

This is a **community project** and is **not supported by Red Hat**. It is provided as-is, without warranties or guarantees of any kind. This repository and its code were partially generated with the help of GenAI tools and may contain errors or inaccuracies. Use at your own risk and always review and test thoroughly before deploying to production environments.

## Further Reading

- [docs/tutorial.md](docs/tutorial.md) — step-by-step tutorial covering both Kyverno and VAP approaches
- [Kyverno documentation](https://kyverno.io/docs/)
- [Validating Admission Policy documentation](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [OpenShift OLM documentation](https://docs.openshift.com/container-platform/latest/operators/understanding/olm/olm-understanding-olm.html)
