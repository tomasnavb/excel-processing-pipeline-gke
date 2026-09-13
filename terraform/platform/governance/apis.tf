# APIs needed by domain workspaces to create their own resources — see
# locals.tf's project_apis for the list itself.
resource "google_project_service" "domain_apis" {
  for_each = local.project_api_bindings

  project = google_project.this[each.value.environment].project_id
  service = each.value.api

  # Default is true — destroying this resource would actively disable the
  # API, breaking every domain resource in this environment that depends
  # on it (see wif.tf for the same reasoning applied to iamcredentials/sts).
  disable_on_destroy = false
}
