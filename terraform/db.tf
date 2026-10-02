resource "aws_db_subnet_group" "app" {
  name        = "week6-db-subnet-group"
  description = "Subnet group for the RDS instance"
  subnet_ids  = aws_subnet.private[*].id
}

resource "aws_db_instance" "app" {
  identifier                  = "week6-postgres"
  allocated_storage           = 20
  engine                      = "postgres"
  engine_version              = "17"
  instance_class              = "db.t4g.micro"
  db_name                     = "hc"
  username                    = "hc"
  manage_master_user_password = true
  storage_type                = "gp3"
  db_subnet_group_name        = aws_db_subnet_group.app.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  skip_final_snapshot         = true
  publicly_accessible         = false
  multi_az                    = false
  storage_encrypted           = true
  backup_retention_period     = 1
  deletion_protection         = false
}