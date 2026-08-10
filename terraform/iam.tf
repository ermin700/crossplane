# NOTE: this project is a locked-down training-sandbox project (setIamPolicy is
# denied for every identity available here, including the logged-in lab user) — see
# crossplane_gcp_setup.md and crossplane_gke_cluster_setup.md for details. There is no
# dedicated SA / Workload Identity setup in this stack as a result: GKE nodes and
# everything running on them (Crossplane, providers) fall back to the project's
# default Compute Engine service account, which the lab platform pre-grants
# roles/editor. That's broader-privileged than the least-privilege design this repo
# would otherwise use — restore per-provider dedicated SAs + Workload Identity
# (see git history / crossplane_gcp_setup.md's "Why a separate SA" notes) once this
# runs against a project where you can grant IAM roles.

# GCS bucket for Terraform remote state
resource "google_storage_bucket" "terraform_state" {
  name          = var.terraform_state_bucket
  location      = var.region
  project       = var.project_id
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}
