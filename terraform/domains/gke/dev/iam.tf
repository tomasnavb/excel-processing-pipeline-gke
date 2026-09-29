# Needed for the project number in the Workload Identity principal path
# below — project_id alone isn't enough, GCP requires the numeric one there.
data "google_project" "this" {
  project_id = var.project_id
}

resource "google_service_account" "this" {
  for_each     = local.identities
  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
}

# group_key.id takes the group's email directly — the group itself is
# managed by governance's Terraform, but its email is a value we chose at
# creation time, not something GCP computes, so a lookup by known ID is
# the right tool here rather than tfe_outputs (see the devlog).
data "google_cloud_identity_group_lookup" "this" {
  for_each = local.identities

  group_key {
    id = each.value.group_email
  }
}

resource "google_cloud_identity_group_membership" "this" {
  for_each = local.identities

  # .name from the lookup ("groups/{id}"), not the raw email — that's what
  # this resource's `group` argument expects.
  group = data.google_cloud_identity_group_lookup.this[each.key].name

  preferred_member_key {
    id = google_service_account.this[each.key].email
  }

  roles {
    name = "MEMBER"
  }
}

# Only the pairs in identity_role_bindings exist here — worker-gke-sa's
# group ends up with zero bindings from this file, since all of its roles
# are granted by terraform/domains/data instead.
resource "google_project_iam_member" "this" {
  for_each = local.identity_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "group:${local.identities[each.value.identity_key].group_email}"
}

resource "google_service_account_iam_member" "ksa_binding" {
  for_each           = local.identities
  service_account_id = google_service_account.this[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/projects/${data.google_project.this.number}/locations/global/workloadIdentityPools/${var.project_id}.svc.id.goog/subject/ns/${each.value.namespace}/sa/${each.value.ksa_name}"

  # The member string references the cluster's own Workload Identity Pool
  # by its fixed, predictable name — not a real resource attribute — so
  # nothing here otherwise tells Terraform this has to wait for the
  # cluster to actually finish creating first. Without this, the binding
  # can (and did) run in parallel with the cluster and fail because the
  # pool doesn't exist yet.
  depends_on = [module.gke_autopilot]
}

# The annotation that maps each KSA to its GSA lives in gke-addons (for
# keda-operator) and will live in Kustomize (for the worker's own KSA) —
# not here. This domain only grants the permission (above); it doesn't
# touch the kubernetes provider at all anymore (see the devlog for why
# that split happened).
