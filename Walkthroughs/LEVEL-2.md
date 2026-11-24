# Level 2 – Seal of the Shadow (The Rogue Spirit)

**Result:** the compromised service account and its stolen token no longer
work, the monitoring account has only the rights its job needs, it is defined
in Git, the attacker's backdoors are removed, and no credential is in Git any
more.

## 1. The kitchen helper: `observability/metrics-collector`

### What we found

| Check | Command | Finding |
|---|---|---|
| Its rights | `kubectl auth can-i --list --as=system:serviceaccount:observability:metrics-collector` | `*.*  [*]` and Non-Resource `[*]  [*]`: **full cluster-admin** |
| Where from | `kubectl get clusterrolebindings -o custom-columns=...` | `monitoring-collector-reader → cluster-admin`, managed by Helm: the hole was **in our own chart** (`templates/rbac.yaml`) |
| Its own role | `templates/rbac.yaml` | An aggregated ClusterRole; one part (`monitoring-collector-scrape-config`) allowed reading **every Secret** and writing **every ConfigMap** |
| What it really needs | `templates/monitoring.yaml` | Its loop only runs `kubectl get nodes`, `kubectl get pods -A`, `kubectl get --raw /metrics` |
| Long-lived tokens | `kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token` | None |
| Hand-made changes in the cluster | `managedFields` of all ConfigMaps, Secrets, Deployments, ServiceAccounts and RBAC objects (`kubectl get ... -o json --show-managed-fields`) | Only OVH (`OpenAPI-Generator`), Terraform (`HashiCorp`), Helm and Kubernetes itself. No hand-made writes in `scrolls`, `oracle` or `observability` |
| Non-system RBAC bindings outside Helm | `kubectl get clusterrolebindings,rolebindings -A` | Only OVH components (calico, canal, csi, cloud-controller-manager, cluster-autoscaler, metrics-server, yacht, `view` for kubernetes-ovh) |

Conclusion: no visible writes, but the account could **read every Secret**,
including `scrolls/scrolls-app-credentials` (the S3 keys). Reads leave no trace
in `managedFields`, so we treat those keys as stolen.

### What we changed (PR `fix/level2-least-privilege`, chart 0.4.2)

- `templates/rbac.yaml`: one ClusterRole `metrics-scraper-reader` with exactly
  `nodes, pods: list` and `GET /metrics`. No aggregation (an aggregated role
  grows whenever someone adds a ClusterRole with its label).
- `templates/serviceaccounts.yaml`: the account is replaced by
  `metrics-scraper`. Tokens are bound to the account, so every token ever
  issued for `metrics-collector`, including the stolen one, became invalid.
- The binding got a new name because a binding's `roleRef` cannot be changed.

### Proof

Tested with an **empty kubeconfig**, so only the token counts (with the normal
kubeconfig, kubectl also sends the admin client certificate and every test
"works"):

```powershell
New-Item -ItemType File -Force empty-kubeconfig.yaml | Out-Null
$api = kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# Token of the old account, saved before the fix
kubectl --kubeconfig=empty-kubeconfig.yaml --server=$api --token=$oldToken --insecure-skip-tls-verify get secrets -A
# error: You must be logged in to the server (Unauthorized)

# Token of the new account
$newToken = kubectl create token metrics-scraper -n observability --duration=10m
kubectl --kubeconfig=empty-kubeconfig.yaml --server=$api --token=$newToken --insecure-skip-tls-verify get pods -A     # works
kubectl --kubeconfig=empty-kubeconfig.yaml --server=$api --token=$newToken --insecure-skip-tls-verify get secrets -A  # Forbidden
```

- `kubectl get sa -n observability`: `default`, `metrics-scraper`
- `kubectl get pods -n observability`: `metrics-collector-…` `1/1 Running` with the new account: it still does its job

## 2. The attacker's keys and backdoors (OVHcloud)

| Finding | Fix | PR |
|---|---|---|
| Ghost node pool `hotfix-pool` (came back in the second drift wave) | Destroyed | `fix(seal-1): destroy ghost hotfix-pool and debug-admin backdoor` |
| OVH project user `debug_admin`: a backdoor account | Destroyed | same |
| A rogue S3 key on the `scrolls-app` user, made by the attacker | Imported into Terraform and revoked | `fix(seal-2): import attacker's rogue S3 key …`, `fix(seal-2): revoke attacker's rogue key and rotate scrolls-app credentials` |
| S3 policy `TempFixAllAccess`: `s3:*` on all buckets, including the state bucket (see LEVEL1.md #9) | Reverted to 8 actions on the scrolls bucket | Level 1, `fix/drift-wave-2` |
| `scrolls-app` S3 key (leaked: in Git and readable through the collector) | Rotated, with a rotation trigger in Terraform | `seal-2-rotate-scrolls-key` |

<fill in: what `debug_admin` was (role, created when), what the rogue key was
and how it was found>

## 3. Credentials out of Git (PRs `fix/level2-export-scrolls-key`, `fix/level2-secrets-out-of-git`, chart 0.4.3)

`templates/scrolls.yaml` had the S3 key pair and the signing key hardcoded, so
anyone with the repo had them.

- `core/outputs.tf`: the rotated `scrolls-app` S3 key is exported as a
  **sensitive** output.
- `workload/monitoring.tf`: Terraform passes it to the chart with
  `set_sensitive`, together with a signing key it generates
  (`random_password`, rotated by changing its `keepers`).
- `templates/scrolls.yaml`: the values come from Terraform; the chart refuses to
  render without them (`required`). A checksum annotation restarts
  `scrolls-app` when a credential changes.
- The credentials now live only in the private, encrypted state bucket and in
  the cluster's Secret: our "vault".

Proof: the access key in `scrolls/scrolls-app-credentials` is no longer the
leaked `9d4e1c7a…` key. The old values remain in Git history, but they are
rotated and no longer work.

## 4. How the account is now kept in check

- The account, its role and its binding are in the chart in Git; every change
  goes through a PR and the pipeline.
- The hourly pipeline run would show any change to the release made outside Git.

## Open / next

- [ ] Optional: a CI check that fails a PR when a chart grants `cluster-admin`,
      wildcards, or Secret access, or contains a hardcoded key.