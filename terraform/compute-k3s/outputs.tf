output "server_instance_id" {
  value = aws_instance.k3s_server.id
}

output "instance_ids" {
  value = concat([aws_instance.k3s_server.id], aws_instance.k3s_agent[*].id)
}

output "k3s_sg_id" {
  value = aws_security_group.k3s.id
}

output "server_private_ip" {
  value = aws_instance.k3s_server.private_ip
}