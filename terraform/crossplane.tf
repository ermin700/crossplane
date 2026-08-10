provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }

  # Isolated from ~/.config/helm — the shared global repo list on this machine has
  # unrelated (and in some cases dead) repos, and the Helm SDK errors out if *any*
  # configured repo lacks a cached index, even when it's not the one being used.
  repository_config_path = "${path.module}/.helm/repositories.yaml"
  repository_cache       = "${path.module}/.helm/cache"
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

resource "helm_release" "crossplane" {
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  namespace        = "crossplane-system"
  create_namespace = true
  version          = var.crossplane_version

  # No serviceAccount.annotations.iam.gke.io/gcp-service-account: no Workload Identity
  # in this sandbox (see iam.tf). The Crossplane pod authenticates to GCP as the
  # node's default Compute Engine SA via the metadata server instead.

  depends_on = [google_container_node_pool.primary_nodes]
}
