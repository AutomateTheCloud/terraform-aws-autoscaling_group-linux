# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

locals {
  # Names. The launch template, Auto Scaling group and security groups use the abbreviations;
  # the stack and load balancer names allow only letters, digits and hyphens.
  name             = "${local.scope.abbr}-${local.purpose.abbr}-${local.environment.abbr}-${local.aws.region.abbr}"
  stack_name       = "${local.scope.machine}-${local.purpose.machine}-${local.environment.machine}-${local.aws.region.abbr}"
  machine_name     = "${local.scope.machine}-${local.purpose.machine}-${local.environment.machine}"
  iam_name_prefix  = "${trimsuffix(substr(local.name, 0, 33), "-")}-ec2-"
  log_group_prefix = "/${local.scope.abbr}/${local.purpose.abbr}/${local.environment.abbr}"

  # The public AMI parameters for each operating system and architecture.
  ami_parameters = {
    al2023 = {
      x86_64 = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
      arm64  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    }
    ubuntu22 = {
      x86_64 = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"
      arm64  = "/aws/service/canonical/ubuntu/server/22.04/stable/current/arm64/hvm/ebs-gp2/ami-id"
    }
    ubuntu24 = {
      x86_64 = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
      arm64  = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
    }
  }
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.ami.insecure_value

  ##---------------------------------------------------------------------------
  # Load balancer
  lb      = var.load_balancer
  lb_type = local.lb == null ? null : local.lb.type
  lb_v2   = contains(["application", "network"], coalesce(local.lb_type, "-"))
  # The default name: scope and purpose, shortened to fit 32 characters with the environment.
  lb_environment = substr(local.environment.machine, 0, 12)
  lb_name = local.lb == null ? null : coalesce(
    local.lb.name,
    "${trimsuffix(substr("${local.scope.machine}-${local.purpose.machine}", 0, 28 - length(local.lb_environment)), "-")}-${local.lb_environment}-lb"
  )

  target_groups     = local.lb_v2 ? local.lb.target_groups : {}
  listeners         = local.lb_v2 ? local.lb.listeners : {}
  classic_listeners = local.lb_type == "classic" ? local.lb.classic_listeners : {}

  # The Classic Load Balancer's health check: the given target, or TCP on the first
  # listener's instance port.
  classic_health_check_target = local.lb_type == "classic" ? coalesce(
    local.lb.classic_health_check.target,
    "TCP:${values(local.lb.classic_listeners)[0].instance_port}"
  ) : null

  # Where the load balancer sends traffic and health checks on the instances: the only
  # ports the instances' security group opens to it, and the load balancer's to them.
  lb_to_instance_ports = distinct(concat(
    flatten([
      for tg in values(local.target_groups) : concat(
        [for p in(tg.protocol == "TCP_UDP" ? ["tcp", "udp"] : [tg.protocol == "UDP" ? "udp" : "tcp"]) : { ip_protocol = p, port = tg.port }],
        [{ ip_protocol = "tcp", port = tg.health_check.port == "traffic-port" ? tg.port : tonumber(tg.health_check.port) }],
      )
    ]),
    [for l in values(local.classic_listeners) : { ip_protocol = "tcp", port = l.instance_port }],
    local.classic_health_check_target == null ? [] : [{ ip_protocol = "tcp", port = tonumber(regex("^[A-Z]+:([0-9]+)", local.classic_health_check_target)[0]) }],
  ))
  lb_to_instance_rules = { for p in local.lb_to_instance_ports : "${p.ip_protocol}-${p.port}" => p }

  ##---------------------------------------------------------------------------
  # Log groups the instances write to
  system_log_groups = var.cloudwatch_agent.logs ? {
    for k in ["system", "auth", "cloud-init", "cfn-init"] : k => "${local.log_group_prefix}/ec2/${k}"
  } : {}
  codedeploy_log_groups = var.codedeploy == null ? {} : {
    for g in var.codedeploy.log_groups : g => "${local.log_group_prefix}/application/${var.codedeploy.application_name}/${g}"
  }
}
