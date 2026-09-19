#############################################################################
# Security groups
#############################################################################

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app"
  description = "Access to application instances"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb"
  description = "Access to application load balancer"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-${var.environment}-db"
  description = "Access to database instance"
  vpc_id      = module.vpc.vpc_id
}

#############################################################################
# Ingress rules
#############################################################################

resource "aws_vpc_security_group_ingress_rule" "alb_ingress" {
  description       = "Allow HTTP from the internet"
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
}

resource "aws_vpc_security_group_ingress_rule" "app_ingress" {
  description       = "Allow HTTP from ALB"
  security_group_id = aws_security_group.app.id

  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "db_ingress" {
  description       = "Allow PostgreSQL from application instances"
  security_group_id = aws_security_group.db.id

  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

#############################################################################
# Egress rules
#############################################################################

resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  description       = "Allow all outbound IPv4 traffic"
  security_group_id = aws_security_group.alb.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "app_egress" {
  description       = "Allow all outbound IPv4 traffic"
  security_group_id = aws_security_group.app.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "db_egress" {
  description       = "Allow all outbound IPv4 traffic"
  security_group_id = aws_security_group.db.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}