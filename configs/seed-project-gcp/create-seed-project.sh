#!/usr/bin/env bash
set -euo pipefail

# --- Set these manually before running ---
ORG_ID=""
ADMIN_USER=""
SEED_FOLDER_NAME="seed-projects"
SEED_PROJECT_ID="excel-pipeline-seed"
REGION="europe-west9"
# ------------------------------------------

# Grant the admin user permission to create folders at the organization level
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="user:$ADMIN_USER" \
  --role="roles/resourcemanager.folderAdmin"

# Create a folder to hold the seed project, then extract its numeric ID
SEED_FOLDER_NAME_FULL=$(gcloud resource-manager folders create \
  --display-name="$SEED_FOLDER_NAME" \
  --organization="$ORG_ID" \
  --format="value(name)")
SEED_FOLDER_ID="${SEED_FOLDER_NAME_FULL#folders/}"

# Create the seed project inside that folder
gcloud projects create "$SEED_PROJECT_ID" \
  --folder="$SEED_FOLDER_ID" \
  --name="excel-pipeline-seed-project" \
  --labels=type=seed-project

# Create a dedicated gcloud CLI configuration, to avoid operating
# accidentally against another project/context
gcloud config configurations create excel-pipeline-seed
gcloud config set project "$SEED_PROJECT_ID"
gcloud config set compute/region "$REGION"

gcloud config configurations describe excel-pipeline-seed
