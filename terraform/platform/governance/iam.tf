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
