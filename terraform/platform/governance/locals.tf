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
      members = concat(
        ["${local.workload_sa_names[pair[0]]}@${local.projects[pair[1]].project_id}.iam.gserviceaccount.com"],
        pair[0] == "infra-admins" ? [var.personal_account_email] : []
      )
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
}
