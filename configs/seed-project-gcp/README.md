# GCP Bootstrap & Shared Projects

Two manually-created GCP projects, each in its own folder, needed before
Terraform can manage the rest of the organization:

- **`excel-pipeline-seed`** (folder `bootstrap`): hosts the Workload
  Identity Pool/Provider and the service account Terraform impersonates to
  manage folders and projects org-wide. Kept isolated and low-traffic on
  purpose — it holds org-level IAM grants, so it stays easy to audit.
- **`excel-pipeline-shared`** (folder `shared`): hosts resources shared
  across dev and prod, starting with the Artifact Registry both environments
  pull images from. Kept in its own project so neither dev nor prod depends
  on the other, and so it doesn't share a security boundary with the
  sensitive bootstrap project above.

Both exist to break the same chicken-and-egg problem: WIF-based
authentication needs an identity pool, which must live inside an
already-existing GCP project.

Set the variables at the top of `create-seed-project.sh`, then run the whole
script.
