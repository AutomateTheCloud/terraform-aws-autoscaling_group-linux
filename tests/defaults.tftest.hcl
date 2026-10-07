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

# With only the required inputs: private instances with IMDSv2, encrypted volumes, no inbound
# rules, HTTP and HTTPS out, no load balancer, logs to the module's own log groups, and an
# apply that waits for each instance's success signal.
run "secure_defaults_plan" {
  command = plan
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.instance) == 0 && length(aws_vpc_security_group_ingress_rule.instance_from_load_balancer) == 0
    error_message = "Nothing may connect to the instances by default."
  }
  assert {
    condition = (
      length(aws_vpc_security_group_egress_rule.instance) == 2 &&
      aws_vpc_security_group_egress_rule.instance["https"].from_port == 443 && aws_vpc_security_group_egress_rule.instance["https"].to_port == 443 &&
      aws_vpc_security_group_egress_rule.instance["http"].from_port == 80 && aws_vpc_security_group_egress_rule.instance["http"].cidr_ipv4 == "0.0.0.0/0" &&
      aws_vpc_security_group_egress_rule.instance["http"].ip_protocol == "tcp"
    )
    error_message = "By default the instances may connect out on HTTPS and HTTP only."
  }
  assert {
    condition     = length(aws_lb.this) == 0 && length(aws_elb.this) == 0 && length(aws_security_group.load_balancer) == 0 && length(aws_eip.load_balancer) == 0
    error_message = "No load balancer by default."
  }
  assert {
    condition     = length(aws_codedeploy_deployment_group.this) == 0 && length(aws_vpc_security_group_ingress_rule.efs) == 0
    error_message = "No CodeDeploy and no EFS by default."
  }
  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.system)) == toset(["system", "auth", "cloud-init", "cfn-init"]) && aws_cloudwatch_log_group.system["auth"].name == "/test/web/test/ec2/auth" && aws_cloudwatch_log_group.system["auth"].retention_in_days == 30
    error_message = "Four log groups, named after details, kept 30 days."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && endswith(aws_iam_role_policy_attachment.ssm[0].policy_arn, ":iam::aws:policy/AmazonSSMManagedInstanceCore") && length(aws_iam_role_policy_attachment.this) == 0
    error_message = "Only AmazonSSMManagedInstanceCore is attached by default."
  }
  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com" && jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "Only EC2 in this account may use the role."
  }
  assert {
    condition     = startswith(aws_iam_role.this.name_prefix, "test-web-test-use1-ec2-") && length(aws_iam_role.this.name_prefix) <= 38
    error_message = "The role's name prefix must be at most 38 characters."
  }
  assert {
    condition     = aws_cloudformation_stack.this.name == "test-web-test-use1" && data.aws_ssm_parameter.ami.name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "Unexpected stack name or AMI parameter."
  }
}

run "secure_defaults_template" {
  command = apply
  assert {
    condition     = local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.MetadataOptions.HttpTokens == "required" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.MetadataOptions.HttpPutResponseHopLimit == 2
    error_message = "IMDSv2 must be required."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.NetworkInterfaces[0].AssociatePublicIpAddress == false && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.NetworkInterfaces[0].Groups == ["sg-0123456789abcdef0"]
    error_message = "The instances must get no public IP address, and the module's security group."
  }
  assert {
    condition     = alltrue([for b in local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings : b.Ebs.Encrypted && b.Ebs.DeleteOnTermination]) && length(local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings) == 1 && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].DeviceName == "/dev/xvda" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.VolumeType == "gp3" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.BlockDeviceMappings[0].Ebs.VolumeSize == 20
    error_message = "One encrypted 20 GiB gp3 root volume on the AMI's root device."
  }
  assert {
    condition     = !contains(keys(local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData), "KeyName") && !contains(keys(local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData), "CreditSpecification") && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.ImageId == "ami-0123456789abcdef0" && local.template.Resources.LaunchTemplate.Properties.LaunchTemplateData.Monitoring.Enabled
    error_message = "No key pair and no credit specification by default; the AMI from the parameter; detailed monitoring on."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.Properties.MinSize == "1" && local.template.Resources.AutoScalingGroup.Properties.MaxSize == "1" && !contains(keys(local.template.Resources.AutoScalingGroup.Properties), "DesiredCapacity") && local.template.Resources.AutoScalingGroup.Properties.HealthCheckType == "EC2" && local.template.Resources.AutoScalingGroup.Properties.VPCZoneIdentifier == tolist(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "One instance across the subnets, EC2 health checks."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.Properties.MixedInstancesPolicy.InstancesDistribution.OnDemandPercentageAboveBaseCapacity == 100 && local.template.Resources.AutoScalingGroup.Properties.MixedInstancesPolicy.InstancesDistribution.SpotAllocationStrategy == "price-capacity-optimized"
    error_message = "On-Demand only by default."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.CreationPolicy.ResourceSignal.Count == 1 && local.template.Resources.AutoScalingGroup.CreationPolicy.ResourceSignal.Timeout == "PT15M" && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.WaitOnResourceSignals && local.template.Resources.AutoScalingGroup.UpdatePolicy.AutoScalingRollingUpdate.PauseTime == "PT15M"
    error_message = "Creating and updating the group must wait for the instances' signals."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].configSets.Bootstrap == ["cfn_hup", "instance", "swap", "cloudwatch_agent", "cleanup"]
    error_message = "Unexpected configs by default."
  }
  assert {
    condition     = local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].swap.commands["01_configure_swap"].command == "/usr/local/sbin/configure-swap 2048"
    error_message = "A 2048 MiB swap file by default."
  }
  assert {
    condition     = toset([for f in jsondecode(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.files["/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"].content).logs.logs_collected.files.collect_list : "${f.file_path}=${f.log_group_name}"]) == toset(["/var/log/messages=/test/web/test/ec2/system", "/var/log/secure=/test/web/test/ec2/auth", "/var/log/cloud-init-output.log=/test/web/test/ec2/cloud-init", "/var/log/cfn-init.log=/test/web/test/ec2/cfn-init"])
    error_message = "The agent must send the Amazon Linux logs to the module's log groups."
  }
  assert {
    condition     = !contains(keys(jsondecode(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.files["/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"].content)), "metrics") && contains(keys(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].cloudwatch_agent.commands), "02_rsyslog")
    error_message = "No custom metrics by default; rsyslog on Amazon Linux 2023 for the log files."
  }
  assert {
    condition     = strcontains(local.user_data, "dnf -y upgrade") && strcontains(local.user_data, "/opt/aws/bin/cfn-signal --exit-code") == false && strcontains(local.user_data, "\"$CFN_BIN/cfn-signal\" --exit-code \"$1\"") && strcontains(local.user_data, "CFN_BIN=/opt/aws/bin")
    error_message = "Amazon Linux user data: update packages, run cfn-init, then signal."
  }
  assert {
    condition     = output.metadata.auto_scaling_group.name == "test-web-test-use1" && output.metadata.launch_template.id == "lt-0123456789abcdef0" && output.metadata.lb == null && output.metadata.elb == null && output.metadata.codedeploy_deployment_group == null
    error_message = "Unexpected metadata."
  }
}
