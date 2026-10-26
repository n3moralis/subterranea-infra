variable "name" {
  description = "VM name (also the hostname set by cloud-init)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,62}$", var.name))
    error_message = "Lowercase letters, digits and dashes only."
  }
}

variable "vm_id" {
  description = "Proxmox VMID. Convention: VLAN id * 10 + host number (VLAN 70 -> 700-709)."
  type        = number
}

variable "node_name" {
  description = "Proxmox node the VM runs on."
  type        = string
}

variable "template_vm_id" {
  description = "VMID of the cloud-image template to clone (terraform/proxmox/templates.tf)."
  type        = number
}

variable "datastore_id" {
  description = "Datastore for the VM disk and the cloud-init drive."
  type        = string
  default     = "local-lvm"
}

variable "cores" {
  type    = number
  default = 2
}

variable "cpu_type" {
  description = "x86-64-v2 is the minimum for Rocky/RHEL 9; also fine for Debian."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  description = "Root disk size; must be >= the template disk. cloud-init grows the filesystem."
  type        = number
  default     = 20
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag on the VM NIC (bridge must be VLAN-aware). null = untagged."
  type        = number
  default     = null
}

variable "ipv4_cidr" {
  description = "Static address with the REAL prefix, e.g. 10.0.70.10/24 (never /32: peers would be routed via the gateway)."
  type        = string
  validation {
    condition     = can(cidrhost(var.ipv4_cidr, 0)) && !endswith(var.ipv4_cidr, "/32")
    error_message = "Use address/prefix with the subnet's real prefix, not /32."
  }
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "dns_domain" {
  type    = string
  default = null
}

variable "admin_user" {
  description = "Initial admin account created by cloud-init (key login only; Ansible hardens it afterwards)."
  type        = string
  default     = "ops"
}

variable "ssh_public_keys" {
  description = "Public keys for admin_user. Never a private key."
  type        = list(string)
  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for k in var.ssh_public_keys : !strcontains(k, "PRIVATE KEY")])
    error_message = "At least one PUBLIC key is required."
  }
}

variable "qemu_agent" {
  description = "Enable once qemu-guest-agent is installed (Ansible base role). While false, Terraform does not wait for the agent."
  type        = bool
  default     = false
}

variable "pve_firewall" {
  description = "Proxmox firewall on the NIC. Segmentation is enforced on OPNsense; keep false unless rules exist in Proxmox."
  type        = bool
  default     = false
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "description" {
  type    = string
  default = ""
}
