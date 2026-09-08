# IAM Groups and Roles

All IAM permissions in this project are granted to **Cloud Identity groups**,
never to individual service accounts or user accounts directly — a service
account's or user's access comes entirely from which group(s) it belongs to.
This keeps access auditable at the group level and avoids one-off bindings
that drift out of sync with the rest of the system.

## Why groups are split by environment

Most of the service accounts these groups wrap exist once per project
(`worker-gke-sa` in dev, a separate `worker-gke-sa` in prod, etc.). A single
shared group containing both would leak access across environments: if the
group is bound to a resource in dev *and* separately to one in prod, every
member — including prod's identity — inherits both bindings. Splitting the
group itself by environment keeps that isolation intact. The one exception
is `ci-cd-pipelines@`, which only ever targets the shared project, so there's
no dev/prod boundary to leak across.

## Groups and members

| Group | Purpose | Members |
|---|---|---|
| `gke-workloads-dev@tomasnavarro.dev` | GKE worker's application code (Workload Identity) — dev | *(empty — added by `terraform/domains/gke` when it creates `worker-gke-sa`)* |
| `gke-workloads-prod@tomasnavarro.dev` | Same, prod | *(empty — same, prod)* |
| `app-runtime-dev@tomasnavarro.dev` | Cloud Run API's application code — dev | *(empty — added by `terraform/domains/cloud-run` when it creates `api-runtime-sa`)* |
| `app-runtime-prod@tomasnavarro.dev` | Same, prod | *(empty — same, prod)* |
| `infra-admins-dev@tomasnavarro.dev` | Creates and manages infrastructure — dev | `sa-terraform-deployer` (dev project), personal account |
| `infra-admins-prod@tomasnavarro.dev` | Same, prod | `sa-terraform-deployer` (prod project), personal account |
| `api-invokers-dev@tomasnavarro.dev` | Authorized to call the dev Cloud Run API | *(empty — added by `terraform/domains/cloud-run` when it creates `excel-client-sa`)* |
| `api-invokers-prod@tomasnavarro.dev` | Authorized to call the prod Cloud Run API | *(empty — same, prod)* |
| `ci-cd-pipelines@tomasnavarro.dev` | Builds and pushes container images | *(empty — added by whichever domain creates `cloudbuild-deployer-sa`)* |

`infra-admins-{env}@` is the only group `governance` populates directly —
`sa-terraform-deployer` is the one SA `governance` itself creates
(`wif.tf`). Every other group starts empty: adding a member for a
service account that doesn't exist yet fails outright (GCP returns
`Permission denied ... or it may not exist` — a real error hit on the
first apply, see the devlog). Membership follows the same ownership split
as the roles below — whichever domain creates a given SA is responsible
for adding it to its group, via a `data "google_cloud_identity_group"`
lookup rather than re-declaring the group.

## Roles per group

| Group | Role | Scope | Applied in |
|---|---|---|---|
| `infra-admins-{env}@` | `roles/container.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/compute.networkAdmin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/run.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/storage.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/pubsub.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/datastore.owner` | Its own project | `terraform/platform/governance` |
| `gke-workloads-{env}@` | `roles/pubsub.subscriber` | The `excel-pipeline-jobs-sub-{env}` subscription | `terraform/domains/data` |
| `gke-workloads-{env}@` | `roles/datastore.user` | Its own project (Firestore has no finer-grained IAM scope) | `terraform/domains/data` |
| `gke-workloads-{env}@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `app-runtime-{env}@` | `roles/datastore.user` | Its own project | `terraform/domains/data` |
| `app-runtime-{env}@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `ci-cd-pipelines@` | `roles/artifactregistry.writer` | The `excel-pipeline-images` repository | `terraform/domains/cloud-run` |
| `api-invokers-{env}@` | `roles/run.invoker` | The specific `excel-pipeline-api-{env}` service | `terraform/domains/cloud-run` |

## Why the split between `governance` and each domain

`governance` owns the GCP projects themselves, so project-level grants
(`infra-admins-{env}@`) live there. Every other role targets a specific
resource (a bucket, a subscription, a Cloud Run service, an Artifact
Registry repo) that `governance` doesn't create — those bindings are
attached by whichever domain creates that resource, referencing the group
by its email rather than re-declaring a resource it doesn't own.

## Known gap, tracked for later

Image pulls on GKE nodes and Cloud Run don't use the workload identities
above (`gke-workloads-{env}@`, `app-runtime-{env}@`) — they use the GKE node
service account and the Cloud Run service agent respectively, which need
their own `roles/artifactregistry.reader` grant on `excel-pipeline-images`.
This is GKE/Cloud Run-specific configuration to work out when those domains
are implemented, not a gap in this table.
