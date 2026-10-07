# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# A deployment group for the Auto Scaling group, in the caller's CodeDeploy application.
resource "aws_codedeploy_deployment_group" "this" {
  count = var.codedeploy == null ? 0 : 1

  region                 = var.region
  app_name               = var.codedeploy.application_name
  deployment_group_name  = local.name
  service_role_arn       = var.codedeploy.service_role_arn
  autoscaling_groups     = [local.name]
  deployment_config_name = var.codedeploy.deployment_config_name

  deployment_style {
    deployment_option = local.lb == null ? "WITHOUT_TRAFFIC_CONTROL" : "WITH_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  dynamic "load_balancer_info" {
    for_each = local.lb == null ? [] : [1]
    content {
      dynamic "target_group_info" {
        for_each = local.target_groups
        content {
          name = aws_lb_target_group.this[target_group_info.key].name
        }
      }
      dynamic "elb_info" {
        for_each = local.lb_type == "classic" ? [1] : []
        content {
          name = aws_elb.this[0].name
        }
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  tags = local.tags

  # The stack creates the Auto Scaling group named in autoscaling_groups.
  depends_on = [aws_cloudformation_stack.this]
}
