# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# An Auto Scaling group that mixes On-Demand and Spot Instances of several instance types,
# for capacity that costs less and survives a shortage of any one type.

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

module "instances" {
  source = "../../"

  details = {
    scope       = "Example"
    purpose     = "Spot Instances"
    environment = "Development"
  }

  os         = "al2023"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # The types the group may launch. Each counts for its weight in the sizes below: a t3.small
  # has twice the memory of a t3.micro, so it counts as 2.
  instance_types = [
    { type = "t3.micro", weighted_capacity = 1 },
    { type = "t3a.micro", weighted_capacity = 1 },
    { type = "t3.small", weighted_capacity = 2 },
  ]

  auto_scaling_group = {
    # Sizes are in weight units: 4 units is four micro instances, two small ones, or a mix.
    min_size = 4
    max_size = 8
    # The first unit is always On-Demand, so something runs even when Spot capacity is gone;
    # everything above it is Spot.
    on_demand_base_capacity                  = 1
    on_demand_percentage_above_base_capacity = 0
    # Spot Instances from the pools with the lowest price among those least likely to be
    # interrupted.
    spot_allocation_strategy = "price-capacity-optimized"
  }
}

output "auto_scaling_group" {
  description = "The Auto Scaling group's name, to see which instances it launched"
  value       = module.instances.metadata.auto_scaling_group.name
}
