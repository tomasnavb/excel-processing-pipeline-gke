# IAM Groups and Roles

All IAM permissions in this project are granted to **Cloud Identity groups**,
never to individual service accounts or user accounts directly — a service
account's or user's access comes entirely from which group(s) it belongs to.
This keeps access auditable at the group level and avoids one-off bindings
that drift out of sync with the rest of the system.

## Groups and members

| Group | Purpose | Members |
|---|---|---|
| `gke-workloads@tomasnavarro.dev` | Identity for the GKE worker's application code (Workload Identity) | `worker-gke-sa` |
| `app-runtime@tomasnavarro.dev` | Identity for the Cloud Run API's application code | `api-runtime-sa` |
| `infra-admins@tomasnavarro.dev` | Creates and manages infrastructure within a project | `sa-terraform-deployer`, personal account |
| `ci-cd-pipelines@tomasnavarro.dev` | Builds and pushes container images | `cloudbuild-deployer-sa` |
| `api-invokers@tomasnavarro.dev` | Authorized to call the Cloud Run API | `excel-client-sa` |

## Roles per group

| Group | Role | Scope | Applied in |
|---|---|---|---|
| `infra-admins@` | `roles/container.admin` | Project (dev and prod) | `terraform/platform/governance` |
| `infra-admins@` | `roles/compute.networkAdmin` | Project | `terraform/platform/governance` |
| `infra-admins@` | `roles/run.admin` | Project | `terraform/platform/governance` |
| `infra-admins@` | `roles/storage.admin` | Project | `terraform/platform/governance` |
| `infra-admins@` | `roles/pubsub.admin` | Project | `terraform/platform/governance` |
| `infra-admins@` | `roles/datastore.owner` | Project | `terraform/platform/governance` |
| `gke-workloads@` | `roles/pubsub.subscriber` | The `excel-pipeline-jobs-sub-{env}` subscription | `terraform/domains/data` |
| `gke-workloads@` | `roles/datastore.user` | Project (Firestore has no finer-grained IAM scope) | `terraform/domains/data` |
| `gke-workloads@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `app-runtime@` | `roles/datastore.user` | Project | `terraform/domains/data` |
| `app-runtime@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `ci-cd-pipelines@` | `roles/artifactregistry.writer` | The `excel-pipeline-images` repository | `terraform/domains/cloud-run` |
| `api-invokers@` | `roles/run.invoker` | The specific `excel-pipeline-api-{env}` service | `terraform/domains/cloud-run` |

## Why the split between `governance` and each domain

`governance` owns the GCP projects themselves, so project-level grants
(`infra-admins@`) live there. Every other role targets a specific resource
(a bucket, a subscription, a Cloud Run service, an Artifact Registry repo)
that `governance` doesn't create — those bindings are attached by whichever
domain creates that resource, referencing the group by its email rather than
re-declaring a resource it doesn't own.

## Known gap, tracked for later

Image pulls on GKE nodes and Cloud Run don't use the workload identities
above (`gke-workloads@`, `app-runtime@`) — they use the GKE node service
account and the Cloud Run service agent respectively, which need their own
`roles/artifactregistry.reader` grant on `excel-pipeline-images`. This is
GKE/Cloud Run-specific configuration to work out when those domains are
implemented, not a gap in this table.
