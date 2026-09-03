output "project_ids" {
  description = "IDs of the dev and prod HCP Terraform projects"
  value       = { for env, project in tfe_project.environments : env => project.id }
}

output "workspace_ids" {
  description = "IDs of the domain workspaces, keyed by domain-environment"
  value       = { for key, ws in tfe_workspace.domain : key => ws.id }
}
