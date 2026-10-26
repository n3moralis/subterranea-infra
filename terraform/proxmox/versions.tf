terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78" # exact version is pinned in .terraform.lock.hcl (committed)
    }
  }

  # State lives in the self-hosted GitLab (Terraform state API, with locking).
  # Address/credentials are passed at init time — see ../README.md.
  backend "http" {}
}
