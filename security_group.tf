# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# The instances' security group. A details change renames it, which replaces it: the new
# group is created first, the instances move to it in a rolling update, and only then is
# the old one deleted.
resource "aws_security_group" "instance" {
  region                 = var.region
  name_prefix            = "${local.name}-ec2-"
  description            = "EC2 instances of ${local.stack_name}"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(local.tags, { Name = "${local.name}-ec2" })

  lifecycle {
    create_before_destroy = true
  }
}

# The load balancer's security group: who may reach it, and that it may reach the instances.
resource "aws_security_group" "load_balancer" {
  count = local.lb == null ? 0 : 1

  region                 = var.region
  name_prefix            = "${local.name}-lb-"
  description            = "Load balancer of ${local.stack_name}"
  vpc_id                 = var.vpc_id
  revoke_rules_on_delete = true

  tags = merge(local.tags, { Name = "${local.name}-lb" })

  lifecycle {
    create_before_destroy = true
  }
}
