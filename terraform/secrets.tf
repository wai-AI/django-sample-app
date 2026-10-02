ephemeral "random_password" "django" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "django" {
  name                    = "week6/django-secret-key"
  description             = "Django SECRET_KEY"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "django" {
  secret_id                = aws_secretsmanager_secret.django.id
  secret_string_wo         = ephemeral.random_password.django.result
  secret_string_wo_version = 1
}