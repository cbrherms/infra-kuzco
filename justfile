set shell := ["bash", "-euo", "pipefail", "-c"]

host    := env("KUZCO_HOST", "kuzco.local")
user    := env("KUZCO_USER", "ubuntu")
ssh     := "ssh " + user + "@" + host

default:
    @just --list

# Run bootstrap.sh on the endpoint over SSH (first run only)
bootstrap:
    {{ssh}} 'sudo bash -s' < bootstrap.sh
    just provision --ask-pass

# Apply the Ansible playbook from this workstation
provision *args:
    ansible-galaxy collection install -r ansible/requirements.yml
    ansible-playbook ansible/site.yaml {{args}}

# Trigger an immediate Doco-CD resync on the endpoint
deploy:
    {{ssh}} 'sudo systemctl restart doco-cd.service'

# Deploy one service directly with docker compose over SSH (bypasses Doco-CD)
deploy-compose service:
    docker compose -f docker/{{service}}/docker-compose.yaml up -d --build

# Pull latest repo locally, then apply host configuration from the workstation
update:
    git pull --ff-only
    just provision

# Follow Doco-CD logs on the endpoint
logs:
    {{ssh}} 'journalctl -u doco-cd.service -f -n 100'

# Show GPU status on the endpoint
gpu-info:
    {{ssh}} 'nvidia-smi'

# Create the age key (once) and write .sops.yaml; back the key up in 1Password
age-init:
    mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"
    [ -f "$SOPS_AGE_KEY_FILE" ] || age-keygen -o "$SOPS_AGE_KEY_FILE"
    printf 'creation_rules:\n  - path_regex: \\.enc\\.[a-z]+$\n    age: %s\n' "$(age-keygen -y "$SOPS_AGE_KEY_FILE")" > .sops.yaml
    @echo "Public key written to .sops.yaml. Store $SOPS_AGE_KEY_FILE in 1Password."

[doc('Encrypt any unencrypted *.enc.* files in the repo')]
[script]
encrypt:
    find "{{ justfile_directory() }}" -type f -name "*.enc.*" -not -path "*/.git/*" | while read -r file; do
        if sops filestatus "$file" | jq --exit-status '.encrypted == false' >/dev/null 2>&1; then
            sops --encrypt --in-place "$file"
            echo "encrypted $file"
        fi
    done

# Run every lint check (yamllint, shellcheck, ansible-lint, compose config, SOPS encryption)
lint:
    ansible-galaxy collection install -r ansible/requirements.yml
    pre-commit run --all-files

# Install the git pre-commit hook
hooks:
    pre-commit install

# Create or edit an encrypted file, e.g. just secret-edit docker/open-webui/secrets.enc.env
secret-edit file:
    sops edit {{file}}

# Deliver the age key to the endpoint and restart Doco-CD
secrets:
    ansible-playbook ansible/secrets.yaml
