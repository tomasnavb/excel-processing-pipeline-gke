# Project-level bindings for infra-admins-{env}@ only. Every other group's
# roles target a specific resource (a bucket, a subscription, a Cloud Run
# service, an Artifact Registry repo) that governance doesn't create — those
# bindings live in the domain that creates that resource instead.
resource "google_project_iam_member" "infra_admins" {
  for_each = local.infra_admin_bindings

  project = google_project.this[each.value.environment].project_id
  role    = each.value.role
  member  = "group:${module.per_env_groups["infra-admins-${each.value.environment}"].id}"
}

# registry-admins@ — project-level, same reasoning: governance creates the
# shared project, so these bindings live here too.
resource "google_project_iam_member" "registry_admins" {
  for_each = toset(local.registry_admin_roles)

  project = google_project.this["shared"].project_id
  role    = each.value
  member  = "group:${module.registry_admins_group.id}"
}

# Deliberately NOT here: keda-operators-{env}@'s roles/monitoring.viewer.
# governance only grants roles for identities it creates itself
# (sa-terraform-deployer, above) — keda-operator-sa is created by gke, and
# no domain here represents Cloud Monitoring the way data represents
# Firestore/Pub/Sub/GCS, so gke grants it directly, same as data already
# does for gke-workloads-{env}@'s project-level roles (see the devlog).

# infra-admins-{env}@ needs iam.serviceAccountUser on the project's own
# default Compute Engine SA to create a GKE cluster that uses it for
# nodes (GKE's default when no custom node SA is configured) — resource-
# scoped, not project-level, so it can't just be a string in
# infra_admin_roles like the roles above. Lives here, not in gke itself:
# governance already has both the project number and the group as direct
# resource references, no extra data lookup needed either way.
resource "google_service_account_iam_member" "infra_admins_default_compute_sa_user" {
  for_each = toset(["dev", "prod"])

  service_account_id = "projects/${google_project.this[each.key].project_id}/serviceAccounts/${google_project.this[each.key].number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "group:${module.per_env_groups["infra-admins-${each.key}"].id}"
}
