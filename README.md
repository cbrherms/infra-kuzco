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
6. Check Doco-CD logs and Arcane login, then run `just llama-model-download`
   and verify GPU access and llama-swap's API from a network client.

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
| `just llama-model-download` | Download and verify the configured Unsloth GGUF on the host |
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

`just llmfit` opens a temporary GPU-enabled llmfit container over SSH without
starting its web dashboard. Its settings and downloads are not persisted, and
fit and throughput figures are estimates; verify model placement and
performance on Kuzco.

llama-swap starts llama.cpp's `llama-server` on demand. Its initial
`qwen3.8-27b` model uses Unsloth's independently quantized Q4_K_M GGUF at
32K context with q8_0 KV cache and one parallel slot. This first setup is
text-only, without the vision projector or speculative decoding. The model
configuration is in Git; `just llama-model-download` downloads the pinned
revision into `/srv/models/llama-swap` and verifies its SHA-256 before use. An
interrupted download can be resumed by rerunning the command.

llama-swap unloads its model after 10 minutes idle.
The pinned `unified-cuda-276` image contains llama-swap v275 and llama.cpp
commit `8bf97934eb2a53e239084a9af1d89ef28840775d`; the image tag is not
proof that all bundled components have the same release number.

The llama-swap API key is in the SOPS-encrypted service environment file.
Use `sops --decrypt docker/llama-swap/secrets.enc.env` locally to retrieve it
for an authorized client; do not share the output. Doco-CD decrypts it on
deployment. The key protects the API and UI but is not a substitute for
network restrictions. The route uses the existing Traefik HTTPS configuration;
check firewall and DNS access before connecting the cluster. The generic
`just deploy-compose` recipe does not decrypt SOPS files or copy bind-mounted
configuration to the remote host; use Doco-CD for this stack.

For initial bring-up, apply the storage role and run
`just llama-model-download`. Doco-CD polls `main`; the service is not deployed
from uncommitted local changes. Check its logs, authenticated model listing
and a real request before connecting LiteLLM or wol-proxy.

Arcane has direct Docker socket access, effectively host-administrator access.
Its direct HTTP port is not protected by Traefik's TLS.

## GPU unlock

Provisioning builds and installs the pinned gpu-unlock DKMS and firmware
packages and enables it for supported GPUs at boot. It requires Ubuntu 26.04,
Dracut and disabled Secure Boot. Reboot manually after boot configuration
changes, then check `journalctl -k -b | grep gpu_unlock` and confirm each GPU
was unlocked. Keep console recovery available for boot changes.

Set `gpu_unlock_enabled: false` in Ansible variables and run `just provision`
to remove the managed boot option; reboot to disable the unlock.

## Storage and secrets

Docker named volumes on the OS disk store persistent data:

| Volume | Data |
|---|---|
| `kuzco-traefik-acme` | Traefik certificates and ACME account |
| `kuzco-arcane-data` | Arcane database and application data |

Arcane also mounts `/opt/docker` for projects. Do not remove volumes if their
data is needed. A manual backup and restore procedure for the volumes and
encryption keys remains to be defined and tested.

The storage role keeps the ext4 root LV at least 100 GiB, and creates a
500 GiB ext4 model LV mounted at `/srv/models`. llama-swap bind-mounts
`/srv/models/llama-swap` read-only; the admin user can manage files there.
The filesystem's default ext4 reserved blocks reduce space available to
non-root users below the LV's nominal size.
The role checks existing devices and refuses to format an existing model LV
without an ext4 filesystem or hide files under an occupied mountpoint.

Change `root_volume_size` or `models_volume_size` in Ansible variables to
grow either LV and its filesystem on a later provisioning run; the role never
shrinks them. Review capacity and backups before resizing. Preview with
`just provision --check --tags storage`; apply only that role with
`just provision --tags storage`. A normal `just provision` also applies the
storage role. It does not resize partitions or physical volumes, enforce a
free-space reserve, or provide backups.

Secrets use SOPS + age. Doco-CD decrypts encrypted files at deployment time;
use `*.enc.<ext>` for files covered by `.sops.yaml`. The age private key stays
on the workstation and at `/etc/doco-cd/age.key` on the host (root, `0400`).
Doco-CD waits for the key before starting.

`just age-init` creates a key if missing and rewrites `.sops.yaml`; avoid it
unless intentionally changing recipients. After changing recipients, run
`sops updatekeys` on each encrypted file.

## Updates

Doco-CD polls `main` every 120 seconds. Use `just provision` to apply host
configuration from the local checkout.
