#!/usr/bin/env bash
# Fail if any *.enc.* file is not SOPS-encrypted. Content check, so no key is needed.
set -euo pipefail

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(git ls-files '*.enc.*')
fi

status=0
for file in "${files[@]}"; do
  if ! grep -q 'ENC\[' "$file" || ! grep -q 'sops' "$file"; then
    echo "not encrypted: $file (run: just encrypt)" >&2
    status=1
  fi
done
exit "$status"
