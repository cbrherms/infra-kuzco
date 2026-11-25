# infra-kuzco

Configuration for the Kuzco Ubuntu 26.04 AI host with two NVIDIA GPUs.
Ansible provisions the host; Doco-CD deploys Compose stacks from Git.
The v2 configuration has not yet been tested on the new host.

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
   up. Arcane and Traefik secrets are encrypted in the repo.
4. Run `just bootstrap`, then `just secrets` to deliver the age key and start
   Doco-CD. Bootstrap uses SSH and sudo to install Python and runs Ansible
   with `--ask-pass`.
5. Reboot if required, then run `just gpu-info` and check the persistence
   daemon. The GPU role does not fail if the daemon fails to start or restart.
6. Check Doco-CD logs and Arcane login, then pull models and verify GPU access
   and Ollama's API from a network client.

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
| `just secret-edit <file>` | Edit a SOPS-encrypted file |
| `just encrypt` | Encrypt plaintext `*.enc.*` files |
| `just lint` | Run the pre-commit checks |
| `just hooks` | Install the pre-commit hook |

## Services

| Service | Access | Notes |
|---|---|---|
| Ollama | HTTP port 11434; `https://ollama.lan.${SECRET_DOMAIN}` | Model management and inference |
| Traefik | Ports 80 and 443 | HTTPS proxy with a Cloudflare DNS challenge |
| Arcane | HTTP port 3552; `https://arcane.lan.${SECRET_DOMAIN}` | Docker GUI; persistent Compose configuration stays in Git |

Ollama exposes both its native API (`/api`) and an OpenAI-compatible subset
(`/v1`). Both routes are unauthenticated and unrestricted by this configuration;
an OpenAI client API key is ignored. Anyone who can reach them can use the API,
including model-management operations.

Ollama has access to both GPUs and chooses model placement. Inference settings
use Ollama defaults, cloud features are disabled, and models are pulled
manually.

Arcane has direct Docker socket access, effectively host-administrator access.
Its direct HTTP port is not protected by Traefik's TLS.

## Storage and secrets

Docker named volumes on the OS disk store persistent data:

| Volume | Data |
|---|---|
| `kuzco-ollama-data` | Ollama models and state |
| `kuzco-traefik-acme` | Traefik certificates and ACME account |
| `kuzco-arcane-data` | Arcane database and application data |

Arcane also mounts `/opt/docker` for projects. Do not remove volumes if their
data is needed. A manual backup and restore procedure for the volumes and
encryption keys remains to be defined and tested.

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
