# Terraform — VM building blocks on Proxmox

One generic module (`modules/proxmox-vm`) turns a cloud-image template into a
VM: Debian 13 or Rocky 9, static IPv4 in a VLAN, key-only admin account. What
runs inside (hardening, Docker/Podman, services) is Ansible's job. The goal is
to split the current Docker "monolith" into themed blocks, one VM each
(CI first; Podman stacks next).

```
Proxmox template (templates.tf)           ──clone──►  VM block (Terraform)  ──►  Ansible (base, runtime, service)
   debian13 9001 / rocky9 9002                          cloud-init: IP, ops + key       hardening, podman/docker, app
```

| Decision | Why |
|---|---|
| Templates as code: Proxmox downloads a **pinned, checksum-verified** image and Terraform builds the template; VMs are full clones | Proxmox 9 imports through the API: no SSH/root on the hypervisor; image updates are reviewed MRs |
| Provider `bpg/proxmox`, exact version in committed `.terraform.lock.hcl` | supply chain: upgrades are reviewed MRs |
| State in the **self-hosted GitLab** (HTTP backend with locking) | no state on laptops, no cloud dependency, access = GitLab permissions |
| Credentials only from environment (`read -rs`), never in files | nothing to leak through git or state; later: from Vault |
| VM definitions committed in `proxmox/vms.tf` | the VM list *is* the documentation; no `*.tfvars` with the real layout |
| `ipv4_cidr` rejects `/32` | the Vault incident: /32 sent peer traffic through the firewall |

## One-time setup

### 1. Proxmox: least-privilege API user (root shell on the node)

```bash
pveum role add TerraformProv -privs "Datastore.Allocate Datastore.AllocateSpace \
  Datastore.AllocateTemplate Datastore.Audit Sys.Audit Sys.Modify \
  VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit \
  VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory \
  VM.Config.Network VM.Config.Options VM.PowerMgmt SDN.Use"
pveum user add terraform@pve --comment "Terraform (API token only, no password)"
pveum aclmod / -user terraform@pve -role TerraformProv
pveum user token add terraform@pve tf --privsep 0 --expire $(date -d "+90 days" +%s)   # secret shown ONCE -> password manager
```
If `pveum` rejects a privilege name (they differ slightly between Proxmox 8
and 9), drop it and re-run; if `apply` later fails with "permission check
failed", the error names the missing privilege.

### 2. Templates

Datacenter → Storage → `local` → Content: add **Import** (once). Pin image
version + checksum in `template_images` (`variables.tf`); `apply` downloads,
verifies and builds the template.
The bridge must be VLAN aware and the switch port must carry the VLAN tags.

### 3. Laptop: trust the Proxmox certificate

```bash
scp root@<pve>:/etc/pve/pve-root-ca.pem /tmp/pve-root-ca.crt
sudo cp /tmp/pve-root-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
curl -sI https://<pve>:8006 | head -1     # works without -k
```

### 4. GitLab: state backend

Project → Settings → Access tokens → **project access token**, role Maintainer,
scope `api`, short expiry → password manager.

```bash
cd terraform/proxmox
GITLAB=https://<gitlab-host>; PROJECT_ID=<id>; STATE=proxmox
read -rs TF_HTTP_PASSWORD && export TF_HTTP_PASSWORD     # project access token
terraform init \
  -backend-config="address=$GITLAB/api/v4/projects/$PROJECT_ID/terraform/state/$STATE" \
  -backend-config="lock_address=$GITLAB/api/v4/projects/$PROJECT_ID/terraform/state/$STATE/lock" \
  -backend-config="unlock_address=$GITLAB/api/v4/projects/$PROJECT_ID/terraform/state/$STATE/lock" \
  -backend-config="username=<gitlab-user-or-token-name>" \
  -backend-config="lock_method=POST" -backend-config="unlock_method=DELETE" \
  -backend-config="retry_wait_min=5"
git add .terraform.lock.hcl     # pin the provider; commit with the MR
```

## Daily use

```bash
cd terraform/proxmox
export PROXMOX_VE_ENDPOINT=https://<pve>:8006/
read -rs PROXMOX_VE_API_TOKEN && export PROXMOX_VE_API_TOKEN   # terraform@pve!tf=<secret>
read -rs TF_HTTP_PASSWORD && export TF_HTTP_PASSWORD
terraform fmt -recursive .. && terraform validate
terraform plan -out=tfplan        # review: only the VMs you expect
terraform apply tfplan
terraform output ansible_inventory
unset PROXMOX_VE_API_TOKEN TF_HTTP_PASSWORD; rm -f tfplan
```

New block = new entry in `local.vms` (`proxmox/vms.tf`) → MR → plan → apply →
Ansible. Removing an entry destroys that VM (plan shows it — read it).

## After apply

```bash
ssh -i ~/.ssh/<key> ops@<ip>      # key login works, cloud-init grew the disk
```
Then Ansible takes over (`ansible/playbooks/ci-runner.yml` for the runner):
baseline hardening (SELinux, key-only SSH, sudo password, firewalld, chrony,
security updates, qemu-guest-agent → then set `qemu_agent = true`), then the
runtime (rootless Podman) and the service.

## CI

`ci/lint.sh` runs **checkov** over `terraform/`. `terraform fmt -check` / `validate` run on the laptop
before every MR (CI image has no Terraform binary yet).
