# Level 1 – Seal of the Ancient Scrolls (The Desync Drift)

**Result:** the live realm matches this repository exactly. `terraform plan` says
"No changes" for both `core/` and `workload/`, no ghost resources are left in the
cluster's node pools, and every change now goes through Git and the pipeline
(`.github/workflows/terraform.yml`).

## 1. How we measured the drift

1. `terraform plan` on both stacks, output kept as evidence (`drift-core.txt`,
   `drift-workload.txt`). Every proposed change is a difference between the code
   (the "Ancient Scrolls") and the live environment.
2. Settings the code does not manage are invisible to `plan`. We read them with a
   temporary file of read-only `data` sources plus outputs, ran `plan`, then
   deleted the file:
   - `ovh_cloud_project_kube_iprestrictions` → the API server's IP allow-list
   - `ovh_cloud_project_kube` → the cluster's status
   - `ovh_cloud_project_kube_nodepool` (by name) → the ID and settings of the ghost node pool
3. `kubectl get nodes`, `kubectl get ns` and `kubectl get secrets -A -l owner=helm`
   to compare the cluster with the state (the kubeconfig was read from the core
   state with `terraform show -json`, never written to Git).

## 2. What we found and what we decided

All changes were made by hand in the console; the node pool was even labelled
`managed-by = console`, `owner = night-shift`.

| # | Drift | Found with | Needed? | Decision |
|---|---|---|---|---|
| 1 | API server IP allow-list set to `198.51.100.0/24`, a documentation range (TEST-NET-2). Everyone was locked out: `kubectl` and Terraform failed with `EOF` / TLS handshake errors | `data` source `ovh_cloud_project_kube_iprestrictions` | No | Removed |
| 2 | `update_policy = NEVER_UPDATE`: security updates of the cluster switched off | `terraform plan` (core) | No | Back to `MINIMAL_DOWNTIME` (the code) |
| 3 | Node pool autoscaling min 2 / max 5 instead of 1 / 3 | `terraform plan` (core) | No: more cost, the realm's load fits easily | Back to 1 / 3 (the code) |
| 4 | Node pool labels `managed-by = console`, `owner = night-shift` | `terraform plan` (core), `template` block | No | Back to the code's labels |
| 5 | Ghost node pool `hotfix-pool` (1× `b3-8`), not in the code. Ran only system pods (canal, kube-proxy, apiserver-proxy, konnectivity) | `kubectl get nodes`, `kubectl get pods -A --field-selector spec.nodeName=…` | No | Removed |
| 6 | `helm_release.monitoring` planned as "will be created" while the release existed (`status=deployed`) | `terraform plan` (workload), `kubectl get secrets -l owner=helm` | – | Side effect of #1: Terraform could not reach the cluster. "No changes" after #1 was fixed |

## 3. How we fixed it

Terraform can only change or delete what it manages, so the two hand-made objects
(#1 and #5) were taken over by Terraform first and then removed from the code:

1. An `import {}` block plus a matching `resource` → `terraform plan` shows
   `1 to import` → apply.
2. Delete that file → `terraform plan` shows `1 to destroy` (checked that it was
   the imported object, not `default`) → apply.

```hcl
# Step 1 for #1, deleted again in step 2
import {
  to = ovh_cloud_project_kube_iprestrictions.api
  id = "<service_name>/<kube_id>"
}

resource "ovh_cloud_project_kube_iprestrictions" "api" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = ["198.51.100.0/24"]
}
```

```hcl
# Step 1 for #5, deleted again in step 2
import {
  to = ovh_cloud_project_kube_nodepool.ghost
  id = "<service_name>/<kube_id>/<nodepool_id>"
}

resource "ovh_cloud_project_kube_nodepool" "ghost" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.this.id
  name          = "hotfix-pool"
  flavor_name   = "b3-8"
  desired_nodes = 1
  min_nodes     = 1
  max_nodes     = 1
  autoscale     = false

  # Only imported to be deleted: never change or replace it in between.
  lifecycle {
    ignore_changes = all
  }
}
```

Drift #2–#4 needed no code change: the code already described the right state,
so applying the code reverts them. (They disappeared from the plan between 11:33
and 11:34; <fill in: applied by teammate X / reverted by the environment>.)

After the lockout was removed the cluster's client certificates no longer worked;
`terraform apply -refresh-only` updated the state and a fresh kubeconfig was read
from it.

### Break-glass

The lockout (#1) also blocked the pipeline, and the pipeline did not exist yet.
So the fixes for #1 and #5 were applied **with Terraform from one laptop**, never
in the console, by one person at a time. This file is the record of those changes.
Everything after that goes through a pull request.

## 4. Keeping it in sync: the pipeline

`.github/workflows/terraform.yml`:

| Trigger | What happens |
|---|---|
| Pull request | `terraform fmt -check`, `init`, `validate`, `plan` for `core` then `workload` |
| Push to `main` | Same, then `apply` of exactly the saved plan, only when it has changes |
| Every hour | `plan -detailed-exitcode`: the run fails when the realm no longer matches Git |

- One concurrency group (`terraform-state`) for every run: the S3 backend has no
  state locking, so two applies must never overlap.
- Credentials come from repository secrets (`OVH_ENDPOINT`, `OVH_CLIENT_ID`,
  `OVH_CLIENT_SECRET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), never from Git.
  `.gitignore` keeps `*.env`, `kubeconfig` and `*.tfplan` out.

## 5. Proof

- `drift-core.txt`, `drift-workload.txt`: the plans before the fix.
- Pipeline run on `main`: both jobs green, plan "No changes", `Apply` skipped.
- `kubectl get nodes`: only the two `achrona-pool` nodes.

## 6. Rules from now on

- No changes in the console, no `terraform apply` from a laptop: branch → PR →
  read the plan → merge.
- `git pull` before starting; add files by name, never `git add .`.

## Open

- [ ] Check the OVHcloud console (read only) for other ghosts: instances, users,
      buckets, S3 keys, load balancers, gateways, networks, registries. Expected:
      2 `achrona-pool` nodes, user `achrona-scrolls-app` (+ the organizers' state
      user), buckets `-scrolls` and `-tfstate`, 1 load balancer (Traefik),
      `achrona-gateway`, `achrona-net`, `achrona-registry`.