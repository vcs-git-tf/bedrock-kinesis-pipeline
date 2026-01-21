variable "secret_name" {
  description = "Name of the secret"
  type        = string
}

variable "secret_value" {
  description = "Value of the secret"
  type        = string
  sensitive   = true
}

resource "aws_secretsmanager_secret" "secret" {
  name = var.secret_name
}

resource "aws_secretsmanager_secret_version" "secret_version" {
  secret_id     = aws_secretsmanager_secret.secret.id
  secret_string = var.secret_value
}

output "secret_arn" {
  value = aws_secretsmanager_secret.secret.arn
}