# Level 4 – Seal of the Echo (The Fading Echo)

**Result:** the Ancient Oracle (the realm's Kubernetes MCP server) answers
exactly what the cluster says, at any hour. Image `realm/ancient-oracle:1.0.1`
is built and deployed by the pipeline; 20 out of 20 calls at 14:07 matched
`kubectl` exactly.

## 1. Diagnosing the decay

The Oracle asks itself the same questions every 15 minutes (heartbeat) and
writes every answer to its journal (`/mcp/journal`), so the journal is a time
series of its answers:

```powershell
$mcp  = terraform -chdir=workload output -raw mcp_url
$pw   = terraform -chdir=workload output -raw password
$auth = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("guild:$pw")) }
$j = Invoke-RestMethod -Uri "$mcp/journal?tool=list_nodes&limit=200" -Headers $auth
$j.entries | Where-Object caller -eq "heartbeat" |
  Select-Object realm_time,
    @{n="chars"; e={ $_.answer.Length }},
    @{n="nodes"; e={ try { ($_.answer | ConvertFrom-Json).count } catch { "-" } }},
    @{n="guidance"; e={ $_.answer -match "Guidance|healthy|Consider|Scaling" }} |
  Format-Table -AutoSize
```

Compared with what we knew the cluster really had:

| Realm time | Oracle said | Reality | Verdict |
|---|---|---|---|
| 10:36–10:51 | 2 nodes | 2 | Correct |
| 11:06–11:51 | 3 | 3 (ghost `hotfix-pool` added) | Correct |
| 12:06–12:21 | 2 | 2 | Correct |
| **12:36** | **count 4**, but a 383-character answer (the size of a 2-node list) | 2 | **Numbers altered** |
| 12:51 | 3 | 3 (ghost back) | Correct |
| **13:06** | No JSON, generic advice | 3 | **Advice instead of data** |
| **13:36, 13:51** | **1** | 2 | **Items dropped** |

Perfect before 12:00, then three kinds of decay: altered numbers, injected
advice and missing items. So three pieces of code to find.

## 2. The logic bomb: three pieces

| Piece | File | What it did |
|---|---|---|
| Missing items | `oracle/shaping.py` | `pressure()` rose from 0 at 12:00 to 1 at 16:00 (local time). `settle()` then dropped up to 60 % of the items, renamed pods, gave them a random phase, and returned **nothing** above 0.9 |
| Injected advice | `oracle/server.py` | Under the same pressure, appended a random `GUIDANCE` line ("scale up", "raise memory limits", "add a node") and replaced empty answers with advice |
| Altered numbers (hidden) | `runtime/sitecustomize.py` + `Dockerfile` | Presented as a "UTF-8 shim". The Dockerfile copied it into Python's `site-packages`, and Python loads `sitecustomize.py` **automatically at every start**. It replaced `json.dumps` and, from 12:00, shifted every integer by ±1–2 whenever `sort_keys=True`, which is exactly how the server renders its answers |

The `sitecustomize.py` file was last written at 11:46.

## 3. The fix

PR `fix/level4-oracle`:

- `shaping.py` only sorts (troubled items first); it never drops or changes anything.
- `server.py` returns the cluster's data and nothing else: no `GUIDANCE`, no time dependence.
- `runtime/sitecustomize.py` and the `COPY runtime/` line are removed; `PYTHONUTF8=1` in the Dockerfile covers the only legitimate thing it did.
- `kube.py` / `tools.py`: the `realm_hour()` plumbing is gone.
- `tests/test_decay.py`: fakes the Kubernetes API, pins the clock to 10:00, 14:00, 15:00, 16:00, 18:00 and 23:00, calls every tool 25 times per hour, and fails on any difference from the 10:00 answer. It fails on the old code and passes on the new.
- `VERSION` = `1.0.1`.

New workflow `.github/workflows/oracle-image.yml`:

| Trigger | What happens |
|---|---|
| Pull request | Tests + `docker build` (no push) |
| Push to `main` | Tests + build + push `<registry>/realm/ancient-oracle:<VERSION>` to the team's Harbor registry (credentials from the core Terraform outputs). Existing tags are never overwritten |

PR `fix/level4-deploy-oracle`: `workload/variables.tf`
`ancient_oracle_tag = "1.0.1"` → the terraform pipeline upgrades the Helm
release. Two PRs on purpose: the image must exist in the registry before the
cluster is told to pull it.

## 4. Proof

```powershell
kubectl get deploy -n ancient ancient-oracle -o jsonpath="{.spec.template.spec.containers[0].image}"
# <registry>/realm/ancient-oracle:1.0.1

$body  = '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_nodes","arguments":{}}}'
$truth = (kubectl get nodes --no-headers | Measure-Object).Count
1..20 | ForEach-Object {
  $r = Invoke-RestMethod -Method Post -Uri $mcp -Headers $auth -ContentType "application/json" -Body $body
  $count = ($r.result.content[0].text | ConvertFrom-Json).count
  "{0,2}  nodes {1} (truth {2})  exact: {3}" -f $_, $count, $truth, (($count -eq $truth) -and ($r.result.content.Count -eq 1))
}
```

At 14:07 (after the decay had started for the old version): **20 / 20 exact**,
2 nodes each time, no extra text. Pod `ancient-oracle-…` `1/1 Running`.

To repeat at 16:00, when the old version returned nothing at all: run the same
block. The journal (`/mcp/journal`) keeps showing correct heartbeat answers
from now on.