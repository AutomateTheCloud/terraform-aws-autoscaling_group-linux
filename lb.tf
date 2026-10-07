# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# An Application or Network Load Balancer.
resource "aws_lb" "this" {
  count = local.lb_v2 ? 1 : 0

  region             = var.region
  name               = local.lb_name
  load_balancer_type = local.lb.type
  internal           = var.load_balancer == null ? true : var.load_balancer.internal
  security_groups    = [aws_security_group.load_balancer[0].id]
  ip_address_type    = local.lb.ip_address_type

  # With Elastic IP addresses, each subnet is mapped to its own address.
  subnets = local.lb.elastic_ip_addresses ? null : local.lb.subnet_ids
  dynamic "subnet_mapping" {
    for_each = local.lb.elastic_ip_addresses ? range(length(local.lb.subnet_ids)) : []
    content {
      subnet_id     = local.lb.subnet_ids[subnet_mapping.value]
      allocation_id = aws_eip.load_balancer[subnet_mapping.value].id
    }
  }

  enable_deletion_protection       = local.lb.deletion_protection
  enable_cross_zone_load_balancing = local.lb.type == "network" ? coalesce(local.lb.cross_zone_load_balancing, false) : null
  idle_timeout                     = local.lb.type == "application" ? local.lb.idle_timeout : null
  drop_invalid_header_fields       = local.lb.type == "application" ? local.lb.drop_invalid_header_fields : null
  enable_http2                     = local.lb.type == "application" ? local.lb.http2 : null

  dynamic "access_logs" {
    for_each = local.lb.access_logs == null ? [] : [local.lb.access_logs]
    content {
      enabled = true
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
    }
  }

  tags = merge(local.tags, { Name = local.lb_name })
}

# One Elastic IP address per subnet, for an internet-facing Network Load Balancer.
resource "aws_eip" "load_balancer" {
  count = local.lb_v2 && try(local.lb.elastic_ip_addresses, false) ? length(local.lb.subnet_ids) : 0

  region = var.region
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.lb_name}-${count.index + 1}" })
}
