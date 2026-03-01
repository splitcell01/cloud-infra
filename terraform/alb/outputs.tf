output "alb_dns_name" {
  description = "DNS name of the ALB — point your Route53 record here"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  value = aws_lb.main.zone_id
}

output "alb_arn" {
  value = aws_lb.main.arn
}