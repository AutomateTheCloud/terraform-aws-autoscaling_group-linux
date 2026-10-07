# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Offline tests: every provider is mocked, so no AWS account is used.
mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1", description = "US East (N. Virginia)" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_service_principal" {
    defaults = { name = "ec2.amazonaws.com" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0", root_device_name = "/dev/xvda", architecture = "x86_64" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0", arn = "arn:aws:ec2:us-east-1:111111111111:security-group/sg-0123456789abcdef0" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/test-web-test-use1-ec2-1", name = "test-web-test-use1-ec2-1", id = "test-web-test-use1-ec2-1" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111111111111:instance-profile/test-web-test-use1-ec2-1" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:/test/web/test/ec2/system" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/test/0123456789abcdef" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/test/0123456789abcdef" }
  }
  mock_resource "aws_eip" {
    defaults = { id = "eipalloc-0123456789abcdef0" }
  }
  mock_resource "aws_cloudformation_stack" {
    defaults = { outputs = { AutoScalingGroupName = "test-web-test-use1", LaunchTemplateId = "lt-0123456789abcdef0", LaunchTemplateVersion = "1" } }
  }
}

variables {
  details        = { scope = "Test", purpose = "Web", environment = "test" }
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  os             = "al2023"
  instance_types = [{ type = "t3.micro" }]
}

run "ubuntu_with_everything" {
  command = apply
  variables {
    os                          = "ubuntu24"
    architecture                = "arm64"
    key_pair_name               = "admin"
    credit_specification        = "standard"
    detailed_monitoring         = false
    associate_public_ip_address = true
    update_packages             = false
    swap_size_mb                = 0
    instance_metadata           = { http_tokens = "optional", http_put_response_hop_limit = 1 }
    instance_types              = [{ type = "t4g.small", weighted_capacity = 1 }, { type = "t4g.medium", weighted_capacity = 2 }]
    auto_scaling_group = {
      min_size                 = 2, max_size = 6, desired_capacity = 4, on_demand_base_capacity = 1, on_demand_percentage_above_base_capacity = 50
      spot_allocation_strategy = "lowest-price", max_instance_lifetime = 604800, health_check_grace_period = 600, default_cooldown = 120
      termination_policies     = ["NewestInstance"]
    }
    rolling_update   = { max_batch_size = 2, min_instances_in_service = 2, min_successful_instances_percent = 50 }
    resource_signals = { timeout = "PT30M" }
    volumes = {
      root       = { size_gb = 30, type = "io2", iops = 4000 }
      data       = { count = 2, size_gb = 100, type = "gp3", iops = 4000, throughput = 250 }
      kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/0123abcd-0123-0123-0123-0123456789ab"
    }
    cloudwatch_agent  = { metrics = true, log_retention_in_days = 90, log_kms_key_id = "arn:aws:kms:us-east-1:111111111111:key/logs" }
    efs_file_system   = { id = "fs-0123456789abcdef0", security_group_id = "sg-0fedcba9876543210", mount_point = "/mnt/shared" }
    user_data_scripts = ["#!/bin/bash\necho 'first' > /tmp/first\n", "#!/usr/bin/env python3\nprint(\"second\")\n"]
    codedeploy = {
      application_name = "web-app"
      service_role_arn = "arn:aws:iam::111111111111:role/codedeploy"
      revision_bucket  = { arn = "arn:aws:s3:::web-app-revisions", path = "releases/" }
      log_groups       = ["application", "access-log"]
    }
  }

  # The launch template
  assert {
    condition     = data.aws_ssm_parameter.ami.name == "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
    error_message = "Expected the Ubuntu 24.04 arm64 parameter."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.KeyName == "admin" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.CreditSpecification.CpuCredits == "standard" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.Monitoring.Enabled == false
    error_message = "Key pair, credit specification and monitoring must follow the inputs."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.NetworkInterfaces[0].AssociatePublicIpAddress && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.MetadataOptions.HttpTokens == "optional" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.MetadataOptions.HttpPutResponseHopLimit == 1
    error_message = "Public address and metadata options must follow the inputs."
  }
  assert {
    condition = (
      [for b in local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings : b.DeviceName] == ["/dev/xvda", "/dev/sdb", "/dev/sdc"] &&
      local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.Iops == 4000 &&
      local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[2].Ebs.Throughput == 250 &&
      alltrue([for b in local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings : b.Ebs.KmsKeyId == "arn:aws:kms:us-east-1:111111111111:key/0123abcd-0123-0123-0123-0123456789ab" && b.Ebs.Encrypted])
    )
    error_message = "The root and two data volumes, encrypted with the key."
  }

  # The Auto Scaling group
  assert {
    condition = (
      local.template.Resources.AutoScalingGroup.Properties.DesiredCapacity == "4" &&
      local.template.Resources.AutoScalingGroup.Properties.MaxInstanceLifetime == 604800 &&
      local.template.Resources.AutoScalingGroup.Properties.MixedInstancesPolicy.InstancesDistribution.SpotInstancePools == 2 &&
      local.template.Resources.AutoScalingGroup.Properties.MixedInstancesPolicy.InstancesDistribution.OnDemandBaseCapacity == 1 &&
      [for o in local.template.Resources.AutoScalingGroup.Properties.MixedInstancesPolicy.LaunchTemplate.Overrides : "${o.InstanceType}=${o.WeightedCapacity}"] == ["t4g.small=1", "t4g.medium=2"] &&
      local.template.Resources.AutoScalingGroup.Properties.TerminationPolicies == tolist(["NewestInstance"]) &&
      local.template.Resources.AutoScalingGroup.Properties.Cooldown == "120"
    )
    error_message = "The group's settings must follow auto_scaling_group."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.CreationPolicy.ResourceSignal.Count == 2 && local.template.Resources.AutoScalingGroup.CreationPolicy.ResourceSignal.Timeout == "PT30M" && local.template.Resources.AutoScalingGroup.CreationPolicy.AutoScalingCreationPolicy.MinSuccessfulInstancesPercent == 50
    error_message = "Creation waits for the fewest instances that make up desired_capacity: 4 units, largest weight 2."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.MaxBatchSize == 2 && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.MinInstancesInService == 2 && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.PauseTime == "PT30M"
    error_message = "The rolling update must follow rolling_update and resource_signals."
  }

  # Boot setup
  assert {
    condition     = local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].configSets.Bootstrap == ["cfn_hup", "instance", "cloudwatch_agent", "efs", "codedeploy", "cleanup"]
    error_message = "No swap with swap_size_mb = 0; EFS and CodeDeploy configs."
  }
  assert {
    condition     = strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].efs.commands["02_mount"].command, "/usr/local/sbin/mount-efs stunnel fs-0123456789abcdef0 /mnt/shared fs-0123456789abcdef0.efs.us-east-1.amazonaws.com") && strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].efs.commands["01_install"].command, "install nfs-common stunnel4")
    error_message = "Ubuntu mounts EFS through stunnel."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.files["/deploy/codedeploy.dat"].content == "CODEDEPLOY_APPLICATION_NAME='web-app'\nCODEDEPLOY_LOG_GROUP_ACCESS_LOG='/test/web/test/application/web-app/access-log'\nCODEDEPLOY_LOG_GROUP_APPLICATION='/test/web/test/application/web-app/application'\n"
    error_message = "Unexpected codedeploy.dat."
  }
  assert {
    condition     = strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["01_install"].command, "install ruby-full && curl -fsSL -o /tmp/codedeploy-install https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install")
    error_message = "The CodeDeploy agent is installed from the Region's bucket."
  }
  assert {
    condition = (
      jsondecode(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.files["/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"].content).metrics.namespace == "CWAgent" &&
      !contains(keys(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.commands), "02_rsyslog") &&
      strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.commands["01_install"].command, "https://amazoncloudwatch-agent-us-east-1.s3.us-east-1.amazonaws.com/ubuntu/$(dpkg --print-architecture)/latest/amazon-cloudwatch-agent.deb")
    )
    error_message = "Ubuntu installs the agent's package from the Region's bucket, with metrics."
  }
  assert {
    condition = (
      strcontains(local.user_data, "CFN_BIN=/opt/aws/cfn-bootstrap/bin") && !strcontains(local.user_data, " upgrade") &&
      strcontains(local.user_data, "echo '${base64encode("#!/bin/bash\necho 'first' > /tmp/first\n")}' | base64 -d > /var/lib/autoscaling_group-linux/user-data-1") &&
      strcontains(local.user_data, "/var/lib/autoscaling_group-linux/user-data-2") &&
      strcontains(local.user_data, "signal 0")
    )
    error_message = "Ubuntu user data: no upgrade, both scripts, then the success signal."
  }

  # Logs, permissions and rules
  assert {
    condition     = aws_cloudwatch_log_group.codedeploy["access-log"].name == "/test/web/test/application/web-app/access-log" && aws_cloudwatch_log_group.codedeploy["access-log"].retention_in_days == 90 && aws_cloudwatch_log_group.system["system"].kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/logs"
    error_message = "CodeDeploy log groups, retention and key."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.efs[0].security_group_id == "sg-0fedcba9876543210" && aws_vpc_security_group_ingress_rule.efs[0].referenced_security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.efs[0].from_port == 2049
    error_message = "NFS into the file system's group from the instances."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.instance_to_efs[0].security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_egress_rule.instance_to_efs[0].referenced_security_group_id == "sg-0fedcba9876543210" && aws_vpc_security_group_egress_rule.instance_to_efs[0].to_port == 2049
    error_message = "NFS out of the instances' group to the file system."
  }
  assert {
    condition     = aws_codedeploy_deployment_group.this[0].app_name == "web-app" && aws_codedeploy_deployment_group.this[0].autoscaling_groups == toset(["test-web-test-use1"]) && aws_codedeploy_deployment_group.this[0].deployment_style[0].deployment_option == "WITHOUT_TRAFFIC_CONTROL" && aws_codedeploy_deployment_group.this[0].deployment_config_name == "CodeDeployDefault.OneAtATime"
    error_message = "A deployment group for the Auto Scaling group, without traffic control."
  }
  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "The role gets the module's policy."
  }
}

# The role's policy names only what the module created or was given.
run "role_policy" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  variables {
    cloudwatch_agent = { metrics = true }
    codedeploy = {
      application_name = "web-app"
      service_role_arn = "arn:aws:iam::111111111111:role/codedeploy"
      revision_bucket  = { arn = "arn:aws:s3:::web-app-revisions", path = "/releases/" }
    }
    iam_role = {
      ssm_managed_instance_core = false
      source_policy_documents   = ["{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::data/*\"}]}"]
      managed_policy_arns       = { app = "arn:aws:iam::111111111111:policy/app" }
    }
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "ReadRevisions"]) == toset(["arn:aws:s3:::web-app-revisions/releases/*"])
    error_message = "The revisions may be read only under revision_path."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.condition if s.sid == "PutAgentMetrics"]) != null && contains(flatten([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "WriteLogs"]), "logs:PutLogEvents")
    error_message = "Metrics in the agent's namespace and logs to the module's groups."
  }
  assert {
    condition     = !contains(flatten([for s in data.aws_iam_policy_document.this.statement : s.actions]), "logs:CreateLogGroup")
    error_message = "The instances must not create log groups."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 0 && aws_iam_role_policy_attachment.this["app"].policy_arn == "arn:aws:iam::111111111111:policy/app" && data.aws_iam_policy_document.this.source_policy_documents == tolist(["{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::data/*\"}]}"])
    error_message = "The caller's policies, and no Systems Manager policy when turned off."
  }
}

# No logs, no metrics, no Systems Manager and no grants: no inline policy at all.
run "no_role_policy" {
  command = plan
  variables {
    cloudwatch_agent = { logs = false }
    iam_role         = { ssm_managed_instance_core = false }
  }
  assert {
    condition     = length(aws_iam_role_policy.this) == 0 && length(aws_cloudwatch_log_group.system) == 0
    error_message = "No log groups and no inline policy."
  }
}

run "instance_rules" {
  command = plan
  variables {
    security_group_ingress = {
      ssh   = { from_port = 22, cidr_ipv4 = "10.0.0.0/8", description = "SSH from the corporate network" }
      ping  = { ip_protocol = "icmp", from_port = 8, cidr_ipv4 = "10.0.0.0/8" }
      ipv6  = { from_port = 443, to_port = 444, cidr_ipv6 = "2600:1f18:1234:5600::/56" }
      peers = { ip_protocol = "-1", security_group_id = "sg-0aaaaaaaaaaaaaaaa" }
    }
    security_group_egress = {
      all = { ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
    }
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance["ssh"].from_port == 22 && aws_vpc_security_group_ingress_rule.instance["ssh"].to_port == 22 && aws_vpc_security_group_ingress_rule.instance["ssh"].ip_protocol == "tcp" && aws_vpc_security_group_ingress_rule.instance["ssh"].description == "SSH from the corporate network"
    error_message = "TCP ports default to one port."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance["ping"].from_port == 8 && aws_vpc_security_group_ingress_rule.instance["ping"].to_port == -1 && aws_vpc_security_group_ingress_rule.instance["ping"].description == "ping"
    error_message = "ICMP code defaults to -1, description to the key."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance["ipv6"].cidr_ipv6 == "2600:1f18:1234:5600::/56" && aws_vpc_security_group_ingress_rule.instance["ipv6"].referenced_security_group_id == null && aws_vpc_security_group_ingress_rule.instance["ipv6"].to_port == 444
    error_message = "An IPv6 range must be sent as one."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance["peers"].from_port == null && aws_vpc_security_group_ingress_rule.instance["peers"].referenced_security_group_id == "sg-0aaaaaaaaaaaaaaaa"
    error_message = "Every protocol takes no ports."
  }
  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.instance) == ["all"] && aws_vpc_security_group_egress_rule.instance["all"].ip_protocol == "-1"
    error_message = "Setting security_group_egress replaces the defaults."
  }
}

# Without signals, nothing waits, and a rolling update pauses for pause_time.
run "no_signals" {
  command = apply
  variables {
    resource_signals = { enabled = false }
    rolling_update   = { pause_time = "PT5M" }
  }
  assert {
    condition     = !contains(keys(local.template.Resources.AutoScalingGroup), "CreationPolicy") && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.WaitOnResourceSignals == false && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.PauseTime == "PT5M"
    error_message = "No creation policy, and a pause between batches."
  }
  assert {
    condition     = !strcontains(local.user_data, "cfn-signal")
    error_message = "No signals sent."
  }
}

# A group that starts empty waits for no signal.
run "empty_group" {
  command = apply
  variables {
    auto_scaling_group = { min_size = 0, max_size = 4 }
  }
  assert {
    condition     = !contains(keys(local.template.Resources.AutoScalingGroup), "CreationPolicy") && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.WaitOnResourceSignals
    error_message = "No signals to wait for at creation; updates still wait."
  }
}

# Names and values with quotes and dollar signs reach the instances as they are.
run "quoting" {
  command = apply
  variables {
    details = { scope = "O'Brien \"Labs\"", purpose = "Web $HOME", environment = "test", additional_tags = { Note = "a \"quoted\" value" } }
  }
  assert {
    condition     = strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].instance.files["/deploy/instance.dat"].content, "\nINSTANCE_SCOPE_NAME='O'\\''Brien \"Labs\"'\n")
    error_message = "Values must be single-quoted for the shell."
  }
  assert {
    condition     = one([for t in jsondecode(aws_cloudformation_stack.this.template_body).Resources.AutoScalingGroup.Properties.Tags : t.Value if t.Key == "Note"]) == "a \"quoted\" value" && aws_cloudformation_stack.this.name == "obrienlabs-webhome-test-use1"
    error_message = "Tags must survive the template."
  }
}

# Parameter Store: the paths and everything under them, for reading by name or by path, and
# decryption with the given keys only through Parameter Store.
run "parameter_store" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  variables {
    cloudwatch_agent = { logs = false }
    parameter_store = {
      paths        = ["/secrets/test/web/test", "/secrets/test/web/global"]
      kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/0123abcd-0123-0123-0123-0123456789ab"]
    }
  }
  assert {
    condition = one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "ReadParameters"]) == toset([
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/test",
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/test/*",
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/global",
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/global/*",
    ])
    error_message = "Each path and everything under it."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "ReadParameters"]) == toset(["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"])
    error_message = "Reading by name and by path."
  }
  assert {
    condition = toset(flatten([for s in data.aws_iam_policy_document.this.statement : [for c in s.condition : c.values] if s.sid == "DecryptParameters"])) == toset([
      "ssm.us-east-1.amazonaws.com",
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/test/*",
      "arn:aws:ssm:us-east-1:111111111111:parameter/secrets/test/web/global/*",
    ])
    error_message = "Decryption only through Parameter Store in the Region, and only of parameters under the paths."
  }
  assert {
    condition     = length(aws_iam_role_policy.this) == 1
    error_message = "Parameter Store access alone needs the inline policy."
  }
}

# Signals are counted by instance, sizes by weight: wait for the fewest instances that fill it.
run "signals_with_weights" {
  command = apply
  variables {
    instance_types     = [{ type = "t3.micro", weighted_capacity = 1 }, { type = "t3.small", weighted_capacity = 2 }]
    auto_scaling_group = { min_size = 5, max_size = 8 }
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.CreationPolicy.ResourceSignal.Count == 3
    error_message = "5 units with a largest weight of 2 need at least 3 instances."
  }
}

# Systems Manager by default: the managed policy, the agent's AWS-owned buckets in the
# instances' Region, and what Session Manager logging needs.
run "systems_manager_by_default" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  variables {
    cloudwatch_agent = { logs = false }
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && length(aws_iam_role_policy.this) == 1
    error_message = "The managed policy and the inline policy by default."
  }
  assert {
    condition = one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "SSMAgentBuckets"]) == toset([
      "arn:aws:s3:::aws-ssm-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-packages-us-east-1/*",
      "arn:aws:s3:::us-east-1-birdwatcher-prod/*",
      "arn:aws:s3:::aws-windows-downloads-us-east-1/*",
      "arn:aws:s3:::patch-baseline-snapshot-us-east-1/*",
      "arn:aws:s3:::patch-baseline-snapshot-us-east-1-*/*",
      "arn:aws:s3:::aws-patch-manager-us-east-1-*/*",
    ])
    error_message = "The SSM Agent buckets of the instances' Region."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "SSMAgentBuckets"]) == toset(["s3:GetObject"])
    error_message = "Reading only."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "SessionManagerLogs"]) == toset(["arn:aws:logs:us-east-1:111111111111:log-group:*", "arn:aws:logs:us-east-1:111111111111:log-group:*:log-stream:*"])
    error_message = "Session logging to log groups in this account and Region."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "SessionManagerLogBucketEncryption"]) == toset(["s3:GetEncryptionConfiguration"])
    error_message = "Checking the session log bucket's encryption."
  }
  assert {
    condition     = length([for s in data.aws_iam_policy_document.this.statement : s if contains(["SessionManagerLogBucket", "SessionManagerKeys"], coalesce(s.sid, "-"))]) == 0
    error_message = "No S3 log bucket or KMS key grants unless asked for."
  }
}

# Without Systems Manager, none of its statements.
run "systems_manager_off" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  variables {
    iam_role = { ssm_managed_instance_core = false }
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 0 && length([for s in data.aws_iam_policy_document.this.statement : s if startswith(coalesce(s.sid, "-"), "SSM") || startswith(coalesce(s.sid, "-"), "SessionManager")]) == 0
    error_message = "No Systems Manager permissions when turned off."
  }
}

run "session_manager_log_bucket_and_keys" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  variables {
    session_manager = {
      log_bucket   = { arn = "arn:aws:s3:::session-logs", prefix = "/sessions/" }
      kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/0123abcd-0123-0123-0123-0123456789ab"]
    }
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "SessionManagerLogBucket"]) == toset(["arn:aws:s3:::session-logs/sessions/*"])
    error_message = "Writing session logs only under the prefix."
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "SessionManagerKeys"]) == toset(["kms:Decrypt", "kms:GenerateDataKey"])
    error_message = "Using the session keys."
  }
}

# GovCloud: the buckets in the Region's partition.
run "systems_manager_other_partition" {
  command = plan
  override_data {
    target = data.aws_region.this
    values = { region = "us-gov-west-1", description = "AWS GovCloud (US-West)" }
  }
  override_data {
    target = data.aws_partition.this
    values = { partition = "aws-us-gov", dns_suffix = "amazonaws.com" }
  }
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  assert {
    condition     = contains(one([for s in data.aws_iam_policy_document.this.statement : s.resources if s.sid == "SSMAgentBuckets"]), "arn:aws-us-gov:s3:::amazon-ssm-us-gov-west-1/*")
    error_message = "Expected the GovCloud bucket ARN."
  }
}
