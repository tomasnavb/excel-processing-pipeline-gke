locals {
  # Folder names follow the one exception in the naming convention: full
  # words, not the short dev/prod used everywhere else in the project.
  projects = {
    dev = {
      folder_name = "development"
      project_id  = "excel-pipeline-dev"
    }
    prod = {
      folder_name = "production"
      project_id  = "excel-pipeline-prod"
    }
    shared = {
      folder_name = "shared"
      project_id  = "excel-pipeline-shared"
    }
  }

  folder_names = [for p in local.projects : p.folder_name]

  group_domain = "tomasnavarro.dev"

  # One group per (purpose x environment) — env-suffixed because the SA it
  # wraps exists once per project, and a shared group would otherwise leak
  # access across dev/prod through membership alone.
  workload_sa_names = {
    gke-workloads = "worker-gke-sa"
    app-runtime   = "api-runtime-sa"
    infra-admins  = "sa-terraform-deployer"
    api-invokers  = "excel-client-sa"
  }

  per_env_groups = {
    for pair in setproduct(keys(local.workload_sa_names), ["dev", "prod"]) :
    "${pair[0]}-${pair[1]}" => {
      # Only infra-admins gets members here: sa-terraform-deployer is the
      # one SA governance itself creates (wif.tf). worker-gke-sa/
      # api-runtime-sa/excel-client-sa don't exist yet — the domain that
      # creates each one (gke, cloud-run) is responsible for adding it to
      # its own group, the same way domains own their resource-scoped IAM
      # bindings instead of governance.
      members = pair[0] == "infra-admins" ? [
        # A resource reference, not a hand-built string — a literal string
        # here creates no dependency, so Terraform could (and did, once)
        # try to add this membership before the SA itself existed.
        google_service_account.deployer[pair[1]].email,
        # nonsensitive(): the group module keys a for_each on each member's
        # email internally, and Terraform categorically forbids sensitive
        # values as for_each keys. Not a real secret to begin with — the
        # sensitive flag on the variable was just hygiene against
        # hardcoding it, which loading it as a workspace variable already
        # covers regardless of this flag.
        nonsensitive(var.personal_account_email),
      ] : []
    }
  }

  # infra-admins-{env}@ project-level roles — the only group whose bindings
  # governance owns directly, since governance is what creates the projects.
  infra_admin_roles = [
    "roles/container.admin",
    "roles/compute.networkAdmin",
    "roles/run.admin",
    "roles/storage.admin",
    "roles/pubsub.admin",
    "roles/datastore.owner",
  ]

  infra_admin_bindings = {
    for pair in setproduct(["dev", "prod"], local.infra_admin_roles) :
    "${pair[0]}-${replace(pair[1], "/", "-")}" => {
      environment = pair[0]
      role        = pair[1]
    }
  }

  # dev/prod only — shared has no domain workspaces deploying into it, so
  # it doesn't need its own deployer identity.
  deployer_environments = toset(["dev", "prod"])

  # The HCP Terraform Projects created in terraform/platform/hcp/, one per
  # environment, containing exactly that environment's 4 domain workspaces.
  hcp_project_names = {
    dev  = "excel-processing-pipeline-gke-dev"
    prod = "excel-processing-pipeline-gke-prod"
  }

  tfc_gcp_credentials = {
    for env in local.deployer_environments : env => {
      TFC_GCP_PROVIDER_AUTH             = "true"
      TFC_GCP_PRINCIPAL_TYPE            = "service_account"
      TFC_GCP_PROJECT_NUMBER            = google_project.this[env].number
      TFC_GCP_WORKLOAD_POOL_ID          = google_iam_workload_identity_pool.deployer[env].workload_identity_pool_id
      TFC_GCP_WORKLOAD_PROVIDER_ID      = google_iam_workload_identity_pool_provider.deployer[env].workload_identity_pool_provider_id
      TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL = google_service_account.deployer[env].email
    }
  }

  tfc_gcp_variable_instances = {
    for entry in flatten([
      for env, vars in local.tfc_gcp_credentials : [
        for key, value in vars : {
          instance_key = "${env}-${key}"
          environment  = env
          key          = key
          value        = value
        }
      ]
    ]) : entry.instance_key => entry
  }
}
