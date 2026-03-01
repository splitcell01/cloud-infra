#!/usr/bin/env bash
set -euo pipefail

echo "Nodes:"
kubectl get nodes -o wide

ready_count="$(kubectl get nodes --no-headers | awk '$2=="Ready"{c++} END{print c+0}')"
if [[ "$ready_count" -lt 3 ]]; then
  echo "FAIL: expected 3 Ready nodes, got ${ready_count}"
  exit 1
fi

echo "ArgoCD:"
kubectl -n argocd get deploy argocd-server
kubectl -n argocd get pods

echo "Traefik (k3s default):"
kubectl -n kube-system get deploy traefik || true

echo "OK: cluster contract passed"