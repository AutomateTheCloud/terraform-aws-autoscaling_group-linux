# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# The log groups the CloudWatch agent writes the system logs to. The module creates them,
# with a retention period, so the agent does not create them itself with none.
resource "aws_cloudwatch_log_group" "system" {
  for_each = local.system_log_groups

  region            = var.region
  name              = each.value
  retention_in_days = var.cloudwatch_agent.log_retention_in_days
  kms_key_id        = var.cloudwatch_agent.log_kms_key_id

  tags = local.tags
}

# The CodeDeploy application's log groups, which /deploy/codedeploy.dat names.
resource "aws_cloudwatch_log_group" "codedeploy" {
  for_each = local.codedeploy_log_groups

  region            = var.region
  name              = each.value
  retention_in_days = var.cloudwatch_agent.log_retention_in_days
  kms_key_id        = var.cloudwatch_agent.log_kms_key_id

  tags = local.tags
}
