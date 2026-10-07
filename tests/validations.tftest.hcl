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

# Each validation refuses what AWS or the provider would refuse, at plan time.
run "details_empty_scope" {
  command = plan
  variables {
    details = { scope = " ", purpose = "Web", environment = "test" }
  }
  expect_failures = [var.details]
}

run "details_empty_purpose" {
  command = plan
  variables {
    details = { scope = "Test", purpose = "", environment = "test" }
  }
  expect_failures = [var.details]
}

run "details_empty_environment" {
  command = plan
  variables {
    details = { scope = "Test", purpose = "Web", environment = "" }
  }
  expect_failures = [var.details]
}

run "os_amzn2" {
  command = plan
  variables {
    os = "amzn2"
  }
  expect_failures = [var.os]
}

run "architecture" {
  command = plan
  variables {
    architecture = "i386"
  }
  expect_failures = [var.architecture]
}

run "ami_id" {
  command = plan
  variables {
    ami_id = "ami-XYZ"
  }
  expect_failures = [var.ami_id]
}

run "vpc_id" {
  command = plan
  variables {
    vpc_id = "vpc-xyz"
  }
  expect_failures = [var.vpc_id]
}

run "subnet_ids_empty" {
  command = plan
  variables {
    subnet_ids = []
  }
  expect_failures = [var.subnet_ids]
}

run "subnet_ids_duplicate" {
  command = plan
  variables {
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef0"]
  }
  expect_failures = [var.subnet_ids]
}

run "instance_types_empty" {
  command = plan
  variables {
    instance_types = []
  }
  expect_failures = [var.instance_types]
}

run "instance_types_duplicate" {
  command = plan
  variables {
    instance_types = [{ type = "t3.micro" }, { type = "t3.micro" }]
  }
  expect_failures = [var.instance_types]
}

run "instance_types_bad" {
  command = plan
  variables {
    instance_types = [{ type = "large" }]
  }
  expect_failures = [var.instance_types]
}

run "instance_types_weight" {
  command = plan
  variables {
    instance_types = [{ type = "t3.micro", weighted_capacity = 0 }]
  }
  expect_failures = [var.instance_types]
}

run "asg_min_over_max" {
  command = plan
  variables {
    auto_scaling_group = { min_size = 3, max_size = 2 }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_desired_out_of_range" {
  command = plan
  variables {
    auto_scaling_group = { min_size = 1, max_size = 2, desired_capacity = 3 }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_fraction" {
  command = plan
  variables {
    auto_scaling_group = { min_size = 1.5, max_size = 2 }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_percentage" {
  command = plan
  variables {
    auto_scaling_group = { on_demand_percentage_above_base_capacity = 101 }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_spot_strategy" {
  command = plan
  variables {
    auto_scaling_group = { spot_allocation_strategy = "cheapest" }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_health_check_type" {
  command = plan
  variables {
    auto_scaling_group = { health_check_type = "elb" }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_lifetime" {
  command = plan
  variables {
    auto_scaling_group = { max_instance_lifetime = 3600 }
  }
  expect_failures = [var.auto_scaling_group]
}

run "asg_termination" {
  command = plan
  variables {
    auto_scaling_group = { termination_policies = ["Random"] }
  }
  expect_failures = [var.auto_scaling_group]
}

run "rolling_min_in_service" {
  command = plan
  variables {
    rolling_update = { min_instances_in_service = 1 }
  }
  expect_failures = [var.rolling_update]
}

run "rolling_batch" {
  command = plan
  variables {
    rolling_update = { max_batch_size = 0 }
  }
  expect_failures = [var.rolling_update]
}

run "rolling_percent" {
  command = plan
  variables {
    rolling_update = { min_successful_instances_percent = 120 }
  }
  expect_failures = [var.rolling_update]
}

run "rolling_pause" {
  command = plan
  variables {
    rolling_update = { pause_time = "PT2H" }
  }
  expect_failures = [var.rolling_update]
}

run "rolling_pause_format" {
  command = plan
  variables {
    rolling_update = { pause_time = "5m" }
  }
  expect_failures = [var.rolling_update]
}

run "signals_timeout_long" {
  command = plan
  variables {
    resource_signals = { timeout = "PT2H" }
  }
  expect_failures = [var.resource_signals]
}

run "signals_timeout_short" {
  command = plan
  variables {
    resource_signals = { timeout = "PT30S" }
  }
  expect_failures = [var.resource_signals]
}

run "signals_timeout_format" {
  command = plan
  variables {
    resource_signals = { timeout = "15m" }
  }
  expect_failures = [var.resource_signals]
}

run "volume_type" {
  command = plan
  variables {
    volumes = { root = { type = "st1" } }
  }
  expect_failures = [var.volumes]
}

run "volume_size" {
  command = plan
  variables {
    volumes = { data = { count = 1, size_gb = 0 } }
  }
  expect_failures = [var.volumes]
}

run "volume_io2_without_iops" {
  command = plan
  variables {
    volumes = { root = { type = "io2" } }
  }
  expect_failures = [var.volumes]
}

run "volume_throughput_gp2" {
  command = plan
  variables {
    volumes = { root = { type = "gp2", throughput = 200 } }
  }
  expect_failures = [var.volumes]
}

run "volume_count" {
  command = plan
  variables {
    volumes = { data = { count = 26 } }
  }
  expect_failures = [var.volumes]
}

run "volume_kms" {
  command = plan
  variables {
    volumes = { kms_key_id = "alias/ebs" }
  }
  expect_failures = [var.volumes]
}

run "swap" {
  command = plan
  variables {
    swap_size_mb = -1
  }
  expect_failures = [var.swap_size_mb]
}

run "metadata_tokens" {
  command = plan
  variables {
    instance_metadata = { http_tokens = "no" }
  }
  expect_failures = [var.instance_metadata]
}

run "metadata_hops" {
  command = plan
  variables {
    instance_metadata = { http_put_response_hop_limit = 65 }
  }
  expect_failures = [var.instance_metadata]
}

run "credit" {
  command = plan
  variables {
    credit_specification = "burst"
  }
  expect_failures = [var.credit_specification]
}

run "scripts" {
  command = plan
  variables {
    user_data_scripts = ["echo no shebang"]
  }
  expect_failures = [var.user_data_scripts]
}

run "timeouts" {
  command = plan
  variables {
    timeouts = { create = "30 minutes" }
  }
  expect_failures = [var.timeouts]
}

run "log_retention" {
  command = plan
  variables {
    cloudwatch_agent = { log_retention_in_days = 10 }
  }
  expect_failures = [var.cloudwatch_agent]
}

run "log_kms" {
  command = plan
  variables {
    cloudwatch_agent = { log_kms_key_id = "alias/logs" }
  }
  expect_failures = [var.cloudwatch_agent]
}

run "iam_policy_arn" {
  command = plan
  variables {
    iam_role = { managed_policy_arns = { x = "AmazonS3ReadOnlyAccess" } }
  }
  expect_failures = [var.iam_role]
}

run "efs_ids" {
  command = plan
  variables {
    efs_file_system = { id = "efs-1", security_group_id = "sg-0123456789abcdef0" }
  }
  expect_failures = [var.efs_file_system]
}

run "efs_mount_point" {
  command = plan
  variables {
    efs_file_system = { id = "fs-0123456789abcdef0", security_group_id = "sg-0123456789abcdef0", mount_point = "efs" }
  }
  expect_failures = [var.efs_file_system]
}

run "codedeploy_app" {
  command = plan
  variables {
    codedeploy = { application_name = "", service_role_arn = "arn:aws:iam::111111111111:role/cd" }
  }
  expect_failures = [var.codedeploy]
}

run "codedeploy_role" {
  command = plan
  variables {
    codedeploy = { application_name = "app", service_role_arn = "codedeploy" }
  }
  expect_failures = [var.codedeploy]
}

run "codedeploy_bucket" {
  command = plan
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd", revision_bucket = { arn = "my-bucket" } }
  }
  expect_failures = [var.codedeploy]
}

run "codedeploy_log_groups" {
  command = plan
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd", log_groups = ["a/b"] }
  }
  expect_failures = [var.codedeploy]
}

run "codedeploy_log_groups_duplicate" {
  command = plan
  variables {
    codedeploy = { application_name = "app", service_role_arn = "arn:aws:iam::111111111111:role/cd", log_groups = ["a", "a"] }
  }
  expect_failures = [var.codedeploy]
}

run "ingress_two_sources" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22, cidr_ipv4 = "10.0.0.0/8", security_group_id = "sg-0123456789abcdef0" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_no_source" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22 } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_no_port" {
  command = plan
  variables {
    security_group_ingress = { x = { cidr_ipv4 = "10.0.0.0/8" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_ports_reversed" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 23, to_port = 22, cidr_ipv4 = "10.0.0.0/8" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_all_with_port" {
  command = plan
  variables {
    security_group_ingress = { x = { ip_protocol = "-1", from_port = 22, cidr_ipv4 = "10.0.0.0/8" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_protocol" {
  command = plan
  variables {
    security_group_ingress = { x = { ip_protocol = "6", from_port = 22, cidr_ipv4 = "10.0.0.0/8" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_host_bits" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22, cidr_ipv4 = "10.0.0.5/8" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_ipv6_as_ipv4" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22, cidr_ipv4 = "2600:1f18::/56" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_sg_id" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22, security_group_id = "default" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "ingress_description" {
  command = plan
  variables {
    security_group_ingress = { x = { from_port = 22, cidr_ipv4 = "10.0.0.0/8", description = "caf\u00e9 <access>" } }
  }
  expect_failures = [var.security_group_ingress]
}

run "egress_no_source" {
  command = plan
  variables {
    security_group_egress = { x = { from_port = 443 } }
  }
  expect_failures = [var.security_group_egress]
}

run "egress_icmp_range" {
  command = plan
  variables {
    security_group_egress = { x = { ip_protocol = "icmp", from_port = 300, cidr_ipv4 = "10.0.0.0/8" } }
  }
  expect_failures = [var.security_group_egress]
}

run "egress_prefix_list" {
  command = plan
  variables {
    security_group_egress = { x = { from_port = 443, prefix_list_id = "s3" } }
  }
  expect_failures = [var.security_group_egress]
}

run "lb_type" {
  command = plan
  variables {
    load_balancer = { type = "gateway", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
  }
  expect_failures = [var.load_balancer]
}

run "lb_alb_one_subnet" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "HTTP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_name" {
  command = plan
  variables {
    load_balancer = { type = "network", name = "internal-lb", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_name_long" {
  command = plan
  variables {
    load_balancer = { type = "network", name = "a-name-that-is-much-too-long-for-elb", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_ip_address_type" {
  command = plan
  variables {
    load_balancer = { type = "network", ip_address_type = "ipv6", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_idle_timeout" {
  command = plan
  variables {
    load_balancer = { type = "classic", idle_timeout = 0, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], classic_listeners = { w = { lb_port = 80, lb_protocol = "HTTP", instance_port = 80, instance_protocol = "HTTP" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_eip_internal" {
  command = plan
  variables {
    load_balancer = { type = "network", elastic_ip_addresses = true, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_eip_alb" {
  command = plan
  variables {
    load_balancer = { type = "application", internal = false, elastic_ip_addresses = true, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "HTTP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_access_logs_arn" {
  command = plan
  variables {
    load_balancer = { type = "network", access_logs = { bucket = "arn:aws:s3:::logs" }, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_ingress_two_sources" {
  command = plan
  variables {
    load_balancer = { type = "network", security_group_ingress = { x = { from_port = 80, cidr_ipv4 = "10.0.0.0/8", cidr_ipv6 = "2600:1f18::/56" } }, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_ingress_icmp" {
  command = plan
  variables {
    load_balancer = { type = "network", security_group_ingress = { x = { ip_protocol = "icmp", from_port = 8, cidr_ipv4 = "10.0.0.0/8" } }, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_ingress_description" {
  command = plan
  variables {
    load_balancer = { type = "network", security_group_ingress = { "a<b" = { from_port = 80, cidr_ipv4 = "10.0.0.0/8" } }, subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_no_listeners" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_classic_with_target_groups" {
  command = plan
  variables {
    load_balancer = { type = "classic", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, classic_listeners = { w = { lb_port = 80, lb_protocol = "HTTP", instance_port = 80, instance_protocol = "HTTP" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_tg_protocol" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_tg_proxy_on_alb" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "HTTP", proxy_protocol_v2 = true } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_tg_stickiness" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP", stickiness = { type = "lb_cookie" } } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_tg_udp_without_client_ip" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 53, protocol = "UDP", preserve_client_ip = false } }, listeners = { w = { port = 53, protocol = "UDP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_tg_health_port" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP", health_check = { port = "http" } } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_protocol" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_unknown_target_group" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", target_group = "x" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_two_actions" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "HTTP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w", redirect = { protocol = "HTTPS" } } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_redirect_on_nlb" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 80, protocol = "TCP", redirect = { protocol = "HTTPS" } } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_no_certificate" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "HTTP" } }, listeners = { w = { port = 443, protocol = "HTTPS", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_certificate_on_http" {
  command = plan
  variables {
    load_balancer = { type = "application", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], target_groups = { w = { port = 80, protocol = "HTTP" } }, listeners = { w = { port = 80, protocol = "HTTP", target_group = "w", certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/x" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_alpn" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { w = { port = 443, protocol = "TLS", target_group = "w", certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/x", alpn_policy = "HTTP3" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_listener_same_port" {
  command = plan
  variables {
    load_balancer = { type = "network", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], target_groups = { w = { port = 80, protocol = "TCP" } }, listeners = { a = { port = 80, protocol = "TCP", target_group = "w" }, b = { port = 80, protocol = "TCP", target_group = "w" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_classic_no_listeners" {
  command = plan
  variables {
    load_balancer = { type = "classic", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"] }
  }
  expect_failures = [var.load_balancer]
}

run "lb_classic_https_without_certificate" {
  command = plan
  variables {
    load_balancer = { type = "classic", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], classic_listeners = { w = { lb_port = 443, lb_protocol = "HTTPS", instance_port = 80, instance_protocol = "HTTP" } } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_classic_health_target" {
  command = plan
  variables {
    load_balancer = { type = "classic", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], classic_listeners = { w = { lb_port = 80, lb_protocol = "HTTP", instance_port = 80, instance_protocol = "HTTP" } }, classic_health_check = { target = "HTTP:80" } }
  }
  expect_failures = [var.load_balancer]
}

run "lb_classic_draining" {
  command = plan
  variables {
    load_balancer = { type = "classic", subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"], classic_listeners = { w = { lb_port = 80, lb_protocol = "HTTP", instance_port = 80, instance_protocol = "HTTP" } }, connection_draining_timeout = 3601 }
  }
  expect_failures = [var.load_balancer]
}

run "parameter_store_relative" {
  command = plan
  variables {
    parameter_store = { paths = ["secrets/web"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_trailing_slash" {
  command = plan
  variables {
    parameter_store = { paths = ["/secrets/web/"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_root" {
  command = plan
  variables {
    parameter_store = { paths = ["/"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_reserved_aws" {
  command = plan
  variables {
    parameter_store = { paths = ["/AWSconfig/web"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_reserved_ssm" {
  command = plan
  variables {
    parameter_store = { paths = ["/ssm/web"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_double_slash" {
  command = plan
  variables {
    parameter_store = { paths = ["/secrets//web"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_duplicate" {
  command = plan
  variables {
    parameter_store = { paths = ["/a", "/a"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_kms_alias" {
  command = plan
  variables {
    parameter_store = { kms_key_arns = ["alias/aws/ssm"] }
  }
  expect_failures = [var.parameter_store]
}

run "parameter_store_keys_without_paths" {
  command = plan
  variables {
    parameter_store = { kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/0123abcd-0123-0123-0123-0123456789ab"] }
  }
  expect_failures = [var.parameter_store]
}

run "session_manager_bucket_name" {
  command = plan
  variables {
    session_manager = { log_bucket = { arn = "session-logs" } }
  }
  expect_failures = [var.session_manager]
}

run "session_manager_kms_alias" {
  command = plan
  variables {
    session_manager = { kms_key_arns = ["alias/session"] }
  }
  expect_failures = [var.session_manager]
}
