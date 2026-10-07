# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

output "metadata" {
  description = <<-EOT
    Everything the module created, in one object, so that other configurations need only one reference:

    - `details` - The scope, purpose and environment, each with its `name`, `abbr` (lowercase, words joined by underscores) and `machine` (lowercase letters and numbers only) forms, and the `tags` applied to every resource.
    - `aws` - The `account.id`, and the `region` `name`, `abbr` (such as `use1` for `us-east-1`) and `description`.
    - `ami` - The AMI the launch template uses: its `id`, `name`, `architecture` and `root_device_name`.
    - `auto_scaling_group` - The Auto Scaling group's `name`. Use it for scaling policies, scheduled actions and alarms.
    - `launch_template` - The launch template's `id`, `name` and latest `version`.
    - `cloudformation_stack` - The CloudFormation stack that holds the launch template and the Auto Scaling group: its `id`, `name`, `outputs` and the rest of its attributes, except the template itself.
    - `iam_role` - The instances' IAM role, with its `name` and `arn`. Attach more policies to it by `name`.
    - `iam_instance_profile` - The instance profile, with its `name` and `arn`.
    - `iam_role_policy` - The role's inline policy, or `null` when it has none.
    - `iam_role_policy_attachment` - The managed policies attached to the role: `ssm`, or `null` when `iam_role.ssm_managed_instance_core` is `false`, and `custom`, keyed like `iam_role.managed_policy_arns`.
    - `security_group` - The security groups: `instance`, and `load_balancer` (`null` without a load balancer), each with its `id`, `arn` and `name`. Use the `instance` group's `id` as a source in other groups' rules, such as a database's.
    - `vpc_security_group_ingress_rule` - The inbound rules, each a map keyed by rule: `instance` (keyed like `security_group_ingress`), `instance_from_load_balancer` and `load_balancer` (keyed like `load_balancer.security_group_ingress`), and `efs` (`null` without `efs_file_system`).
    - `vpc_security_group_egress_rule` - The outbound rules: `instance` (keyed like `security_group_egress`), `instance_to_efs` (`null` without `efs_file_system`) and `load_balancer_to_instance`.
    - `cloudwatch_log_group` - The log groups, each with its `name` and `arn`: `system` (keyed `system`, `auth`, `cloud-init` and `cfn-init`; empty when `cloudwatch_agent.logs` is `false`) and `codedeploy` (keyed like `codedeploy.log_groups`).
    - `codedeploy_deployment_group` - The CodeDeploy deployment group, or `null` without `codedeploy`.
    - `lb` - The Application or Network Load Balancer, with its `arn`, `dns_name`, `zone_id` and the rest of its attributes, or `null`.
    - `lb_target_group` - The target groups, keyed like `load_balancer.target_groups`, each with its `arn` and `name`.
    - `lb_listener` - The listeners, keyed like `load_balancer.listeners`, each with its `arn`.
    - `eip` - The Network Load Balancer's Elastic IP addresses, one per subnet in the order of `load_balancer.subnet_ids`, each with its `public_ip` and `allocation_id`; empty without `elastic_ip_addresses`.
    - `elb` - The Classic Load Balancer, with its `name`, `dns_name`, `zone_id` and the rest of its attributes, or `null`.
    - `lb_ssl_negotiation_policy` - The Classic Load Balancer's security policies, keyed like the `HTTPS` and `SSL` entries of `load_balancer.classic_listeners`.

    Left out because they change after the apply, without any change in the configuration: the Classic Load Balancer's `instances` and the target groups' `load_balancer_arns`, which the Auto Scaling group and the listeners fill in, and the security groups' inline `ingress` and `egress`.
  EOT
  value = {
    details = {
      scope = {
        name    = local.scope.name
        abbr    = local.scope.abbr
        machine = local.scope.machine
      }
      purpose = {
        name    = local.purpose.name
        abbr    = local.purpose.abbr
        machine = local.purpose.machine
      }
      environment = {
        name    = local.environment.name
        abbr    = local.environment.abbr
        machine = local.environment.machine
      }
      tags = local.tags
    }

    aws = {
      account = {
        id = local.aws.account.id
      }
      region = {
        name        = local.aws.region.name
        abbr        = local.aws.region.abbr
        description = local.aws.region.description
      }
    }

    ami = {
      id               = data.aws_ami.this.id
      name             = data.aws_ami.this.name
      architecture     = data.aws_ami.this.architecture
      root_device_name = data.aws_ami.this.root_device_name
    }

    auto_scaling_group = {
      name = lookup(aws_cloudformation_stack.this.outputs, "AutoScalingGroupName", local.name)
    }

    launch_template = {
      id      = lookup(aws_cloudformation_stack.this.outputs, "LaunchTemplateId", null)
      name    = local.name
      version = lookup(aws_cloudformation_stack.this.outputs, "LaunchTemplateVersion", null)
    }

    cloudformation_stack = {
      capabilities       = aws_cloudformation_stack.this.capabilities
      disable_rollback   = aws_cloudformation_stack.this.disable_rollback
      iam_role_arn       = aws_cloudformation_stack.this.iam_role_arn
      id                 = aws_cloudformation_stack.this.id
      name               = aws_cloudformation_stack.this.name
      notification_arns  = aws_cloudformation_stack.this.notification_arns
      on_failure         = aws_cloudformation_stack.this.on_failure
      outputs            = aws_cloudformation_stack.this.outputs
      parameters         = aws_cloudformation_stack.this.parameters
      policy_body        = aws_cloudformation_stack.this.policy_body
      policy_url         = aws_cloudformation_stack.this.policy_url
      region             = aws_cloudformation_stack.this.region
      tags               = aws_cloudformation_stack.this.tags
      tags_all           = aws_cloudformation_stack.this.tags_all
      template_url       = aws_cloudformation_stack.this.template_url
      timeout_in_minutes = aws_cloudformation_stack.this.timeout_in_minutes
    }

    iam_role = {
      arn                   = aws_iam_role.this.arn
      assume_role_policy    = aws_iam_role.this.assume_role_policy
      create_date           = aws_iam_role.this.create_date
      description           = aws_iam_role.this.description
      force_detach_policies = aws_iam_role.this.force_detach_policies
      id                    = aws_iam_role.this.id
      max_session_duration  = aws_iam_role.this.max_session_duration
      name                  = aws_iam_role.this.name
      name_prefix           = aws_iam_role.this.name_prefix
      path                  = aws_iam_role.this.path
      permissions_boundary  = aws_iam_role.this.permissions_boundary
      tags                  = aws_iam_role.this.tags
      tags_all              = aws_iam_role.this.tags_all
      unique_id             = aws_iam_role.this.unique_id
    }

    iam_instance_profile = {
      arn         = aws_iam_instance_profile.this.arn
      create_date = aws_iam_instance_profile.this.create_date
      id          = aws_iam_instance_profile.this.id
      name        = aws_iam_instance_profile.this.name
      name_prefix = aws_iam_instance_profile.this.name_prefix
      path        = aws_iam_instance_profile.this.path
      role        = aws_iam_instance_profile.this.role
      tags        = aws_iam_instance_profile.this.tags
      tags_all    = aws_iam_instance_profile.this.tags_all
      unique_id   = aws_iam_instance_profile.this.unique_id
    }

    iam_role_policy = length(aws_iam_role_policy.this) == 0 ? null : {
      id          = aws_iam_role_policy.this[0].id
      name        = aws_iam_role_policy.this[0].name
      name_prefix = aws_iam_role_policy.this[0].name_prefix
      policy      = aws_iam_role_policy.this[0].policy
      role        = aws_iam_role_policy.this[0].role
    }

    iam_role_policy_attachment = {
      ssm = length(aws_iam_role_policy_attachment.ssm) == 0 ? null : {
        id         = aws_iam_role_policy_attachment.ssm[0].id
        policy_arn = aws_iam_role_policy_attachment.ssm[0].policy_arn
        role       = aws_iam_role_policy_attachment.ssm[0].role
      }
      custom = {
        for k in keys(var.iam_role.managed_policy_arns) : k => {
          id         = aws_iam_role_policy_attachment.this[k].id
          policy_arn = aws_iam_role_policy_attachment.this[k].policy_arn
          role       = aws_iam_role_policy_attachment.this[k].role
        }
      }
    }

    security_group = {
      instance = {
        arn                    = aws_security_group.instance.arn
        description            = aws_security_group.instance.description
        id                     = aws_security_group.instance.id
        name                   = aws_security_group.instance.name
        name_prefix            = aws_security_group.instance.name_prefix
        owner_id               = aws_security_group.instance.owner_id
        region                 = aws_security_group.instance.region
        revoke_rules_on_delete = aws_security_group.instance.revoke_rules_on_delete
        tags                   = aws_security_group.instance.tags
        tags_all               = aws_security_group.instance.tags_all
        vpc_id                 = aws_security_group.instance.vpc_id
      }
      load_balancer = length(aws_security_group.load_balancer) == 0 ? null : {
        arn                    = aws_security_group.load_balancer[0].arn
        description            = aws_security_group.load_balancer[0].description
        id                     = aws_security_group.load_balancer[0].id
        name                   = aws_security_group.load_balancer[0].name
        name_prefix            = aws_security_group.load_balancer[0].name_prefix
        owner_id               = aws_security_group.load_balancer[0].owner_id
        region                 = aws_security_group.load_balancer[0].region
        revoke_rules_on_delete = aws_security_group.load_balancer[0].revoke_rules_on_delete
        tags                   = aws_security_group.load_balancer[0].tags
        tags_all               = aws_security_group.load_balancer[0].tags_all
        vpc_id                 = aws_security_group.load_balancer[0].vpc_id
      }
    }

    vpc_security_group_ingress_rule = {
      instance = {
        for k in keys(var.security_group_ingress) : k => {
          arn                          = aws_vpc_security_group_ingress_rule.instance[k].arn
          cidr_ipv4                    = aws_vpc_security_group_ingress_rule.instance[k].cidr_ipv4
          cidr_ipv6                    = aws_vpc_security_group_ingress_rule.instance[k].cidr_ipv6
          description                  = aws_vpc_security_group_ingress_rule.instance[k].description
          from_port                    = aws_vpc_security_group_ingress_rule.instance[k].from_port
          id                           = aws_vpc_security_group_ingress_rule.instance[k].id
          ip_protocol                  = aws_vpc_security_group_ingress_rule.instance[k].ip_protocol
          prefix_list_id               = aws_vpc_security_group_ingress_rule.instance[k].prefix_list_id
          referenced_security_group_id = aws_vpc_security_group_ingress_rule.instance[k].referenced_security_group_id
          region                       = aws_vpc_security_group_ingress_rule.instance[k].region
          security_group_id            = aws_vpc_security_group_ingress_rule.instance[k].security_group_id
          security_group_rule_id       = aws_vpc_security_group_ingress_rule.instance[k].security_group_rule_id
          tags                         = aws_vpc_security_group_ingress_rule.instance[k].tags
          tags_all                     = aws_vpc_security_group_ingress_rule.instance[k].tags_all
          to_port                      = aws_vpc_security_group_ingress_rule.instance[k].to_port
        }
      }
      instance_from_load_balancer = {
        for k in keys(local.lb_to_instance_rules) : k => {
          arn                          = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].arn
          cidr_ipv4                    = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].cidr_ipv4
          cidr_ipv6                    = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].cidr_ipv6
          description                  = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].description
          from_port                    = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].from_port
          id                           = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].id
          ip_protocol                  = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].ip_protocol
          prefix_list_id               = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].prefix_list_id
          referenced_security_group_id = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].referenced_security_group_id
          region                       = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].region
          security_group_id            = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].security_group_id
          security_group_rule_id       = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].security_group_rule_id
          tags                         = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].tags
          tags_all                     = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].tags_all
          to_port                      = aws_vpc_security_group_ingress_rule.instance_from_load_balancer[k].to_port
        }
      }
      load_balancer = {
        for k in keys(var.load_balancer == null ? {} : var.load_balancer.security_group_ingress) : k => {
          arn                          = aws_vpc_security_group_ingress_rule.load_balancer[k].arn
          cidr_ipv4                    = aws_vpc_security_group_ingress_rule.load_balancer[k].cidr_ipv4
          cidr_ipv6                    = aws_vpc_security_group_ingress_rule.load_balancer[k].cidr_ipv6
          description                  = aws_vpc_security_group_ingress_rule.load_balancer[k].description
          from_port                    = aws_vpc_security_group_ingress_rule.load_balancer[k].from_port
          id                           = aws_vpc_security_group_ingress_rule.load_balancer[k].id
          ip_protocol                  = aws_vpc_security_group_ingress_rule.load_balancer[k].ip_protocol
          prefix_list_id               = aws_vpc_security_group_ingress_rule.load_balancer[k].prefix_list_id
          referenced_security_group_id = aws_vpc_security_group_ingress_rule.load_balancer[k].referenced_security_group_id
          region                       = aws_vpc_security_group_ingress_rule.load_balancer[k].region
          security_group_id            = aws_vpc_security_group_ingress_rule.load_balancer[k].security_group_id
          security_group_rule_id       = aws_vpc_security_group_ingress_rule.load_balancer[k].security_group_rule_id
          tags                         = aws_vpc_security_group_ingress_rule.load_balancer[k].tags
          tags_all                     = aws_vpc_security_group_ingress_rule.load_balancer[k].tags_all
          to_port                      = aws_vpc_security_group_ingress_rule.load_balancer[k].to_port
        }
      }
      efs = length(aws_vpc_security_group_ingress_rule.efs) == 0 ? null : {
        arn                          = aws_vpc_security_group_ingress_rule.efs[0].arn
        cidr_ipv4                    = aws_vpc_security_group_ingress_rule.efs[0].cidr_ipv4
        cidr_ipv6                    = aws_vpc_security_group_ingress_rule.efs[0].cidr_ipv6
        description                  = aws_vpc_security_group_ingress_rule.efs[0].description
        from_port                    = aws_vpc_security_group_ingress_rule.efs[0].from_port
        id                           = aws_vpc_security_group_ingress_rule.efs[0].id
        ip_protocol                  = aws_vpc_security_group_ingress_rule.efs[0].ip_protocol
        prefix_list_id               = aws_vpc_security_group_ingress_rule.efs[0].prefix_list_id
        referenced_security_group_id = aws_vpc_security_group_ingress_rule.efs[0].referenced_security_group_id
        region                       = aws_vpc_security_group_ingress_rule.efs[0].region
        security_group_id            = aws_vpc_security_group_ingress_rule.efs[0].security_group_id
        security_group_rule_id       = aws_vpc_security_group_ingress_rule.efs[0].security_group_rule_id
        tags                         = aws_vpc_security_group_ingress_rule.efs[0].tags
        tags_all                     = aws_vpc_security_group_ingress_rule.efs[0].tags_all
        to_port                      = aws_vpc_security_group_ingress_rule.efs[0].to_port
      }
    }

    vpc_security_group_egress_rule = {
      instance = {
        for k in keys(var.security_group_egress) : k => {
          arn                          = aws_vpc_security_group_egress_rule.instance[k].arn
          cidr_ipv4                    = aws_vpc_security_group_egress_rule.instance[k].cidr_ipv4
          cidr_ipv6                    = aws_vpc_security_group_egress_rule.instance[k].cidr_ipv6
          description                  = aws_vpc_security_group_egress_rule.instance[k].description
          from_port                    = aws_vpc_security_group_egress_rule.instance[k].from_port
          id                           = aws_vpc_security_group_egress_rule.instance[k].id
          ip_protocol                  = aws_vpc_security_group_egress_rule.instance[k].ip_protocol
          prefix_list_id               = aws_vpc_security_group_egress_rule.instance[k].prefix_list_id
          referenced_security_group_id = aws_vpc_security_group_egress_rule.instance[k].referenced_security_group_id
          region                       = aws_vpc_security_group_egress_rule.instance[k].region
          security_group_id            = aws_vpc_security_group_egress_rule.instance[k].security_group_id
          security_group_rule_id       = aws_vpc_security_group_egress_rule.instance[k].security_group_rule_id
          tags                         = aws_vpc_security_group_egress_rule.instance[k].tags
          tags_all                     = aws_vpc_security_group_egress_rule.instance[k].tags_all
          to_port                      = aws_vpc_security_group_egress_rule.instance[k].to_port
        }
      }
      instance_to_efs = length(aws_vpc_security_group_egress_rule.instance_to_efs) == 0 ? null : {
        arn                          = aws_vpc_security_group_egress_rule.instance_to_efs[0].arn
        cidr_ipv4                    = aws_vpc_security_group_egress_rule.instance_to_efs[0].cidr_ipv4
        cidr_ipv6                    = aws_vpc_security_group_egress_rule.instance_to_efs[0].cidr_ipv6
        description                  = aws_vpc_security_group_egress_rule.instance_to_efs[0].description
        from_port                    = aws_vpc_security_group_egress_rule.instance_to_efs[0].from_port
        id                           = aws_vpc_security_group_egress_rule.instance_to_efs[0].id
        ip_protocol                  = aws_vpc_security_group_egress_rule.instance_to_efs[0].ip_protocol
        prefix_list_id               = aws_vpc_security_group_egress_rule.instance_to_efs[0].prefix_list_id
        referenced_security_group_id = aws_vpc_security_group_egress_rule.instance_to_efs[0].referenced_security_group_id
        region                       = aws_vpc_security_group_egress_rule.instance_to_efs[0].region
        security_group_id            = aws_vpc_security_group_egress_rule.instance_to_efs[0].security_group_id
        security_group_rule_id       = aws_vpc_security_group_egress_rule.instance_to_efs[0].security_group_rule_id
        tags                         = aws_vpc_security_group_egress_rule.instance_to_efs[0].tags
        tags_all                     = aws_vpc_security_group_egress_rule.instance_to_efs[0].tags_all
        to_port                      = aws_vpc_security_group_egress_rule.instance_to_efs[0].to_port
      }
      load_balancer_to_instance = {
        for k in keys(local.lb_to_instance_rules) : k => {
          arn                          = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].arn
          cidr_ipv4                    = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].cidr_ipv4
          cidr_ipv6                    = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].cidr_ipv6
          description                  = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].description
          from_port                    = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].from_port
          id                           = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].id
          ip_protocol                  = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].ip_protocol
          prefix_list_id               = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].prefix_list_id
          referenced_security_group_id = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].referenced_security_group_id
          region                       = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].region
          security_group_id            = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].security_group_id
          security_group_rule_id       = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].security_group_rule_id
          tags                         = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].tags
          tags_all                     = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].tags_all
          to_port                      = aws_vpc_security_group_egress_rule.load_balancer_to_instance[k].to_port
        }
      }
    }

    cloudwatch_log_group = {
      system = {
        for k in keys(local.system_log_groups) : k => {
          arn               = aws_cloudwatch_log_group.system[k].arn
          id                = aws_cloudwatch_log_group.system[k].id
          kms_key_id        = aws_cloudwatch_log_group.system[k].kms_key_id
          log_group_class   = aws_cloudwatch_log_group.system[k].log_group_class
          name              = aws_cloudwatch_log_group.system[k].name
          name_prefix       = aws_cloudwatch_log_group.system[k].name_prefix
          region            = aws_cloudwatch_log_group.system[k].region
          retention_in_days = aws_cloudwatch_log_group.system[k].retention_in_days
          skip_destroy      = aws_cloudwatch_log_group.system[k].skip_destroy
          tags              = aws_cloudwatch_log_group.system[k].tags
          tags_all          = aws_cloudwatch_log_group.system[k].tags_all
        }
      }
      codedeploy = {
        for k in keys(local.codedeploy_log_groups) : k => {
          arn               = aws_cloudwatch_log_group.codedeploy[k].arn
          id                = aws_cloudwatch_log_group.codedeploy[k].id
          kms_key_id        = aws_cloudwatch_log_group.codedeploy[k].kms_key_id
          log_group_class   = aws_cloudwatch_log_group.codedeploy[k].log_group_class
          name              = aws_cloudwatch_log_group.codedeploy[k].name
          name_prefix       = aws_cloudwatch_log_group.codedeploy[k].name_prefix
          region            = aws_cloudwatch_log_group.codedeploy[k].region
          retention_in_days = aws_cloudwatch_log_group.codedeploy[k].retention_in_days
          skip_destroy      = aws_cloudwatch_log_group.codedeploy[k].skip_destroy
          tags              = aws_cloudwatch_log_group.codedeploy[k].tags
          tags_all          = aws_cloudwatch_log_group.codedeploy[k].tags_all
        }
      }
    }

    codedeploy_deployment_group = length(aws_codedeploy_deployment_group.this) == 0 ? null : {
      alarm_configuration             = aws_codedeploy_deployment_group.this[0].alarm_configuration
      app_name                        = aws_codedeploy_deployment_group.this[0].app_name
      arn                             = aws_codedeploy_deployment_group.this[0].arn
      auto_rollback_configuration     = aws_codedeploy_deployment_group.this[0].auto_rollback_configuration
      autoscaling_groups              = aws_codedeploy_deployment_group.this[0].autoscaling_groups
      blue_green_deployment_config    = aws_codedeploy_deployment_group.this[0].blue_green_deployment_config
      compute_platform                = aws_codedeploy_deployment_group.this[0].compute_platform
      deployment_config_name          = aws_codedeploy_deployment_group.this[0].deployment_config_name
      deployment_group_id             = aws_codedeploy_deployment_group.this[0].deployment_group_id
      deployment_group_name           = aws_codedeploy_deployment_group.this[0].deployment_group_name
      deployment_style                = aws_codedeploy_deployment_group.this[0].deployment_style
      ec2_tag_filter                  = aws_codedeploy_deployment_group.this[0].ec2_tag_filter
      ec2_tag_set                     = aws_codedeploy_deployment_group.this[0].ec2_tag_set
      ecs_service                     = aws_codedeploy_deployment_group.this[0].ecs_service
      id                              = aws_codedeploy_deployment_group.this[0].id
      load_balancer_info              = aws_codedeploy_deployment_group.this[0].load_balancer_info
      on_premises_instance_tag_filter = aws_codedeploy_deployment_group.this[0].on_premises_instance_tag_filter
      outdated_instances_strategy     = aws_codedeploy_deployment_group.this[0].outdated_instances_strategy
      region                          = aws_codedeploy_deployment_group.this[0].region
      service_role_arn                = aws_codedeploy_deployment_group.this[0].service_role_arn
      tags                            = aws_codedeploy_deployment_group.this[0].tags
      tags_all                        = aws_codedeploy_deployment_group.this[0].tags_all
      termination_hook_enabled        = aws_codedeploy_deployment_group.this[0].termination_hook_enabled
      trigger_configuration           = aws_codedeploy_deployment_group.this[0].trigger_configuration
    }

    lb = length(aws_lb.this) == 0 ? null : {
      access_logs                                                  = aws_lb.this[0].access_logs
      arn                                                          = aws_lb.this[0].arn
      arn_suffix                                                   = aws_lb.this[0].arn_suffix
      client_keep_alive                                            = aws_lb.this[0].client_keep_alive
      connection_logs                                              = aws_lb.this[0].connection_logs
      customer_owned_ipv4_pool                                     = aws_lb.this[0].customer_owned_ipv4_pool
      desync_mitigation_mode                                       = aws_lb.this[0].desync_mitigation_mode
      dns_name                                                     = aws_lb.this[0].dns_name
      dns_record_client_routing_policy                             = aws_lb.this[0].dns_record_client_routing_policy
      drop_invalid_header_fields                                   = aws_lb.this[0].drop_invalid_header_fields
      enable_cross_zone_load_balancing                             = aws_lb.this[0].enable_cross_zone_load_balancing
      enable_deletion_protection                                   = aws_lb.this[0].enable_deletion_protection
      enable_http2                                                 = aws_lb.this[0].enable_http2
      enable_tls_version_and_cipher_suite_headers                  = aws_lb.this[0].enable_tls_version_and_cipher_suite_headers
      enable_waf_fail_open                                         = aws_lb.this[0].enable_waf_fail_open
      enable_xff_client_port                                       = aws_lb.this[0].enable_xff_client_port
      enable_zonal_shift                                           = aws_lb.this[0].enable_zonal_shift
      enforce_security_group_inbound_rules_on_private_link_traffic = aws_lb.this[0].enforce_security_group_inbound_rules_on_private_link_traffic
      id                                                           = aws_lb.this[0].id
      idle_timeout                                                 = aws_lb.this[0].idle_timeout
      internal                                                     = aws_lb.this[0].internal
      ip_address_type                                              = aws_lb.this[0].ip_address_type
      ipam_pools                                                   = aws_lb.this[0].ipam_pools
      load_balancer_type                                           = aws_lb.this[0].load_balancer_type
      minimum_load_balancer_capacity                               = aws_lb.this[0].minimum_load_balancer_capacity
      name                                                         = aws_lb.this[0].name
      name_prefix                                                  = aws_lb.this[0].name_prefix
      preserve_host_header                                         = aws_lb.this[0].preserve_host_header
      region                                                       = aws_lb.this[0].region
      security_groups                                              = aws_lb.this[0].security_groups
      subnet_mapping                                               = aws_lb.this[0].subnet_mapping
      subnets                                                      = aws_lb.this[0].subnets
      tags                                                         = aws_lb.this[0].tags
      tags_all                                                     = aws_lb.this[0].tags_all
      vpc_id                                                       = aws_lb.this[0].vpc_id
      xff_header_processing_mode                                   = aws_lb.this[0].xff_header_processing_mode
      zone_id                                                      = aws_lb.this[0].zone_id
    }

    lb_target_group = {
      for k in keys(local.target_groups) : k => {
        arn                                = aws_lb_target_group.this[k].arn
        arn_suffix                         = aws_lb_target_group.this[k].arn_suffix
        connection_termination             = aws_lb_target_group.this[k].connection_termination
        deregistration_delay               = aws_lb_target_group.this[k].deregistration_delay
        health_check                       = aws_lb_target_group.this[k].health_check
        id                                 = aws_lb_target_group.this[k].id
        ip_address_type                    = aws_lb_target_group.this[k].ip_address_type
        lambda_multi_value_headers_enabled = aws_lb_target_group.this[k].lambda_multi_value_headers_enabled
        load_balancing_algorithm_type      = aws_lb_target_group.this[k].load_balancing_algorithm_type
        load_balancing_anomaly_mitigation  = aws_lb_target_group.this[k].load_balancing_anomaly_mitigation
        load_balancing_cross_zone_enabled  = aws_lb_target_group.this[k].load_balancing_cross_zone_enabled
        name                               = aws_lb_target_group.this[k].name
        name_prefix                        = aws_lb_target_group.this[k].name_prefix
        port                               = aws_lb_target_group.this[k].port
        preserve_client_ip                 = aws_lb_target_group.this[k].preserve_client_ip
        protocol                           = aws_lb_target_group.this[k].protocol
        protocol_version                   = aws_lb_target_group.this[k].protocol_version
        proxy_protocol_v2                  = aws_lb_target_group.this[k].proxy_protocol_v2
        region                             = aws_lb_target_group.this[k].region
        slow_start                         = aws_lb_target_group.this[k].slow_start
        stickiness                         = aws_lb_target_group.this[k].stickiness
        tags                               = aws_lb_target_group.this[k].tags
        tags_all                           = aws_lb_target_group.this[k].tags_all
        target_failover                    = aws_lb_target_group.this[k].target_failover
        target_group_health                = aws_lb_target_group.this[k].target_group_health
        target_health_state                = aws_lb_target_group.this[k].target_health_state
        target_type                        = aws_lb_target_group.this[k].target_type
        vpc_id                             = aws_lb_target_group.this[k].vpc_id
      }
    }

    lb_listener = {
      for k in keys(local.listeners) : k => {
        alpn_policy                                                           = aws_lb_listener.this[k].alpn_policy
        arn                                                                   = aws_lb_listener.this[k].arn
        certificate_arn                                                       = aws_lb_listener.this[k].certificate_arn
        default_action                                                        = aws_lb_listener.this[k].default_action
        id                                                                    = aws_lb_listener.this[k].id
        load_balancer_arn                                                     = aws_lb_listener.this[k].load_balancer_arn
        mutual_authentication                                                 = aws_lb_listener.this[k].mutual_authentication
        port                                                                  = aws_lb_listener.this[k].port
        protocol                                                              = aws_lb_listener.this[k].protocol
        region                                                                = aws_lb_listener.this[k].region
        routing_http_request_x_amzn_mtls_clientcert_header_name               = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_header_name
        routing_http_request_x_amzn_mtls_clientcert_issuer_header_name        = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_issuer_header_name
        routing_http_request_x_amzn_mtls_clientcert_leaf_header_name          = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_leaf_header_name
        routing_http_request_x_amzn_mtls_clientcert_serial_number_header_name = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_serial_number_header_name
        routing_http_request_x_amzn_mtls_clientcert_subject_header_name       = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_subject_header_name
        routing_http_request_x_amzn_mtls_clientcert_validity_header_name      = aws_lb_listener.this[k].routing_http_request_x_amzn_mtls_clientcert_validity_header_name
        routing_http_request_x_amzn_tls_cipher_suite_header_name              = aws_lb_listener.this[k].routing_http_request_x_amzn_tls_cipher_suite_header_name
        routing_http_request_x_amzn_tls_version_header_name                   = aws_lb_listener.this[k].routing_http_request_x_amzn_tls_version_header_name
        routing_http_response_access_control_allow_credentials_header_value   = aws_lb_listener.this[k].routing_http_response_access_control_allow_credentials_header_value
        routing_http_response_access_control_allow_headers_header_value       = aws_lb_listener.this[k].routing_http_response_access_control_allow_headers_header_value
        routing_http_response_access_control_allow_methods_header_value       = aws_lb_listener.this[k].routing_http_response_access_control_allow_methods_header_value
        routing_http_response_access_control_allow_origin_header_value        = aws_lb_listener.this[k].routing_http_response_access_control_allow_origin_header_value
        routing_http_response_access_control_expose_headers_header_value      = aws_lb_listener.this[k].routing_http_response_access_control_expose_headers_header_value
        routing_http_response_access_control_max_age_header_value             = aws_lb_listener.this[k].routing_http_response_access_control_max_age_header_value
        routing_http_response_content_security_policy_header_value            = aws_lb_listener.this[k].routing_http_response_content_security_policy_header_value
        routing_http_response_server_enabled                                  = aws_lb_listener.this[k].routing_http_response_server_enabled
        routing_http_response_strict_transport_security_header_value          = aws_lb_listener.this[k].routing_http_response_strict_transport_security_header_value
        routing_http_response_x_content_type_options_header_value             = aws_lb_listener.this[k].routing_http_response_x_content_type_options_header_value
        routing_http_response_x_frame_options_header_value                    = aws_lb_listener.this[k].routing_http_response_x_frame_options_header_value
        ssl_policy                                                            = aws_lb_listener.this[k].ssl_policy
        tags                                                                  = aws_lb_listener.this[k].tags
        tags_all                                                              = aws_lb_listener.this[k].tags_all
        tcp_idle_timeout_seconds                                              = aws_lb_listener.this[k].tcp_idle_timeout_seconds
      }
    }

    eip = [
      for i in range(length(aws_eip.load_balancer)) : {
        address                   = aws_eip.load_balancer[i].address
        allocation_id             = aws_eip.load_balancer[i].allocation_id
        arn                       = aws_eip.load_balancer[i].arn
        associate_with_private_ip = aws_eip.load_balancer[i].associate_with_private_ip
        carrier_ip                = aws_eip.load_balancer[i].carrier_ip
        customer_owned_ip         = aws_eip.load_balancer[i].customer_owned_ip
        customer_owned_ipv4_pool  = aws_eip.load_balancer[i].customer_owned_ipv4_pool
        domain                    = aws_eip.load_balancer[i].domain
        id                        = aws_eip.load_balancer[i].id
        ipam_pool_id              = aws_eip.load_balancer[i].ipam_pool_id
        network_border_group      = aws_eip.load_balancer[i].network_border_group
        ptr_record                = aws_eip.load_balancer[i].ptr_record
        public_dns                = aws_eip.load_balancer[i].public_dns
        public_ip                 = aws_eip.load_balancer[i].public_ip
        public_ipv4_pool          = aws_eip.load_balancer[i].public_ipv4_pool
        region                    = aws_eip.load_balancer[i].region
        tags                      = aws_eip.load_balancer[i].tags
        tags_all                  = aws_eip.load_balancer[i].tags_all
      }
    ]

    elb = length(aws_elb.this) == 0 ? null : {
      access_logs                 = aws_elb.this[0].access_logs
      arn                         = aws_elb.this[0].arn
      availability_zones          = aws_elb.this[0].availability_zones
      connection_draining         = aws_elb.this[0].connection_draining
      connection_draining_timeout = aws_elb.this[0].connection_draining_timeout
      cross_zone_load_balancing   = aws_elb.this[0].cross_zone_load_balancing
      desync_mitigation_mode      = aws_elb.this[0].desync_mitigation_mode
      dns_name                    = aws_elb.this[0].dns_name
      health_check                = aws_elb.this[0].health_check
      id                          = aws_elb.this[0].id
      idle_timeout                = aws_elb.this[0].idle_timeout
      internal                    = aws_elb.this[0].internal
      listener                    = aws_elb.this[0].listener
      name                        = aws_elb.this[0].name
      name_prefix                 = aws_elb.this[0].name_prefix
      region                      = aws_elb.this[0].region
      security_groups             = aws_elb.this[0].security_groups
      source_security_group       = aws_elb.this[0].source_security_group
      source_security_group_id    = aws_elb.this[0].source_security_group_id
      subnets                     = aws_elb.this[0].subnets
      tags                        = aws_elb.this[0].tags
      tags_all                    = aws_elb.this[0].tags_all
      zone_id                     = aws_elb.this[0].zone_id
    }

    lb_ssl_negotiation_policy = {
      for k, l in local.classic_listeners : k => {
        attribute     = aws_lb_ssl_negotiation_policy.this[k].attribute
        id            = aws_lb_ssl_negotiation_policy.this[k].id
        lb_port       = aws_lb_ssl_negotiation_policy.this[k].lb_port
        load_balancer = aws_lb_ssl_negotiation_policy.this[k].load_balancer
        name          = aws_lb_ssl_negotiation_policy.this[k].name
        region        = aws_lb_ssl_negotiation_policy.this[k].region
        triggers      = aws_lb_ssl_negotiation_policy.this[k].triggers
      } if contains(["HTTPS", "SSL"], l.lb_protocol)
    }
  }
}
