#!/usr/bin/env bash
# Publish the public skeleton to GitHub. Runs ONLY in GitLab CI on the default
# branch: GitLab is the single write path to GitHub, the laptop has none.
#
#   ci/publish-github.sh preview   export + diff as job artifact, nothing pushed
#   ci/publish-github.sh push      export + commit + push (manual job)
#
# Needs (GitLab → Settings → CI/CD → Variables, all Protected):
#   GITHUB_DEPLOY_KEY_B64  Var (masked)  base64 -w0 of the private half of the
#                                        write deploy key of $GITHUB_REPO only
#   PUBLIC_MAP             File          "old|new" redaction map (never in git)
#   GITHUB_COMMIT_EMAIL    Var           <id>+n3moralis@users.noreply.github.com
# and in the job: GITHUB_REPO=owner/name.
# Transport: SSH over port 443 (CI egress allows HTTPS only), host key pinned in
# ci/github_known_hosts — no trust-on-first-use.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

MODE=${1:-}
[[ $MODE == preview || $MODE == push ]] || die "usage: $0 preview|push"
: "${GITHUB_REPO:?set in the job}"
: "${GITHUB_DEPLOY_KEY_B64:?protected masked variable missing (protected branches only)}"
: "${PUBLIC_MAP:?protected File variable missing}"
: "${GITHUB_COMMIT_EMAIL:?variable missing}"
[[ ${CI_COMMIT_BRANCH:-} == "${CI_DEFAULT_BRANCH:-main}" ]] || die "publishing only from the default branch"

ROOT=$(git rev-parse --show-toplevel)
[[ -s $ROOT/ci/github_known_hosts ]] || die "ci/github_known_hosts missing (pinned GitHub host keys, see docs/ci/public-showcase.md)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUT=$WORK/public

# One-line base64 in a masked variable: no newline/CRLF damage from the GitLab UI.
( umask 077; printf '%s' "$GITHUB_DEPLOY_KEY_B64" | base64 -d > "$WORK/deploy_key" ) \
  || die "GITHUB_DEPLOY_KEY_B64 is not valid base64"
grep -q '^-----BEGIN OPENSSH PRIVATE KEY-----$' "$WORK/deploy_key" \
  || die "GITHUB_DEPLOY_KEY_B64 does not decode to an OpenSSH private key"
echo "Deploy key fingerprint (compare with GitHub → Settings → Deploy keys):"
ssh-keygen -lf "$WORK/deploy_key" || die "deploy key cannot be parsed"

# SSH user via -o User (not user@host in the URL): keeps the export's e-mail check quiet.
export GIT_SSH_COMMAND="ssh -i $WORK/deploy_key -o IdentitiesOnly=yes -o User=git \
  -o UserKnownHostsFile=$ROOT/ci/github_known_hosts -o StrictHostKeyChecking=yes"

git clone --quiet --depth 1 "ssh://ssh.github.com:443/${GITHUB_REPO}.git" "$OUT"

PUBLIC_MAP=$PUBLIC_MAP "$ROOT/tools/public-export.sh" "$OUT"

cd "$OUT"
git add -A
if git diff --cached --quiet; then
  echo "Nothing to publish — GitHub already matches the allowlisted tree."
  exit 0
fi

git diff --cached --stat | tee "$ROOT/publish-diff.stat"
git diff --cached > "$ROOT/publish.diff"

if [[ $MODE == preview ]]; then
  echo "Preview only. Read publish.diff in the job artifacts, then run publish:github."
  exit 0
fi

git -c user.name=n3moralis -c user.email="$GITHUB_COMMIT_EMAIL" \
  commit --quiet -m "Publish skeleton ($(date -u +%F))"
git push --quiet origin HEAD:main
echo "Published to https://github.com/${GITHUB_REPO}"
