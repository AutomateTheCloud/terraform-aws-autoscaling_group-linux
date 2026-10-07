# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# What the module's own features need, each limited to the resources the module creates or
# was given, followed by the caller's documents.
data "aws_iam_policy_document" "this" {
  source_policy_documents = var.iam_role.source_policy_documents

  # The CloudWatch agent and applications write to the module's log groups only.
  dynamic "statement" {
    for_each = length(local.log_group_arns) > 0 ? [1] : []
    content {
      sid       = "WriteLogs"
      actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      resources = flatten([for arn in local.log_group_arns : [arn, "${arn}:log-stream:*"]])
    }
  }

  # Custom metrics, in the CloudWatch agent's namespace only. The agent reads the instance's
  # tags for its Auto Scaling group's name.
  dynamic "statement" {
    for_each = var.cloudwatch_agent.metrics ? [1] : []
    content {
      sid       = "PutAgentMetrics"
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = ["CWAgent"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.cloudwatch_agent.metrics ? [1] : []
    content {
      sid       = "DescribeTags"
      actions   = ["ec2:DescribeTags"]
      resources = ["*"]
    }
  }

  # Systems Manager, beyond AmazonSSMManagedInstanceCore: the AWS-owned buckets SSM Agent reads
  # from (agent updates, Distributor packages, patching, document modules), in the instances'
  # Region, as AWS documents them. Needed when the instances reach Amazon S3 through a VPC
  # endpoint, or through a bucket policy or network that requires an identity.
  dynamic "statement" {
    for_each = var.iam_role.ssm_managed_instance_core ? [1] : []
    content {
      sid     = "SSMAgentBuckets"
      actions = ["s3:GetObject"]
      resources = [for b in [
        "aws-ssm-${local.aws.region.name}",
        "amazon-ssm-${local.aws.region.name}",
        "amazon-ssm-packages-${local.aws.region.name}",
        "${local.aws.region.name}-birdwatcher-prod",
        "aws-windows-downloads-${local.aws.region.name}",
        "patch-baseline-snapshot-${local.aws.region.name}",
        "patch-baseline-snapshot-${local.aws.region.name}-*",
        "aws-patch-manager-${local.aws.region.name}-*",
      ] : "arn:${data.aws_partition.this.partition}:s3:::${b}/*"]
    }
  }

  # Session Manager session logging, when the account's Session Manager preferences turn it on:
  # writing to the session log group in CloudWatch Logs, and checking that the session log
  # bucket is encrypted. AWS documents both on any resource; the log actions are limited here
  # to log groups in this account and Region.
  dynamic "statement" {
    for_each = var.iam_role.ssm_managed_instance_core ? [1] : []
    content {
      sid     = "SessionManagerLogs"
      actions = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
      resources = [
        "arn:${data.aws_partition.this.partition}:logs:${local.aws.region.name}:${local.aws.account.id}:log-group:*",
        "arn:${data.aws_partition.this.partition}:logs:${local.aws.region.name}:${local.aws.account.id}:log-group:*:log-stream:*",
      ]
    }
  }

  dynamic "statement" {
    for_each = var.iam_role.ssm_managed_instance_core ? [1] : []
    content {
      sid       = "SessionManagerLogBucketEncryption"
      actions   = ["s3:GetEncryptionConfiguration"]
      resources = ["*"]
    }
  }

  # Session logs written to S3, and sessions or log buckets encrypted with your own KMS keys.
  dynamic "statement" {
    for_each = var.session_manager.log_bucket == null ? [] : [var.session_manager.log_bucket]
    content {
      sid       = "SessionManagerLogBucket"
      actions   = ["s3:PutObject"]
      resources = ["${statement.value.arn}/${statement.value.prefix == null ? "" : "${trim(statement.value.prefix, "/")}/"}*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.session_manager.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "SessionManagerKeys"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = var.session_manager.kms_key_arns
    }
  }

  # Parameter Store: every parameter under each path, and the path itself, which IAM checks
  # for GetParametersByPath.
  dynamic "statement" {
    for_each = length(var.parameter_store.paths) > 0 ? [1] : []
    content {
      sid     = "ReadParameters"
      actions = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      resources = flatten([
        for p in var.parameter_store.paths : [
          "arn:${data.aws_partition.this.partition}:ssm:${local.aws.region.name}:${local.aws.account.id}:parameter${p}",
          "arn:${data.aws_partition.this.partition}:ssm:${local.aws.region.name}:${local.aws.account.id}:parameter${p}/*",
        ]
      ])
    }
  }

  # Decrypting SecureString parameters under the paths only: through Parameter Store in this
  # Region, which names the parameter in the encryption context. Without that condition, the
  # instances could decrypt any parameter encrypted with the keys, since the Systems Manager
  # managed policy lets them read every parameter by name.
  dynamic "statement" {
    for_each = length(var.parameter_store.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptParameters"
      actions   = ["kms:Decrypt"]
      resources = var.parameter_store.kms_key_arns
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["ssm.${local.aws.region.name}.${data.aws_partition.this.dns_suffix}"]
      }
      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:PARAMETER_ARN"
        values   = [for p in var.parameter_store.paths : "arn:${data.aws_partition.this.partition}:ssm:${local.aws.region.name}:${local.aws.account.id}:parameter${p}/*"]
      }
    }
  }

  # The CodeDeploy agent downloads revisions from the application's bucket.
  dynamic "statement" {
    for_each = var.codedeploy == null ? [] : var.codedeploy.revision_bucket == null ? [] : [var.codedeploy.revision_bucket]
    content {
      sid       = "ReadRevisions"
      actions   = ["s3:GetObject", "s3:GetObjectVersion"]
      resources = ["${statement.value.arn}/${statement.value.path == null ? "" : "${trim(statement.value.path, "/")}/"}*"]
    }
  }
}

locals {
  log_group_arns = [for g in merge(aws_cloudwatch_log_group.system, aws_cloudwatch_log_group.codedeploy) : g.arn]
  has_role_policy = (
    length(var.iam_role.source_policy_documents) > 0 ||
    var.iam_role.ssm_managed_instance_core ||
    (var.session_manager.log_bucket != null) || length(var.session_manager.kms_key_arns) > 0 ||
    length(var.parameter_store.paths) > 0 || length(var.parameter_store.kms_key_arns) > 0 ||
    var.cloudwatch_agent.logs || var.cloudwatch_agent.metrics ||
    length(local.codedeploy_log_groups) > 0 ||
    (var.codedeploy == null ? false : var.codedeploy.revision_bucket != null)
  )
}

resource "aws_iam_role_policy" "this" {
  count = local.has_role_policy ? 1 : 0

  name   = "autoscaling_group-linux"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}
