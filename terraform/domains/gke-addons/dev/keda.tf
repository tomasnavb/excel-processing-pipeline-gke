# Dedicated namespace for KEDA.
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
}

# Deploy KEDA with Helm charts. No depends_on needed here — the
# kubernetes/helm providers are themselves configured from
# data.google_container_cluster.autopilot (providers.tf), so Terraform
# already has to resolve that cluster lookup before it can do anything
# with this provider at all.
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.20.2"
  namespace  = kubernetes_namespace.keda.metadata[0].name

  # Optional configurations
  set = [
    {
      name = "watchNamespace"
      # Empty string = watches all namespaces, so a ScaledObject/
      # ScaledJob anywhere in the cluster (e.g. in processor's own
      # namespace) gets picked up without listing namespaces here.
      value = ""
    },
    {
      name  = "logging.operator.level"
      value = "info"
    }
  ]
}
