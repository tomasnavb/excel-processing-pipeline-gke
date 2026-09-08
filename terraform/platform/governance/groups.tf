resource "google_project_service" "resource_manager" {
  for_each = local.deployer_environments

  project = google_project.this[each.key].project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = false
}

module "per_env_groups" {
  source   = "terraform-google-modules/group/google"
  version  = "~> 0.8"
  for_each = local.per_env_groups

  id      = "${each.key}@${local.group_domain}"
  domain  = local.group_domain
  members = each.value.members

  depends_on = [google_project_service.resource_manager]
}

# The only group that isn't split by environment — it targets exclusively
# the shared project's Artifact Registry, so there's no dev/prod boundary
# to leak across.
module "ci_cd_pipelines_group" {
  source  = "terraform-google-modules/group/google"
  version = "~> 0.8"

  id      = "ci-cd-pipelines@${local.group_domain}"
  domain  = local.group_domain
  members = ["cloudbuild-deployer-sa@${local.projects["shared"].project_id}.iam.gserviceaccount.com"]

  depends_on = [google_project_service.resource_manager]
}
