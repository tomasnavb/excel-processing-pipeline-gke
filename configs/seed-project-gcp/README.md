# GCP Seed Project

The one manually-created GCP project needed before Terraform can manage
anything else: **`excel-pipeline-seed`** (folder `bootstrap`). It hosts the
Workload Identity Pool/Provider and the service account Terraform
impersonates to manage folders and projects org-wide. Kept isolated and
low-traffic on purpose — it holds org-level IAM grants, so it stays easy to
audit.

It's the only project that has to be created by hand: WIF-based
authentication needs an identity pool, which must live inside an
already-existing GCP project. Every other project (`dev`, `prod`, `shared`)
is created by `terraform/platform/governance/` instead, since none of them
need to exist before this one's WIF does.

## Scripts, in order

1. **`create-seed-project.sh`** — creates the `bootstrap` folder and the
   `excel-pipeline-seed` project. Set the variables at the top, then run the
   whole script.
2. **`create-seed-wif.sh`** — run after (1). Creates the Workload Identity
   Pool/Provider and service account inside `excel-pipeline-seed`, scoped
   (via an attribute condition on the provider) to be usable only by the
   `excel-pipeline-governance-mgmt` HCP Terraform workspace, plus the
   organization-level IAM roles that service account needs to create
   folders/projects. Prints the 6 `TFC_GCP_*` values to load manually as
   Environment Variables on that workspace once it's done.
