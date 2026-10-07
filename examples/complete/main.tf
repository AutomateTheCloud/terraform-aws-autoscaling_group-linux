# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Two Ubuntu 24.04 web servers on AWS Graviton, behind an internal Application Load Balancer
# that anything in the VPC can reach, sharing an Amazon EFS file system that accepts only
# encrypted connections, and ready for AWS CodeDeploy deployments.

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
  description = "ID of the VPC to launch the instances in"
  type        = string
}

variable "subnet_ids" {
  description = "IDs of private subnets in two or more Availability Zones, with outbound internet access through a NAT gateway"
  type        = list(string)
}

locals {
  details = {
    scope       = "Example"
    purpose     = "Complete"
    environment = "Development"
  }
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_partition" "this" {}

##-----------------------------------------------------------------------------
# A shared file system, with a mount target in each subnet. Its policy refuses connections
# without TLS; the module mounts it with TLS. It also allows root access: the boot scripts run
# as root, and without ClientRootAccess EFS treats root as an anonymous user, who cannot write
# to the file system's top directory.
resource "aws_efs_file_system" "shared" {
  encrypted = true
  tags      = { Name = "example-complete-shared" }
}

resource "aws_security_group" "efs" {
  name_prefix = "example-complete-efs-"
  description = "EFS mount targets of example-complete"
  vpc_id      = var.vpc_id
}

resource "aws_efs_mount_target" "shared" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_file_system_policy" "shared" {
  file_system_id = aws_efs_file_system.shared.id

  # The instances mount the file system once this policy exists, through its mount targets.
  depends_on = [aws_efs_mount_target.shared]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowMountAsRoot"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"]
        Resource  = aws_efs_file_system.shared.arn
        Condition = { Bool = { "elasticfilesystem:AccessedViaMountTarget" = "true" } }
      },
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "*"
        Resource  = aws_efs_file_system.shared.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

##-----------------------------------------------------------------------------
# A CodeDeploy application and the role CodeDeploy uses. A deployment group for an Auto
# Scaling group with a launch template also needs to launch and tag instances with the
# instances' role.
resource "aws_codedeploy_app" "web" {
  name             = "example-complete-web"
  compute_platform = "Server"
}

resource "aws_iam_role" "codedeploy" {
  name_prefix = "example-complete-codedeploy-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:${data.aws_partition.this.partition}:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role_policy" "codedeploy_launch_template" {
  name = "launch-template"
  role = aws_iam_role.codedeploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:CreateTags"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.instances.metadata.iam_role.arn
      },
    ]
  })
}

##-----------------------------------------------------------------------------
module "instances" {
  source = "../../"

  details = local.details

  os             = "ubuntu24"
  architecture   = "arm64"
  instance_types = [{ type = "t4g.small" }, { type = "t4g.medium" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids

  auto_scaling_group = {
    min_size = 2
    max_size = 4
  }
  rolling_update = {
    max_batch_size           = 1
    min_instances_in_service = 1
  }

  volumes = {
    root = { size_gb = 20 }
    data = { count = 1, size_gb = 10 }
  }

  # A web server on each instance, showing which instance answered and the shared file.
  user_data_scripts = [<<-EOT
    #!/bin/bash
    set -euo pipefail
    apt-get install -y nginx
    echo "Shared at $(date -u) by $(hostname)" >> /efs/shared.txt
    printf '<h1>%s</h1>\n<pre>%s</pre>\n' "$(hostname)" "$(cat /efs/shared.txt)" > /var/www/html/index.html
    systemctl enable --now nginx
  EOT
  ]

  # Taken from the policy, so the module waits for it and the mount targets. A depends_on on
  # the module call would instead make Terraform read the module's data sources at apply
  # time, and plan to replace its resources whenever the file system changes.
  efs_file_system = {
    id                = aws_efs_file_system_policy.shared.file_system_id
    security_group_id = aws_security_group.efs.id
  }

  load_balancer = {
    type       = "application"
    subnet_ids = var.subnet_ids
    security_group_ingress = {
      vpc = { from_port = 80, cidr_ipv4 = data.aws_vpc.this.cidr_block, description = "Anything in the VPC" }
    }
    target_groups = {
      web = { port = 80, protocol = "HTTP", deregistration_delay = 30, health_check = { path = "/" } }
    }
    listeners = {
      http = { port = 80, protocol = "HTTP", target_group = "web" }
    }
  }

  codedeploy = {
    application_name = aws_codedeploy_app.web.name
    service_role_arn = aws_iam_role.codedeploy.arn
    log_groups       = ["application"]
  }
}

output "url" {
  description = "The load balancer's address, reachable from inside the VPC"
  value       = "http://${module.instances.metadata.lb.dns_name}/"
}

output "auto_scaling_group" {
  description = "The Auto Scaling group's name"
  value       = module.instances.metadata.auto_scaling_group.name
}

output "codedeploy_deployment_group" {
  description = "The CodeDeploy deployment group to deploy to"
  value       = module.instances.metadata.codedeploy_deployment_group.deployment_group_name
}
