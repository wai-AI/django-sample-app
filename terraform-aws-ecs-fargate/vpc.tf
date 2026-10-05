module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name                 = "main"
  cidr                 = "10.0.0.0/16"
  azs                  = var.availability_zones
  enable_dns_support   = true
  enable_dns_hostnames = true

  # This module manages only the VPC; networking resources are defined below.
  create_igw                    = false
  enable_nat_gateway            = false
  manage_default_network_acl    = false
  manage_default_route_table    = false
  manage_default_security_group = false
}

resource "aws_internet_gateway" "main" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "week6-igw"
  }
}

# Public subnets and routes

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = cidrsubnet(module.vpc.vpc_cidr_block, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  # Fargate public IPs will be enabled explicitly in the ECS service.
  tags = {
    Name = "week6-public-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "week6-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets

resource "aws_subnet" "private" {
  count                   = length(var.availability_zones)
  vpc_id                  = module.vpc.vpc_id
  cidr_block              = cidrsubnet(module.vpc.vpc_cidr_block, 8, count.index + 10)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "week6-private-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "week6-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb" {
  name        = "week6-alb"
  description = "Allow inbound traffic to the ALB"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group" "ecs" {
  name        = "week6-ecs"
  description = "Allow inbound traffic to the ECS tasks"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group" "rds" {
  name        = "week6-rds"
  description = "Allow inbound traffic to the RDS instance"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
}

resource "aws_vpc_security_group_egress_rule" "ecs_to_rds" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}