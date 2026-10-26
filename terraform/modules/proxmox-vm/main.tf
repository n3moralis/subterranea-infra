# One generic "building block" VM: full clone of a cloud-image template
# (Debian or Rocky), static IPv4 via cloud-init, key-only admin account.
# Everything inside the OS (hardening, Docker/Podman, services) is Ansible's job.

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  vm_id       = var.vm_id
  node_name   = var.node_name
  description = trimspace("Managed by Terraform. ${var.description}")
  tags        = sort(distinct(concat(["terraform"], var.tags)))

  on_boot         = true
  started         = true
  stop_on_destroy = true # no guest agent at first -> do not wait for a clean shutdown on destroy

  clone {
    vm_id        = var.template_vm_id
    full         = true
    datastore_id = var.datastore_id
  }

  agent {
    enabled = var.qemu_agent
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge   = var.bridge
    vlan_id  = var.vlan_id
    firewall = var.pve_firewall
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_cidr
        gateway = var.gateway
      }
    }

    dns {
      servers = length(var.dns_servers) > 0 ? var.dns_servers : [var.gateway]
      domain  = var.dns_domain
    }

    user_account {
      username = var.admin_user
      keys     = [for k in var.ssh_public_keys : trimspace(k)]
    }
  }

  lifecycle {
    # Keys are rotated by Ansible inside the OS; a cloud-init change must not
    # force a VM rebuild.
    ignore_changes = [initialization[0].user_account]
  }
}
