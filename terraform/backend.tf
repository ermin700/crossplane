terraform {
  backend "gcs" {
    bucket = "playground-s-11-1fc9fa68-crossplane-tfstate"
    prefix = "crossplane/state"
  }
}
