resource "tfe_oauth_client" "github" {
  organization        = var.organization
  api_url             = "https://api.github.com"
  http_url            = "https://github.com"
  oauth_token         = var.github_oauth_token
  service_provider    = "github"
  organization_scoped = true
}
