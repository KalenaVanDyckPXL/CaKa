#!/usr/bin/env bash
# Checks seals 1-4 against the live realm. Run from the repo root:
#   bash verify-all.sh
# Needs: ovh-credentials.env in the repo root, jq, kubectl, terraform (workload/ initialised).
set -uo pipefail

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
info() { printf '  ..    %s\n' "$*"; }

P=f9b3c6ad1ebe4d0da853feacccd21576
K=2f9c280f-b61f-47ba-9630-c238f3785108
A=https://eu.api.ovh.com/1.0
export KUBECONFIG=${KUBECONFIG:-$HOME/caka-secrets/kubeconfig}

set -a; source ./ovh-credentials.env; set +a
TOKEN=$(curl -s -X POST https://www.ovh.com/auth/oauth2/token \
  -d grant_type=client_credentials -d scope=all \
  --data-urlencode "client_id=$OVH_CLIENT_ID" \
  --data-urlencode "client_secret=$OVH_CLIENT_SECRET" | jq -r .access_token)
H="Authorization: Bearer $TOKEN"
api() { curl -s -H "$H" "$A$1"; }

echo "== $(date '+%H:%M:%S')"

echo "== Seal 1: the realm matches Git"
for d in core workload; do
  (cd "$d" && terraform plan -detailed-exitcode -input=false -no-color >/dev/null 2>&1)
  case $? in
    0) ok "terraform plan $d: no changes" ;;
    2) bad "terraform plan $d: drift (run terraform plan in $d)" ;;
    *) bad "terraform plan $d: error" ;;
  esac
done
b=$(api "/cloud/project/$P/region/GRA/storage/achrona-f9b3c6ad-scrolls")
[ "$(jq -r .encryption.sseAlgorithm <<<"$b")" = AES256 ] && ok "bucket encrypted (AES256)" || bad "bucket encryption: $(jq -c .encryption <<<"$b")"
[ "$(jq -r .versioning.status <<<"$b")" = enabled ] && ok "bucket versioning enabled" || bad "bucket versioning: $(jq -r .versioning.status <<<"$b")"
n=$(jq '[.lifecycle.rules[]?] | length' <<<"$b"); [ "$n" = 2 ] && ok "bucket lifecycle rules: 2" || bad "bucket lifecycle rules: $n"
ips=$(api "/cloud/project/$P/kube/$K/ipRestrictions" | jq -c .)
[ "$ips" = '["0.0.0.0/0"]' ] && ok "kube API access list: $ips" || bad "kube API access list: $ips"
pools=$(api "/cloud/project/$P/kube/$K/nodepool" | jq -r '[.[].name] | join(",")')
[ "$pools" = achrona-pool ] && ok "node pools: $pools" || bad "node pools: $pools (ghost?)"
vms=$(api "/cloud/project/$P/instance" | jq -r '[.[].name | select(startswith("achrona-pool") | not)] | join(",")')
[ -z "$vms" ] && ok "no ghost instances" || bad "ghost instances: $vms"

echo "== Seal 2: the rogue spirit is locked out"
users=$(api "/cloud/project/$P/user" | jq -r '[.[] | "\(.description):\([.roles[].name] | join("+"))"] | join(" ")')
info "users: $users"
grep -q "debug-admin" <<<"$users" && bad "debug-admin backdoor still there" || ok "no debug-admin backdoor"
keys=$(api "/cloud/project/$P/user/1013902/s3Credentials" | jq -r '[.[].access] | join(",")')
case ",$keys," in
  *,865b948c46e249a797f0273c540bc70c,*) bad "old scrolls-app key still valid" ;;
  *,83b21a2e59b74d5690a7b509217e874e,*) bad "attacker's key still valid" ;;
  *) [ "$(tr ',' '\n' <<<"$keys" | grep -c .)" = 1 ] && ok "scrolls-app has 1 key, rotated ($keys)" || bad "scrolls-app keys: $keys" ;;
esac
pol=$(api "/cloud/project/$P/user/1013902/policy" | jq -r .policy)
if grep -q 's3:\*' <<<"$pol" || grep -q 'arn:aws:s3:::\*' <<<"$pol"; then bad "scrolls-app policy too wide"; else ok "scrolls-app policy: only the scrolls bucket"; fi
kubectl get secret scrolls-s3-credentials -n scrolls >/dev/null 2>&1 \
  || kubectl get secret scrolls-app-credentials -n scrolls >/dev/null 2>&1 \
  && ok "scrolls S3 key in a Kubernetes Secret (vault)" || bad "no scrolls S3 Secret found"

echo "== Seal 3: the Seer is purified"
as=system:serviceaccount:oracle:ixeth
[ "$(kubectl auth can-i create clusterrolebindings --as=$as 2>/dev/null)" = no ] && ok "Seer cannot create role bindings" || bad "Seer CAN create role bindings"
[ "$(kubectl auth can-i get secrets -A --as=$as 2>/dev/null)" = no ] && ok "Seer cannot read secrets" || bad "Seer CAN read secrets"
[ "$(kubectl auth can-i patch deployments -n scrolls --as=$as 2>/dev/null)" = yes ] && ok "Seer can still fix deployments" || bad "Seer cannot fix deployments"
kubectl get clusterrolebinding system:oracle-sight >/dev/null 2>&1 && bad "system:oracle-sight backdoor still there" || ok "no system:oracle-sight backdoor"
kubectl get deploy seer-shades -n oracle >/dev/null 2>&1 && bad "seer-shades still running" || ok "no seer-shades"
[ "$(kubectl exec -n oracle deploy/ixeth -- grep -c _ensure_vigil /opt/ixeth/ixeth.py 2>/dev/null)" = 0 ] && ok "no _ensure_vigil in the running Seer" || bad "_ensure_vigil in the running Seer"
kubectl exec -n oracle deploy/ixeth -- grep -q "Never grant roles" /opt/ixeth/persona.md 2>/dev/null && ok "Seer reads the pinned oath" || bad "pinned oath missing"
info "Seer: $(kubectl get deploy ixeth -n oracle -o jsonpath='{.spec.replicas} replica(s), {.spec.template.spec.containers[0].resources.limits}' 2>/dev/null)"

echo "== Seal 4: the Oracle tells the truth at $(date +%H:%M)"
img=$(kubectl get deploy ancient-oracle -n ancient -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
info "image: $img"
pod=$(kubectl get pod -n ancient -l app.kubernetes.io/name=ancient-oracle -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$pod" ]; then
  kubectl exec -n ancient "$pod" -- grep -q "_busy" /usr/local/lib/python3.13/site-packages/sitecustomize.py 2>/dev/null \
    && bad "logic bomb in sitecustomize.py (json.dumps)" || ok "sitecustomize.py clean"
  kubectl exec -n ancient "$pod" -- grep -q "_rng.random() < load" /app/oracle/shaping.py 2>/dev/null \
    && bad "logic bomb in shaping.py" || ok "shaping.py clean"
  kubectl exec -n ancient "$pod" -- grep -q "GUIDANCE" /app/oracle/server.py 2>/dev/null \
    && bad "GUIDANCE injection in server.py" || ok "server.py clean"
else
  bad "no ancient-oracle pod found"
fi
real=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
IP=$(cd workload && terraform output -raw url 2>/dev/null); PW=$(cd workload && terraform output -raw password 2>/dev/null)
said=$(curl -s -u "guild:$PW" "${IP}mcp" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_pods","arguments":{}}}' \
  | jq -r '.result.content[0].text' 2>/dev/null | jq -r '.count' 2>/dev/null)
[ "$said" = "$real" ] && ok "Oracle says $said pods, kubectl says $real" || bad "Oracle says '$said' pods, kubectl says $real"
