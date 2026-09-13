# Networking — dev

Applied by the `excel-pipeline-networking-dev` workspace. Creates the VPC and
subnet that every other dev-environment domain (`gke`, `data`, `cloud-run`)
runs inside.

## What this creates

- The `excel-pipeline-vpc-dev` VPC network, in custom subnet mode (no
  auto-created subnets).
- The `gke-subnet-dev-europe-west9` regional subnet, with Private Google
  Access enabled (nodes reach Firestore/GCS/Pub/Sub/Artifact Registry
  without a public IP).
- Two secondary IP ranges on that subnet, reserved for GKE Autopilot's
  alias IPs — `gke-pods-dev` and `gke-services-dev`. Reserved now, before
  `gke` exists, so that domain never has to come back and resize this
  subnet later.

## What this does NOT do (yet)

- Create the GKE cluster itself — that's `terraform/domains/gke`, which
  will read this domain's `subnet_name`/`subnet_self_link` outputs via
  `tfe_outputs` (the one place in this project where that mechanism is
  actually needed — see `docs/devlog/bitacora.md`).
- Define firewall rules. None exist yet because there's no cross-service
  traffic pattern to allow beyond what GKE manages internally for its own
  control plane — add them here once a real need shows up.

## IP ranges

| Name | Type | CIDR | Size | Used by |
|---|---|---|---|---|
| `gke-subnet-dev-europe-west9` | Primary | `10.0.0.0/20` | 4,096 | GKE node IPs |
| `gke-pods-dev` | Secondary | `10.4.0.0/20` | 4,096 | Pod alias IPs (GKE Autopilot IP aliasing) — real, routable within the VPC |
| `gke-services-dev` | Secondary | `10.8.0.0/20` | 4,096 | Service (`ClusterIP`) addresses — virtual, translated via iptables/eBPF on each node, never routed on the VPC |

Sized for a small Autopilot cluster, not copied from GCP's generic
documentation examples — see the devlog for the sizing reasoning (how many
nodes a given pod-range size actually supports, and why the services range
has no real capacity ceiling to optimize against). dev and prod use
different, non-overlapping ranges purely for readability (there's no VPC
peering between them, so nothing would actually break if they matched).

## Required workspace variables

| Variable | Category | Notes |
|---|---|---|
| `project_id` | Terraform variable | Set automatically by `governance`, via the per-project variable set `hcp` created — no manual action needed |
| `region` | Terraform variable | Defaults to `europe-west9` — no need to set unless overriding |
| `TFC_GCP_PROVIDER_AUTH` | Environment variable | Inherited from the `dev-credentials` variable set — no manual action needed |
| `TFC_GCP_PRINCIPAL_TYPE` | Environment variable | Same |
| `TFC_GCP_PROJECT_NUMBER` | Environment variable | Same |
| `TFC_GCP_WORKLOAD_POOL_ID` | Environment variable | Same |
| `TFC_GCP_WORKLOAD_PROVIDER_ID` | Environment variable | Same |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | Environment variable | Same |

Nothing in this table needs to be typed in by hand — this workspace only
needs to be attached to the `dev` HCP Terraform Project, and it inherits
everything above from that project's variable set.
