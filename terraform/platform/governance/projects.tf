resource "google_project_service" "resource_manager" {
  for_each = local.deployer_environments

  project = google_project.this[each.key].project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = false
}


resource "google_project" "this" {
  for_each = local.projects

  project_id      = each.value.project_id
  name            = each.value.project_id
  folder_id       = module.folders.ids[each.value.folder_name]
  billing_account = var.billing_account_id

}
