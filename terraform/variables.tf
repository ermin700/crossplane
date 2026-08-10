variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
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
  description = "Minimum nodes per zone (cluster autoscaler lower bound)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes per zone (cluster autoscaler upper bound)"
  type        = number
  default     = 5
}

variable "machine_type" {
  description = "GCE machine type for cluster nodes"
  type        = string
  default     = "e2-standard-4"
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
