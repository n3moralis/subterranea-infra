#!/usr/bin/env bash
# Static checks — the ONLY definition of "lint". Called by .gitlab-ci.yml
# (self-hosted GitLab, Debian job image) and .github/workflows/ci.yml (same
# image as a job container). On the laptop run it inside a venv:
#   python3 -m venv .venv && . .venv/bin/activate && bash ci/lint.sh
set -euo pipefail
export PIP_DISABLE_PIP_VERSION_CHECK=1 DEBIAN_FRONTEND=noninteractive

# git is needed for the CIS role (Galaxy installs it from a git URL)
if ! command -v git >/dev/null; then
  # The CI network allows outbound 443 only (no plain HTTP). Debian images point
  # apt at http://deb.debian.org; switch to HTTPS (apt verifies the GPG
  # signatures either way, HTTPS just keeps us inside the egress policy).
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [ -f "$f" ]; then sed -i 's#http://deb.debian.org#https://deb.debian.org#g' "$f"; fi
  done
  echo "== apt sources (must be https)"; grep -rhE '^(URIs:|deb )' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends git ca-certificates >/dev/null
fi
pip install --quiet --root-user-action=ignore -r ci/requirements.txt

echo "== yamllint";   yamllint -s .
# Only the scripts that exist: the public showcase ships a subset of the repo.
shopt -s nullglob
scripts=(ansible/scripts/pki/*.sh tools/*.sh ci/*.sh)
shopt -u nullglob
echo "== shellcheck"; shellcheck -S warning "${scripts[@]}"
echo "== checkov (terraform)"; checkov -d terraform --framework terraform --compact --quiet --skip-download

cd ansible
echo "== galaxy"
ansible-galaxy collection install -r requirements.yml >/dev/null
ansible-galaxy role install -r requirements.yml -p roles >/dev/null
echo "== ansible-lint"; ansible-lint --offline
echo "== syntax-check"
for p in playbooks/*.yml; do ansible-playbook --syntax-check "$p" >/dev/null && echo "ok  $p"; done
