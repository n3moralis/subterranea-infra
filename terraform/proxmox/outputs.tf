output "hosts" {
  description = "name -> IPv4, for the Ansible inventory."
  value       = { for k, m in module.vm : k => m.ipv4 }
}

output "ansible_inventory" {
  description = "Inventory snippet for ansible/inventory (group terraform_vms)."
  value = yamlencode({
    all = {
      children = {
        terraform_vms = {
          hosts = { for k, m in module.vm : k => { ansible_host = m.ipv4 } }
        }
      }
    }
  })
}
