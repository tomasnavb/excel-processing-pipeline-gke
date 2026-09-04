#!/usr/bin/env bash
set -euo pipefail

# --- Set these manually before running ---
SEED_PROJECT_ID="excel-pipeline-seed"
ORG_ID=""
WIF_POOL_ID="hcp-terraform-pool"
WIF_PROVIDER_ID="hcp-terraform-provider"
SA_NAME="governance-admin-sa"
TFC_ORG_NAME=""
TFC_PROJECT_NAME="excel-processing-pipeline-gke-mgmt"
TFC_WORKSPACE_NAME="excel-pipeline-governance-mgmt"
# ------------------------------------------

SA_EMAIL="${SA_NAME}@${SEED_PROJECT_ID}.iam.gserviceaccount.com"
SEED_PROJECT_NUMBER=$(gcloud projects describe "$SEED_PROJECT_ID" --format="value(projectNumber)")

# Assumes a single open billing account on the caller's account. If you have
# more than one, replace this with the specific billingAccounts/XXXXXX-XXXXXX-XXXXXX ID.
BILLING_ACCOUNT_ID=$(gcloud billing accounts list --filter="open=true" --format="value(name)" --limit=1)
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID#billingAccounts/}"

# APIs required for Workload Identity Federation
gcloud services enable iamcredentials.googleapis.com sts.googleapis.com \
  --project="$SEED_PROJECT_ID"

# Workload Identity Pool
gcloud iam workload-identity-pools create "$WIF_POOL_ID" \
  --project="$SEED_PROJECT_ID" \
  --location="global" \
  --display-name="HCP Terraform pool"

# OIDC provider trusting HCP Terraform, restricted to one specific workspace
# via the attribute condition (never widen this to the whole pool/org).
gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
  --project="$SEED_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WIF_POOL_ID" \
  --issuer-uri="https://app.terraform.io" \
  --attribute-mapping="google.subject=assertion.sub,attribute.terraform_organization_id=assertion.terraform_organization_id,attribute.terraform_organization_name=assertion.terraform_organization_name,attribute.terraform_project_id=assertion.terraform_project_id,attribute.terraform_project_name=assertion.terraform_project_name,attribute.terraform_workspace_id=assertion.terraform_workspace_id,attribute.terraform_workspace_name=assertion.terraform_workspace_name" \
  --attribute-condition="assertion.sub.startsWith(\"organization:${TFC_ORG_NAME}:project:${TFC_PROJECT_NAME}:workspace:${TFC_WORKSPACE_NAME}\")"

# Service account Terraform will impersonate
gcloud iam service-accounts create "$SA_NAME" \
  --project="$SEED_PROJECT_ID" \
  --display-name="Terraform admin (governance)"

# Organization-level permissions: create folders/projects, attach billing
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/resourcemanager.folderCreator"

gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/resourcemanager.projectCreator"

gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/billing.user"

# Only a token whose "sub" claim matches the attribute condition above can
# even reach this point, so it's safe to scope this binding to the pool.
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --project="$SEED_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${SEED_PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/*"

# Load these 6 values as Environment Variables on excel-pipeline-governance-mgmt
echo "TFC_GCP_PROVIDER_AUTH=true"
echo "TFC_GCP_PRINCIPAL_TYPE=service_account"
echo "TFC_GCP_PROJECT_NUMBER=${SEED_PROJECT_NUMBER}"
echo "TFC_GCP_WORKLOAD_POOL_ID=${WIF_POOL_ID}"
echo "TFC_GCP_WORKLOAD_PROVIDER_ID=${WIF_PROVIDER_ID}"
echo "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL=${SA_EMAIL}"
