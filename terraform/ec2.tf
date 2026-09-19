#############################################################################
# Ubuntu AMI
#############################################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

#############################################################################
# Application instances
#############################################################################

resource "aws_instance" "app" {
  count = 2

  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id                   = module.vpc.private_subnets[count.index]
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    set -eu
    snap start --enable amazon-ssm-agent
  EOF

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-${count.index + 1}"
    Role = "app"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    aws_vpc_security_group_egress_rule.app_egress
  ]
}

#############################################################################
# DB instance
#############################################################################

resource "aws_instance" "db" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.db.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    set -eu
    snap start --enable amazon-ssm-agent
  EOF

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
    Role = "db"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm_core,
    aws_vpc_security_group_egress_rule.db_egress
  ]
}
