# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# An Amazon Linux 2023 web server behind an internal Classic Load Balancer, the previous
# generation of Elastic Load Balancing, for applications that still use one.

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
    purpose     = "Classic Load Balancer"
    environment = "Development"
  }

  os             = "al2023"
  instance_types = [{ type = "t3.micro" }]
  vpc_id         = var.vpc_id
  subnet_ids     = var.subnet_ids

  user_data_scripts = [<<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf -y install nginx
    echo "<h1>$(hostname)</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOT
  ]

  load_balancer = {
    type       = "classic"
    subnet_ids = var.subnet_ids
    security_group_ingress = {
      vpc = { from_port = 80, cidr_ipv4 = data.aws_vpc.this.cidr_block, description = "Anything in the VPC" }
    }
    classic_listeners = {
      http = { lb_port = 80, lb_protocol = "HTTP", instance_port = 80, instance_protocol = "HTTP" }
    }
    classic_health_check = { target = "HTTP:80/" }
  }
}

output "address" {
  description = "The load balancer's DNS name, reachable from inside the VPC"
  value       = module.instances.metadata.elb.dns_name
}
