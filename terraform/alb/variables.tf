variable "acm_certificate_arn" {
  description = "ACM cert ARN for the ALB HTTPS listener"
  type        = string
}

variable "k3s_sg_id" {
  description = "Security group ID for the k3s nodes"
  type        = string
}