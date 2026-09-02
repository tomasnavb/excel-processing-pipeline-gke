output "project_ids" {
  description = "IDs of the dev and prod HCP Terraform projects"
  value       = local.projects
}

output "workspace_ids" {
  description = "IDs of the domain workspaces, keyed by domain-environment"
  value       = { for key, ws in tfe_workspace.domain : key => ws.id }
}
