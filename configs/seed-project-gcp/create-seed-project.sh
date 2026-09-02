#!/usr/bin/env bash
set -euo pipefail

# --- Set these manually before running ---
ORG_ID=""
ADMIN_USER=""
BOOTSTRAP_FOLDER_NAME="bootstrap"
SEED_PROJECT_ID="excel-pipeline-seed"
SHARED_FOLDER_NAME="shared"
SHARED_PROJECT_ID="excel-pipeline-shared"
REGION="europe-west9"
# ------------------------------------------

# Grant the admin user permission to create folders at the organization level
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:$ADMIN_USER" \
  --role="roles/resourcemanager.folderAdmin"

# --- bootstrap folder + seed project ---
# Isolated on purpose: hosts the identity Terraform impersonates to manage
# the rest of the org, so it stays low-traffic and easy to audit.

BOOTSTRAP_FOLDER_NAME_FULL=$(gcloud resource-manager folders create \
  --display-name="$BOOTSTRAP_FOLDER_NAME" \
  --organization="$ORG_ID" \
  --format="value(name)")
BOOTSTRAP_FOLDER_ID="${BOOTSTRAP_FOLDER_NAME_FULL#folders/}"

gcloud projects create "$SEED_PROJECT_ID" \
  --folder="$BOOTSTRAP_FOLDER_ID" \
  --name="excel-pipeline-seed-project" \
  --labels=type=seed-project

# --- shared folder + shared project ---
# Hosts resources used by both dev and prod (e.g. Artifact Registry), kept
# separate from both environments and from the bootstrap project above.

SHARED_FOLDER_NAME_FULL=$(gcloud resource-manager folders create \
  --display-name="$SHARED_FOLDER_NAME" \
  --organization="$ORG_ID" \
  --format="value(name)")
SHARED_FOLDER_ID="${SHARED_FOLDER_NAME_FULL#folders/}"

gcloud projects create "$SHARED_PROJECT_ID" \
  --folder="$SHARED_FOLDER_ID" \
  --name="excel-pipeline-shared-project" \
  --labels=type=shared-project

# Create a dedicated gcloud CLI configuration for the seed project, to avoid
# operating accidentally against another project/context
gcloud config configurations create excel-pipeline-seed
gcloud config set project "$SEED_PROJECT_ID"
gcloud config set compute/region "$REGION"

gcloud config configurations describe excel-pipeline-seed
