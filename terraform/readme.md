# Cloud Infrastructure – AWS + k3s + GitOps

This repository contains the cloud-based evolution of my on-prem homelab infrastructure.

It provisions AWS networking and compute resources using Terraform and deploys Kubernetes workloads through a GitOps workflow (ArgoCD + declarative manifests).

---

## Architecture Overview

The infrastructure is split into three Terraform stages:

### 1. bootstrap/
- S3 bucket for remote Terraform state
- DynamoDB table for state locking

### 2. network/
- VPC
- Public & private subnets
- Internet gateway
- Route tables

### 3. compute-k3s/
- EC2 instance (Ubuntu 24.04)
- Security groups
- IAM role + SSM access
- k3s Kubernetes node

Remote state is stored in S3 with DynamoDB locking to ensure safe concurrent operations.

---

## GitOps Layout

Kubernetes workloads are organized under:

```
terraform/cloud-gitops/clusters/k3s-dev/apps/
```

Example applications:
- whoami
- secure-messenger
- observability
- ingress

These are applied via ArgoCD for declarative deployment.

---

## Migration Context

This repository represents the cloud evolution of my local homelab environment.

- Local version: Bare metal / k3s homelab
- Cloud version: AWS-hosted k3s node + GitOps-managed workloads

The goal is full infrastructure reproducibility using:
- Infrastructure as Code (Terraform)
- Declarative Kubernetes manifests
- Remote state management
- GitOps deployment patterns

---

## Deployment Order

To provision from scratch:

```bash
cd terraform/bootstrap
terraform init
terraform apply

cd ../network
terraform init
terraform apply

cd ../compute-k3s
terraform init
terraform apply
```

After compute is provisioned:

- Install k3s (via user_data or manually)
- Deploy ArgoCD
- Sync applications from cloud-gitops/

---

## Security

- No secrets are committed to this repository
- Terraform state is stored remotely in S3
- IAM roles are used instead of static credentials
- SSH access managed via AWS key pairs

---

## Future Improvements

- Multi-node HA k3s cluster
- CI pipeline for Terraform validation
- Module abstraction for reusable network layer
- Migration to managed Kubernetes (EKS) comparison

---

## Engineering Goals

This project demonstrates:

- Designing reproducible AWS infrastructure using Terraform modules
- Implementing remote state storage with S3 + DynamoDB locking
- Building a minimal Kubernetes environment on raw EC2 (k3s)
- Applying GitOps principles for declarative workload management
- Migrating from a local homelab to a cloud-hosted environment

---

## High-Level Architecture

```
User -> Internet -> AWS VPC
                    |-> Public Subnet -> k3s Node (EC2)
                    |-> Private Subnet (future expansion)

Terraform -> S3 Remote State
Terraform -> DynamoDB Lock Table
ArgoCD -> Syncs manifests from Git
```