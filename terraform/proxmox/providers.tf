# Credentials come ONLY from the environment (never from files in git):
#   PROXMOX_VE_ENDPOINT   https://<pve-host>:8006/
#   PROXMOX_VE_API_TOKEN  terraform@pve!tf=<secret>   (read -rs, password manager)
# TLS is verified: the laptop trusts the Proxmox CA (/etc/pve/pve-root-ca.pem).
# No SSH to the hypervisor is needed: VMs are full clones of templates (API only).
provider "proxmox" {
  insecure = false
}
