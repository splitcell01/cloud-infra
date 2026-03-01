# terraform/alb/main.tf
# Provisions an Application Load Balancer in the public subnets,
# with an HTTPS listener that forwards to the k3s NodePort for secure-messenger.
# HTTP redirects to HTTPS.

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket  = "cole-tf-state-us-east-1"
    key     = "network/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket  = "cole-tf-state-us-east-1"
    key     = "compute-k3s/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

locals {
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
  k3s_instance_id   = data.terraform_remote_state.compute.outputs.instance_id
  k3s_sg_id         = data.terraform_remote_state.compute.outputs.k3s_sg_id
}

# ── Security group: ALB (public internet → ALB) ──────────────────────────────

resource "aws_security_group" "alb" {
  name        = "cole-alb-sg"
  description = "ALB: allow HTTP/HTTPS from internet"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "cole-alb-sg" }
}

# Allow ALB to reach the k3s NodePort (30080) on the EC2 instance.
# We add a rule to the existing k3s SG rather than hardcoding the SG ID here.
resource "aws_security_group_rule" "k3s_nodeport_from_alb" {
  description              = "ALB to k3s NodePort 30080"
  type                     = "ingress"
  security_group_id        = local.k3s_sg_id
  from_port                = 30080
  to_port                  = 30080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
}

# ── ALB ───────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "cole-k3s-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  tags = { Name = "cole-k3s-alb" }
}

# ── Target group pointing at the k3s NodePort ─────────────────────────────────

resource "aws_lb_target_group" "secure_messenger" {
  name        = "cole-sm-tg"
  port        = 30080 # k3s NodePort for secure-messenger
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    port                = "30080"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "cole-sm-tg" }
}

resource "aws_lb_target_group_attachment" "k3s" {
  target_group_arn = aws_lb_target_group.secure_messenger.arn
  target_id        = local.k3s_instance_id
  port             = 30080
}

# ── Listeners ─────────────────────────────────────────────────────────────────

# HTTP → HTTPS redirect
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# HTTPS → secure-messenger target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.secure_messenger.arn
  }
}
