#
# A poor attempt to list all operators that are nor covered with OKE
#

oc get packagemanifests -n openshift-marketplace -l catalog=redhat-operators -o json | jq -r '
  .items[] | .metadata.name as $name |
  .status.channels[] |
  [
    $name,
    .name,
    .currentCSV,
    (.currentCSVDesc.annotations["operators.openshift.io/valid-subscription"] // "Not Specified")
  ] | @tsv' |
  while IFS=$'\t' read -r name channel csv sub; do
    printf "%-35s | %-12s | %-30s | %-20s\n" "$name" "$channel" "$csv" "$sub"
done | grep -v 'OpenShift Kubernetes Engine' | while read s r
do
echo $s
done | sort -u

