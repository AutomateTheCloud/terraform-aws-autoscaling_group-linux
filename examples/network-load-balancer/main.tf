# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Two Ubuntu 24.04 web servers behind an internal Network Load Balancer, which passes TCP
# connections on port 80 to them. Anything in the VPC can connect.

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

data "aws_vpc" "this" {
  id = var.vpc_id
}

module "instances" {
  source = "../../"

  details = {
    scope       = "Example"
    purpose     = "Network Load Balancer"
    environment = "Development"
  }

  os             = "ubuntu24"
  instance_types = [{ type = "t3.micro" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids

  auto_scaling_group = { min_size = 2, max_size = 2 }

  # nginx answers on port 80 with the instance's name.
  user_data_scripts = [<<-EOT
    #!/bin/bash
    set -euo pipefail
    apt-get install -y nginx
    echo "<h1>$(hostname)</h1>" > /var/www/html/index.html
  EOT
  ]

  load_balancer = {
    type       = "network"
    subnet_ids = var.subnet_ids

    # Who may connect to the load balancer: anything in the VPC, on the listener's port.
    security_group_ingress = {
      vpc = { from_port = 80, cidr_ipv4 = data.aws_vpc.this.cidr_block, description = "Anything in the VPC" }
    }

    # Where the load balancer sends connections, and how it checks each instance. The module
    # lets the load balancer reach the instances on this port only.
    target_groups = {
      web = {
        port                 = 80
        protocol             = "TCP"
        deregistration_delay = 30
        health_check         = { protocol = "HTTP", path = "/" }
      }
    }

    # What the load balancer accepts: TCP on port 80, forwarded to the web target group.
    listeners = {
      web = { port = 80, protocol = "TCP", target_group = "web" }
    }
  }
}

output "address" {
  description = "The load balancer's DNS name, reachable from inside the VPC"
  value       = module.instances.metadata.lb.dns_name
}
