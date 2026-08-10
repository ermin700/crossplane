variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the (zonal, single-node) GKE cluster — keep in an always-free-eligible region (us-central1/us-west1/us-east1) to minimize cost"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "crossplane-control-plane"
}

variable "environment" {
  description = "Environment label applied to node pool"
  type        = string
  default     = "prod"
}

variable "min_node_count" {
  description = "Node pool size, fixed at 1 (no autoscaling) to minimize cost"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "GCE machine type for cluster nodes — e2-small is the practical minimum that reliably runs GKE system pods + Crossplane; e2-micro (the free-tier-eligible shape) is too memory-constrained for a GKE node in practice"
  type        = string
  default     = "e2-small"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the GKE subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Secondary range CIDR for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range CIDR for services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "master_cidr" {
  description = "CIDR for GKE control plane (must be /28, must not overlap other ranges)"
  type        = string
  default     = "172.16.0.0/28"
}

variable "crossplane_version" {
  description = "Crossplane Helm chart version"
  type        = string
  default     = "1.17.1"
}

variable "terraform_state_bucket" {
  description = "Name of the GCS bucket for Terraform remote state (must be globally unique)"
  type        = string
}
