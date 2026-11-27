# infra-kuzco

Configuration for the Kuzco Ubuntu 26.04 AI host with two NVIDIA GPUs.
Ansible provisions the host; Doco-CD deploys Compose stacks from Git.
llama-swap provides on-demand inference using the host's GPUs.

## Repo map

| Path | Notes |
|---|---|
| `ansible/` | Host provisioning and age-key delivery |
| `docker/` | Service Compose definitions |
| `bootstrap.sh`, `systemd/`, `.doco-cd.yaml` | Host setup and Doco-CD deployment |
| `scripts/`, `.mise.toml`, `justfile` | Workstation tools and commands |

## First bring-up

Before starting: Ubuntu 26.04 is installed, and `KUZCO_USER` can SSH in with
passwordless sudo. SSH key authentication must work before provisioning:
Ansible installs the configured public key and disables SSH password login.

From the workstation, in this repo:

1. Run `mise install` and optionally `just hooks`. Mise installs Python 3.13
   for Ansible 15 on the workstation.
2. Set connection and admin values in `.mise.local.toml`, including
   `KUZCO_HOST`, `KUZCO_USER`, `ANSIBLE_ADMIN_USER` and
   `ANSIBLE_ADMIN_SSH_KEY`. Set the domain and ACME email variables. If using
   remote Docker recipes, set `DOCKER_HOST` too; the shared default can be
   rendered before local overrides.
3. Ensure the existing age key is available at `$SOPS_AGE_KEY_FILE` and backed
   up. Service secrets are encrypted in the repo.
4. Run `just bootstrap`, then `just secrets` to deliver the age key and start
   Doco-CD. Bootstrap uses SSH and sudo to install Python and runs Ansible
   with `--ask-pass`.
5. Reboot if required, then run `just gpu-info` and check the persistence
   daemon. The GPU role does not fail if the daemon fails to start or restart.
6. Check Doco-CD logs and Arcane login, download the model as described below,
   then verify GPU access and llama-swap's API from a network client.

| Command | Action |
|---|---|
| `just bootstrap` | Install Python and run initial Ansible provisioning |
| `just provision` | Apply Ansible configuration from the local checkout |
| `just secrets` | Deliver the age key and start Doco-CD |
| `just deploy` | Restart Doco-CD for an immediate resync |
| `just deploy-compose <service>` | Deploy one stack directly over the configured Docker host, bypassing Doco-CD |
| `just update` | Pull changes locally and provision the host |
| `just logs` | Follow Doco-CD logs |
| `just gpu-info` | Run `nvidia-smi` on the host |
| `just llmfit` | Browse model fit estimates in a temporary container on the host |
| `just hf-download <repo> <filename>` | Download a Hugging Face file to Kuzco |
| `just secret-edit <file>` | Edit a SOPS-encrypted file |
| `just encrypt` | Encrypt plaintext `*.enc.*` files |
| `just lint` | Run the pre-commit checks |
| `just hooks` | Install the pre-commit hook |

## Services

| Service | Access | Notes |
|---|---|---|
| llama-swap | `https://llama-swap-kuzco.lan.${SECRET_DOMAIN}` | API-key-protected inference; no direct published HTTP port |
| Traefik | Ports 80 and 443 | HTTPS proxy with a Cloudflare DNS challenge |
| Arcane | HTTP port 3552; `https://arcane-kuzco.lan.${SECRET_DOMAIN}` | Docker GUI; persistent Compose configuration stays in Git |

- llama-swap model settings live in `docker/llama-swap/config.yaml`; the
  initial model is text-only.
- `qwen3.8-27b` uses experimental tensor splitting; select
  `qwen3.8-27b-safe` for layer splitting. Switching is manual, not automatic
  failover.
- `qwen3.8-27b-xl` is an optional tensor-split Q4_K_XL test model.
- `just llmfit` uses a temporary container: settings and downloads are not
  persisted, and fit estimates need verification.

## GPU unlock

gpu-unlock requires Ubuntu 26.04, Dracut and disabled Secure Boot. After
provisioning, reboot and check `journalctl -k -b | grep gpu_unlock`. To
disable it, set `gpu_unlock_enabled: false`, provision and reboot. Keep
console recovery available for boot changes.

## Storage and secrets

- Models live in `/srv/models/llama-swap`, on a separate ext4 LV mounted
  read-only in llama-swap. Change `root_volume_size` or `models_volume_size`
  to grow the LVs; preview with `just provision --check --tags storage`.
  The role does not shrink volumes or resize partitions.
- Traefik and Arcane use Docker volumes on the OS disk.
- Secrets use SOPS + age and are decrypted by Doco-CD.

To download the default model from the workstation:

```sh
just hf-download unsloth/Qwen3.8-27B-GGUF Qwen3.8-27B-UD-Q4_K_M.gguf \
  --revision 4af51b3542f775b0a8e4b310bfb3f17e01c306c9
```

Additional `hf download` options can be passed through. Ubuntu's package falls
back to HTTP downloads when `hf_xet` is unavailable; update it through the system package manager.

## Updates

Doco-CD polls `main` every 120 seconds. Use `just provision` to apply host
configuration from the local checkout.
