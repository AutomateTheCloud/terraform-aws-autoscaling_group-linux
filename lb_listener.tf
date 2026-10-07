# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

resource "aws_lb_listener" "this" {
  for_each = local.listeners

  region            = var.region
  load_balancer_arn = aws_lb.this[0].arn
  port              = each.value.port
  protocol          = each.value.protocol
  certificate_arn   = each.value.certificate_arn
  ssl_policy        = contains(["HTTPS", "TLS"], each.value.protocol) ? each.value.ssl_policy : null
  alpn_policy       = each.value.alpn_policy

  default_action {
    type             = each.value.target_group != null ? "forward" : each.value.redirect != null ? "redirect" : "fixed-response"
    target_group_arn = each.value.target_group != null ? aws_lb_target_group.this[each.value.target_group].arn : null

    dynamic "redirect" {
      for_each = each.value.redirect == null ? [] : [each.value.redirect]
      content {
        protocol    = redirect.value.protocol
        port        = redirect.value.port
        host        = redirect.value.host
        path        = redirect.value.path
        query       = redirect.value.query
        status_code = redirect.value.status_code
      }
    }

    dynamic "fixed_response" {
      for_each = each.value.fixed_response == null ? [] : [each.value.fixed_response]
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.lb_name}-${each.key}" })
}
