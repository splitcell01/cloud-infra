output "instance_id" {
  value = aws_instance.k3s.id
}

output "public_ip" {
  value = aws_instance.k3s.public_ip
}

output "k3s_sg_id" {
  description = "Security group ID of the k3s node"
  value       = aws_security_group.k3s.id
}