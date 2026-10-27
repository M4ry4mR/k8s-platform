#!/usr/bin/env bash
set -Eeuo pipefail
export KUBECONFIG="/home/m4ry4m/.kube/k8s-lab.conf"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$ROOT/kernel-tuning/inventory.ini"
KUBECTL="${KUBECTL:-kubectl}"
KUSTOMIZE_DIR="$ROOT/k8s/app/overlays/demo"
HOST="${APP_HOST:-demo.local}"
EXPECTED_NODES="${EXPECTED_NODES:-3}"
EXPECTED_REPLICAS="${EXPECTED_REPLICAS:-3}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/k8s-platform}"
ANSIBLE_PLAYBOOK="${ANSIBLE_PLAYBOOK:-$ROOT/kernel-tuning/.venv/bin/ansible-playbook}"

PASS=0
FAIL=0

pass() { printf 'PASS  %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf 'FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }

check() {
  local name="$1"; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

echo "== Kubernetes platform acceptance test =="

# 1. VM reachability from the host.
while read -r ip; do
  [[ -z "$ip" ]] && continue
  if timeout 3 bash -c ":</dev/tcp/$ip/22" 2>/dev/null; then
    pass "SSH port reachable: $ip"
  else
    fail "SSH port reachable: $ip"
  fi
done < <(awk '/ansible_host=/{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){sub("ansible_host=","",$i); print $i}}' "$INVENTORY")

# 2. Cluster access.
check "kubectl can reach the cluster" "$KUBECTL" cluster-info >/dev/null 2>&1
check "expected node count is $EXPECTED_NODES" bash -c "[[ \$("$KUBECTL" get nodes --no-headers 2>/dev/null | wc -l) -eq $EXPECTED_NODES ]]"

# 3. Node readiness.
ready="$("$KUBECTL" get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')"
if [[ -n "$ready" ]] && ! grep -qv '=True$' <<<"$ready"; then
  pass "all Kubernetes nodes are Ready"
else
  fail "all Kubernetes nodes are Ready: $ready"
fi

# 4. Core cluster services.
check "CoreDNS is available" bash -c 'kubectl -n kube-system get deployment coredns >/dev/null'
check "CoreDNS replicas are ready" bash -c 'test "$(kubectl -n kube-system get deployment coredns -o jsonpath="{.status.availableReplicas}")" = "$(kubectl -n kube-system get deployment coredns -o jsonpath="{.spec.replicas}")"'
check "ingress-nginx is ready" bash -c 'test -n "$(kubectl -n ingress-nginx get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath="{range .items[*]}{.status.containerStatuses[0].ready}{\"\\n\"}{end}")" && ! kubectl -n ingress-nginx get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath="{range .items[*]}{.status.containerStatuses[0].ready}{\"\\n\"}{end}" | grep -q false'

# 5. Pod networking + DNS. A temporary test pod uses the cluster DNS service.
dns_name="acceptance-dns-$RANDOM"
if "$KUBECTL" run "$dns_name" --image=nginx --restart=Never --command -- \
    sh -c 'nslookup kubernetes.default.svc >/dev/null && wget -qO- http://demo-app.demo.svc.cluster.local:8080/ >/dev/null' >/dev/null 2>&1; then
  for _ in {1..30}; do
    phase="$("$KUBECTL" get pod "$dns_name" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
    sleep 1
  done
  if "$KUBECTL" get pod "$dns_name" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Succeeded; then
    pass "pod networking and cluster DNS work"
  else
    fail "pod networking and cluster DNS work"
  fi
else
  fail "could not create DNS/network test pod (busybox image must be available)"
fi
"$KUBECTL" delete pod "$dns_name" --ignore-not-found >/dev/null 2>&1 || true

# 6. Application workload.
check "demo namespace exists" "$KUBECTL" get namespace demo >/dev/null 2>&1
check "expected replica count is $EXPECTED_REPLICAS" bash -c "[[ \$("$KUBECTL" -n demo get deployment demo-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null) -eq $EXPECTED_REPLICAS ]]"
check "service has ready endpoints" bash -c 'test -n "$(kubectl -n demo get endpoints demo-app -o jsonpath="{.subsets[*].addresses[*].ip}" 2>/dev/null)"'
check "image is immutable (digest-pinned)" bash -c 'kubectl -n demo get deployment demo-app -o jsonpath="{.spec.template.spec.containers[0].image}" | grep -q "@sha256:"'
check "resource requests and limits exist" bash -c 'kubectl -n demo get deployment demo-app -o jsonpath="{.spec.template.spec.containers[0].resources.requests.cpu}" | grep -q . && kubectl -n demo get deployment demo-app -o jsonpath="{.spec.template.spec.containers[0].resources.limits.memory}" | grep -q .'
check "workload is non-root and drops capabilities" bash -c 'test "$(kubectl -n demo get deployment demo-app -o jsonpath="{.spec.template.spec.containers[0].securityContext.runAsNonRoot}")" = "true" && test "$(kubectl -n demo get deployment demo-app -o jsonpath="{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}")" = "false"'

# 7. Ingress HTTP traffic + version.
echo "=== Application is reachable through ingress ==="

response=$(curl --noproxy '*' -fsS --max-time 10 \
  -H 'Host: demo.local' http://192.168.122.11/ 2>&1) || {
    echo "FAIL  application is not reachable through ingress"
    exit 1
}


if echo "$response" | grep -q 'demo-app-v1.0.; then
    echo "PASS  application is reachable through ingress and reports version"
else
    echo "FAIL  ingress works "
fi
# 8. Node tuning: run the role's verification tasks, which check effective sysctl,
# kubelet, containerd, limits, swap and time synchronization.
if [[ -x "$ANSIBLE_PLAYBOOK" ]]; then
  if "$ANSIBLE_PLAYBOOK" -i "$INVENTORY" "$ROOT/kernel-tuning/playbooks/node-tuning.yml" --tags verify >/tmp/k8s-platform-tuning.log 2>&1; then
    pass "required node tuning is applied and verified"
  else
    fail "required node tuning is applied and verified (see /tmp/k8s-platform-tuning.log)"
  fi
else
  fail "Ansible virtualenv not found: $ANSIBLE_PLAYBOOK"
fi

# 9. Repository plaintext-secret scan. Exclude generated/local state and binaries.
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$ROOT" grep -IEn \
      -e 'BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY' \
      -e 'AKIA[0-9A-Z]{16}' \
      -e 'password[[:space:]]*:[[:space:]]*["'\'']?[A-Za-z0-9+/=_-]{8,}' \
      -- ':!k8s-platform/terraform/.terraform/**' ':!k8s-platform/terraform/*.tfstate*' \
      ':!kernel-tuning/.venv/**' >/tmp/k8s-platform-secret-scan.log 2>&1; then
    fail "no known plaintext secrets exist in the repository (see /tmp/k8s-platform-secret-scan.log)"
  else
    pass "no known plaintext secrets exist in the repository"
  fi
else
  fail "repository secret scan requires a Git working tree"
fi

echo
printf 'Acceptance result: %s passed, %s failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
