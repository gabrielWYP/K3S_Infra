# Structural guards for the rendered Fulbito manifests. Run with bash.
set -euo pipefail
app="$1"
runner="$2"

grep -q 'image: ghcr.io/gabrielwyp/fulbito-escolar:bootstrap' "${app}"
grep -q 'match: Host(`fulbito.ikigais.app`)' "${app}"
grep -q 'readOnlyRootFilesystem: true' "${app}"
grep -q 'type: Recreate' "${app}"
# Every namespaced object must land in the fulbito namespace.
test -z "$(grep '^  namespace:' "${app}" "${runner}" | grep -v 'namespace: fulbito$' || true)"
# The deployer must stay namespace-scoped.
if grep -q '^kind: ClusterRole' "${runner}"; then
  echo "ClusterRole/ClusterRoleBinding not allowed for the Fulbito runner" >&2
  exit 1
fi
echo "Fulbito manifest guards passed"
