resource "google_project" "this" {
  for_each = local.projects

  project_id      = each.value.project_id
  name            = each.value.project_id
  folder_id       = module.folders.ids[each.value.folder_name]
  billing_account = var.billing_account_id
}
