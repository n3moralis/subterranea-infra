# Building blocks: every VM is the same generic module; only size, OS and
# network differ. Services (CI runner, Podman stacks, ...) are added by
# Ansible on top — Terraform knows nothing about what runs inside.
#
# VMID convention: <VLAN id><host number>  (VLAN 70 -> 701, 702, ...)
# Templates:        templates.tf (var.template_images: rocky9 = 9002, debian13 = 9001)

locals {
  # name -> template VMID; referencing the resource makes clones wait for it
  templates = { for k, t in proxmox_virtual_environment_vm.template : k => t.vm_id }

  ssh_public_keys = [for f in var.ssh_public_key_files : file(pathexpand(f))]

  vms = {
    ci-runner = {
      os         = "rocky9"
      vm_id      = 10201
      vlan_id    = 201
      ipv4_cidr  = "10.0.191.101/24" # CHANGE to your CI VLAN
      gateway    = "10.0.191.1"      # OPNsense CI interface
      cores      = 2
      memory_mb  = 4096
      disk_gb    = 40
      qemu_agent = true # true once ci-runner.yml has installed qemu-guest-agent
      tags       = ["ci", "podman"]
      desc       = "GitLab Runner, rootless Podman. Isolated CI VLAN: only GitLab:443 + internet:443."
    }

    # Next blocks, same pattern (uncomment when needed):
    # svc-01 = {
    #   os = "rocky9", vm_id = 801, vlan_id = 80, ipv4_cidr = "10.0.80.11/24", gateway = "10.0.80.1",
    #   cores = 2, memory_mb = 4096, disk_gb = 40, tags = ["podman"], desc = "Podman stack: <theme>"
    # }
  }
}

module "vm" {
  source   = "../modules/proxmox-vm"
  for_each = local.vms

  name           = each.key
  vm_id          = each.value.vm_id
  node_name      = var.proxmox_node
  template_vm_id = local.templates[each.value.os]
  datastore_id   = var.datastore_id

  cores     = each.value.cores
  memory_mb = each.value.memory_mb
  disk_gb   = each.value.disk_gb

  bridge    = var.bridge
  vlan_id   = each.value.vlan_id
  ipv4_cidr = each.value.ipv4_cidr
  gateway   = each.value.gateway

  qemu_agent      = try(each.value.qemu_agent, false)
  ssh_public_keys = local.ssh_public_keys
  tags            = concat([each.value.os], each.value.tags)
  description     = each.value.desc
}
