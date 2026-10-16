#!/usr/bin/env bash
# First-run setup on the endpoint. Run as root: just bootstrap
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3

if [[ -f /var/run/reboot-required ]]; then
  echo "NVIDIA driver installed: reboot required (sudo reboot)."
fi
