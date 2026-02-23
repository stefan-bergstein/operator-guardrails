# contrib — Helper Scripts

## no-oke-ops.sh

Lists all OLM operators from a catalog source that are not included in an OpenShift Kubernetes Engine (OKE) subscription. The output is a sorted, unique list of package names — one per line.

This is useful for generating the blocklist ConfigMap on clusters where only OKE-entitled operators should be available.

### How it works

The script queries `packagemanifests` and checks the `operators.openshift.io/valid-subscription` annotation on each channel's CSV. Any operator whose annotation includes "OpenShift Kubernetes Engine" is filtered out. The remaining operators are the ones **not** covered by OKE and therefore candidates for blocking.

### Prerequisites

- `oc` CLI, authenticated to an OpenShift cluster
- `jq` installed

### Usage

```bash
bash contrib/no-oke-ops.sh
```

Sample output:

```
3scale-operator
ansible-automation-platform-operator
compliance-operator
...
```

### Generating the blocked-operators ConfigMap

Pipe the output into the ConfigMap format expected by the blocklist policy.

#### For Kyverno (namespace: kyverno)

```bash
PACKAGES=$(bash contrib/no-oke-ops.sh | paste -sd ',' - | sed 's/,/,\n    /g')

cat > policies/kyverno/blocklist/blocked-operators-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: blocked-operators
  namespace: kyverno
  labels:
    app.kubernetes.io/part-of: operator-guardrails
data:
  # Auto-generated from contrib/no-oke-ops.sh
  # Operators not included in an OKE subscription.
  #
  packages: >-
    ${PACKAGES}
EOF
```

```bash
oc apply -f policies/kyverno/blocklist/blocked-operators-configmap.yaml
```

#### For VAP (namespace: operator-guardrails)

```bash
PACKAGES=$(bash contrib/no-oke-ops.sh | paste -sd ',' - | sed 's/,/,\n    /g')

cat > policies/vap/blocklist/blocked-operators-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: blocked-operators
  namespace: operator-guardrails
  labels:
    app.kubernetes.io/part-of: operator-guardrails
data:
  # Auto-generated from contrib/no-oke-ops.sh
  # Operators not included in an OKE subscription.
  #
  packages: >-
    ${PACKAGES}
EOF
```

```bash
oc apply -f policies/vap/blocklist/blocked-operators-configmap.yaml
```
