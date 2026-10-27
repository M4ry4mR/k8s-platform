#!/usr/bin/env bash
set -Eeuo pipefail

# Meaningful readiness-failure exercise. It temporarily makes the readiness
# probe fail, observes traffic exclusion/availability loss, then restores it.
NS=demo
DEPLOY=demo-app
KUBECTL="${KUBECTL:-kubectl}"

cleanup() {
  "$KUBECTL" -n "$NS" patch deployment "$DEPLOY" --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]' \
    >/dev/null 2>&1 || true
  "$KUBECTL" -n "$NS" rollout status deployment/"$DEPLOY" --timeout=120s >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Injecting readiness failure..."
"$KUBECTL" -n "$NS" patch deployment "$DEPLOY" --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/does-not-exist"}]'

echo "Waiting for the failing rollout to become unavailable..."
for _ in {1..60}; do
  ready="$("$KUBECTL" -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  [[ "${ready:-0}" -lt 3 ]] && break
  sleep 2
done

ready="$("$KUBECTL" -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
if [[ "${ready:-0}" -ge 3 ]]; then
  echo "FAIL: readiness failure was not observed"
  exit 1
fi

echo "Observed ready replicas: ${ready:-0} (expected < 3)"
echo "Restoring the healthy readiness probe..."
cleanup
ready="$("$KUBECTL" -n "$NS" get deployment "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
[[ "${ready:-0}" -eq 3 ]] || { echo "FAIL: recovery did not restore 3 ready replicas"; exit 1; }
echo "PASS: readiness failure detected and workload recovered"
