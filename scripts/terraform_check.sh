#!/usr/bin/env bash
set -euo pipefail

STACKS=(network compute-k3s alb bootstrap)

for s in "${STACKS[@]}"; do
  echo "==> terraform/${s}"
  pushd "terraform/${s}" >/dev/null
  terraform fmt -check
  terraform init -backend=false >/dev/null
  terraform validate
  popd >/dev/null
done

echo "OK: fmt + validate passed for all stacks"