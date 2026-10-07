# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# The instances' role. IAM names are unique in the account across Regions, so the name is
# a prefix that AWS completes.
resource "aws_iam_role" "this" {
  name_prefix = local.iam_name_prefix
  description = "EC2 instances of ${local.stack_name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = data.aws_service_principal.ec2.name }
      Action    = "sts:AssumeRole"
      # Only for this account's instances.
      Condition = { StringEquals = { "aws:SourceAccount" = local.aws.account.id } }
    }]
  })

  tags = local.tags

  # A new name replaces the role. Creating the new role first lets the instance profile
  # move to it before the old one is deleted.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = local.iam_name_prefix
  role        = aws_iam_role.this.name

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}
