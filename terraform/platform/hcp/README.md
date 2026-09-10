# HCP Terraform Platform

Applied by the `excel-pipeline-hcp-mgmt` workspace. This configuration
manages HCP Terraform's own organizational structure — Projects and
Workspaces inside HCP Terraform — not GCP resources. It's the first thing
that runs in the bootstrap chain, since it creates the workspace that
`terraform/platform/governance/` runs in.

## What this creates

- The `dev`, `prod`, and `shared` HCP Terraform Projects.
- One workspace per domain (`networking`, `gke`, `data`, `cloud-run`) inside
  the `dev`/`prod` projects — 8 total.
- The `excel-pipeline-registry-shared` workspace, inside the `shared`
  project — the one domain workspace that isn't scoped to dev or prod
  (Artifact Registry, and the Cloud Build ↔ GitHub connection).
- The `excel-pipeline-governance-mgmt` workspace, inside the manually
  created mgmt project.
- The custom GitHub OAuth connection's usage across all 10 workspaces above.
- An empty `tfe_variable_set` per project (`dev`, `prod`, and `shared`),
  attached to its respective project. Populated later by `governance`, once
  it creates the per-project GCP identities those variable sets need to
  hold.
- A `hcp_organization_name` Terraform variable on `governance-mgmt`, set to
  this workspace's own value — so it isn't typed manually a second time.

## What this does NOT do

- Touch any GCP resource. This workspace only talks to the HCP Terraform
  API — no `google` provider here.
- Create the mgmt project or this workspace itself — both are created
  manually, to avoid a workspace managing (and potentially destroying)
  itself.

## Required workspace variables

| Variable | Category | Notes |
|---|---|---|
| `hcp_organization_name` | Terraform variable | HCP Terraform organization name |
| `vcs_repo_identifier` | Terraform variable | `owner/repo` |
| `github_oauth_token_id` | Terraform variable (sensitive) | `ot-xxxxxxxx`, from the custom GitHub connection created manually at the organization level |
| `TFE_TOKEN` | Environment variable (sensitive) | Team API Token (`owners` team, free-tier limitation — see the devlog) |

See [`docs/devlog/bitacora.md`](../../../docs/devlog/bitacora.md) and
[`docs/governance/iam.md`](../../../docs/governance/iam.md) for the
reasoning behind these decisions.
