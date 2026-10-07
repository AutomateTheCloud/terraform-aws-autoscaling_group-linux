# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Three Amazon Linux 2023 instances on an AMI you choose, replaced one at a time, with two
# always in service, when you change it.

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

variable "ami_id" {
  description = "The AMI to run: an Amazon Linux 2023 AMI for x86_64 in us-east-1, such as the one aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 returns"
  type        = string
}

module "instances" {
  source = "../../"

  details = {
    scope       = "Example"
    purpose     = "Pinned AMI"
    environment = "Development"
  }

  os             = "al2023"
  ami_id         = var.ami_id
  instance_types = [{ type = "t3.micro" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids

  # Keep the AMI's packages as they are, so every instance runs exactly the same software.
  update_packages = false

  auto_scaling_group = { min_size = 3, max_size = 4 }

  # Replace one instance at a time, keep at least two in service, and wait up to 10 minutes
  # for each new instance to report that its setup succeeded.
  rolling_update   = { max_batch_size = 1, min_instances_in_service = 2 }
  resource_signals = { timeout = "PT10M" }
}

output "auto_scaling_group" {
  description = "The Auto Scaling group's name"
  value       = module.instances.metadata.auto_scaling_group.name
}

output "stack" {
  description = "The CloudFormation stack whose events show each rolling update"
  value       = module.instances.metadata.cloudformation_stack.name
}
