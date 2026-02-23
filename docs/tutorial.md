# Operator Guardrails on OpenShift — Tutorial

This tutorial walks you through controlling which operators can be installed on an OpenShift cluster. Two policy approaches are covered:

- **Blocklist** — deny specific operators; allow everything else.
- **Allowlist** — allow only approved operators; deny everything else.

Two enforcement engines are available:

- **Kyverno** — a standalone policy engine deployed as a controller.
- **Validating Admission Policy (VAP)** — built into Kubernetes 1.30+ / OpenShift 4.17+, no extra controller needed.

No prior Kyverno or VAP experience is required.

## Table of Contents

1. [What is Kyverno?](#what-is-kyverno)
2. [What is Validating Admission Policy?](#what-is-validating-admission-policy)
3. [Installing Kyverno on OpenShift](#installing-kyverno-on-openshift)
4. [Core Concepts — Kyverno](#core-concepts--kyverno)
5. [Core Concepts — VAP](#core-concepts--vap)
6. [How the Blocklist Policy Works](#how-the-blocklist-policy-works)
7. [How the Allowlist Policy Works](#how-the-allowlist-policy-works)
8. [Deploying the Policies](#deploying-the-policies)
9. [Testing Locally with the Kyverno CLI](#testing-locally-with-the-kyverno-cli)
10. [Testing VAP on a Live Cluster](#testing-vap-on-a-live-cluster)
11. [Verifying on a Live Cluster](#verifying-on-a-live-cluster)
12. [Managing the Operator Lists](#managing-the-operator-lists)
13. [Troubleshooting](#troubleshooting)

---

## What is Kyverno?

Kyverno is a policy engine designed for Kubernetes. It runs as an admission controller — a webhook that intercepts every request to the Kubernetes API server (create, update, delete) and evaluates it against a set of policies you define.

**Why use it?**

- **No new language to learn.** Policies are plain Kubernetes YAML. There is no Rego or other DSL.
- **Familiar tooling.** You manage policies with `kubectl`/`oc`, Kustomize, Helm, and GitOps workflows.
- **Validate, mutate, or generate resources.** This project uses the *validate* capability to deny blocked operators.
- **Offline testing.** The Kyverno CLI can test policies without a running cluster.

## What is Validating Admission Policy?

Validating Admission Policy (VAP) is a built-in Kubernetes feature (GA since Kubernetes 1.30 / OpenShift 4.17) that provides in-process admission control without an external webhook controller.

**Why use it?**

- **No controller to install.** VAP is part of the Kubernetes API server — nothing extra to deploy or maintain.
- **CEL expressions.** Validation rules use the Common Expression Language (CEL), a lightweight, safe expression language.
- **Lower latency.** Validation runs in-process, avoiding the network hop to a webhook.
- **Two resources.** A `ValidatingAdmissionPolicy` defines the rules; a `ValidatingAdmissionPolicyBinding` scopes and activates them.

**Trade-offs vs Kyverno:**

| | Kyverno | VAP |
|---|---|---|
| Requires controller | Yes | No |
| Expression language | JMESPath (in YAML) | CEL |
| Offline CLI testing | Yes (`kyverno test`) | No (requires cluster) |
| Mutation support | Yes | No |
| Generation support | Yes | No |
| Min K8s version | 1.25+ | 1.30+ |

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

## Core Concepts — Kyverno

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

## Core Concepts — VAP

### ValidatingAdmissionPolicy

A `ValidatingAdmissionPolicy` is a cluster-scoped resource that defines validation rules using CEL expressions. It specifies what resources to match and how to validate them.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: example-policy
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: "object.spec.replicas <= 5"
      message: "Replicas must be 5 or fewer."
```

### ValidatingAdmissionPolicyBinding

A `ValidatingAdmissionPolicyBinding` activates a policy and scopes it. Without a binding, the policy has no effect. The binding also specifies the enforcement action and parameter references.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: example-policy
spec:
  policyName: example-policy
  validationActions:
    - Deny
```

### Parameters (paramKind / paramRef)

VAP policies can reference external data through parameters. The policy declares a `paramKind` (e.g., ConfigMap), and the binding provides the specific `paramRef` (name and namespace). Inside CEL expressions, the parameter data is available as `params`.

```yaml
# In the policy
spec:
  paramKind:
    apiVersion: v1
    kind: ConfigMap

# In the binding
spec:
  paramRef:
    name: my-configmap
    namespace: my-namespace
    parameterNotFoundAction: Deny  # Fail-closed if ConfigMap is missing
```

### CEL Expressions

CEL (Common Expression Language) is used for validation logic. Key variables:

| Variable | Description |
|----------|-------------|
| `object` | The resource being created or updated |
| `oldObject` | The existing resource (for UPDATE/DELETE) |
| `params` | The parameter resource (e.g., ConfigMap data) |
| `request` | The admission request metadata |

Common CEL operations:

```cel
// String splitting and list operations
params.data.packages.split(',')
list.exists(item, item == "value")

// Field existence checks
has(object.spec.name)

// String methods
"  hello  ".trim()
```

### Validation Actions

| Action | Behavior |
|--------|----------|
| `Deny` | Blocks non-compliant resources. The API request is denied. |
| `Audit` | Allows the resource but records an audit annotation. |
| `Warn` | Allows the resource but returns a warning to the client. |

Set the action in the binding's `spec.validationActions` list.

---

## How the Blocklist Policy Works

The blocklist policy blocks OLM operator installations by denying `Subscription` resources whose package name appears in a ConfigMap.

### The ConfigMap

Both engines use the same data format — a comma-separated list of OLM package names:

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

- **Kyverno:** `policies/blocklist/blocked-operators-configmap.yaml` (namespace: `kyverno`)
- **VAP:** `policies/vap/blocklist/blocked-operators-configmap.yaml` (namespace: `operator-guardrails`)

### Kyverno — Block Subscriptions

File: `policies/blocklist/block-operator-subscriptions.yaml`

When someone creates or updates a `Subscription` resource, this policy:

1. Loads the `blocked-operators` ConfigMap as a context variable.
2. Splits the `packages` string into an array.
3. Checks if `spec.name` (the OLM package name) is in the blocked list.
4. If it matches, the request is denied with a descriptive message.

**Key technique:** The `AnyIn` operator checks membership in the array produced by `split()`.

### VAP — Block Subscriptions

Files: `policies/vap/blocklist/block-operator-subscriptions-policy.yaml` and `block-operator-subscriptions-binding.yaml`

The same logic, expressed in CEL:

1. The policy declares `paramKind: ConfigMap` and the binding references the `blocked-operators` ConfigMap.
2. A CEL variable splits the packages string: `params.data.packages.split(',')`.
3. The validation expression checks membership: `!variables.blockedPackages.exists(p, p.trim() == variables.operatorName)`.
4. If the operator is in the blocked list, the expression returns `false` and the request is denied.

**Key technique:** CEL's `exists()` macro with `trim()` handles the comma-separated list with whitespace.

---

## How the Allowlist Policy Works

The allowlist policy is the inverse of the blocklist. It denies `Subscription` resources whose package name is **not** in a ConfigMap of approved operators.

### The ConfigMap

Both engines use the same data format:

```yaml
data:
  packages: >-
    web-terminal,
    openshift-gitops-operator
```

- **Kyverno:** `policies/allowlist/allowed-operators-configmap.yaml` (namespace: `kyverno`)
- **VAP:** `policies/vap/allowlist/allowed-operators-configmap.yaml` (namespace: `operator-guardrails`)

### Kyverno — Allow Subscriptions

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

### VAP — Allow Subscriptions

Files: `policies/vap/allowlist/allow-operator-subscriptions-policy.yaml` and `allow-operator-subscriptions-binding.yaml`

The same logic, expressed in CEL:

1. The policy declares `paramKind: ConfigMap` and the binding references the `allowed-operators` ConfigMap.
2. A CEL variable splits the packages string: `params.data.packages.split(',')`.
3. The validation expression checks membership: `variables.allowedPackages.exists(p, p.trim() == variables.operatorName)`.
4. If the operator is **not** in the allowed list, the expression returns `false` and the request is denied.

**Key technique:** The expression is the positive form (`exists`) rather than the negated form used for blocklist — returning `true` only when the operator is found in the allowed list.

### Blocklist vs Allowlist — When to Use Each

| Approach | Best for |
|----------|----------|
| **Blocklist** | Clusters where most operators are fine, but a few must be restricted. |
| **Allowlist** | Locked-down clusters where only a curated set of operators is permitted. |

Deploy one or the other — not both at the same time on the same cluster.

---

## Deploying the Policies

Choose **one** approach — blocklist or allowlist — and **one** engine — Kyverno or VAP.

### Kyverno

#### Blocklist — Using Kustomize (recommended)

```bash
oc apply -k policies/blocklist/
```

This applies the blocked-operators ConfigMap and the block ClusterPolicy in one step.

#### Allowlist — Using Kustomize (recommended)

```bash
oc apply -k policies/allowlist/
```

#### Verify Kyverno

```bash
oc get clusterpolicies

# Expected output (blocklist):
# NAME                           ADMISSION   BACKGROUND   VALIDATE ACTION   READY
# block-operator-subscriptions   true        false        Enforce           True
```

### VAP

#### Blocklist

```bash
oc apply -f policies/vap/namespace.yaml
oc apply -k policies/vap/blocklist/
```

This creates the `operator-guardrails` namespace, applies the ConfigMap, and creates the ValidatingAdmissionPolicy and its binding.

#### Allowlist

```bash
oc apply -f policies/vap/namespace.yaml
oc apply -k policies/vap/allowlist/
```

#### Verify VAP

```bash
oc get validatingadmissionpolicy

# Expected output (blocklist):
# NAME                           VALIDATIONS   PARAMKIND        AGE
# block-operator-subscriptions   1             ConfigMap        10s

oc get validatingadmissionpolicybinding

# Expected output (blocklist):
# NAME                           POLICYNAME                     PARAMREF          AGE
# block-operator-subscriptions   block-operator-subscriptions   blocked-operators  10s
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

## Testing VAP on a Live Cluster

VAP does not have an offline CLI testing tool like Kyverno. Tests run against a live cluster using `oc apply --dry-run=server`, which sends the request through admission policies without creating the resource.

### Run the test scripts

```bash
# Blocklist tests
tests/vap/blocklist/test.sh

# Allowlist tests
tests/vap/allowlist/test.sh

# Audit policy tests
tests/vap/audit/test.sh
```

### What the tests verify

The VAP tests check the same scenarios as the Kyverno tests:

| Test | Blocklist Expected | Allowlist Expected |
|------|-------------------|-------------------|
| `ansible-automation-platform-operator` | Denied | Denied |
| `web-terminal` | Allowed | Allowed |

---

## Verifying on a Live Cluster

After deploying the policy, test it on the cluster.

### Kyverno Verification

#### Blocklist — Blocked Subscription

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

#### Blocklist — Allowed Subscription

```bash
oc apply -f tests/blocklist/resources/allowed-subscription.yaml
```

Expected: the Subscription is created (or you see an OLM error if the operator doesn't exist in your catalog — but no Kyverno denial).

#### Allowlist — Approved Subscription

```bash
oc apply -f tests/allowlist/resources/whitelisted-subscription.yaml
```

Expected: the Subscription is created (the operator is on the approved list).

#### Allowlist — Unapproved Subscription

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

### VAP Verification

#### Blocklist — Blocked Subscription

```bash
oc apply -f tests/vap/blocklist/resources/blocked-subscription.yaml
```

Expected output:

```
Error from server: admission webhook denied the request:
ValidatingAdmissionPolicy 'block-operator-subscriptions' ...
The operator "ansible-automation-platform-operator" is blocked by policy.
Contact your cluster administrator to request an exception.
```

#### Blocklist — Allowed Subscription

```bash
oc apply -f tests/vap/blocklist/resources/allowed-subscription.yaml
```

Expected: the Subscription is created without denial.

#### Allowlist — Approved Subscription

```bash
oc apply -f tests/vap/allowlist/resources/whitelisted-subscription.yaml
```

Expected: the Subscription is created (the operator is on the approved list).

#### Allowlist — Unapproved Subscription

```bash
oc apply -f tests/vap/allowlist/resources/non-whitelisted-subscription.yaml
```

Expected output:

```
Error from server: admission webhook denied the request:
ValidatingAdmissionPolicy 'allow-operator-subscriptions' ...
The operator "ansible-automation-platform-operator" is not on the approved list.
Contact your cluster administrator to request approval.
```

---

## Managing the Operator Lists

### Kyverno

#### Blocklist — Add or remove a blocked operator

1. Edit `policies/blocklist/blocked-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/blocklist/blocked-operators-configmap.yaml
   ```

Kyverno picks up the ConfigMap change automatically — no policy restart needed.

#### Allowlist — Add or remove an approved operator

1. Edit `policies/allowlist/allowed-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/allowlist/allowed-operators-configmap.yaml
   ```

#### Switch to Audit mode

Edit the relevant ClusterPolicy YAML and change `validationFailureAction: Enforce` to `validationFailureAction: Audit`. Re-apply the policy. View violations with:

```bash
oc get policyreport -A
oc get clusterpolicyreport
```

### VAP

#### Blocklist — Add or remove a blocked operator

1. Edit `policies/vap/blocklist/blocked-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/vap/blocklist/blocked-operators-configmap.yaml
   ```

The API server picks up ConfigMap changes automatically — no policy redeployment needed.

#### Allowlist — Add or remove an approved operator

1. Edit `policies/vap/allowlist/allowed-operators-configmap.yaml`.
2. Add or remove the OLM package name in the `packages` field.
3. Apply the updated ConfigMap:

   ```bash
   oc apply -f policies/vap/allowlist/allowed-operators-configmap.yaml
   ```

#### Switch to Audit mode

Edit the relevant binding YAML and change `validationActions: [Deny]` to `validationActions: [Audit]`. Re-apply the binding. Audit events appear in the Kubernetes API server audit log.

---

## Troubleshooting

### Kyverno — Policy shows READY=False

```bash
oc describe clusterpolicy block-operator-subscriptions
oc describe clusterpolicy allow-operator-subscriptions
```

Check `status.conditions` for error messages. Common causes:

- The ConfigMap (`blocked-operators` or `allowed-operators`) does not exist in the `kyverno` namespace.
- Kyverno does not have permission to read ConfigMaps in its namespace.

### VAP — Policy not taking effect

```bash
oc describe validatingadmissionpolicy block-operator-subscriptions
oc describe validatingadmissionpolicybinding block-operator-subscriptions
```

Common causes:

- The ConfigMap does not exist in the `operator-guardrails` namespace. Check with `oc get configmap -n operator-guardrails`.
- The `operator-guardrails` namespace was not created. Apply `policies/vap/namespace.yaml` first.
- The cluster does not support VAP (requires Kubernetes 1.30+ / OpenShift 4.17+). Check with `oc api-resources | grep validatingadmissionpolicies`.
- The binding has `parameterNotFoundAction: Deny`, so a missing ConfigMap will deny all subscriptions.

### Operator still installs despite the policy

- **Kyverno:** Confirm the policy is in `Enforce` mode (not `Audit`).
- **VAP:** Confirm the binding uses `validationActions: [Deny]` (not `[Audit]`).
- For blocklist: confirm the operator's package name is in the blocked ConfigMap's `packages` list with the exact spelling used by the OLM catalog.
- For allowlist: confirm the operator's package name is **not** in the allowed ConfigMap's `packages` list (if you want it denied), or **is** in the list (if you want it permitted).
- Check if the Subscription already existed before the policy was applied — both engines only intercept new creates/updates.

  ```bash
  oc get subscriptions -A
  ```

### Find the OLM package name for an operator

```bash
oc get packagemanifests -n openshift-marketplace | grep <operator-keyword>
```

The `NAME` column is the package name to add to the ConfigMap.
