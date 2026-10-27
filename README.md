# infra-kuzco

My notes and config for a single-node Ubuntu 26.04 AI host (`kuzco`) with an OCuLink eGPU.
Ansible handles the host; Doco-CD watches this repo for Compose changes.

## Repo map

| Path | Notes |
|---|---|
| `ansible/` | Host provisioning |
| `docker/` | Service Compose definitions and Dockerfiles |
| `bootstrap.sh`, `systemd/`, `.doco-cd.yaml` | Host setup and Doco-CD deployment |
| `scripts/`, `.mise.toml`, `justfile` | Workstation tools and commands |

## First bring-up

Before starting: Ubuntu 26.04 is installed, the eGPU is connected, and `KUZCO_USER` can SSH in with
passwordless sudo.

From the workstation, in this repo:

```sh
git clone https://github.com/cbrherms/infra-kuzco.git && cd infra-kuzco
mise install                 # just, ansible, docker CLI, age, sops, linters, etc.
just hooks                   # pre-commit lint + SOPS-encryption check
```

1. Create and set local connection and admin override values in `.mise.local.toml`. Set `ANSIBLE_ADMIN_SSH_KEY` to desired public key; SSH key auth is required. `DOCKER_HOST` also needs copying over due to variable rendering order.
2. Run `just age-init` once and keep a backup of `$SOPS_AGE_KEY_FILE` in 1Password.
3. Create secrets locally and encrypt with `just encrypt` before pushing, e.g. `docker/open-webui/secrets.enc.env` with `WEBUI_SECRET_KEY`.
4. Push `.sops.yaml` and encrypted secrets before bootstrapping; Doco-CD reads them from GitHub.
5. `just bootstrap` prepares Python on the endpoint, then prompts for the SSH password during initial provisioning. Ansible installs the configured key and disables SSH password login. Later runs use `just provision` without `--ask-pass`. `just secrets` installs the age key and starts Doco-CD.
6. If bootstrap reports a pending reboot, reboot before checking the GPU with `just gpu-info`.

| Command | Action |
|---|---|
| `just bootstrap` | Run `bootstrap.sh` and perform initial provisioning over SSH |
| `just provision` | `ansible-playbook ansible/site.yaml` from the workstation |
| `just deploy` | Restart Doco-CD manually; normally its poll is enough |
| `just deploy-compose ollama` | Deploy one stack directly over `DOCKER_HOST=ssh://...` |
| `just update` | `git pull`, then apply Ansible configuration from the workstation |
| `just logs` | Follow Doco-CD logs from journald |
| `just gpu-info` | `nvidia-smi` on the endpoint |
| `just age-init` | Create the age key and `.sops.yaml` |
| `just secret-edit <file>` | Edit an existing SOPS-encrypted file |
| `just encrypt` | Encrypt any plaintext `*.enc.*` file in place (run before committing) |
| `just lint` | yamllint, shellcheck, ansible-lint, compose config, SOPS check |
| `just hooks` | Install the pre-commit hook (runs the same checks) |
| `just secrets` | Copy the age key to the endpoint and restart Doco-CD |

## Services

| Service | Port | Notes |
|---|---|---|
| ollama | 11434 | LLM server and model manager (`docker exec ollama ollama pull qwen2.5-coder:14b`) |
| traefik | 80, 443 | HTTPS reverse proxy for Open WebUI, ComfyUI, and Arcane |
| open-webui | 3000, 443 | Chat front end at `https://open-webui.lan.${SECRET_DOMAIN}` |
| comfyui | 8188, 443 | Built from `docker/comfyui/Dockerfile`; `https://comfyui.lan.${SECRET_DOMAIN}` |
| arcane | 3552, 443 | Docker manager at `https://arcane.lan.${SECRET_DOMAIN}` |
| litellm | 443 | OpenAI-compatible API and usage dashboard at `https://litellm.lan.${SECRET_DOMAIN}`; backed by PostgreSQL |
| whisper | 10300 | Wyoming faster-whisper STT (GPU) for Home Assistant |
| piper | 10200 | Wyoming TTS (CPU) for Home Assistant |

For the 12 GB Nvidia card, Ollama is limited to one loaded model and unloads it after 10 minutes idle.
LiteLLM is the OpenAI-compatible gateway in front of Ollama (model alias `local-coder`; keys and spend logs in
PostgreSQL) and is reachable only through Traefik. Continue and other OpenAI-compatible clients should use
`https://litellm.lan.${SECRET_DOMAIN}/v1` with a LiteLLM virtual key. Home Assistant still uses its Ollama
integration at `http://kuzco:11434`, plus the Wyoming integrations on ports `10300` and `10200` - for now.

Model data is under `/srv/ai/` on the host, which is a dedicated NVMe mounted by the `storage` role (ext4, label `ai-data`, mounted by label; the role only formats a blank disk). New services need a `docker/<name>/docker-compose.yaml` and an
entry in `.doco-cd.yaml`.

## Secrets

Keep secrets in the repo, but encrypted with SOPS + age. Doco-CD decrypts SOPS files in its checkout at deploy
time (env, YAML, JSON, and text/binary files). Use `*.enc.<ext>` so `.sops.yaml` matches them.

```sh
# Create docker/open-webui/secrets.enc.env locally with WEBUI_SECRET_KEY=<random value>
just encrypt
just secret-edit docker/open-webui/secrets.enc.env   # later edits
```

The age private key stays on the workstation (`$SOPS_AGE_KEY_FILE`, backed up in 1Password) and the endpoint at
`/etc/doco-cd/age.key` (root, `0400`). Doco-CD waits for that file before starting. After changing recipients,
run `sops updatekeys` on each encrypted file.

## Updates

- Doco-CD polls `main` every 120 seconds for Compose changes; no manual redeploy is normally needed.
- Host changes: `just update` pulls and provisions, while `just provision` applies the current local checkout.
