# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# One Amazon Linux 2023 instance, kept running by an Auto Scaling group, in private subnets
# you give. Nothing can connect to it from the network; open a shell with Session Manager.

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

module "instances" {
  source = "../../"

  details = {
    scope       = "Example"
    purpose     = "Basic"
    environment = "Development"
  }

  os             = "al2023"
  instance_types = [{ type = "t3.micro" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids
}

output "auto_scaling_group" {
  description = "The Auto Scaling group's name, to find the instance"
  value       = module.instances.metadata.auto_scaling_group.name
}
