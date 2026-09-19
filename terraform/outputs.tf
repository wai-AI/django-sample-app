#############################################################################
# Infrastructure outputs
#############################################################################

output "app_url" {
  description = "Application URL"
  value       = "http://${aws_lb.app.dns_name}"
}

output "app_instances" {
  description = "Application instance IDs and private IP addresses"

  value = {
    for index, instance in aws_instance.app :
    "app-${index + 1}" => {
      id         = instance.id
      private_ip = instance.private_ip
    }
  }
}

output "db_instance" {
  description = "Database instance ID and private IP address"

  value = {
    id         = aws_instance.db.id
    private_ip = aws_instance.db.private_ip
  }
}

#############################################################################
# Generated Ansible inventory
#############################################################################

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory.yml"
  file_permission = "0644"

  content = yamlencode({
    all = {
      vars = {
        deployment_environment = var.environment
        aws_region             = var.aws_region
        db_host                = aws_instance.db.private_ip
        app_hostname           = aws_lb.app.dns_name
      }

      children = {
        webservers = {
          hosts = {
            for index, instance in aws_instance.app :
            "app-${index + 1}" => {
              ansible_host = instance.private_ip
              instance_id  = instance.id
            }
          }
        }

        db = {
          hosts = {
            "db-1" = {
              ansible_host = aws_instance.db.private_ip
              instance_id  = aws_instance.db.id
            }
          }
        }
      }
    }
  })
}