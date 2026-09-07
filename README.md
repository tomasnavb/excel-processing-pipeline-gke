# excel-processing-pipeline-gke

> 🚧 **Active development.** This repository is being built and documented
> incrementally, in public — infrastructure, application code, and docs land
> as they're actually finished, not all at once. See [Status](#status) below
> for what's live today and what's next.

## Overview

An asynchronous Excel file processing pipeline on Google Cloud:

- A **FastAPI** API, deployed on **Cloud Run**, receives a file, validates
  it, uploads it to **GCS**, and writes a status record to **Firestore**
  (keyed by `job_id`).
- GCS natively notifies **Pub/Sub** when the upload finishes
  (`OBJECT_FINALIZE`) — the API never publishes the event itself, to avoid a
  dual-write.
- A **worker on GKE** consumes the event, processes the file, writes the
  result back to GCS, and updates the job status.
- Dev and prod are fully separate GCP projects (isolated IAM, quotas, and
  billing), each under its own Folder in a Cloud Identity organization.
- Infrastructure is managed with **HCP Terraform**, authenticating to GCP
  via **Workload Identity Federation** — no static service account keys
  anywhere in the pipeline.

## Background

This project is inspired by a real tool I designed and built: a Python +
PyQt5 program that splits a merged customer spreadsheet into one file per
customer, with correct headers and filenames, ready to email out
individually. Some publishers send data for up to 60 customers mixed into a
single file; a VBA post-processing step handles a legacy `.xls` export
format one client still requires.

It's in active use across 16 recurring publishers. Manual segmentation used
to take 1–1.5 hours per publisher (~20 hours total); the tool now does each
in under a minute (~20 minutes total).

This repository is not a 1:1 port of it — it's a reconstruction of the same
underlying business problem (splitting and routing a shared file to many
distinct recipients) on a cloud-native stack (GCP, Kubernetes, event-driven
architecture, Terraform), built to explore how that problem scales and to
demonstrate an infrastructure approach, not to replace the original system.

## Architecture

![Infrastructure diagram](docs/architecture/infra-excel-processing-pipeline-gke.png)

Diagrams follow the conventions in [`docs/architecture/style-guide.md`](docs/architecture/style-guide.md).

### GCP resource hierarchy

![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?logo=googlecloud&logoColor=white)

```
tomasnavarro.dev (Organization)
├── development (Folder)
│   └── excel-pipeline-dev (Project)
├── production (Folder)
│   └── excel-pipeline-prod (Project)
├── bootstrap (Folder)
│   └── excel-pipeline-seed (Project)
└── shared (Folder)
    └── excel-pipeline-shared (Project)
```

### HCP Terraform resource hierarchy

![HCP Terraform](https://img.shields.io/badge/HCP_Terraform-7B42BC?logo=terraform&logoColor=white)

A separate hierarchy from the one above — an HCP Terraform "Project" is an
organizational concept for grouping workspaces, unrelated to a GCP Project.

```
<hcp-terraform-org> (Organization)
├── excel-processing-pipeline-gke-dev (Project)
│   ├── excel-pipeline-networking-dev (Workspace)
│   ├── excel-pipeline-gke-dev (Workspace)
│   ├── excel-pipeline-data-dev (Workspace)
│   └── excel-pipeline-cloud-run-dev (Workspace)
├── excel-processing-pipeline-gke-prod (Project)
│   ├── excel-pipeline-networking-prod (Workspace)
│   ├── excel-pipeline-gke-prod (Workspace)
│   ├── excel-pipeline-data-prod (Workspace)
│   └── excel-pipeline-cloud-run-prod (Workspace)
└── excel-processing-pipeline-gke-mgmt (Project)
    ├── excel-pipeline-hcp-mgmt (Workspace)
    └── excel-pipeline-governance-mgmt (Workspace)
```

## Status

### Done

- Architecture defined; repo structure and GCP/HCP Terraform naming
  conventions established.
- `terraform/platform/hcp/`: creates the `dev`/`prod` HCP Terraform
  projects and their 8 domain workspaces via `for_each`, wires up VCS
  connectivity (`tfe_oauth_client`), and drives it all from a manually
  bootstrapped management workspace.
- `terraform/domains/{networking,gke,data,cloud-run}/{dev,prod}` scaffolded
  (not yet implemented).
- GCP organization set up under a Cloud Identity Free domain; `bootstrap`
  and `shared` folders and their seed/shared projects created.
- Architecture diagram and [diagramming style guide](docs/architecture/style-guide.md).

### Next steps

- Workload Identity Pool/Provider and service account in the seed project,
  with organization-level IAM bindings.
- Artifact Registry in the shared project, with cross-project IAM for GKE.
- `terraform/platform/governance/`: folders, dev/prod GCP projects, and IAM
  group bindings.
- `terraform/domains/{networking,gke,data,cloud-run}` implementation.
- The FastAPI API and the GKE worker.
- Kustomize manifests and Cloud Build pipelines.

A detailed, chronological log of decisions and problems solved along the way
lives in [`docs/devlog/bitacora.md`](docs/devlog/bitacora.md) (in Spanish).

## Tech stack

Google Cloud (Cloud Run, GKE Autopilot, Firestore, GCS, Pub/Sub, Cloud
Identity/IAM) · Terraform + HCP Terraform · FastAPI · Docker · Kustomize
