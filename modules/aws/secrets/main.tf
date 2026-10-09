# [Secrets] 

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_secretsmanager_secret" "this" {
  for_each    = var.secrets
  name        = "${var.name_prefix}/${each.key}"
  description = each.value
}
