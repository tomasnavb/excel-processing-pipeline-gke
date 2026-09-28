# Dedicated namespace for KEDA.
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
}

# Deploy KEDA with Helm charts.
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

  depends_on = [google_container_cluster.autopilot]
}


