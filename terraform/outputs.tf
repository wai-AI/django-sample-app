output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "The URL of the ECR repository"
}

output "app_url" {
  value       = "http://${aws_alb.app.dns_name}"
  description = "The URL of the application"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.app.name
  description = "The name of the ECS cluster"
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.app.arn
  description = "The ARN of the ECS task definition"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "The IDs of the public subnets"
}

output "ecs_security_group_id" {
  value       = aws_security_group.ecs.id
  description = "The ID of the ECS security group"
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "target_group_arn" {
  value       = aws_lb_target_group.app.arn
  description = "The ARN of the ECS target group"
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.app.name
  description = "The name of the CloudWatch log group"
}
