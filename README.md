# excel-processing-pipeline-gke

> 🚧 **Active development.** This repository is being built and documented
> incrementally, in public — infrastructure, application code, and docs land
> as they're actually finished, not all at once. See [Status](#-status) below
> for what's live today and what's next.

## 📖 Overview

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

---

## 🧭 Background

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

---

## 🏗️ Architecture

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

---

## ✅ Status

### Done

- [x] Architecture defined; repo structure and GCP/HCP Terraform naming
      conventions established.
- [x] `terraform/platform/hcp/`: creates the `dev`/`prod` HCP Terraform
      projects and their 8 domain workspaces via `for_each`, connects them
      to a custom GitHub OAuth connection, and drives it all from a
      manually bootstrapped management workspace.
- [x] GCP organization set up under a Cloud Identity Free domain; the
      `bootstrap` folder and seed project created, with their own Workload
      Identity Pool/Provider and service account for governance's auth.
- [x] `terraform/platform/governance/`: creates the `development`/
      `production`/`shared` folders and their GCP projects, the 9 Cloud
      Identity groups (split by environment where needed), project-level
      IAM for `infra-admins`, and a per-project Workload Identity
      Pool/Provider/service account for the domain workspaces to use.
- [x] IAM groups/roles reference table and diagramming style guide.
- [x] Architecture diagram.

### Next steps

- [ ] Artifact Registry in the shared project, with cross-project IAM for
      GKE/Cloud Run image pulls.
- [ ] Resource-scoped IAM bindings (`gke-workloads`, `app-runtime`,
      `api-invokers`, `ci-cd-pipelines` roles), attached by each domain as
      it creates its own resources.
- [ ] `terraform/domains/{networking,gke,data,cloud-run}` implementation
      (currently scaffolded, not yet implemented).
- [ ] The FastAPI API and the GKE worker.
- [ ] Kustomize manifests and Cloud Build pipelines.

A detailed, chronological log of decisions and problems solved along the way
lives in [`docs/devlog/bitacora.md`](docs/devlog/bitacora.md) (in Spanish).

---

## 🛠️ Tech stack

![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?logo=googlecloud&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)

Google Cloud (Cloud Run, GKE Autopilot, Firestore, GCS, Pub/Sub, Cloud
Identity/IAM) · Terraform + HCP Terraform · FastAPI · Docker · Kustomize
