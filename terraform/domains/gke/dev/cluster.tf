data "tfe_outputs" "networking" {
  workspace = "excel-pipeline-networking-dev"
}

resource "google_container_cluster" "autopilot" {
  name     = "excel-pipeline-gke-dev"
  location = var.region

  # Enable Autopilot mode
  enable_autopilot = true

  # Network configuration
  network    = data.tfe_outputs.networking.values.network_self_link
  subnetwork = data.tfe_outputs.networking.values.subnet_self_link

  # Pod/service alias IP ranges are reserved by networking, not chosen
  # here — see terraform/domains/networking's own comments for sizing.
  ip_allocation_policy {
    cluster_secondary_range_name  = data.tfe_outputs.networking.values.pods_range_name
    services_secondary_range_name = data.tfe_outputs.networking.values.services_range_name
  }

  # Use the stable release channel for production
  release_channel {
    channel = "REGULAR"
  }

  # Nodes get no public IP. master_ipv4_cidr_block is still required by
  # the API whenever enable_private_nodes is true, even though the IP
  # endpoint itself ends up fully disabled below — GCP uses this range
  # for the master's internal peering into the VPC, independent of
  # whether that endpoint is ever exposed.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # DNS-based control plane access instead of a bastion or
  # master_authorized_networks — access is gated by IAM
  # (container.clusters.connect), not by source IP. ip_endpoints_config
  # below turns the IP endpoint off entirely (public or private); once
  # that's off, enable_private_endpoint above has nothing left to apply
  # to, which is why the two don't conflict despite looking redundant.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
    ip_endpoints_config {
      enabled = false
    }
  }
}

