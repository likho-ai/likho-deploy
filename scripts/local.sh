#!/bin/sh
# The local cluster, start to finish (the same as local.ps1, for a Unix shell):
#   scripts/local.sh up | run | status | down | destroy
set -eu
cd "$(dirname "$0")/.."
command=${1:-up}
cpus=${LIKHO_MINIKUBE_CPUS:-4}
memory=${LIKHO_MINIKUBE_MEMORY:-5120}

ensure_cluster() {
  if [ "$(minikube status --format '{{.Host}}' 2>/dev/null || true)" != "Running" ]; then
    echo "Starting minikube ($cpus cpus, $memory MB)..."
    minikube start --driver=docker --container-runtime=docker --cpus="$cpus" --memory="$memory" --addons=storage-provisioner --addons=default-storageclass
  fi
  kubectl config use-context minikube >/dev/null
}

ensure_stack() {
  uv run python scripts/secrets.py staging --namespace likho --allow-placeholders
  helm upgrade --install likho-stack charts/likho-stack --namespace likho -f environments/local/stack.yaml --wait --timeout 10m
  uv run python scripts/render.py local
}

case "$command" in
  up)
    ensure_cluster
    ensure_stack
    skaffold dev --port-forward
    ;;
  run)
    ensure_cluster
    ensure_stack
    skaffold run
    echo "Reach it with: kubectl -n likho port-forward svc/likho-gateway 8080:80"
    ;;
  status)
    minikube status
    kubectl -n likho get pods,pvc
    ;;
  down) skaffold delete; helm uninstall likho-stack --namespace likho ;;
  destroy) minikube delete ;;
  *) echo "usage: $0 up|run|status|down|destroy"; exit 2 ;;
esac
