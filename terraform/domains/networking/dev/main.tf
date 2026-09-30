# Node subnet, plus secondary ranges reserved for GKE Autopilot's alias IPs
# (pods/services) — the gke domain doesn't exist yet, but the ranges live
# here so gke never has to come back and resize this subnet later.
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.2"

  project_id   = var.project_id
  network_name = "excel-pipeline-vpc-dev"
  routing_mode = "GLOBAL"

  # Explicit subnets only — auto mode would create one /20 per region
  # across the whole project, none of it under our naming convention.
  auto_create_subnetworks = false

  subnets = [
    {
      subnet_name   = "gke-subnet-dev-europe-west9"
      subnet_ip     = "10.0.0.0/20"
      subnet_region = var.region
      # Lets nodes reach Google APIs (Firestore, GCS, Pub/Sub, Artifact
      # Registry) without a public IP.
      subnet_private_access = "true"
    },
  ]

  secondary_ranges = {
    "gke-subnet-dev-europe-west9" = [
      {
        range_name    = "gke-pods-dev"
        ip_cidr_range = "10.4.0.0/20"
      },
      {
        range_name    = "gke-services-dev"
        ip_cidr_range = "10.8.0.0/20"
      },
    ]
  }
}

# subnet_private_access above only covers Google APIs (Firestore, GCS,
# Artifact Registry, etc.) — nodes with enable_private_nodes still have no
# route to the public internet at all without this, which is required for
# anything pulling images from a registry outside Google (e.g. ghcr.io for
# community Helm charts like KEDA's). A NAT is the standard way to give a
# private node real (if address-translated) internet egress.
resource "google_compute_router" "nat" {
  name    = "excel-pipeline-router-dev"
  project = var.project_id
  region  = var.region
  network = module.vpc.network_id
}

resource "google_compute_router_nat" "nat" {
  name    = "excel-pipeline-nat-dev"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.nat.name

  # Only one subnet exists here right now, so this and ALL_SUBNETWORKS_
  # ALL_IP_RANGES are equivalent — used instead of naming the subnet
  # explicitly so a future second subnet isn't silently excluded from NAT.
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  nat_ip_allocate_option             = "AUTO_ONLY"
}
