# Governance

Applied by the `excel-pipeline-governance-mgmt` workspace. This is the first
configuration that touches GCP directly — it authenticates via Workload
Identity Federation using the identity created manually in the `excel-pipeline-seed`
project (see `configs/seed-project-gcp/`).

## What this creates

- The `development`, `production`, and `shared` folders under the
  Organization.
- The `excel-pipeline-dev`, `excel-pipeline-prod`, and `excel-pipeline-shared`
  GCP projects, one per folder.
- The 9 Cloud Identity groups (split by environment where the underlying
  service account exists once per project — see
  [`docs/governance/iam.md`](../../../docs/governance/iam.md) for why).
- The `infra-admins-{env}@` project-level IAM bindings.

## What this does NOT do (yet)

- Create the per-project Workload Identity Pool/Provider/Service Account
  that `terraform/domains/*` workspaces will use to create GKE, Cloud Run,
  Storage, Pub/Sub, and Firestore resources.
- Write the resulting `TFC_GCP_*` values into the variable sets that
  `terraform/platform/hcp/` already created for the `dev`/`prod` projects.
- Grant any of the resource-scoped roles (`gke-workloads-{env}@`,
  `app-runtime-{env}@`, `api-invokers-{env}@`, `ci-cd-pipelines@`) — those
  are attached by whichever domain creates the resource they target.

## Required workspace variables

| Variable | Category | Notes |
|---|---|---|
| `gcp_organization_id` | Terraform variable | Numeric GCP Organization ID |
| `billing_account_id` | Terraform variable | Attached to the 3 projects created here |
| `personal_account_email` | Terraform variable (sensitive) | Added to `infra-admins-{env}@`; not hardcoded since this repo is public |
| `TFC_GCP_PROVIDER_AUTH` | Environment variable | `true` |
| `TFC_GCP_PRINCIPAL_TYPE` | Environment variable | `service_account` |
| `TFC_GCP_PROJECT_NUMBER` | Environment variable | From `excel-pipeline-seed`, printed by `create-seed-wif.sh` |
| `TFC_GCP_WORKLOAD_POOL_ID` | Environment variable | Same |
| `TFC_GCP_WORKLOAD_PROVIDER_ID` | Environment variable | Same |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | Environment variable | Same |

See [`docs/devlog/bitacora.md`](../../../docs/devlog/bitacora.md) for the
full reasoning behind this bootstrap chain.
