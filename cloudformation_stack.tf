# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# The launch template and the Auto Scaling group are in an AWS CloudFormation stack, for
# what CloudFormation adds to them: each new instance signals that its setup succeeded
# (cfn-signal), a launch template change replaces the instances in rolling batches that
# wait for those signals and roll back on failure, and the setup in the launch template's
# AWS::CloudFormation::Init metadata is applied again on running instances when it changes
# (cfn-hup). The template is built here as an object and written out with jsonencode(), so
# every value is quoted correctly.
locals {
  # A value for a shell file that is read with `source`: single-quoted, so nothing in it is
  # expanded.
  shell_quote = { for k, v in merge(
    {
      INSTANCE_SCOPE_NAME       = local.scope.name
      INSTANCE_SCOPE_ABBR       = local.scope.abbr
      INSTANCE_PURPOSE_NAME     = local.purpose.name
      INSTANCE_PURPOSE_ABBR     = local.purpose.abbr
      INSTANCE_ENVIRONMENT_NAME = local.environment.name
      INSTANCE_ENVIRONMENT_ABBR = local.environment.abbr
      INSTANCE_REGION_NAME      = local.aws.region.name
      INSTANCE_REGION_ABBR      = local.aws.region.abbr
    },
    var.codedeploy == null ? {} : merge(
      { CODEDEPLOY_APPLICATION_NAME = var.codedeploy.application_name },
      { for k, v in local.codedeploy_log_groups : "CODEDEPLOY_LOG_GROUP_${upper(replace(k, "/[^A-Za-z0-9]/", "_"))}" => v },
    ),
  ) : k => "${k}='${replace(v, "'", "'\\''")}'" }

  is_ubuntu   = var.os != "al2023"
  cfn_bin     = local.is_ubuntu ? "/opt/aws/cfn-bootstrap/bin" : "/opt/aws/bin"
  install     = local.is_ubuntu ? "DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install" : "dnf -y install"
  s3_endpoint = "s3.${local.aws.region.name}.${data.aws_partition.this.dns_suffix}"

  # Starts a service and fails the step unless it is running. An AMI can ship a service as a
  # SysV init script, which systemd wraps in a generated unit: there, `systemctl enable --now`
  # exited 0 without starting the CodeDeploy agent, and every launch deployment waited for it.
  # The reload picks up units and init scripts installed since boot; `start` leaves a service
  # that is already running alone, so cfn-hup running the setup again never interrupts it.
  start_service = { for svc in ["cfn-hup", "codedeploy-agent", "rsyslog"] : svc => join(" && ", [
    "systemctl daemon-reload",
    "systemctl enable ${svc}",
    "systemctl start ${svc}",
    "systemctl is-active --quiet ${svc}",
  ]) }

  cfn_init_command = "${local.cfn_bin}/cfn-init -v --stack ${local.stack_name} --resource LaunchTemplate --region ${local.aws.region.name} --configsets Bootstrap"

  # The CloudWatch agent's configuration: the logs to send and the metrics to collect.
  cloudwatch_agent_logs = {
    system     = local.is_ubuntu ? "/var/log/syslog" : "/var/log/messages"
    auth       = local.is_ubuntu ? "/var/log/auth.log" : "/var/log/secure"
    cloud-init = "/var/log/cloud-init-output.log"
    cfn-init   = "/var/log/cfn-init.log"
  }
  cloudwatch_agent_config = merge(
    { agent = { run_as_user = "root" } },
    var.cloudwatch_agent.logs ? {
      logs = {
        logs_collected = {
          files = {
            collect_list = [
              for k, path in local.cloudwatch_agent_logs : {
                file_path       = path
                log_group_name  = local.system_log_groups[k]
                log_stream_name = "{instance_id}"
              }
            ]
          }
        }
      }
    } : {},
    var.cloudwatch_agent.metrics ? {
      metrics = {
        namespace = "CWAgent"
        append_dimensions = {
          AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
          InstanceId           = "$${aws:InstanceId}"
        }
        aggregation_dimensions = [["AutoScalingGroupName"]]
        metrics_collected = {
          mem  = { measurement = ["mem_used_percent"], metrics_collection_interval = 60 }
          swap = { measurement = ["swap_used_percent"], metrics_collection_interval = 60 }
          disk = { measurement = ["used_percent", "inodes_free"], resources = ["/"], metrics_collection_interval = 60 }
        }
      }
    } : {},
  )
  cloudwatch_agent_enabled = var.cloudwatch_agent.logs || var.cloudwatch_agent.metrics

  # AWS::CloudFormation::Init: one config per feature, run in the order of the Bootstrap
  # config set. Within a config, cfn-init writes the files, then runs the commands in the
  # order of their names. Every command can run again: cfn-hup runs the whole set again
  # when this metadata changes.
  cfn_init_configs = merge(
    {
      cfn_hup = {
        files = {
          "/etc/cfn/cfn-hup.conf" = {
            content = "[main]\nstack=${local.stack_name}\nregion=${local.aws.region.name}\ninterval=5\n"
            mode    = "000400", owner = "root", group = "root"
          }
          "/etc/cfn/hooks.d/cfn-auto-reloader.conf" = {
            content = "[cfn-auto-reloader-hook]\ntriggers=post.update\npath=Resources.LaunchTemplate.Metadata.AWS::CloudFormation::Init\naction=${local.cfn_init_command}\nrunas=root\n"
            mode    = "000400", owner = "root", group = "root"
          }
          "/etc/systemd/system/cfn-hup.service" = {
            content = "[Unit]\nDescription=AWS CloudFormation helper daemon (cfn-hup)\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=simple\nExecStart=${local.cfn_bin}/cfn-hup\nRestart=always\n\n[Install]\nWantedBy=multi-user.target\n"
            mode    = "000644", owner = "root", group = "root"
          }
        }
        commands = {
          "01_start_cfn_hup" = { command = local.start_service["cfn-hup"] }
        }
      }
      instance = {
        files = {
          "/deploy/instance.dat" = {
            content = join("\n", concat([for k, v in local.shell_quote : v if startswith(k, "INSTANCE_")], [""]))
            mode    = "000444", owner = "root", group = "root"
          }
        }
      }
      cleanup = {
        commands = {
          "01_log_permissions" = { command = "find /var/log -type f -exec chmod g-wx,o-rwx {} +" }
        }
      }
    },
    var.swap_size_mb > 0 ? {
      swap = {
        files = {
          "/usr/local/sbin/configure-swap" = { content = file("${path.module}/files/configure-swap.sh"), mode = "000755", owner = "root", group = "root" }
        }
        commands = {
          "01_configure_swap" = { command = "/usr/local/sbin/configure-swap ${var.swap_size_mb}" }
        }
      }
    } : {},
    local.cloudwatch_agent_enabled ? {
      cloudwatch_agent = {
        files = {
          "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json" = {
            content = jsonencode(local.cloudwatch_agent_config)
            mode    = "000640", owner = "root", group = "root"
          }
        }
        commands = merge(
          {
            "01_install" = {
              command = local.is_ubuntu ? join(" && ", [
                "curl -fsSL -o /tmp/amazon-cloudwatch-agent.deb https://amazoncloudwatch-agent-${local.aws.region.name}.${local.s3_endpoint}/ubuntu/$(dpkg --print-architecture)/latest/amazon-cloudwatch-agent.deb",
                "dpkg -i -E /tmp/amazon-cloudwatch-agent.deb",
                "rm -f /tmp/amazon-cloudwatch-agent.deb",
              ]) : "${local.install} amazon-cloudwatch-agent"
              test = "! test -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl"
            }
            "03_start" = {
              command = "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
            }
          },
          # Amazon Linux 2023 keeps the system and authentication logs in the systemd journal
          # only; rsyslog writes them to /var/log/messages and /var/log/secure.
          !local.is_ubuntu && var.cloudwatch_agent.logs ? {
            "02_rsyslog" = {
              command = "${local.install} rsyslog && ${local.start_service["rsyslog"]}"
              test    = "! systemctl is-active --quiet rsyslog.service"
            }
          } : {},
        )
      }
    } : {},
    var.efs_file_system != null ? {
      efs = {
        files = {
          "/usr/local/sbin/mount-efs" = { content = file("${path.module}/files/mount-efs.sh"), mode = "000755", owner = "root", group = "root" }
        }
        commands = {
          "01_install" = {
            command = local.is_ubuntu ? "${local.install} nfs-common stunnel4" : "${local.install} amazon-efs-utils"
          }
          "02_mount" = {
            command = join(" ", [
              "/usr/local/sbin/mount-efs",
              local.is_ubuntu ? "stunnel" : "efs-utils",
              var.efs_file_system.id,
              var.efs_file_system.mount_point,
              "${var.efs_file_system.id}.efs.${local.aws.region.name}.${data.aws_partition.this.dns_suffix}",
            ])
          }
        }
      }
    } : {},
    var.codedeploy != null ? {
      codedeploy = {
        files = {
          "/deploy/codedeploy.dat" = {
            content = join("\n", concat([for k, v in local.shell_quote : v if startswith(k, "CODEDEPLOY_")], [""]))
            mode    = "000444", owner = "root", group = "root"
          }
        }
        commands = {
          "01_install" = {
            command = join(" && ", [
              local.is_ubuntu ? "${local.install} ruby-full" : "${local.install} ruby",
              "curl -fsSL -o /tmp/codedeploy-install https://aws-codedeploy-${local.aws.region.name}.${local.s3_endpoint}/latest/install",
              "chmod +x /tmp/codedeploy-install",
              "/tmp/codedeploy-install auto",
              "rm -f /tmp/codedeploy-install",
            ])
            # Skipped when the AMI already has the agent, in either place it can be.
            test = "! test -d /opt/codedeploy-agent && ! test -e /etc/init.d/codedeploy-agent"
          }
          "02_start" = { command = local.start_service["codedeploy-agent"] }
        }
      }
    } : {},
  )
  cfn_init_order = ["cfn_hup", "instance", "swap", "cloudwatch_agent", "efs", "codedeploy", "cleanup"]

  user_data = templatefile("${path.module}/files/user-data.sh.tftpl", {
    os              = var.os
    stack_name      = local.stack_name
    region          = local.aws.region.name
    update_packages = var.update_packages
    signals         = var.resource_signals.enabled
    scripts         = [for s in var.user_data_scripts : base64encode(s)]
  })

  data_device_letters = "bcdefghijklmnopqrstuvwxyz"
  block_device_mappings = concat(
    [{
      DeviceName = data.aws_ami.this.root_device_name
      Ebs = merge(
        { VolumeSize = var.volumes.root.size_gb, VolumeType = var.volumes.root.type, Encrypted = true, DeleteOnTermination = true },
        var.volumes.root.iops == null ? {} : { Iops = var.volumes.root.iops },
        var.volumes.root.throughput == null ? {} : { Throughput = var.volumes.root.throughput },
        var.volumes.kms_key_id == null ? {} : { KmsKeyId = var.volumes.kms_key_id },
      )
    }],
    [for i in range(var.volumes.data.count) : {
      DeviceName = "/dev/sd${substr(local.data_device_letters, i, 1)}"
      Ebs = merge(
        { VolumeSize = var.volumes.data.size_gb, VolumeType = var.volumes.data.type, Encrypted = true, DeleteOnTermination = true },
        var.volumes.data.iops == null ? {} : { Iops = var.volumes.data.iops },
        var.volumes.data.throughput == null ? {} : { Throughput = var.volumes.data.throughput },
        var.volumes.kms_key_id == null ? {} : { KmsKeyId = var.volumes.kms_key_id },
      )
    }],
  )

  instance_name = "${local.scope.name} - ${local.purpose.name} (${local.environment.abbr}) [${local.aws.region.name}]"
  instance_tags = merge(local.tags, { Name = local.instance_name })
  # CloudFormation counts signals by instance, while the group's sizes are in weight units:
  # wait for the fewest instances that can make up the capacity.
  signal_count   = ceil(coalesce(var.auto_scaling_group.desired_capacity, var.auto_scaling_group.min_size) / max([for t in var.instance_types : t.weighted_capacity]...))
  wait_on_signal = var.resource_signals.enabled

  template = {
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "${local.instance_name}: launch template and Auto Scaling group, managed by Terraform"
    Resources = {
      LaunchTemplate = {
        Type = "AWS::EC2::LaunchTemplate"
        Metadata = {
          "AWS::CloudFormation::Init" = merge(
            { configSets = { Bootstrap = [for c in local.cfn_init_order : c if contains(keys(local.cfn_init_configs), c)] } },
            local.cfn_init_configs,
          )
        }
        Properties = {
          LaunchTemplateName = local.name
          LaunchTemplateData = merge(
            {
              ImageId                           = local.ami_id
              IamInstanceProfile                = { Arn = aws_iam_instance_profile.this.arn }
              InstanceInitiatedShutdownBehavior = "terminate"
              Monitoring                        = { Enabled = var.detailed_monitoring }
              MetadataOptions = {
                HttpEndpoint            = "enabled"
                HttpTokens              = var.instance_metadata.http_tokens
                HttpPutResponseHopLimit = var.instance_metadata.http_put_response_hop_limit
              }
              NetworkInterfaces = [{
                DeviceIndex              = 0
                AssociatePublicIpAddress = var.associate_public_ip_address
                Groups                   = [aws_security_group.instance.id]
                DeleteOnTermination      = true
              }]
              BlockDeviceMappings = local.block_device_mappings
              # The Auto Scaling group tags the instances; these tag what it does not.
              TagSpecifications = [
                for t in ["volume", "network-interface"] : {
                  ResourceType = t
                  Tags         = [for k, v in local.instance_tags : { Key = k, Value = v }]
                }
              ]
              UserData = base64encode(local.user_data)
            },
            var.key_pair_name == null ? {} : { KeyName = var.key_pair_name },
            var.credit_specification == null ? {} : { CreditSpecification = { CpuCredits = var.credit_specification } },
          )
        }
      }
      AutoScalingGroup = merge(
        {
          Type = "AWS::AutoScaling::AutoScalingGroup"
          UpdatePolicy = {
            AutoScalingRollingUpdate = {
              MaxBatchSize                  = var.rolling_update.max_batch_size
              MinInstancesInService         = var.rolling_update.min_instances_in_service
              MinSuccessfulInstancesPercent = var.rolling_update.min_successful_instances_percent
              PauseTime                     = local.wait_on_signal ? var.resource_signals.timeout : var.rolling_update.pause_time
              WaitOnResourceSignals         = local.wait_on_signal
              SuspendProcesses              = ["HealthCheck", "ReplaceUnhealthy", "AZRebalance", "AlarmNotification", "ScheduledActions"]
            }
            AutoScalingScheduledAction = { IgnoreUnmodifiedGroupSizeProperties = true }
          }
          Properties = merge(
            {
              AutoScalingGroupName = local.name
              VPCZoneIdentifier    = var.subnet_ids
              MinSize              = tostring(var.auto_scaling_group.min_size)
              MaxSize              = tostring(var.auto_scaling_group.max_size)
              MixedInstancesPolicy = {
                InstancesDistribution = merge(
                  {
                    OnDemandAllocationStrategy          = "prioritized"
                    OnDemandBaseCapacity                = var.auto_scaling_group.on_demand_base_capacity
                    OnDemandPercentageAboveBaseCapacity = var.auto_scaling_group.on_demand_percentage_above_base_capacity
                    SpotAllocationStrategy              = var.auto_scaling_group.spot_allocation_strategy
                  },
                  var.auto_scaling_group.spot_allocation_strategy == "lowest-price" ? { SpotInstancePools = min(length(var.instance_types), 20) } : {},
                )
                LaunchTemplate = {
                  LaunchTemplateSpecification = {
                    LaunchTemplateId = { Ref = "LaunchTemplate" }
                    Version          = { "Fn::GetAtt" = ["LaunchTemplate", "LatestVersionNumber"] }
                  }
                  Overrides = [for t in var.instance_types : { InstanceType = t.type, WeightedCapacity = tostring(t.weighted_capacity) }]
                }
              }
              HealthCheckType        = coalesce(var.auto_scaling_group.health_check_type, local.lb == null ? "EC2" : "ELB")
              HealthCheckGracePeriod = var.auto_scaling_group.health_check_grace_period
              Cooldown               = tostring(var.auto_scaling_group.default_cooldown)
              MetricsCollection      = [{ Granularity = "1Minute" }]
              TerminationPolicies    = var.auto_scaling_group.termination_policies
              Tags                   = [for k, v in local.instance_tags : { Key = k, Value = v, PropagateAtLaunch = true }]
            },
            var.auto_scaling_group.desired_capacity == null ? {} : { DesiredCapacity = tostring(var.auto_scaling_group.desired_capacity) },
            var.auto_scaling_group.max_instance_lifetime == null ? {} : { MaxInstanceLifetime = var.auto_scaling_group.max_instance_lifetime },
            local.lb_v2 ? { TargetGroupARNs = [for k in keys(local.target_groups) : aws_lb_target_group.this[k].arn] } : {},
            local.lb_type == "classic" ? { LoadBalancerNames = [aws_elb.this[0].name] } : {},
          )
        },
        # With signals, creating the group waits for each instance's success signal.
        local.wait_on_signal && local.signal_count > 0 ? {
          CreationPolicy = {
            ResourceSignal            = { Count = local.signal_count, Timeout = var.resource_signals.timeout }
            AutoScalingCreationPolicy = { MinSuccessfulInstancesPercent = var.rolling_update.min_successful_instances_percent }
          }
        } : {},
      )
    }
    Outputs = {
      AutoScalingGroupName  = { Description = "The Auto Scaling group's name", Value = { Ref = "AutoScalingGroup" } }
      LaunchTemplateId      = { Description = "The launch template's ID", Value = { Ref = "LaunchTemplate" } }
      LaunchTemplateVersion = { Description = "The launch template's latest version", Value = { "Fn::GetAtt" = ["LaunchTemplate", "LatestVersionNumber"] } }
    }
  }
  template_body = jsonencode(local.template)
}

resource "aws_cloudformation_stack" "this" {
  region        = var.region
  name          = local.stack_name
  template_body = local.template_body
  tags          = local.tags

  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  # The instances use their role at boot: the Systems Manager agent registers, and the setup
  # and scripts read and write with it. Its policies must be attached before any instance
  # launches; the instance profile alone does not wait for them.
  depends_on = [aws_iam_role_policy_attachment.ssm, aws_iam_role_policy_attachment.this, aws_iam_role_policy.this]

  # No create_before_destroy: a stack whose creation failed is replaced under the same name,
  # which CloudFormation refuses while the old one exists. A details change renames the stack,
  # so the old one, with its instances, is deleted before the new one is created.
  lifecycle {
    precondition {
      condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,127}$", local.stack_name))
      error_message = "The stack name, ${local.stack_name}, built from details, must start with a letter: set details.scope_abbr to one that does."
    }

    precondition {
      condition     = length(local.user_data) <= 16384
      error_message = "The user data is ${length(local.user_data)} bytes, more than the 16 KB EC2 allows. Shorten user_data_scripts, or have a script download the rest."
    }

    precondition {
      condition     = length(local.template_body) <= 51200
      error_message = "The CloudFormation template is ${length(local.template_body)} bytes, more than the 51,200 CloudFormation accepts. Shorten user_data_scripts."
    }
  }
}
