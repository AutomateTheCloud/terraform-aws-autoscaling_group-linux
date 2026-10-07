# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Mistakes a module like this one easily makes, each with the test that guards against it.
# Others are tested elsewhere:
# - An AMI lookup for one operating system tested for another: validations.tftest.hcl,
#   os_amzn2 (Amazon Linux 2 is not offered).
# - Plans failing when optional inputs are left out: defaults.tftest.hcl plans with only the
#   required inputs.
# - IPv6 ranges sent as security group IDs: features.tftest.hcl, instance_rules.
# - A source security group created in the same run failing for_each: same_run.tftest.hcl.
# - A load balancer internet-facing unless internal is set: load_balancers.tftest.hcl.
# - The EFS egress rule on the file system's group instead of the instances':
#   features.tftest.hcl, ubuntu_with_everything.
# - IMDSv1 allowed: defaults.tftest.hcl.
# - "arn:aws:" hard-coded: region.tftest.hcl, other_partition.
# - Load balancer names over 32 characters: load_balancers.tftest.hcl, long_names.
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

# The CodeDeploy agent is not in the Amazon Linux 2023 AMI: it must be installed before its
# service is started.
run "codedeploy_agent_installed_on_al2023" {
  command = apply
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd" }
  }
  assert {
    condition     = startswith(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["01_install"].command, "dnf -y install ruby && curl -fsSL -o /tmp/codedeploy-install https://aws-codedeploy-us-east-1.s3.us-east-1.amazonaws.com/latest/install") && local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["02_start"].command == "systemctl daemon-reload && systemctl enable codedeploy-agent && systemctl start codedeploy-agent && systemctl is-active --quiet codedeploy-agent"
    error_message = "The agent must be installed, then started."
  }
}

# The root volume uses the AMI's own root device. A hard-coded /dev/sda1 or /dev/xvda gives an
# AMI with another root device an extra empty volume instead of a bigger root volume.
run "root_device_from_the_ami" {
  command = apply
  override_data {
    target = data.aws_ami.this
    values = { root_device_name = "/dev/sda1" }
  }
  variables {
    ami_id = "ami-0aaaaaaaaaaaaaaaa"
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].DeviceName == "/dev/sda1" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.ImageId == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "The root volume must use the AMI's root device, and ami_id the given AMI."
  }
}

# cfn-hup must run cfn-init with the config set: without one, cfn-init does nothing, and
# metadata changes never reach running instances.
run "cfn_hup_runs_the_config_set" {
  command = apply
  assert {
    condition     = strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cfn_hup.files["/etc/cfn/hooks.d/cfn-auto-reloader.conf"].content, "action=/opt/aws/bin/cfn-init -v --stack test-web-test-use1 --resource LaunchTemplate --region us-east-1 --configsets Bootstrap\n")
    error_message = "cfn-hup must run the Bootstrap config set."
  }
}

# The instances may write only to the module's own log groups, and create none.
run "logs_limited_to_the_module" {
  command = plan
  override_data {
    target = data.aws_iam_policy_document.this
    values = { json = "{}" }
  }
  assert {
    condition     = one([for s in data.aws_iam_policy_document.this.statement : s.actions if s.sid == "WriteLogs"]) == toset(["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"])
    error_message = "Only stream and event writes."
  }
}

# A target group with a fixed name could not be replaced (port, protocol) while still in use:
# the new one must be created first, under a new name.
run "target_group_names_change_on_replacement" {
  command = plan
  variables {
    load_balancer = {
      type          = "network"
      subnet_ids    = ["subnet-0aaaaaaaaaaaaaaaa"]
      target_groups = { web = { port = 80, protocol = "TCP" } }
      listeners     = { web = { port = 80, protocol = "TCP", target_group = "web" } }
    }
  }
  assert {
    condition     = random_id.target_group["web"].keepers == tomap({ vpc_id = "vpc-0123456789abcdef0", port = "80", protocol = "TCP", protocol_version = "-" })
    error_message = "The name suffix must change with every input that replaces the group."
  }
}

# `systemctl enable --now` exits 0 without starting a CodeDeploy agent that the AMI ships as a
# SysV init script, and every launch deployment then waits for it (seen in AWS). Each service is
# started, then checked, and the install is skipped for either kind of existing agent.
run "services_started_and_checked" {
  command = apply
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd" }
  }
  assert {
    condition = alltrue([for c in [
      local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cfn_hup.commands["01_start_cfn_hup"].command,
      local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["02_start"].command,
      local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.commands["02_rsyslog"].command,
    ] : strcontains(c, "systemctl daemon-reload && systemctl enable ") && strcontains(c, " && systemctl is-active --quiet ") && !strcontains(c, "--now")])
    error_message = "Every service is reloaded, enabled, started and checked."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["01_install"].test == "! test -d /opt/codedeploy-agent && ! test -e /etc/init.d/codedeploy-agent"
    error_message = "The install is skipped when the agent exists either way."
  }
}
