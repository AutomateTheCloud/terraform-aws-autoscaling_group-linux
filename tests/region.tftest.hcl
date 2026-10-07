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

run "provider_region_by_default" {
  command = plan
  assert {
    condition     = output.metadata.aws.region.name == "us-east-1" && output.metadata.aws.region.abbr == "use1"
    error_message = "Expected the provider's Region."
  }
}

# region reaches every resource and data source that accepts it, with no providers block.
run "region_reaches_every_resource" {
  command = apply
  variables {
    region          = "us-west-2"
    efs_file_system = { id = "fs-0123456789abcdef0", security_group_id = "sg-0fedcba9876543210" }
    codedeploy      = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd", log_groups = ["app"] }
    security_group_ingress = {
      ssh = { from_port = 22, cidr_ipv4 = "10.0.0.0/8" }
    }
    load_balancer = {
      type                   = "network"
      subnet_ids             = ["subnet-0aaaaaaaaaaaaaaaa"]
      internal               = false
      elastic_ip_addresses   = true
      security_group_ingress = { web = { from_port = 80, cidr_ipv4 = "10.0.0.0/8" } }
      target_groups          = { web = { port = 80, protocol = "TCP" } }
      listeners              = { web = { port = 80, protocol = "TCP", target_group = "web" } }
    }
  }
  assert {
    condition = alltrue([for r in concat(
      [data.aws_region.this.region, data.aws_service_principal.ec2.region, data.aws_ssm_parameter.ami.region, data.aws_ami.this.region],
      [aws_cloudformation_stack.this.region, aws_security_group.instance.region, aws_security_group.load_balancer[0].region, aws_lb.this[0].region, aws_eip.load_balancer[0].region],
      [aws_codedeploy_deployment_group.this[0].region, aws_vpc_security_group_ingress_rule.efs[0].region, aws_vpc_security_group_egress_rule.instance_to_efs[0].region],
      [for r in values(aws_lb_target_group.this) : r.region], [for r in values(aws_lb_listener.this) : r.region],
      [for r in values(aws_cloudwatch_log_group.system) : r.region], [for r in values(aws_cloudwatch_log_group.codedeploy) : r.region],
      [for r in values(aws_vpc_security_group_ingress_rule.instance) : r.region], [for r in values(aws_vpc_security_group_egress_rule.instance) : r.region],
      [for r in values(aws_vpc_security_group_ingress_rule.instance_from_load_balancer) : r.region], [for r in values(aws_vpc_security_group_egress_rule.load_balancer_to_instance) : r.region],
      [for r in values(aws_vpc_security_group_ingress_rule.load_balancer) : r.region],
    ) : r == "us-west-2"])
    error_message = "Every regional resource and data source must get region."
  }
}

run "region_reaches_classic_resources" {
  command = plan
  variables {
    region = "us-west-2"
    load_balancer = {
      type              = "classic"
      subnet_ids        = ["subnet-0aaaaaaaaaaaaaaaa"]
      classic_listeners = { https = { lb_port = 443, lb_protocol = "HTTPS", instance_port = 80, instance_protocol = "HTTP", ssl_certificate_id = "arn:aws:acm:us-west-2:111111111111:certificate/x" } }
    }
  }
  assert {
    condition     = aws_elb.this[0].region == "us-west-2" && aws_lb_ssl_negotiation_policy.this["https"].region == "us-west-2"
    error_message = "The Classic Load Balancer and its policy must get region."
  }
}

# Newer Regions: the abbreviation is computed, not looked up in a table, so the plan works.
run "region_newer" {
  command = plan
  override_data {
    target = data.aws_region.this
    values = { region = "ap-southeast-7", description = "Asia Pacific (Thailand)" }
  }
  assert {
    condition     = output.metadata.aws.region.abbr == "apse7" && aws_cloudformation_stack.this.name == "test-web-test-apse7"
    error_message = "Expected the abbreviation apse7."
  }
}

run "region_mexico" {
  command = plan
  override_data {
    target = data.aws_region.this
    values = { region = "mx-central-1", description = "Mexico (Central)" }
  }
  assert {
    condition     = output.metadata.aws.region.abbr == "mxc1"
    error_message = "Expected the abbreviation mxc1."
  }
}

# GovCloud: no hard-coded partition, and the Region's own service principal and DNS suffix.
run "other_partition" {
  command = apply
  override_data {
    target = data.aws_region.this
    values = { region = "us-gov-west-1", description = "AWS GovCloud (US-West)" }
  }
  override_data {
    target = data.aws_partition.this
    values = { partition = "aws-us-gov", dns_suffix = "amazonaws.com" }
  }
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws-us-gov:iam::111111111111:role/cd" }
  }
  assert {
    condition     = aws_iam_role_policy_attachment.ssm[0].policy_arn == "arn:aws-us-gov:iam::aws:policy/AmazonSSMManagedInstanceCore" && output.metadata.aws.region.abbr == "ugw1"
    error_message = "The managed policy must be in the Region's partition."
  }
  assert {
    condition     = strcontains(local.template.Resources.LaunchTemplate.Metadata["AWS::CloudFormation::Init"].codedeploy.commands["01_install"].command, "https://aws-codedeploy-us-gov-west-1.s3.us-gov-west-1.amazonaws.com/latest/install")
    error_message = "The CodeDeploy agent comes from the Region's bucket."
  }
}
