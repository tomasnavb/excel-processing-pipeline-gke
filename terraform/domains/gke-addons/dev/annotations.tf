# keda-operator-sa itself is created by terraform/domains/gke — its email
# is predictable from GCP's own SA email format, not a value that needs a
# cross-workspace lookup.
locals {
  keda_gsa_email = "keda-operator-sa@${var.project_id}.iam.gserviceaccount.com"
}

# Binds keda-operator's own KSA (created above by the Helm chart) to
# impersonate keda-operator-sa via Workload Identity — the actual
# workloadIdentityUser grant lives in terraform/domains/gke, on the GSA
# side; this is just the annotation that tells GKE which GSA a given KSA
# maps to. depends_on is required: metadata.name/namespace below don't
# reference helm_release.keda directly, so nothing else would tell
# Terraform to wait for the chart to finish creating that KSA first.
resource "kubernetes_annotations" "gsa_binding" {
  api_version = "v1"
  kind        = "ServiceAccount"

  metadata {
    name      = "keda-operator"
    namespace = kubernetes_namespace_v1.keda.metadata[0].name
  }

  annotations = {
    "iam.gke.io/gcp-service-account" = local.keda_gsa_email
  }

  depends_on = [helm_release.keda]
}
