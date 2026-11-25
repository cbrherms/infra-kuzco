# infra-kuzco

Configuration for the Kuzco Ubuntu AI host. The v2 baseline is being prepared
before its first deployment; **do not provision or deploy this intermediate
state**. The retained service definitions still need to be adapted for v2.

Ansible provisions the host and Doco-CD deploys the Ollama, Traefik and Arcane
Compose stacks. The obsolete separate-disk role and retired service
definitions have been removed; their history remains in Git. Open-WebUI and
LiteLLM are intended to run on Kubernetes.

The remaining service definitions still use their previous host directories
and settings. Follow the completed v2 documentation after the remaining
pre-deployment changes are reviewed.
