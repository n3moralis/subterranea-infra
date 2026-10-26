# Cloud-image templates, as code (Proxmox 9.x: image import through the API,
# no SSH to the hypervisor).
#
# 1. Proxmox downloads the image itself and VERIFIES the checksum pinned below.
# 2. A VM is built around it and marked as template (never boots).
# 3. vms.tf clones these templates; the reference creates the dependency.
#
# Image update = new URL + checksum in var.template_images -> MR -> plan shows
# the template being replaced. Existing VMs are full clones and are not touched.

resource "proxmox_download_file" "image" {
  for_each = var.template_images

  node_name    = var.proxmox_node
  datastore_id = var.image_datastore_id # needs content type "Import" (runbook B.1)
  content_type = "import"

  url                = each.value.url
  file_name          = "${each.key}-${each.value.version}.qcow2"
  checksum           = each.value.checksum
  checksum_algorithm = each.value.checksum_algorithm
  overwrite          = false
}

resource "proxmox_virtual_environment_vm" "template" {
  for_each = var.template_images

  name        = "tmpl-${each.key}"
  vm_id       = each.value.vm_id
  node_name   = var.proxmox_node
  description = "Managed by Terraform. Cloud image ${each.key} ${each.value.version} (checksum-verified)."
  tags        = sort(["template", "terraform", each.key])

  template = true
  started  = false
  on_boot  = false

  operating_system {
    type = "l26"
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES" # Rocky/RHEL 9 needs at least x86-64-v2
  }

  memory {
    dedicated = 2048
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    import_from  = proxmox_download_file.image[each.key].id
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  # Empty cloud-init drive; every clone writes its own IP/user/key into it.
  initialization {
    datastore_id = var.datastore_id
  }

  network_device {
    bridge = var.bridge # VLAN tag is set per clone
  }

  # Cloud images log to the serial console; Proxmox "Console" shows it.
  serial_device {}

  vga {
    type = "serial0"
  }

  agent {
    enabled = false # installed later by Ansible
  }
}
