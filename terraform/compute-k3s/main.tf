data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket         = "cole-tf-state-us-east-1"
    key            = "network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.network.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

# Latest Ubuntu 24.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group: no inbound at all (SSM doesn't need inbound rules)
resource "aws_security_group" "k3s" {
  name        = "cole-k3s-sg"
  description = "k3s node SG (no inbound; admin via SSM)"
  vpc_id      = local.vpc_id

  egress {
    description = "allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cole-k3s-sg"
  }
  # Allow nodes in this SG to talk to each other (cluster-only)
  ingress {
    description     = "kubernetes API (agents -> server)"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    self            = true
  }

  ingress {
    description     = "kubelet (metrics/exec)"
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    self            = true
  }

  ingress {
    description     = "flannel VXLAN (pod network across nodes)"
    from_port       = 8472
    to_port         = 8472
    protocol        = "udp"
    self            = true
  }

  # Optional: NodePorts if you ever use them internally (common for quick tests)
  ingress {
    description     = "k8s NodePort range (internal only)"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    self            = true
  }
}

# IAM role for SSM
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_role" {
  name               = "cole-k3s-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "cole-k3s-ec2-ssm-profile"
  role = aws_iam_role.ssm_role.name
}

# User data installs k3s and sets kubeconfig readable for ubuntu user
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    apt-get update
    apt-get install -y curl git

    # Install k3s (server)
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

    # Wait for k3s to be ready
    until kubectl get nodes 2>/dev/null | grep -q " Ready"; do
      echo "Waiting for k3s to be ready..."
      sleep 5
    done

    # Convenience: copy kubeconfig to ubuntu home
    mkdir -p /home/ubuntu/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube

    # Install ArgoCD
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    # Bootstrap the app-of-apps (points ArgoCD at your GitOps repo)
    kubectl apply -f - <<ARGOCD
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/splitcell01/cloud-infra
        targetRevision: HEAD
        path: terraform/cloud-gitops/clusters/k3s-dev/apps
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
    ARGOCD

    echo "Bootstrap complete"
  EOF
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "t3a.medium"
  subnet_id                   = local.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = false

  user_data = local.user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "cole-k3s-1"
  }
}
