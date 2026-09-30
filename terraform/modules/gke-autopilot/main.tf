# Fixed security/access posture for every GKE Autopilot cluster this
# project creates — deliberately locals, not variables, so no caller of
# this module can loosen them per environment. This is also the entire
# reason this module exists instead of calling the official
# terraform-google-modules/kubernetes-engine module (see the devlog):
# Autopilot collapses most of what that module would otherwise need to
# orchestrate into these few fixed choices.
locals {
  # This module only ever builds Autopilot clusters — if a Standard
  # cluster were ever needed, that would be a different module, not a
  # variable toggle on this one.
  enable_autopilot = true

  # Nodes get no public IP, and the classic IP endpoint (public or
  # private) is fully disabled — this cluster is reachable only through
  # the DNS-based control plane endpoint below, gated by IAM
  # (container.clusters.connect) instead of source IP. No bastion, no
  # master_authorized_networks to maintain.
  enable_private_nodes    = true
  enable_private_endpoint = true
  ip_endpoints_enabled    = false
  allow_external_traffic  = true
}

# Custom node Service Account, replacing the default Compute Engine SA
# GKE otherwise falls back to — that one is shared project-wide and
# historically over-privileged, a known GKE hardening gap. Created here
# (not in the calling domain's own iam.tf) so every cluster this module
# builds gets one automatically, without duplicating this across dev/prod.
resource "google_service_account" "node" {
  account_id   = var.node_service_account_id
  project      = var.project_id
  display_name = "Service Account for GKE Autopilot nodes"
}

# The group itself is created by governance (same single-source-of-truth
# rule as every other Cloud Identity group in this project) — this module
# only looks it up by the email the caller passes in, same as gke/dev
# already does for gke-workloads-{env}@/keda-operators-{env}@.
data "google_cloud_identity_group_lookup" "node" {
  group_key {
    id = var.node_group_email
  }
}

resource "google_cloud_identity_group_membership" "node" {
  group = data.google_cloud_identity_group_lookup.node.name

  preferred_member_key {
    id = google_service_account.node.email
  }

  roles {
    name = "MEMBER"
  }
}

# roles/container.defaultNodeServiceAccount is what actually lets this SA
# function as a node identity (logging, monitoring, etc.) — granted to
# the group, not the SA directly, following this project's own rule that
# IAM grants always go through a Cloud Identity group.
resource "google_project_iam_member" "node_default_service_account" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "group:${var.node_group_email}"
}

resource "google_container_cluster" "autopilot" {
  name     = var.name
  project  = var.project_id
  location = var.region

  enable_autopilot = local.enable_autopilot

  network    = var.network_self_link
  subnetwork = var.subnetwork_self_link

  # Pod/service alias IP ranges are reserved by networking, not chosen
  # here — see terraform/domains/networking's own comments for sizing.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  release_channel {
    channel = var.release_channel
  }

  # master_ipv4_cidr_block is still required by the API whenever
  # enable_private_nodes is true, even though the IP endpoint itself ends
  # up fully disabled below — GCP uses this range for the master's
  # internal peering into the VPC, independent of whether that endpoint
  # is ever exposed.
  private_cluster_config {
    enable_private_nodes    = local.enable_private_nodes
    enable_private_endpoint = local.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # ip_endpoints_config turns the IP endpoint off entirely (public or
  # private); once that's off, enable_private_endpoint above has nothing
  # left to apply to, which is why the two don't conflict despite looking
  # redundant.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = local.allow_external_traffic
    }
    ip_endpoints_config {
      enabled = local.ip_endpoints_enabled
    }
  }

  # Autopilot enforces Workload Identity as a policy (pods can't opt out
  # of it), but empirically that alone doesn't provision the identity
  # pool itself — a first real apply failed with "Identity Pool does not
  # exist (excel-pipeline-dev.svc.id.goog)" without this block declared
  # explicitly. workload_pool's format is fixed by GCP's own convention
  # ({project_id}.svc.id.goog), not something a caller of this module
  # would ever need to vary.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Without this, Autopilot falls back to the default Compute Engine SA
  # for nodes — the exact identity this module's own google_service_account
  # above exists to replace. enabled is optional as of a relatively recent
  # provider fix (a prior version conflicted between cluster_autoscaling
  # and enable_autopilot, blocking a custom node SA on Autopilot
  # entirely — see the devlog).
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.node.email
    }
  }
}
