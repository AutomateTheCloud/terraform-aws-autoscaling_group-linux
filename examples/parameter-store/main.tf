# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# An Amazon Linux 2023 instance that loads its application's configuration and secrets from
# AWS Systems Manager Parameter Store at boot: everything under one path for its environment
# and one shared by every environment, with the secrets encrypted by their own KMS key.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_id" {
  description = "ID of the VPC to launch the instance in"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of private subnets for the instance, with outbound internet access through a NAT gateway"
  type        = list(string)
}

data "aws_region" "current" {}

locals {
  # One path per environment, and one for values every environment shares, named after the
  # details abbreviations: /secrets/<scope>/<purpose>/<environment or global>.
  parameter_paths = {
    environment = "/secrets/example/parameter_store/development"
    global      = "/secrets/example/parameter_store/global"
  }
}

##-----------------------------------------------------------------------------
# The key for the secrets. Its default key policy lets IAM policies in the account grant
# its use, which the module does for the instances' role.
resource "aws_kms_key" "parameters" {
  description             = "Parameter Store secrets of example-parameter-store"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "parameters" {
  name          = "alias/example-parameter-store"
  target_key_id = aws_kms_key.parameters.key_id
}

# A secret. Terraform creates it with a placeholder and never changes its value again, so the
# real value is set outside Terraform and is never in the state:
#   aws ssm put-parameter --overwrite --type SecureString --name <name> --value '<secret>'
resource "aws_ssm_parameter" "database_password" {
  name   = "${local.parameter_paths.environment}/database/password"
  type   = "SecureString"
  key_id = aws_kms_key.parameters.arn
  value  = "change-me"

  lifecycle {
    ignore_changes = [value]
  }
}

# Configuration that is not secret.
resource "aws_ssm_parameter" "database_host" {
  name  = "${local.parameter_paths.environment}/database/host"
  type  = "String"
  value = "database.example.internal"
}

resource "aws_ssm_parameter" "support_email" {
  name  = "${local.parameter_paths.global}/support_email"
  type  = "String"
  value = "support@example.com"
}

##-----------------------------------------------------------------------------
module "instances" {
  source = "../../"

  details = {
    scope       = "Example"
    purpose     = "Parameter Store"
    environment = "Development"
  }

  os             = "al2023"
  instance_types = [{ type = "t3.micro" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids

  # Read everything under both paths, and decrypt the secrets with their key. The paths are
  # taken from the parameters, so the instance launches only after they exist. (A depends_on
  # on the module call would instead make Terraform read the module's data sources at apply
  # time, and plan to replace its resources whenever a parameter changes.)
  parameter_store = {
    paths = distinct([
      for p in [aws_ssm_parameter.database_password, aws_ssm_parameter.database_host, aws_ssm_parameter.support_email] :
      regex("^/secrets/[^/]+/[^/]+/[^/]+", p.name)
    ])
    kms_key_arns = [aws_kms_key.parameters.arn]
  }

  # At boot, write every parameter under both paths to a file only root can read, one
  # NAME=value line each, named after the parameter's path below the top one, such as
  # DATABASE_PASSWORD. The values are never printed to the boot log.
  user_data_scripts = [<<-EOT
    #!/bin/bash
    set -euo pipefail
    install -d -m 700 /etc/example-app
    umask 077
    : > /etc/example-app/config.env
    for path in ${join(" ", values(local.parameter_paths))}; do
      aws ssm get-parameters-by-path --region ${data.aws_region.current.region} \
        --path "$path" --recursive --with-decryption \
        --query 'Parameters[].[Name,Value]' --output text |
      while IFS=$'\t' read -r name value; do
        key=$(echo "$${name#"$path"/}" | tr '/a-z-' '_A-Z_')
        printf '%s=%q\n' "$key" "$value" >> /etc/example-app/config.env
      done
    done
    echo "Loaded $(wc -l < /etc/example-app/config.env) parameters into /etc/example-app/config.env"
  EOT
  ]
}

output "auto_scaling_group" {
  description = "The Auto Scaling group's name, to find the instance"
  value       = module.instances.metadata.auto_scaling_group.name
}

output "database_password_parameter" {
  description = "The parameter to put the real database password in"
  value       = aws_ssm_parameter.database_password.name
}
