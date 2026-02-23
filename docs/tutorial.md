# Kyverno Operator Guardrails on OpenShift — Tutorial

This tutorial walks you through using Kyverno to control which operators can be installed on an OpenShift cluster. Two approaches are covered:

- **Blocklist** — deny specific operators; allow everything else.
- **Allowlist** — allow only approved operators; deny everything else.

No prior Kyverno experience is required.

## Table of Contents

1. [What is Kyverno?](#what-is-kyverno)
2. [Installing Kyverno on OpenShift](#installing-kyverno-on-openshift)
3. [Core Concepts](#core-concepts)
4. [How the Blocklist Policy Works](#how-the-blocklist-policy-works)
5. [How the Allowlist Policy Works](#how-the-allowlist-policy-works)
6. [Deploying the Policies](#deploying-the-policies)
7. [Testing Locally with the Kyverno CLI](#testing-locally-with-the-kyverno-cli)
8. [Verifying on a Live Cluster](#verifying-on-a-live-cluster)
9. [Managing the Operator Lists](#managing-the-operator-lists)
10. [Troubleshooting](#troubleshooting)

---

## What is Kyverno?

Kyverno is a policy engine designed for Kubernetes. It runs as an admission controller — a webhook that intercepts every request to the Kubernetes API server (create, update, delete) and evaluates it against a set of policies you define.

**Why use it?**

- **No new language to learn.** Policies are plain Kubernetes YAML. There is no Rego or other DSL.
- **Familiar tooling.** You manage policies with `kubectl`/`oc`, Kustomize, Helm, and GitOps workflows.
- **Validate, mutate, or generate resources.** This project uses the *validate* capability to deny blocked operators.

## Installing Kyverno on OpenShift

### Install Kyverno using YAMLs

```bash
kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.16.3/install.yaml
```

### Verify the installation

```bash
oc get pods -n kyverno
```

You should see Kyverno pods in `Running` state.


### Install Kyverno using Helm

You can install Kyverno directly with the Helm CLI. The values file `bootstrap/kyverno/kyverno-openshift-values.yaml` contains OpenShift-specific overrides (security context settings for the restricted-v2 SCC and HA replica counts).

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version 3.5.2 \
  -f bootstrap/kyverno/kyverno-openshift-values.yaml
```

Verify the installation:

```bash
oc get pods -n kyverno
```

You should see the Kyverno controller pods in `Running` state.

### Install Kyverno using ArgoCD (Helm)

If your cluster runs ArgoCD (OpenShift GitOps), you can install Kyverno as a Helm-managed ArgoCD Application. The bootstrap manifests in this repository include OpenShift-specific settings (security context overrides for the restricted-v2 SCC and webhook namespace exclusions for OpenShift system namespaces).

```bash
oc apply -f bootstrap/kyverno/namespace.yaml
oc apply -f bootstrap/kyverno/kyverno-application.yaml
```

ArgoCD will install the Kyverno Helm chart into the `kyverno` namespace and keep it in sync. Verify the sync status and pods:

```bash
oc get application kyverno -n openshift-gitops
oc get pods -n kyverno
```

The ArgoCD Application manifest (`bootstrap/kyverno/kyverno-application.yaml`) already configures the webhook namespace exclusion for OpenShift system namespaces, so the manual ConfigMap update below is not needed when using this method.

### Update kyverno config map

When using the raw YAML install method above, you should prevent Kyverno from scanning OpenShift system namespaces. Update the `kyverno` ConfigMap to include the following `webhooks` entry:

```
{"key":"openshift.io/run-level","operator":"NotIn", "values": ["0","1"]}
```

This step is not needed when installing via ArgoCD, as it is handled by the Helm values.

---

## Core Concepts

### ClusterPolicy

A `ClusterPolicy` is a cluster-scoped Kyverno resource. It applies to all namespaces (unlike a `Policy`, which is namespace-scoped). Each ClusterPolicy contains one or more **rules**.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: example-policy
spec:
  validationFailureAction: Enforce   # or Audit
  rules:
    - name: example-rule
      match: ...
      validate: ...
```

### Rules

A rule has three main sections:

| Section      | Purpose |
|-------------|---------|
| `match`     | Select which resources this rule applies to (by kind, namespace, labels, etc.). |
| `exclude`   | Optionally skip certain resources that otherwise match. |
| `validate`  | Define what makes a resource compliant. Non-compliant resources are denied (Enforce) or flagged (Audit). |

### match / exclude

```yaml
match:
  any:
    - resources:
        kinds:
          - operators.coreos.com/v1alpha1/Subscription
```

This matches all `Subscription` resources from the OLM API group. You can narrow the match with `namespaces`, `names`, `labelSelectors`, and more.

### validate and deny

The `validate` block can either define a **pattern** the resource must match or a **deny** block with conditions. When using `deny`, the resource is rejected if the conditions evaluate to `true`.

```yaml
validate:
  message: "Human-readable denial reason"
  deny:
    conditions:
      any:
        - key: "{{ request.object.spec.name }}"
          operator: AnyIn
          value: ["blocked-pkg-1", "blocked-pkg-2"]
```

### Enforce vs Audit

| Mode      | Behavior |
|-----------|----------|
| `Enforce` | Blocks non-compliant resources from being created or updated. The API request is denied. |
| `Audit`   | Allows the resource but records a policy violation. Useful for dry-run testing. |

Set the mode in `spec.validationFailureAction`.

---

## How the Blocklist Policy Works

The blocklist policy blocks OLM operator installations by denying `Subscription` resources whose package name appears in a ConfigMap.

### The ConfigMap

`policies/blocklist/blocked-operators-configmap.yaml` lives in the `kyverno` namespace and contains one field:

- **`packages`** — comma-separated list of OLM package names to block.

```yaml
data:
  packages: >-
    ansible-automation-platform-operator,
    serverless-operator,
    openshift-pipelines-operator-rh,
    servicemeshoperator,
    cluster-logging,
    compliance-operator
```

### The Policy — Block Subscriptions

File: `policies/blocklist/block-operator-subscriptions.yaml`

When someone creates or updates a `Subscription` resource, this policy:

1. Loads the `blocked-operators` ConfigMap as a context variable.
2. Splits the `packages` string into an array.
3. Checks if `spec.name` (the OLM package name) is in the blocked list.
4. If it matches, the request is denied with a descriptive message.

**Key technique:** The `AnyIn` operator checks membership in the array produced by `split()`.

---

## How the Allowlist Policy Works

The allowlist policy is the inverse of the blocklist. It denies `Subscription` resources whose package name is **not** in a ConfigMap of approved operators.

### The ConfigMap

`policies/allowlist/allowed-operators-configmap.yaml` lives in the `kyverno` namespace and contains one field:

- **`packages`** — comma-separated list of OLM package names that are permitted.

```yaml
data:
  packages: >-
    web-terminal,
    openshift-gitops-operator
```

### The Policy — Allow Subscriptions

File: `policies/allowlist/allow-operator-subscriptions.yaml`

When someone creates or updates a `Subscription` resource, this policy:

1. Loads the `allowed-operators` ConfigMap as a context variable.
2. Splits the `packages` string into an array.
3. Checks if `spec.name` (the OLM package name) is **not** in the allowed list.
4. If it is not in the list, the request is denied with a descriptive message.

**Key technique:** The `AnyNotIn` operator (instead of `AnyIn`) inverts the logic — it denies when the value is absent from the list.

```yaml
deny:
  conditions:
    all:
      - key: "{{ request.object.spec.name }}"
        operator: AnyNotIn
        value: "{{ allowedPackages.data.packages | split(@, ', ') }}"
```

### Blocklist vs Allowlist — When to Use Each

| Approach | Best for |
|----------|----------|
| **Blocklist** | Clusters where most operators are fine, but a few must be restricted. |
| **Allowlist** | Locked-down clusters where only a curated set of operators is permitted. |

Deploy one or the other — not both at the same time on the same cluster.

---

## Deploying the Policies

Choose **one** approach — blocklist or allowlist — and deploy it.

### Blocklist — Using Kustomize (recommended)

```bash
oc apply -k policies/blocklist/
```

This applies the blocked-operators ConfigMap and the block ClusterPolicy in one step.

#### Manual apply

```bash
oc apply -f policies/blocklist/blocked-operators-configmap.yaml
oc apply -f policies/blocklist/block-operator-subscriptions.yaml
```

### Allowlist — Using Kustomize (recommended)

```bash
oc apply -k policies/allowlist/
```

This applies the allowed-operators ConfigMap and the allow ClusterPolicy in one step.

#### Manual apply

```bash
oc apply -f policies/allowlist/allowed-operators-configmap.yaml
oc apply -f policies/allowlist/allow-operator-subscriptions.yaml
```

### Verify

```bash
# Check the policy is ready
oc get clusterpolicies

# Expected output (blocklist):
# NAME                           ADMISSION   BACKGROUND   VALIDATE ACTION   READY
# block-operator-subscriptions   true        false        Enforce           True

# Expected output (allowlist):
# NAME                           ADMISSION   BACKGROUND   VALIDATE ACTION   READY
# allow-operator-subscriptions   true        false        Enforce           True
```

---

## Testing Locally with the Kyverno CLI

The Kyverno CLI lets you test policies against sample resources without a running cluster.

### Install the CLI

```bash
# macOS
brew install kyverno

# Linux (download from GitHub releases)
# https://github.com/kyverno/kyverno/releases
```

### Run the tests

```bash
# Blocklist tests
kyverno test tests/blocklist/

# Allowlist tests
kyverno test tests/allowlist/
```

Each test directory contains a `kyverno-test.yaml` manifest referencing the policy, a values file for ConfigMap context data, and sample resources. The `results` section declares the expected outcome for each resource.

### What the blocklist tests verify

| Resource | Expected |
|----------|----------|
| `aap-operator` Subscription | Denied (fail) |
| `web-terminal` Subscription | Allowed (pass) |

### What the allowlist tests verify

| Resource | Expected |
|----------|----------|
| `web-terminal` Subscription | Allowed (pass) — on the approved list |
| `aap-operator` Subscription | Denied (fail) — not on the approved list |

---

## Verifying on a Live Cluster

After deploying the policy, test it on the cluster.

### Blocklist — Test 1: Blocked Subscription

```bash
oc apply -f tests/blocklist/resources/blocked-subscription.yaml
```

Expected output:

```
Error from server: error when creating "blocked-subscription.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Subscription/openshift-operators/aap-operator was blocked due to
the following policies:

block-operator-subscriptions:
  check-subscription-name: The operator "ansible-automation-platform-operator"
  is blocked by policy. ...
```

### Blocklist — Test 2: Allowed Subscription

```bash
oc apply -f tests/blocklist/resources/allowed-subscription.yaml
```

Expected: the Subscription is created (or you see an OLM error if the operator doesn't exist in your catalog — but no Kyverno denial).

### Allowlist — Test 1: Approved Subscription

```bash
oc apply -f tests/allowlist/resources/whitelisted-subscription.yaml
```

Expected: the Subscription is created (the operator is on the approved list).

### Allowlist — Test 2: Unapproved Subscription

```bash
oc apply -f tests/allowlist/resources/non-whitelisted-subscription.yaml
```

Expected output:

```
Error from server: error when creating "non-whitelisted-subscription.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Subscription/openshift-operators/aap-operator was blocked due to
the following policies:

allow-operator-subscriptions:
  check-subscription-name: The operator "ansible-automation-platform-operator"
  is not on the approved list. ...
```

---

## Managing the Operator Lists

### Blocklist — Add or remove a blocked operator

1. Edit `policies/blocklist/blocked-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/blocklist/blocked-operators-configmap.yaml
   ```

Kyverno picks up the ConfigMap change automatically — no policy restart needed.

### Allowlist — Add or remove an approved operator

1. Edit `policies/allowlist/allowed-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/allowlist/allowed-operators-configmap.yaml
   ```

### Switch to Audit mode for dry-run

Edit the relevant ClusterPolicy YAML and change:

```yaml
spec:
  validationFailureAction: Enforce
```

to:

```yaml
spec:
  validationFailureAction: Audit
```

Re-apply the policy. Violations will be logged but not blocked. View violations with:

```bash
oc get policyreport -A
oc get clusterpolicyreport
```

---

## Troubleshooting

### Policy shows READY=False

```bash
# For blocklist
oc describe clusterpolicy block-operator-subscriptions

# For allowlist
oc describe clusterpolicy allow-operator-subscriptions
```

Check the `status.conditions` for error messages. Common causes:

- The ConfigMap (`blocked-operators` or `allowed-operators`) does not exist in the `kyverno` namespace.
- Kyverno does not have permission to read ConfigMaps in its namespace.

### Operator still installs despite the policy

- Confirm the policy is in `Enforce` mode (not `Audit`).
- For blocklist: confirm the operator's package name is in the blocked ConfigMap's `packages` list with the exact spelling used by the OLM catalog.
- For allowlist: confirm the operator's package name is **not** in the allowed ConfigMap's `packages` list (if you want it denied), or **is** in the list (if you want it permitted).
- Check if the Subscription already existed before the policy was applied — Kyverno only intercepts new creates/updates.

  ```bash
  oc get subscriptions -A
  ```

### Find the OLM package name for an operator

```bash
oc get packagemanifests -n openshift-marketplace | grep <operator-keyword>
```

The `NAME` column is the package name to add to the ConfigMap.
