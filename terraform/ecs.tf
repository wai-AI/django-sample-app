resource "aws_ecs_cluster" "app" {
  name = "week6-cluster"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/week6-web"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "app" {
  family                   = "week6-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.app.repository_url}:v1"
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB", value = "postgres" },
        { name = "DB_NAME", value = "hc" },
        { name = "DB_USER", value = "hc" },
        { name = "DB_HOST", value = aws_db_instance.app.address },
        { name = "DB_PORT", value = "5432" },
        { name = "DB_SSLMODE", value = "require" },
        { name = "DEBUG", value = "False" },
        { name = "ALLOWED_HOSTS", value = aws_alb.app.dns_name },
        { name = "SITE_ROOT", value = "http://${aws_alb.app.dns_name}" }
      ]

      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_db_instance.app.master_user_secret[0].secret_arn}:password::"
        },
        {
          name      = "SECRET_KEY"
          valueFrom = aws_secretsmanager_secret.django.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name                              = "week6-web"
  cluster                           = aws_ecs_cluster.app.arn
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  platform_version                  = "1.4.0"
  enable_execute_command            = true
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "web"
    container_port   = 8000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets,
    aws_iam_role_policy.task_exec,
    aws_secretsmanager_secret_version.django,
    aws_vpc_security_group_ingress_rule.alb_http,
    aws_vpc_security_group_ingress_rule.ecs_from_alb,
    aws_vpc_security_group_ingress_rule.rds_from_ecs,
    aws_vpc_security_group_egress_rule.alb_to_ecs,
    aws_vpc_security_group_egress_rule.ecs_to_rds,
    aws_vpc_security_group_egress_rule.ecs_https
  ]
}