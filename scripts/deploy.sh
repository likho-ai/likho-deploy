#!/bin/sh
# Rolls an environment out: both charts as Helm releases (the same as deploy.ps1, for a Unix shell).
#   scripts/deploy.sh staging [kube-context]
#   scripts/deploy.sh production [kube-context]
set -eu
cd "$(dirname "$0")/.."
env=${1:?usage: deploy.sh staging|production [kube-context]}
case "$env" in staging|production) ;; *) echo "usage: $0 staging|production [kube-context]"; exit 2 ;; esac
namespace="likho-$env"
set -- --namespace "$namespace" --wait --timeout 15m
if [ -n "${2:-}" ]; then set -- "$@" --kube-context "$2"; fi

helm upgrade --install likho-stack charts/likho-stack -f "environments/$env/stack.yaml" "$@"
helm upgrade --install likho charts/likho -f "environments/$env/env.yaml" -f "environments/$env/values.yaml" "$@"
helm list --namespace "$namespace"
