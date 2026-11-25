# infra-kuzco

Configuration for the Kuzco Ubuntu AI host. The v2 baseline is being prepared
before its first deployment; **do not provision or deploy this intermediate
state**. Operational documentation and validation are still being completed.

Ansible provisions the host and Doco-CD deploys the Ollama, Traefik and Arcane
Compose stacks. The obsolete separate-disk role and retired service
definitions have been removed; their history remains in Git. Open-WebUI and
LiteLLM are intended to run on Kubernetes.

Ollama, Traefik and Arcane use named volumes on the OS disk. Ollama exposes
both its direct HTTP API and an HTTPS route through Traefik. Follow the
completed v2 documentation after the remaining pre-deployment changes are
reviewed.
