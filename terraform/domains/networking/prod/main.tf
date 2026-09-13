# Node subnet, plus secondary ranges reserved for GKE Autopilot's alias IPs
# (pods/services) — the gke domain doesn't exist yet, but the ranges live
# here so gke never has to come back and resize this subnet later.
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.2"

  project_id   = var.project_id
  network_name = "excel-pipeline-vpc-prod"
  routing_mode = "GLOBAL"

  # Explicit subnets only — auto mode would create one /20 per region
  # across the whole project, none of it under our naming convention.
  auto_create_subnetworks = false

  subnets = [
    {
      subnet_name   = "gke-subnet-prod-europe-west9"
      subnet_ip     = "10.16.0.0/20"
      subnet_region = var.region
      # Lets nodes reach Google APIs (Firestore, GCS, Pub/Sub, Artifact
      # Registry) without a public IP.
      subnet_private_access = "true"
    },
  ]

  secondary_ranges = {
    "gke-subnet-prod-europe-west9" = [
      {
        range_name    = "gke-pods-prod"
        ip_cidr_range = "10.20.0.0/20"
      },
      {
        range_name    = "gke-services-prod"
        ip_cidr_range = "10.24.0.0/20"
      },
    ]
  }
}
