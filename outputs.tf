output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "instance_ids" {
  description = "IDs of EC2 instances"
  value       = aws_instance.app[*].id
}

output "instance_public_ips" {
  description = "Public IP addresses of EC2 instances"
  value       = aws_eip.app[*].public_ip
}

output "instance_private_ips" {
  description = "Private IP addresses of EC2 instances"
  value       = aws_instance.app[*].private_ip
}

output "security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.app.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.ec2_role.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = var.create_alb ? aws_lb.app[0].dns_name : "ALB not created"
}

output "application_urls" {
  description = "URLs to access the application"
  value = var.create_alb ? [
    "http://${aws_lb.app[0].dns_name}"
    ] : [
    for ip in aws_eip.app[*].public_ip : "http://${ip}"
  ]
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = [
    for i, ip in aws_eip.app[*].public_ip :
    "ssh -i ~/.ssh/${var.key_name != "" ? var.key_name : "${var.project_name}-${var.environment}-key"}.pem ubuntu@${ip}"
  ]
}