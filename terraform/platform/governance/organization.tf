# Not sensitive — the domain is already public in this repo, and looking
# the org up this way removes one manually-typed variable (and the risk of
# a mistyped numeric ID failing silently).
data "google_organization" "this" {
  domain = "tomasnavarro.dev"
}
