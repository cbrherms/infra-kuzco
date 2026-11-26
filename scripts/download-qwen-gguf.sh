#!/usr/bin/env bash
set -euo pipefail

model=Qwen3.8-27B-UD-Q4_K_M.gguf
revision=4af51b3542f775b0a8e4b310bfb3f17e01c306c9
checksum=1bce504dfecd84153666928a41d8a66706f0158d3a317bc5196b72819d7dc529
url="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/${revision}/${model}"
if ! mountpoint -q /srv/models; then
    echo "Model filesystem is not mounted at /srv/models" >&2
    exit 1
fi
cd /srv/models/llama-swap

if [[ -f "$model" ]]; then
    printf '%s  %s\n' "$checksum" "$model" | sha256sum --check
    exit
fi

curl --fail --location --retry 3 --continue-at - --output "${model}.part" "$url"
printf '%s  %s\n' "$checksum" "${model}.part" | sha256sum --check
mv "${model}.part" "$model"
