# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# A random suffix for each target group's name, new whenever a change replaces the group,
# so the new group can be created while the old one is still in use.
resource "random_id" "target_group" {
  for_each = local.target_groups

  byte_length = 4
  keepers = {
    vpc_id           = var.vpc_id
    port             = each.value.port
    protocol         = each.value.protocol
    protocol_version = coalesce(each.value.protocol_version, "-")
  }
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  region           = var.region
  name             = "${trimsuffix(substr("${local.machine_name}-${replace(each.key, "/[^A-Za-z0-9-]/", "")}", 0, 23), "-")}-${random_id.target_group[each.key].hex}"
  vpc_id           = var.vpc_id
  target_type      = "instance"
  port             = each.value.port
  protocol         = each.value.protocol
  protocol_version = each.value.protocol_version

  deregistration_delay          = each.value.deregistration_delay
  slow_start                    = each.value.slow_start
  load_balancing_algorithm_type = each.value.load_balancing_algorithm_type
  proxy_protocol_v2             = each.value.proxy_protocol_v2

  # A Network Load Balancer passes on the client's address by default, and the instances then
  # see traffic from the clients, not from the load balancer's security group, which is all
  # their group allows. Off unless asked for; UDP target groups cannot turn it off.
  preserve_client_ip = local.lb_type == "network" && !contains(["UDP", "TCP_UDP"], each.value.protocol) ? coalesce(each.value.preserve_client_ip, false) : each.value.preserve_client_ip

  health_check {
    enabled             = true
    protocol            = each.value.health_check.protocol
    port                = each.value.health_check.port
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness == null ? [] : [each.value.stickiness]
    content {
      enabled         = true
      type            = stickiness.value.type
      cookie_name     = stickiness.value.cookie_name
      cookie_duration = stickiness.value.cookie_duration
    }
  }

  tags = merge(local.tags, { Name = "${local.lb_name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}
