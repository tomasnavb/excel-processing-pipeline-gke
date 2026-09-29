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
| `registry-admins@tomasnavarro.dev` | Creates and manages the shared registry domain's own resources | `sa-terraform-deployer` (shared project) |
| `keda-operators-dev@tomasnavarro.dev` | KEDA's own operator — polls Cloud Monitoring to decide when to scale the worker Deployment — dev | *(empty — added by `terraform/domains/gke` when it creates `keda-operator-sa`)* |
| `keda-operators-prod@tomasnavarro.dev` | Same, prod | *(empty — same, prod)* |

`infra-admins-{env}@` and `registry-admins@` are the only groups
`governance` populates directly — both members are Terraform-deployer SAs
that `governance` itself creates (`wif.tf`), one per project including
`shared`. Every other group starts empty: adding a member for a service
account that doesn't exist yet fails outright (GCP returns `Permission
denied ... or it may not exist` — a real error hit on the first apply, see
the devlog). Membership follows the same ownership split as the roles
below — whichever domain creates a given SA is responsible for adding it
to its group, via a `data "google_cloud_identity_group_lookup"` lookup
rather than re-declaring the group.

`registry-admins@` is not the same identity as `ci-cd-pipelines@`:
`sa-terraform-deployer` (shared) runs Terraform to create the registry
domain's resources, while `cloudbuild-deployer-sa` (added to
`ci-cd-pipelines@` once `terraform/domains/registry/shared` creates it)
runs the actual builds.

`keda-operators-{env}@` is not the same identity as `gke-workloads-{env}@`
either, and deliberately so: `worker-gke-sa` (the worker's own code) never
touches Cloud Monitoring, and `keda-operator-sa` (KEDA's operator pod,
which polls Cloud Monitoring to decide when to scale the worker's
Deployment) never touches Pub/Sub message content, Firestore, or GCS.
Reusing one SA for both would have been simpler to wire up, but would
have broadened each identity's access beyond what it actually does — see
the devlog for the full reasoning.

Both SAs (`worker-gke-sa` and `keda-operator-sa`) are created by `gke`,
and `gke` also adds each one to its own group (`gke-workloads-{env}@`,
`keda-operators-{env}@`) via a `data "google_cloud_identity_group_lookup"`
lookup — but that doesn't mean `gke` grants every role those groups end
up with. See "Roles per group" below and the note in
[`governance/iam.tf`](../../terraform/platform/governance/iam.tf) for
which roles `gke` grants directly versus which ones `data` grants instead.

## Roles per group

| Group | Role | Scope | Applied in |
|---|---|---|---|
| `infra-admins-{env}@` | `roles/container.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/compute.networkAdmin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/run.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/storage.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/pubsub.admin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/datastore.owner` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/iam.serviceAccountAdmin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/resourcemanager.projectIamAdmin` | Its own project | `terraform/platform/governance` |
| `infra-admins-{env}@` | `roles/iam.serviceAccountUser` | Its own project's default Compute Engine SA | `terraform/platform/governance` |
| `gke-workloads-{env}@` | `roles/pubsub.subscriber` | The `excel-pipeline-jobs-sub-{env}` subscription | `terraform/domains/data` |
| `gke-workloads-{env}@` | `roles/datastore.user` | Its own project (Firestore has no finer-grained IAM scope) | `terraform/domains/data` |
| `gke-workloads-{env}@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `app-runtime-{env}@` | `roles/datastore.user` | Its own project | `terraform/domains/data` |
| `app-runtime-{env}@` | `roles/storage.objectAdmin` | The `excel-pipeline-{env}-jobs` bucket | `terraform/domains/data` |
| `ci-cd-pipelines@` | `roles/artifactregistry.writer` | The `excel-pipeline-images` repository | `terraform/domains/cloud-run` |
| `api-invokers-{env}@` | `roles/run.invoker` | The specific `excel-pipeline-api-{env}` service | `terraform/domains/cloud-run` |
| `registry-admins@` | `roles/artifactregistry.admin` | The `shared` project | `terraform/platform/governance` |
| `registry-admins@` | `roles/cloudbuild.connectionAdmin` | The `shared` project | `terraform/platform/governance` |
| `registry-admins@` | `roles/cloudbuild.builds.editor` | The `shared` project | `terraform/platform/governance` |
| `registry-admins@` | `roles/iam.serviceAccountAdmin` | The `shared` project | `terraform/platform/governance` |
| `keda-operators-{env}@` | `roles/monitoring.viewer` | Its own project (Cloud Monitoring has no finer-grained IAM scope) | `terraform/domains/gke` |
| `keda-operators-{env}@` | `roles/pubsub.viewer` | The `excel-pipeline-jobs-sub-{env}` subscription | `terraform/domains/data` |

`iam.serviceAccountAdmin`, `resourcemanager.projectIamAdmin`, and
`iam.serviceAccountUser` were added after `gke`'s first real apply — until
`gke`, no domain had ever created its own SAs or granted roles to its own
groups, so `infra-admins-{env}@` never needed permission to do either.
Creating a resource (`container.admin`, etc.) and editing who has access
to the project itself are different permissions in GCP's model; the first
two roles cover the latter. `serviceAccountUser`, scoped to the project's
default Compute Engine SA specifically (not project-wide), is needed to
create a GKE cluster that uses that SA for its nodes — see the devlog for
the full apply-log trail.

## Why the split between `governance` and each domain

The split is **not** simply "project-level roles go to `governance`,
resource-scoped roles go to a domain" — `governance` only grants roles for
identities it creates itself: `sa-terraform-deployer` in
`infra-admins-{env}@` and `registry-admins@`, both self-contained
(`governance` creates the SA in `wif.tf` and grants its own roles, without
depending on any other domain).

Every other role — including project-level ones, like `gke-workloads-{env}@`'s
`datastore.user` or `keda-operators-{env}@`'s `monitoring.viewer` — is
granted by whichever domain represents that GCP service in this project's
structure, regardless of which domain created the consuming SA: `data`
grants Firestore/Pub/Sub/GCS-related roles (it owns those resources), and
`gke` grants `monitoring.viewer` because no domain here owns Cloud
Monitoring specifically and `gke` is the only consumer of it (via KEDA).
This was gotten wrong once — `monitoring.viewer` was first placed in
`governance` by pattern-matching "project-level role" to `infra-admins`'
bindings, without checking it against the `datastore.user` precedent
already in this table. See the devlog for the full correction.

## Known gap, tracked for later

Image pulls on GKE nodes and Cloud Run don't use the workload identities
above (`gke-workloads-{env}@`, `app-runtime-{env}@`) at all — image pulls
happen at the node/kubelet level, before any pod's own Workload Identity
context exists. For GKE Autopilot specifically, that identity is fixed and
can't be overridden: the project's Compute Engine default service account
(`{PROJECT_NUMBER}-compute@developer.gserviceaccount.com`). Cloud Run pulls
via its own service agent, similarly unrelated to `app-runtime-{env}@`.

Both need `roles/artifactregistry.reader` on `excel-pipeline-images` — a
repo that lives in the `shared` project, not `dev`/`prod`. Following the
same rule as the rest of this table (whoever owns the target resource
grants access to it, regardless of which domain creates the consuming
identity), this binding belongs to `terraform/domains/registry/shared`,
not `gke`/`cloud-run`. The main open question for when that domain gets
built: reaching dev/prod's Compute Engine default SA email requires their
project *number* (not ID) from within `registry/shared`'s own Terraform —
a cross-project value that governance already knows, so it's a candidate
for the same variable-set channel already used for `project_id` (see the
devlog), rather than `tfe_outputs`.
