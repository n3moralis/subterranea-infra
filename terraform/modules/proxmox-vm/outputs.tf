output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "ipv4" {
  description = "Address without prefix (for SSH / Ansible inventory)."
  value       = split("/", var.ipv4_cidr)[0]
}
