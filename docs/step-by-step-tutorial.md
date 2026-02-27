# Operator Guardrails — Step-by-Step Tutorial

This hands-on tutorial walks you through deploying and testing operator guardrail policies on an OpenShift cluster. You will use the **Ansible Automation Platform (AAP)** operator as a test case — an operator that is either not on the allowlist or explicitly on the blocklist.

The tutorial is divided into two parts:

- **Part 1** — Kyverno (external policy engine)
- **Part 2** — Validating Admission Policy (built into Kubernetes, no controller needed)

Each part follows the same flow: deploy an allowlist, test it, remove it, deploy a blocklist, test it, and clean up.

## Table of Contents

- [Operator Guardrails — Step-by-Step Tutorial](#operator-guardrails--step-by-step-tutorial)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Part 1: Kyverno](#part-1-kyverno)
    - [1.1 Install Kyverno using Helm](#11-install-kyverno-using-helm)
    - [1.2 Deploy the Allowlist Policy](#12-deploy-the-allowlist-policy)
    - [1.3 Test the Allowlist — Install AAP from the UI](#13-test-the-allowlist--install-aap-from-the-ui)
    - [1.4 Remove the Allowlist Policy](#14-remove-the-allowlist-policy)
    - [1.5 Deploy the Blocklist Policy](#15-deploy-the-blocklist-policy)
    - [1.6 Test the Blocklist — Install AAP from the UI](#16-test-the-blocklist--install-aap-from-the-ui)
    - [1.7 Remove the Blocklist Policy](#17-remove-the-blocklist-policy)
    - [1.8 Uninstall Kyverno](#18-uninstall-kyverno)
  - [Part 2: Validating Admission Policy (VAP)](#part-2-validating-admission-policy-vap)
    - [2.1 Deploy the Allowlist Policy](#21-deploy-the-allowlist-policy)
    - [2.2 Test the Allowlist — Install AAP from the UI](#22-test-the-allowlist--install-aap-from-the-ui)
    - [2.3 Remove the Allowlist Policy](#23-remove-the-allowlist-policy)
    - [2.4 Deploy the Blocklist Policy](#24-deploy-the-blocklist-policy)
    - [2.5 Test the Blocklist — Install AAP from the UI](#25-test-the-blocklist--install-aap-from-the-ui)
    - [2.6 Remove the Blocklist Policy](#26-remove-the-blocklist-policy)
  - [Summary](#summary)

---

## Prerequisites

Before you begin, make sure you have:

- An **OpenShift 4.17+** cluster (required for VAP; Kyverno works on older versions too)
- **Cluster-admin** access
- The **`oc`** CLI installed and logged in to your cluster
- The **`helm`** CLI installed (for Kyverno installation)
- This repository cloned locally:

  ```bash
  git clone https://github.com/stefan-bergstein/operator-guardrails.git
  cd operator-guardrails
  ```

Verify your access before starting:

```bash
oc whoami
oc auth can-i create clusterrole
```

The second command should return `yes`.

---

## Part 1: Kyverno

In this part you will install Kyverno, deploy the allowlist and blocklist policies, test each one using the OpenShift web console, and then uninstall Kyverno.

### 1.1 Install Kyverno using Helm

Add the Kyverno Helm repository and install Kyverno into the `kyverno` namespace. The values file `bootstrap/kyverno/kyverno-openshift-values.yaml` contains OpenShift-specific overrides — it sets `runAsUser` and `runAsGroup` to `null` so the restricted-v2 SCC can inject the correct UID/GID, and configures HA replica counts.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
```

```bash
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --version 3.5.2 \
  -f bootstrap/kyverno/kyverno-openshift-values.yaml
```

Wait for all pods to become ready:

```bash
oc get pods -n kyverno -w
```

You should see output similar to:

```
NAME                                             READY   STATUS    RESTARTS   AGE
kyverno-admission-controller-6c4f4b7b9d-xxxxx    1/1     Running   0          60s
kyverno-admission-controller-6c4f4b7b9d-yyyyy    1/1     Running   0          60s
kyverno-admission-controller-6c4f4b7b9d-zzzzz    1/1     Running   0          60s
kyverno-background-controller-5b8f8c5b4d-xxxxx   1/1     Running   0          60s
kyverno-cleanup-controller-7f9b8c5b4d-xxxxx      1/1     Running   0          60s
kyverno-reports-controller-6d8f8c5b4d-xxxxx      1/1     Running   0          60s
```

Press `Ctrl+C` to stop watching once all pods show `Running`.

### 1.2 Deploy the Allowlist Policy

The allowlist only permits operators that are explicitly listed. The default ConfigMap allows two operators: `web-terminal` and `openshift-gitops-operator`. Everything else — including AAP — is denied.

Deploy the allowlist policy and its ConfigMap:

```bash
oc apply -k policies/kyverno/allowlist/
```

Expected output:

```
configmap/allowed-operators created
clusterpolicy.kyverno.io/allow-operator-subscriptions created
```

Verify the policy is active:

```bash
oc get clusterpolicy allow-operator-subscriptions
```

Expected output:

```
NAME                           ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE   MESSAGE
allow-operator-subscriptions   true        false        Enforce           True    10s   Ready
```

The `READY=True` and `VALIDATE ACTION=Enforce` columns confirm the policy is active and enforcing.

**What is in the allowlist?**

The ConfigMap at `policies/kyverno/allowlist/allowed-operators-configmap.yaml` contains:

```yaml
data:
  packages: >-
    web-terminal,
    openshift-gitops-operator
```

Only these two operators can be installed. The AAP operator (`ansible-automation-platform-operator`) is not on this list, so it will be denied.

### 1.3 Test the Allowlist — Install AAP from the UI

Now test the policy by attempting to install the Ansible Automation Platform operator through the OpenShift web console.

1. Open the **OpenShift web console** in your browser.
2. Navigate to **Operators > OperatorHub** in the left menu.
3. In the search bar, type **Ansible Automation Platform**.
4. Click on the **Ansible Automation Platform** operator tile.
5. Click **Install**.
6. Leave the default settings and click **Install** again.

**Expected result:** The installation fails. You will see an error message similar to:

```
The operator "ansible-automation-platform-operator" is not on the approved list.
Contact your cluster administrator to request approval.
```

The OpenShift console displays this as an error in the operator installation view. The Subscription resource was rejected by Kyverno before OLM could act on it.

**Optional — verify from the command line:**

```bash
oc apply -f tests/kyverno/allowlist/resources/non-whitelisted-subscription.yaml
```

Expected output:

```
Error from server: error when creating "non-whitelisted-subscription.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Subscription/openshift-operators/aap-operator was blocked due to
the following policies:

allow-operator-subscriptions:
  check-subscription-name: The operator "ansible-automation-platform-operator"
  is not on the approved list. Contact your cluster administrator to request approval.
```

### 1.4 Remove the Allowlist Policy

Before deploying the blocklist, remove the allowlist policy and its ConfigMap:

```bash
oc delete -k policies/kyverno/allowlist/
```

Expected output:

```
configmap "allowed-operators" deleted
clusterpolicy.kyverno.io "allow-operator-subscriptions" deleted
```

Verify the policy is gone:

```bash
oc get clusterpolicy allow-operator-subscriptions
```

Expected output:

```
Error from server (NotFound): clusterpolicies.kyverno.io "allow-operator-subscriptions" not found
```

### 1.5 Deploy the Blocklist Policy

The blocklist denies specific operators while allowing everything else. The default ConfigMap blocks six operators, including the AAP operator.

Deploy the blocklist policy and its ConfigMap:

```bash
oc apply -k policies/kyverno/blocklist/
```

Expected output:

```
configmap/blocked-operators created
clusterpolicy.kyverno.io/block-operator-subscriptions created
```

Verify the policy is active:

```bash
oc get clusterpolicy block-operator-subscriptions
```

Expected output:

```
NAME                           ADMISSION   BACKGROUND   VALIDATE ACTION   READY   AGE   MESSAGE
block-operator-subscriptions   true        false        Enforce           True    10s   Ready
```

**What is on the blocklist?**

The ConfigMap at `policies/kyverno/blocklist/blocked-operators-configmap.yaml` contains:

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

Any operator on this list is blocked. Operators not on this list (like `web-terminal`) are allowed.

### 1.6 Test the Blocklist — Install AAP from the UI

Test the blocklist using the same steps as before.

1. Open the **OpenShift web console** in your browser.
2. Navigate to **Operators > OperatorHub**.
3. Search for **Ansible Automation Platform**.
4. Click on the operator tile and click **Install**.
5. Leave the default settings and click **Install**.

**Expected result:** The installation fails with an error message similar to:

```
The operator "ansible-automation-platform-operator" is blocked by policy.
Contact your cluster administrator to request an exception.
```

**Optional — verify from the command line:**

```bash
oc apply -f tests/kyverno/blocklist/resources/blocked-subscription.yaml
```

Expected output:

```
Error from server: error when creating "blocked-subscription.yaml":
admission webhook "validate.kyverno.svc-fail" denied the request:

resource Subscription/openshift-operators/aap-operator was blocked due to
the following policies:

block-operator-subscriptions:
  check-subscription-name: The operator "ansible-automation-platform-operator"
  is blocked by policy. Contact your cluster administrator to request an exception.
```

**Verify that non-blocked operators still work:**

An operator not on the blocklist (e.g., `web-terminal`) should install without issues. You can verify from the command line:

```bash
oc apply --dry-run=server -f tests/kyverno/blocklist/resources/allowed-subscription.yaml
```

Expected: no policy denial (you may see an OLM-related message, but no Kyverno block).

### 1.7 Remove the Blocklist Policy

Clean up the blocklist before uninstalling Kyverno:

```bash
oc delete -k policies/kyverno/blocklist/
```

Expected output:

```
configmap "blocked-operators" deleted
clusterpolicy.kyverno.io "block-operator-subscriptions" deleted
```

### 1.8 Uninstall Kyverno

Remove Kyverno from the cluster using Helm:

```bash
helm uninstall kyverno --namespace kyverno
```

Delete the namespace:

```bash
oc delete namespace kyverno
```

Verify that Kyverno is fully removed:

```bash
oc get pods -n kyverno
```

Expected output:

```
No resources found in kyverno namespace.
```

Or the namespace no longer exists:

```
Error from server (NotFound): namespaces "kyverno" not found
```

Kyverno is now completely removed from your cluster.

---

## Part 2: Validating Admission Policy (VAP)

In this part you will use the built-in Kubernetes Validating Admission Policy feature. No external controller is needed — VAP is part of the Kubernetes API server itself.

VAP requires **OpenShift 4.17+** (Kubernetes 1.30+). Verify your cluster version:

```bash
oc version
```

### 2.1 Deploy the Allowlist Policy

First, create the `operator-guardrails` namespace where VAP ConfigMaps are stored:

```bash
oc apply -f policies/vap/namespace.yaml
```

Deploy the allowlist policy, its binding, and the ConfigMap:

```bash
oc apply -k policies/vap/allowlist/
```

Expected output:

```
configmap/allowed-operators created
validatingadmissionpolicy.admissionregistration.k8s.io/allow-operator-subscriptions created
validatingadmissionpolicybinding.admissionregistration.k8s.io/allow-operator-subscriptions created
```

Verify the policy and binding:

```bash
oc get validatingadmissionpolicy allow-operator-subscriptions
```

Expected output:

```
NAME                           VALIDATIONS   PARAMKIND   AGE
allow-operator-subscriptions   1             ConfigMap   10s
```

```bash
oc get validatingadmissionpolicybinding allow-operator-subscriptions
```

Expected output:

```
NAME                           POLICYNAME                     PARAMREF            AGE
allow-operator-subscriptions   allow-operator-subscriptions   allowed-operators   10s
```

**What is in the allowlist?**

The ConfigMap at `policies/vap/allowlist/allowed-operators-configmap.yaml` allows only:

```yaml
data:
  packages: >-
    web-terminal,
    openshift-gitops-operator
```

The AAP operator is not on this list.

### 2.2 Test the Allowlist — Install AAP from the UI

1. Open the **OpenShift web console** in your browser.
2. Navigate to **Operators > OperatorHub**.
3. Search for **Ansible Automation Platform**.
4. Click on the operator tile and click **Install**.
5. Leave the default settings and click **Install**.

**Expected result:** The installation fails. You will see an error message similar to:

```
The operator "ansible-automation-platform-operator" is not on the approved list.
Contact your cluster administrator to request approval.
```

**Optional — verify from the command line:**

```bash
oc apply -f tests/vap/allowlist/resources/non-whitelisted-subscription.yaml
```

Expected output:

```
Error from server (Forbidden): error when creating "non-whitelisted-subscription.yaml":
admission webhook denied the request:
ValidatingAdmissionPolicy 'allow-operator-subscriptions' ...
The operator "ansible-automation-platform-operator" is not on the approved list.
Contact your cluster administrator to request approval.
```

### 2.3 Remove the Allowlist Policy

Remove the allowlist policy, binding, and ConfigMap:

```bash
oc delete -k policies/vap/allowlist/
```

Expected output:

```
configmap "allowed-operators" deleted
validatingadmissionpolicy.admissionregistration.k8s.io "allow-operator-subscriptions" deleted
validatingadmissionpolicybinding.admissionregistration.k8s.io "allow-operator-subscriptions" deleted
```

### 2.4 Deploy the Blocklist Policy

Deploy the blocklist policy, its binding, and the ConfigMap:

```bash
oc apply -k policies/vap/blocklist/
```

Expected output:

```
configmap/blocked-operators created
validatingadmissionpolicy.admissionregistration.k8s.io/block-operator-subscriptions created
validatingadmissionpolicybinding.admissionregistration.k8s.io/block-operator-subscriptions created
```

Verify the policy:

```bash
oc get validatingadmissionpolicy block-operator-subscriptions
```

Expected output:

```
NAME                           VALIDATIONS   PARAMKIND   AGE
block-operator-subscriptions   1             ConfigMap   10s
```

**What is on the blocklist?**

The ConfigMap at `policies/vap/blocklist/blocked-operators-configmap.yaml` blocks:

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

### 2.5 Test the Blocklist — Install AAP from the UI

1. Open the **OpenShift web console** in your browser.
2. Navigate to **Operators > OperatorHub**.
3. Search for **Ansible Automation Platform**.
4. Click on the operator tile and click **Install**.
5. Leave the default settings and click **Install**.

**Expected result:** The installation fails with an error message similar to:

```
The operator "ansible-automation-platform-operator" is blocked by policy.
Contact your cluster administrator to request an exception.
```

**Optional — verify from the command line:**

```bash
oc apply -f tests/vap/blocklist/resources/blocked-subscription.yaml
```

Expected output:

```
Error from server (Forbidden): error when creating "blocked-subscription.yaml":
admission webhook denied the request:
ValidatingAdmissionPolicy 'block-operator-subscriptions' ...
The operator "ansible-automation-platform-operator" is blocked by policy.
Contact your cluster administrator to request an exception.
```

**Verify that non-blocked operators still work:**

```bash
oc apply --dry-run=server -f tests/vap/blocklist/resources/allowed-subscription.yaml
```

Expected: no policy denial.

### 2.6 Remove the Blocklist Policy

Clean up the blocklist policy and its resources:

```bash
oc delete -k policies/vap/blocklist/
```

Expected output:

```
configmap "blocked-operators" deleted
validatingadmissionpolicy.admissionregistration.k8s.io "block-operator-subscriptions" deleted
validatingadmissionpolicybinding.admissionregistration.k8s.io "block-operator-subscriptions" deleted
```

Optionally, remove the `operator-guardrails` namespace if you no longer need it:

```bash
oc delete -f policies/vap/namespace.yaml
```

---

## Summary

You have completed the following:

| Step | Kyverno | VAP |
|------|---------|-----|
| Install engine | Helm install into `kyverno` namespace | Nothing to install (built-in) |
| Deploy allowlist | `oc apply -k policies/kyverno/allowlist/` | `oc apply -k policies/vap/allowlist/` |
| Test: AAP denied | Denied — not on the approved list | Denied — not on the approved list |
| Remove allowlist | `oc delete -k policies/kyverno/allowlist/` | `oc delete -k policies/vap/allowlist/` |
| Deploy blocklist | `oc apply -k policies/kyverno/blocklist/` | `oc apply -k policies/vap/blocklist/` |
| Test: AAP denied | Denied — blocked by policy | Denied — blocked by policy |
| Remove blocklist | `oc delete -k policies/kyverno/blocklist/` | `oc delete -k policies/vap/blocklist/` |
| Uninstall engine | `helm uninstall kyverno` | Nothing to uninstall |

**Key differences:**

- **Kyverno** requires installing and maintaining an external controller, but supports offline CLI testing, mutation, and generation.
- **VAP** requires no installation — it is built into the API server (OpenShift 4.17+). Policies use CEL expressions and run in-process with lower latency.

Both engines use the same data format (comma-separated package names in a ConfigMap) and produce equivalent deny messages. Choose based on your cluster version and operational preferences.
