# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# A Classic Load Balancer.
resource "aws_elb" "this" {
  count = local.lb_type == "classic" ? 1 : 0

  region          = var.region
  name            = local.lb_name
  subnets         = local.lb.subnet_ids
  security_groups = [aws_security_group.load_balancer[0].id]
  internal        = var.load_balancer == null ? true : var.load_balancer.internal

  cross_zone_load_balancing   = coalesce(local.lb.cross_zone_load_balancing, true)
  idle_timeout                = local.lb.idle_timeout
  connection_draining         = local.lb.connection_draining_timeout > 0
  connection_draining_timeout = local.lb.connection_draining_timeout > 0 ? local.lb.connection_draining_timeout : 300

  dynamic "listener" {
    for_each = local.classic_listeners
    content {
      lb_port = listener.value.lb_port
      # AWS reads the protocols back in lowercase; sending them so keeps every plan clean.
      lb_protocol        = lower(listener.value.lb_protocol)
      instance_port      = listener.value.instance_port
      instance_protocol  = lower(listener.value.instance_protocol)
      ssl_certificate_id = listener.value.ssl_certificate_id
    }
  }

  health_check {
    target              = local.classic_health_check_target
    interval            = local.lb.classic_health_check.interval
    timeout             = local.lb.classic_health_check.timeout
    healthy_threshold   = local.lb.classic_health_check.healthy_threshold
    unhealthy_threshold = local.lb.classic_health_check.unhealthy_threshold
  }

  dynamic "access_logs" {
    for_each = local.lb.access_logs == null ? [] : [local.lb.access_logs]
    content {
      enabled       = true
      bucket        = access_logs.value.bucket
      bucket_prefix = access_logs.value.prefix
      interval      = access_logs.value.interval
    }
  }

  tags = merge(local.tags, { Name = local.lb_name })
}

# The security policy of each HTTPS and SSL listener: the predefined policy in
# classic_ssl_policy, instead of the old protocols and ciphers a Classic Load Balancer
# otherwise allows.
resource "aws_lb_ssl_negotiation_policy" "this" {
  for_each = { for k, l in local.classic_listeners : k => l if contains(["HTTPS", "SSL"], l.lb_protocol) }

  region        = var.region
  name          = "${replace(each.key, "/[^A-Za-z0-9-]/", "-")}-${each.value.lb_port}-tls"
  load_balancer = aws_elb.this[0].id
  lb_port       = each.value.lb_port

  attribute {
    name  = "Reference-Security-Policy"
    value = local.lb.classic_ssl_policy
  }
}
