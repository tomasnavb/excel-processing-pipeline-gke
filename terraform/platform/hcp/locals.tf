locals {
  domains = ["networking", "gke", "data", "cloud-run"]

  projects = {
    dev  = tfe_project.dev.id
    prod = tfe_project.prod.id
  }

  workspaces = {
    for pair in setproduct(keys(local.projects), local.domains) :
    "${pair[1]}-${pair[0]}" => {
      environment       = pair[0]
      domain            = pair[1]
      project_id        = local.projects[pair[0]]
      working_directory = "terraform/domains/${pair[1]}/${pair[0]}"
    }
  }
}
