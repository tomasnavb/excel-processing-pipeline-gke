locals {
  # One entry per SA this domain creates. `roles` is only what `gke` itself
  # grants to that identity's group — empty where every role for that group
  # belongs to another domain instead (gke-workloads-dev@'s pubsub.subscriber/
  # datastore.user/storage.objectAdmin all live in terraform/domains/data,
  # same for keda-operators-dev@'s pubsub.viewer — see docs/governance/iam.md).
  identities = {
    worker = {
      account_id   = "worker-gke-sa"
      display_name = "Service Account for the GKE worker"
      group_email  = "gke-workloads-dev@tomasnavarro.dev"
      roles        = []
      ksa_name     = "processor-ksa"
      namespace    = "processor"
    }
    keda = {
      account_id   = "keda-operator-sa"
      display_name = "Service Account for the KEDA operator"
      group_email  = "keda-operators-dev@tomasnavarro.dev"
      roles        = ["roles/monitoring.viewer"]
      ksa_name     = "keda-operator"
      namespace    = "keda"
    }
  }

  # Flattened so the IAM member resource can for_each per (identity, role)
  # pair — same pattern already used in governance (infra_admin_bindings,
  # keda_operator_bindings), needed because the two identities above don't
  # get a symmetric set of roles. With today's data, this produces exactly
  # one entry (replace() only swaps "/" for "-", so the "." in
  # "monitoring.viewer" stays as-is):
  #   "keda-roles-monitoring.viewer" => {
  #     identity_key = "keda"
  #     role         = "roles/monitoring.viewer"
  #   }
  # worker contributes nothing, since its own `roles` list is empty.
  identity_role_bindings = {
    for pair in flatten([
      for key, identity in local.identities : [
        for role in identity.roles : {
          instance_key = "${key}-${replace(role, "/", "-")}"
          identity_key = key
          role         = role
        }
      ]
    ]) : pair.instance_key => pair
  }
}
