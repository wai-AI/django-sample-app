#############################################################################
# IAM role for EC2
#############################################################################

resource "aws_iam_role" "ec2_ssm" {
  name        = "${var.project_name}-${var.environment}-ec2-ssm"
  description = "Allows EC2 instances to use Systems Manager"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

#############################################################################
# SSM permissions
#############################################################################

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#############################################################################
# Instance profile for EC2
#############################################################################

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-${var.environment}-ec2-ssm"
  role = aws_iam_role.ec2_ssm.name
}