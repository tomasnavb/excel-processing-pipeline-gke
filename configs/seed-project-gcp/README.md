# GCP Seed Project

Bootstrap GCP project that will host the Workload Identity Pool/Provider and
the service account Terraform impersonates to manage the rest of the
organization (folders, dev/prod projects) without static credentials.

It exists to break a chicken-and-egg problem: WIF-based authentication needs
an identity pool, and a pool must live inside an already-existing GCP
project. This project is that one exception, created manually and once,
before Terraform can manage anything else.

Set the variables at the top of `create-seed-project.sh`, then run the whole
script.
