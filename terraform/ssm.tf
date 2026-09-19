#############################################################################
# Automatic configuration through SSM State Manager
#############################################################################

variable "deployment_commit" {
  description = "Git commit available on GitHub, used for both playbooks and application code"
  type        = string
  default     = "f6621e422be5a32b9b1f1f8211011d944be07d08"

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.deployment_commit))
    error_message = "Use a full 40-character Git commit SHA already pushed to GitHub."
  }
}

variable "deployment_run" {
  description = "Change this value to explicitly rerun all deployment stages"
  type        = string
  default     = "1"
}

locals {
  deployment_repository = "https://github.com/wai-AI/django-sample-app.git"
  deployment_instances = {
    db    = aws_instance.db.id
    app_1 = aws_instance.app[0].id
    app_2 = aws_instance.app[1].id
  }
  deployment_vars = {
    aws_region                  = var.aws_region
    deployment_environment      = var.environment
    db_host                     = aws_instance.db.private_ip
    app_hostname                = aws_lb.app.dns_name
    app_repo                    = local.deployment_repository
    app_version                 = var.deployment_commit
    postgres_password_parameter = "/${var.project_name}/${var.environment}/postgres/password"
    django_secret_key_parameter = "/${var.project_name}/${var.environment}/django/secret-key"
    postgres_allowed_cidrs      = module.vpc.private_subnets_cidr_blocks
  }
  deployment_scripts = {
    for stage in ["db", "app_1", "app_2"] : stage => templatefile(
      "${path.module}/scripts/configure-instance.sh.tftpl",
      {
        stage          = stage
        repository_b64 = base64encode(local.deployment_repository)
        commit         = var.deployment_commit
        variables_b64 = base64encode(jsonencode(merge(local.deployment_vars, {
          run_migrations = stage == "app_1"
        })))
      }
    )
  }
}

# Waiting for EC2 creation is not enough: the SSM agent must be Online too.
# This local command only reads AWS status; configuration runs remotely via SSM.
resource "terraform_data" "ssm_ready" {
  triggers_replace = [local.deployment_instances, var.aws_region]

  provisioner "local-exec" {
    command     = "bash \"$SSM_WAIT_SCRIPT\""
    interpreter = ["/bin/bash", "-c"]
    environment = {
      SSM_WAIT_SCRIPT = abspath("${path.module}/scripts/wait-for-ssm.sh")
      SSM_REGION      = var.aws_region
      SSM_IDS         = join(",", values(local.deployment_instances))
      SSM_COUNT       = tostring(length(local.deployment_instances))
    }
  }

  depends_on = [
    module.vpc,
    aws_iam_role_policy_attachment.ssm_core,
    aws_vpc_security_group_egress_rule.app_egress,
    aws_vpc_security_group_egress_rule.db_egress
  ]
}

# Recreate associations on a deployment change so their creation waiters
# gate the next stage. Merely updating an association does not reliably wait
# for a new execution in AWS provider 5.100.
resource "terraform_data" "deployment_release" {
  input = sha256(jsonencode({
    instances = local.deployment_instances
    scripts   = local.deployment_scripts
    run       = var.deployment_run
  }))
}

resource "aws_ssm_association" "database" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${var.environment}-database"
  wait_for_success_timeout_seconds = 5400

  targets {
    key    = "InstanceIds"
    values = [aws_instance.db.id]
  }
  parameters = {
    commands         = local.deployment_scripts.db
    executionTimeout = "3600"
  }
  lifecycle {
    replace_triggered_by = [terraform_data.deployment_release]
  }
  depends_on = [terraform_data.ssm_ready]
}

resource "aws_ssm_association" "app_first" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${var.environment}-app-first"
  wait_for_success_timeout_seconds = 5400

  targets {
    key    = "InstanceIds"
    values = [aws_instance.app[0].id]
  }
  parameters = {
    commands         = local.deployment_scripts.app_1
    executionTimeout = "3600"
  }
  lifecycle {
    replace_triggered_by = [terraform_data.deployment_release]
  }
  depends_on = [aws_ssm_association.database]
}

resource "aws_ssm_association" "app_second" {
  name                             = "AWS-RunShellScript"
  association_name                 = "${var.project_name}-${var.environment}-app-second"
  wait_for_success_timeout_seconds = 5400

  targets {
    key    = "InstanceIds"
    values = [aws_instance.app[1].id]
  }
  parameters = {
    commands         = local.deployment_scripts.app_2
    executionTimeout = "3600"
  }
  lifecycle {
    replace_triggered_by = [terraform_data.deployment_release]
  }
  depends_on = [aws_ssm_association.app_first]
}

output "deployment_associations" {
  description = "SSM State Manager association IDs, in execution order"
  value = {
    database   = aws_ssm_association.database.association_id
    app_first  = aws_ssm_association.app_first.association_id
    app_second = aws_ssm_association.app_second.association_id
  }
}
