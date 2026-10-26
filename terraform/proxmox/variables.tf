variable "proxmox_node" {
  description = "Proxmox node that hosts the templates and the VMs."
  type        = string
  default     = "pve-1"
}

variable "datastore_id" {
  type    = string
  default = "local-zfs"
}

variable "bridge" {
  description = "VLAN-aware VM trunk bridge (tagged only: Services + CI)."
  type        = string
  default     = "vmbr1"
}

variable "ssh_public_key_files" {
  description = "Admin PUBLIC key files on the operator's machine (paths, not keys, so nothing personal is committed)."
  type        = list(string)
  default     = ["~/.ssh/blocks_key.pub"]
}

variable "image_datastore_id" {
  description = "Directory storage that holds downloaded cloud images (content type 'Import' enabled)."
  type        = string
  default     = "local"
}

variable "template_images" {
  description = <<-EOT
    Cloud images turned into templates. Pin a VERSIONED file (never ".latest")
    and its checksum from the vendor's checksum file (runbook B.2).
  EOT
  type = map(object({
    vm_id              = number
    version            = string
    url                = string
    checksum           = string
    checksum_algorithm = string # sha256 (Rocky CHECKSUM) / sha512 (Debian SHA512SUMS)
    disk_gb            = number # >= the image's virtual size; clones grow it
  }))
  default = {
    rocky9 = {
      vm_id              = 9002
      version            = "9.8-20260525.0" # e.g. 9.6-20250531.0
      url                = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2"
      checksum           = "92c206cc6f790c61583247eefe87890f8828420662c17cacf247cec78ab4eec8"
      checksum_algorithm = "sha256"
      disk_gb            = 10
    }
    # debian13 = {
    #   vm_id = 9001, version = "<date-build>", checksum_algorithm = "sha512", disk_gb = 3,
    #   url = "https://cloud.debian.org/images/cloud/trixie/<date-build>/debian-13-genericcloud-amd64-<date-build>.qcow2",
    #   checksum = "<from SHA512SUMS in the same directory>"
    # }
  }

  validation {
    condition = alltrue([
      for k, v in var.template_images :
      can(regex("^[0-9a-f]{64}$|^[0-9a-f]{128}$", v.checksum)) && !strcontains(v.url, "latest")
    ])
    error_message = "Each image needs a real hex checksum and a versioned URL (no 'latest')."
  }
}
