locals {
  environments = toset(["dev", "prod"])
  domains      = ["networking", "gke", "data", "cloud-run"]

  workspaces = {
    for pair in setproduct(local.environments, local.domains) :
    "${pair[1]}-${pair[0]}" => {
      environment       = pair[0]
      domain            = pair[1]
      project_id        = tfe_project.environments[pair[0]].id
      working_directory = "terraform/domains/${pair[1]}/${pair[0]}"
    }
  }
}
