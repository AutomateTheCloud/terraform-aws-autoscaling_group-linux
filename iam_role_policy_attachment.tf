# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Systems Manager: the agent's own access, and Session Manager.
resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.iam_role.ssm_managed_instance_core ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = var.iam_role.managed_policy_arns

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
