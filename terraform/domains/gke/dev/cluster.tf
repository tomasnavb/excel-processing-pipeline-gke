data "tfe_outputs" "networking" {
  workspace = "excel-pipeline-networking-dev"
}

module "gke_autopilot" {
  source = "../../../modules/gke-autopilot"

  project_id             = var.project_id
  region                 = var.region
  name                   = "excel-pipeline-gke-dev"
  network_self_link      = data.tfe_outputs.networking.values.network_self_link
  subnetwork_self_link   = data.tfe_outputs.networking.values.subnet_self_link
  pods_range_name        = data.tfe_outputs.networking.values.pods_range_name
  services_range_name    = data.tfe_outputs.networking.values.services_range_name
  master_ipv4_cidr_block = "172.16.0.0/28"
  release_channel        = "REGULAR"
  node_group_email       = "gke-nodes-dev@tomasnavarro.dev"
}
