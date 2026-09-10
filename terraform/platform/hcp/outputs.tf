output "project_ids" {
  description = "IDs of the dev, prod, and shared HCP Terraform projects"
  value = merge(
    { for env, project in tfe_project.environments : env => project.id },
    { shared = tfe_project.shared.id },
  )
}

output "workspace_ids" {
  description = "IDs of the domain workspaces, keyed by domain-environment"
  value = merge(
    { for key, ws in tfe_workspace.domain : key => ws.id },
    { registry-shared = tfe_workspace.registry.id },
  )
}
