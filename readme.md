# Cloud Infrastructure — AWS + k3s + GitOps

> A cloud-native evolution of an on-prem homelab. This repository provisions AWS infrastructure with Terraform and deploys Kubernetes workloads through a GitOps workflow (ArgoCD + declarative manifests).

---

## What This Is

This project migrates a physical homelab (x86 control-plane + ARM workers, Flannel CNI, local-path storage, Traefik ingress) into a reproducible, cloud-hosted platform. The physical network layer — router, managed switch, LAN subnets — is replaced entirely by AWS VPC primitives: subnets, route tables, security groups, NAT Gateway, and ALB.

The goal is a platform that demonstrates real operational depth, not just "infrastructure that exists."

---

## Architecture

```
Internet
    │
    ▼
ALB (public subnet)
    │
    ▼
Private Subnet
    │
  k3s Node (EC2, no public IP)
    │
  ArgoCD → syncs manifests from Git
    │
  Workloads (Kubernetes)
```

AWS networking replaces the on-prem layer:

| On-Prem Component | Cloud Equivalent |
|---|---|
| Physical router (192.168.0.1) | VPC + Internet Gateway |
| Managed switch / VLANs | Subnets (public + private) |
| Flannel CNI overlay | VPC routing + security groups |
| Traefik on bare metal | AWS Load Balancer Controller + ALB |
| Tailscale admin access | SSM Session Manager (no public IP needed) |
| local-path PVCs | EBS CSI Driver + dynamic provisioning |

---

## Terraform Stages

Infrastructure is split into three sequential stages:

### 1. `bootstrap/`
- S3 bucket for remote Terraform state
- DynamoDB table for state locking

### 2. `network/`
- VPC (`10.0.0.0/16`)
- Public subnet (ALB only)
- Private subnet (k3s nodes)
- Internet Gateway + NAT Gateway
- Route tables

### 3. `compute-k3s/`
- EC2 instance (Ubuntu 24.04, private subnet, no public IP)
- Security groups (ingress from ALB only, egress via NAT)
- IAM role + SSM instance profile
- k3s install via `user_data`
- ArgoCD bootstrap via `user_data` (auto-syncs `cloud-gitops/` on startup)

Remote state is stored in S3 with DynamoDB locking for safe concurrent operations.

---

## GitOps Layout

Workloads live under:

```
cloud-gitops/clusters/k3s-dev/apps/
├── ingress/          # AWS Load Balancer Controller + Ingress resources
├── observability/    # Prometheus, Grafana, Loki, Alertmanager
├── secure-messenger/ # Go + WebSocket real-time messaging app
└── whoami/           # Lightweight HTTP echo service (smoke test)
```

ArgoCD watches this directory and applies changes declaratively. One `terraform apply` → full cluster + applications running. No manual steps after provisioning.

---

## Deployment

Provision from scratch in order:

```bash
cd terraform/bootstrap && terraform init && terraform apply
cd ../network         && terraform init && terraform apply
cd ../compute-k3s     && terraform init && terraform apply
```

After `terraform apply` completes:
- k3s is installed and running (via `user_data`)
- ArgoCD is bootstrapped automatically
- Applications sync from `cloud-gitops/`

No SSH required. Access the node via SSM:

```bash
aws ssm start-session --target <instance-id>
```

---

## Storage

PVCs are backed by EBS volumes via the EBS CSI Driver. Storage is dynamically provisioned — no node-local binding.

```yaml
storageClassName: ebs-sc  # dynamic EBS provisioning
```

This replaces the on-prem `local-path` StorageClass, which tied PVCs to specific nodes and prevented rescheduling on node failure.

---

## Observability

Observability is treated as a platform primitive, not an afterthought.

The stack includes Prometheus, Grafana, Loki, and Alertmanager deployed via ArgoCD. At least one synthetic service is running with an associated alert rule that can be intentionally triggered to verify the full alerting pipeline end-to-end.

---

## Security

- Nodes have no public IP — accessed only via SSM
- ALB is the sole public ingress point
- IAM roles used instead of static credentials
- No secrets committed to this repository
- Terraform state stored remotely in S3 (not locally)

---

## Maturity Roadmap

Phases are ordered by impact, not complexity.

| Phase | Goal | Status |
|---|---|---|
| 1 | Move compute to private subnet, SSM access only | ✅ Done |
| 2 | Automate ArgoCD bootstrap via `user_data` | ✅ Done |
| 3 | EBS CSI Driver + dynamic PVC provisioning | ✅ Done |
| 4 | AWS Load Balancer Controller + ALB ingress | 🔄 In Progress |
| 5 | Observability first-class (Prometheus + alerts) | 🔄 In Progress |
| 6 | Multi-node: x86 control-plane + Graviton worker | 🗓 Planned |
| 7 | CI pipeline: `terraform fmt`, `validate`, `tflint` | 🗓 Planned |

---

## On-Prem Homelab (Migration Source)

The source environment this project migrates from:

| Component | Detail |
|---|---|
| Control-plane | Intel i5-4590, 32 GB DDR3, GTX 1060 |
| Workers | 2× Raspberry Pi (ARM64) |
| CNI | Flannel |
| Ingress | Traefik via k3s ServiceLB |
| Storage | local-path provisioner (node-bound PVCs) |
| Remote access | Tailscale (admin-only) |
| OS | Ubuntu 24.04 (server), Debian 12/13 (Pi workers) |

The cloud architecture replaces the physical network layer entirely. The mixed-arch scheduling patterns (x86 + ARM, nodeSelector/affinity) carry forward into Phase 6.

---

## What This Demonstrates

- Reproducible AWS infrastructure using staged Terraform modules
- Remote state management with S3 + DynamoDB locking
- Private compute with SSM access (no bastion, no public IP)
- GitOps deployment via ArgoCD with auto-sync
- Dynamic cloud-native storage (EBS CSI vs. local-path)
- Full observability stack with intentional alert testing
- Migration reasoning: mapping physical network primitives to AWS equivalents