#!/usr/bin/env bash
# Build the PUBLIC GitHub showcase from this repo. The self-hosted GitLab stays
# the only home of the full project; GitHub gets an allowlisted, redacted
# excerpt. History is never published: the public repo gets fresh commits made
# by hand after reviewing the diff.
#
#   tools/public-export.sh ~/github/subterranea-infra
#
# Inputs:
#   tools/public-include.txt  committed  ALLOWLIST: only these paths are published
#   tools/.public-map         PRIVATE    "old|new" replacements (topology, names);
#                                         gitignored — it reverse-maps the redaction
# Checks (any hit aborts, nothing is copied):
#   - a mapped "old" value still present
#   - private/Tailscale IPv4 outside the documentation prefix, real e-mails
#   - gitleaks on the staged tree
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel)
OUT=${1:?usage: tools/public-export.sh <path-to-public-checkout>}
MAP=${PUBLIC_MAP:-$ROOT/tools/.public-map}   # CI: protected File variable PUBLIC_MAP
INCLUDE="$ROOT/tools/public-include.txt"

[[ -f $MAP ]] || die "$MAP missing (copy tools/public-map.example and fill it)"
[[ -d $OUT/.git ]] || die "$OUT is not a git checkout of the public repo"
command -v gitleaks >/dev/null || die "gitleaks not installed"
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  die "uncommitted changes — export only committed state"
fi

STAGE=$(mktemp -d)

# 1. Committed tree only (no .git, nothing gitignored, nothing untracked)
FULL=$(mktemp -d)
trap 'rm -rf "$STAGE" "$FULL"' EXIT
git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$FULL"

# 2. Allowlist: copy only listed paths; a pattern matching nothing is an error
(
  cd "$FULL"
  shopt -s globstar nullglob dotglob
  while IFS= read -r pat; do
    [[ -z $pat || $pat == \#* ]] && continue
    # shellcheck disable=SC2206  # glob expansion of the allowlist pattern is intended
    matches=($pat)
    (( ${#matches[@]} )) || { echo "allowlist pattern matches nothing: $pat" >&2; exit 1; }
    for f in "${matches[@]}"; do
      [[ -f $f ]] || continue
      mkdir -p "$STAGE/$(dirname "$f")" && cp -p -- "$f" "$STAGE/$f"
    done
  done < "$INCLUDE"
) || die "allowlist failed"
# Hard stops even if someone allowlists them by mistake
find "$STAGE" \( -name '*.asc' -o -name '*.crt' -o -name '*.pem' -o -name '*.key' \
  -o -name 'secrets.yml' -o -name '.public-map' -o -path '*/inventory/*' \) -print -delete \
  | sed "s|$STAGE/|removed (never public): |"

# 3. Ceremony record (§6) holds where shares are kept: never public
while IFS= read -r f; do
  awk '/^## 6\. Ceremony record/ {print; print ""; print "_Redacted in the public showcase._"; exit} {print}' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done < <(find "$STAGE" -name 'vault-init-ceremony.md')

# 4. Replacements (literal, longest first)
mapfile -t PAIRS < <(grep -vE '^\s*(#|$)' "$MAP" | awk -F'|' '{print length($1) "\t" $0}' | sort -rn | cut -f2-)
for pair in "${PAIRS[@]}"; do
  old=${pair%%|*}; new=${pair#*|}
  [[ -n $old && $pair == *"|"* ]] || die "bad map line: $pair"
  grep -rlIF -- "$old" "$STAGE" | while IFS= read -r f; do
    OLD=$old NEW=$new perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
  done || true
done

# 5. Verification — print file:line only, never the matched secret context
fail=0
for pair in "${PAIRS[@]}"; do
  old=${pair%%|*}
  if grep -rlIF -- "$old" "$STAGE" >/dev/null; then
    echo "LEFTOVER mapped value in: $(grep -rlIF -- "$old" "$STAGE" | sed "s|$STAGE/||" | tr '\n' ' ')"; fail=1
  fi
done
# Every private (RFC 1918) and Tailscale/CGNAT (100.64/10) address is real
# topology unless it is a documentation value. Allowed: the placeholder prefix
# the map rewrites to (10.0.x.x by convention) and whole-range literals such as
# 10.0.0.0/8. Override with PUBLIC_IP_ALLOW_RE if a real network uses 10.0.x.x.
PRIV_RE='(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3})(/[0-9]{1,2})?'
ALLOW_IP_RE=${PUBLIC_IP_ALLOW_RE:-'^(10\.0\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?|10\.0\.0\.0/8|172\.16\.0\.0/12|192\.168\.0\.0/16|100\.64\.0\.0/10)$'}
leaks=$(grep -rnIoE "$PRIV_RE" "$STAGE" | while IFS= read -r hit; do
          ip=${hit##*:}
          [[ $ip =~ $ALLOW_IP_RE ]] || printf '%s\n' "${hit%:*}"
        done | sed "s|$STAGE/||" | sort -u)
if [[ -n $leaks ]]; then
  echo "PRIVATE/TAILSCALE IP left (file:line) — add the network to the map:"; echo "$leaks"; fail=1
fi
if grep -rnIoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$STAGE" \
     | grep -vE '@([a-z0-9.-]+\.)?(invalid|example\.(com|org|net)|users\.noreply\.github\.com|anthropic\.com|openssh\.com)$' \
     | grep -q .; then
  echo "E-MAIL left:"
  grep -rnIoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$STAGE" \
    | grep -vE '@([a-z0-9.-]+\.)?(invalid|example\.(com|org|net)|users\.noreply\.github\.com|anthropic\.com|openssh\.com)$' \
    | sed "s|$STAGE/||" | cut -d: -f1,2
  fail=1
fi
gitleaks detect --no-git --source "$STAGE" --redact --no-banner -v || fail=1

(( fail == 0 )) || die "verification failed — nothing copied to $OUT"

# 6. Sync into the public checkout (its .git and LICENSE stay)
find "$OUT" -mindepth 1 -maxdepth 1 ! -name .git ! -name LICENSE -exec rm -rf -- {} +
cp -a "$STAGE"/. "$OUT"/
echo
echo "OK — review before committing:"
git -C "$OUT" status --short
echo "Next: cd $OUT && git diff && git add -A && git commit && git push"
