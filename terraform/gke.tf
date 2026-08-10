data "google_client_config" "default" {}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.subnet.id

  # Delete default node pool and manage it separately for full control
  remove_default_node_pool = true
  initial_node_count       = 1

  # No workload_identity_config: this sandbox project blocks all IAM policy changes
  # (setIamPolicy denied), so a Workload Identity binding can never be created. Pods
  # fall back to the node's default Compute Engine SA via the metadata server instead
  # — see the note at the top of iam.tf.

  # VPC-native cluster using secondary ranges defined in the subnet
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Public nodes (no private_cluster_config): Cloud NAT has no free tier at all
  # (hourly + per-GB charges regardless of usage), so nodes get public IPs directly
  # for outbound access instead of routing through NAT. Trades away the
  # defense-in-depth of private nodes for a real recurring-cost line item.

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-node-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name
  project  = var.project_id

  # Fixed at 1 node, no autoscaling: every additional/larger node bills beyond the
  # single always-free e2-micro allowance, so we hold this to the minimum that
  # reliably runs GKE system pods + Crossplane.
  node_count = var.min_node_count

  node_config {
    machine_type = var.machine_type
    disk_size_gb = 30
    disk_type    = "pd-standard"

    # Uses the project's default Compute Engine SA (already roles/editor in this
    # sandbox) — no dedicated node SA, since granting it any roles would require
    # setIamPolicy, which this project denies. See the note at the top of iam.tf.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      env  = var.environment
      role = "crossplane"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
