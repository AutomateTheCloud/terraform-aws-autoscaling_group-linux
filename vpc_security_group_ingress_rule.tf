# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Each rule is replaced with its security group. Creating the new rules first keeps the
# instances reachable while they move to the new group.

# Who may connect to the instances directly. The keys come from the input alone, so a
# source created in the same run can be used.
resource "aws_vpc_security_group_ingress_rule" "instance" {
  for_each = var.security_group_ingress

  region            = var.region
  security_group_id = aws_security_group.instance.id
  description       = coalesce(each.value.description, each.key)
  ip_protocol       = each.value.ip_protocol
  from_port         = contains(["tcp", "udp"], each.value.ip_protocol) ? each.value.from_port : contains(["icmp", "icmpv6"], each.value.ip_protocol) ? coalesce(each.value.from_port, -1) : null
  to_port           = contains(["tcp", "udp"], each.value.ip_protocol) ? coalesce(each.value.to_port, each.value.from_port) : contains(["icmp", "icmpv6"], each.value.ip_protocol) ? coalesce(each.value.to_port, -1) : null

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group_id

  tags = merge(local.tags, { Name = "${local.name}-ec2-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# The load balancer may reach the instances on the target and health check ports only.
resource "aws_vpc_security_group_ingress_rule" "instance_from_load_balancer" {
  for_each = local.lb_to_instance_rules

  region                       = var.region
  security_group_id            = aws_security_group.instance.id
  description                  = "Load balancer"
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = aws_security_group.load_balancer[0].id

  tags = merge(local.tags, { Name = "${local.name}-ec2-lb-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# Who may connect to the load balancer.
resource "aws_vpc_security_group_ingress_rule" "load_balancer" {
  for_each = var.load_balancer == null ? {} : var.load_balancer.security_group_ingress

  region            = var.region
  security_group_id = aws_security_group.load_balancer[0].id
  description       = coalesce(each.value.description, each.key)
  ip_protocol       = each.value.ip_protocol
  from_port         = each.value.from_port
  to_port           = coalesce(each.value.to_port, each.value.from_port)

  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.security_group_id

  tags = merge(local.tags, { Name = "${local.name}-lb-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# NFS from the instances to the EFS file system's mount targets, in the file system's group.
resource "aws_vpc_security_group_ingress_rule" "efs" {
  count = var.efs_file_system == null ? 0 : 1

  region                       = var.region
  security_group_id            = var.efs_file_system.security_group_id
  description                  = "NFS from the instances of ${local.stack_name}"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  referenced_security_group_id = aws_security_group.instance.id

  tags = merge(local.tags, { Name = "${local.name}-efs" })

  lifecycle {
    create_before_destroy = true
  }
}
