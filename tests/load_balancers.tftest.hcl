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

run "application_load_balancer" {
  command = apply
  variables {
    load_balancer = {
      type       = "application"
      subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
      security_group_ingress = {
        https = { from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
        http  = { from_port = 80, cidr_ipv4 = "10.0.0.0/8" }
      }
      target_groups = {
        web = { port = 8080, protocol = "HTTP", health_check = { path = "/health", port = "8081" }, stickiness = { type = "lb_cookie", cookie_duration = 3600 } }
        api = { port = 9000, protocol = "HTTP", protocol_version = "HTTP2" }
      }
      listeners = {
        https    = { port = 443, protocol = "HTTPS", target_group = "web", certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/0123" }
        http     = { port = 80, protocol = "HTTP", redirect = { protocol = "HTTPS", port = "443" } }
        api      = { port = 9000, protocol = "HTTP", target_group = "api" }
        maintain = { port = 8888, protocol = "HTTP", fixed_response = { content_type = "text/plain", message_body = "down", status_code = "503" } }
      }
      access_logs = { bucket = "my-elb-logs", prefix = "web" }
    }
    codedeploy = { application_name = "web-app", service_role_arn = "arn:aws:iam::111111111111:role/codedeploy" }
  }
  assert {
    condition     = aws_lb.this[0].internal == true && aws_lb.this[0].load_balancer_type == "application" && aws_lb.this[0].drop_invalid_header_fields == true && aws_lb.this[0].enable_deletion_protection == false
    error_message = "Internal by default, dropping invalid headers."
  }
  assert {
    condition     = aws_lb.this[0].name == "test-web-test-lb" && aws_lb.this[0].subnets == toset(["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]) && aws_lb.this[0].access_logs[0].bucket == "my-elb-logs" && aws_lb.this[0].access_logs[0].enabled
    error_message = "Name, subnets and access logs."
  }
  assert {
    condition     = aws_lb_listener.this["https"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.this["https"].default_action[0].type == "forward" && aws_lb_listener.this["https"].default_action[0].target_group_arn == aws_lb_target_group.this["web"].arn
    error_message = "HTTPS forwards to web with TLS 1.2 and 1.3."
  }
  assert {
    condition     = aws_lb_listener.this["http"].default_action[0].type == "redirect" && aws_lb_listener.this["http"].default_action[0].redirect[0].status_code == "HTTP_301" && aws_lb_listener.this["http"].default_action[0].target_group_arn == null
    error_message = "HTTP redirects."
  }
  assert {
    condition     = aws_lb_listener.this["maintain"].default_action[0].type == "fixed-response" && aws_lb_listener.this["maintain"].default_action[0].fixed_response[0].status_code == "503"
    error_message = "Fixed response."
  }
  assert {
    condition     = length(aws_lb_target_group.this["web"].name) <= 32 && startswith(aws_lb_target_group.this["web"].name, "test-web-test-web-") && aws_lb_target_group.this["web"].health_check[0].port == "8081" && aws_lb_target_group.this["api"].protocol_version == "HTTP2"
    error_message = "Target group names fit in 32 characters."
  }
  # Only the target and health check ports, both ways between the two groups.
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.instance_from_load_balancer)) == toset(["tcp-8080", "tcp-8081", "tcp-9000"]) && toset(keys(aws_vpc_security_group_egress_rule.load_balancer_to_instance)) == toset(["tcp-8080", "tcp-8081", "tcp-9000"])
    error_message = "The load balancer may reach the instances on the target and health check ports only."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.load_balancer["https"].security_group_id == aws_security_group.load_balancer[0].id && aws_vpc_security_group_ingress_rule.load_balancer["https"].to_port == 443
    error_message = "Clients reach the load balancer's group."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.Properties.HealthCheckType == "ELB" && length(local.template.Resources.AutoScalingGroup.Properties.TargetGroupARNs) == 2 && !contains(keys(local.template.Resources.AutoScalingGroup.Properties), "LoadBalancerNames")
    error_message = "The group registers with both target groups and uses their health checks."
  }
  assert {
    condition     = aws_codedeploy_deployment_group.this[0].deployment_style[0].deployment_option == "WITH_TRAFFIC_CONTROL" && length(aws_codedeploy_deployment_group.this[0].load_balancer_info[0].target_group_info) == 2
    error_message = "Deployments take every target group's traffic away."
  }
  assert {
    condition     = output.metadata.lb.dns_name == aws_lb.this[0].dns_name && toset(keys(output.metadata.lb_target_group)) == toset(["web", "api"]) && output.metadata.security_group.load_balancer.id == aws_security_group.load_balancer[0].id
    error_message = "Unexpected metadata."
  }
}

run "network_load_balancer" {
  command = apply
  variables {
    load_balancer = {
      type                 = "network"
      subnet_ids           = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
      internal             = false
      elastic_ip_addresses = true
      security_group_ingress = {
        dns = { ip_protocol = "udp", from_port = 53, cidr_ipv4 = "0.0.0.0/0" }
      }
      target_groups = {
        dns = { port = 53, protocol = "TCP_UDP", preserve_client_ip = true, health_check = { protocol = "TCP", port = "8053" } }
        tls = { port = 8443, protocol = "TCP" }
      }
      listeners = {
        dns = { port = 53, protocol = "TCP_UDP", target_group = "dns" }
        tls = { port = 443, protocol = "TLS", target_group = "tls", certificate_arn = "arn:aws:acm:us-east-1:111111111111:certificate/0123", alpn_policy = "HTTP2Preferred" }
      }
    }
  }
  assert {
    condition     = aws_lb.this[0].internal == false && aws_lb.this[0].enable_cross_zone_load_balancing == false && length(aws_eip.load_balancer) == 2
    error_message = "Internet-facing with two Elastic IP addresses."
  }
  assert {
    condition     = toset([for m in aws_lb.this[0].subnet_mapping : "${m.subnet_id}=${m.allocation_id}"]) == toset(["subnet-0aaaaaaaaaaaaaaaa=eipalloc-0123456789abcdef0", "subnet-0bbbbbbbbbbbbbbbb=eipalloc-0123456789abcdef0"])
    error_message = "Each subnet mapped to an address."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.instance_from_load_balancer)) == toset(["tcp-53", "udp-53", "tcp-8053", "tcp-8443"])
    error_message = "TCP_UDP opens both protocols; the health check port opens TCP."
  }
  assert {
    condition     = aws_lb_listener.this["tls"].alpn_policy == "HTTP2Preferred" && aws_lb_listener.this["tls"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_target_group.this["dns"].preserve_client_ip == "true"
    error_message = "TLS listener settings."
  }
  assert {
    condition     = aws_lb_target_group.this["tls"].preserve_client_ip == "false"
    error_message = "TCP target groups of a Network Load Balancer do not preserve the client's address by default."
  }
  assert {
    condition     = length(output.metadata.eip) == 2
    error_message = "The addresses in metadata."
  }
}

run "classic_load_balancer" {
  command = apply
  variables {
    load_balancer = {
      type       = "classic"
      subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
      security_group_ingress = {
        https = { from_port = 443, cidr_ipv4 = "10.0.0.0/8" }
      }
      classic_listeners = {
        https = { lb_port = 443, lb_protocol = "HTTPS", instance_port = 8080, instance_protocol = "HTTP", ssl_certificate_id = "arn:aws:acm:us-east-1:111111111111:certificate/0123" }
        tcp   = { lb_port = 2222, lb_protocol = "TCP", instance_port = 22, instance_protocol = "TCP" }
      }
      classic_health_check = { target = "HTTP:8081/health" }
    }
    codedeploy = { application_name = "web-app", service_role_arn = "arn:aws:iam::111111111111:role/codedeploy" }
  }
  assert {
    condition     = aws_elb.this[0].internal == true && aws_elb.this[0].health_check[0].target == "HTTP:8081/health" && aws_elb.this[0].connection_draining && aws_elb.this[0].connection_draining_timeout == 300 && aws_elb.this[0].cross_zone_load_balancing
    error_message = "Internal, with the health check, connection draining and cross-zone."
  }
  assert {
    condition     = keys(aws_lb_ssl_negotiation_policy.this) == ["https"] && aws_lb_ssl_negotiation_policy.this["https"].lb_port == 443 && one(aws_lb_ssl_negotiation_policy.this["https"].attribute).value == "ELBSecurityPolicy-TLS-1-2-2017-01"
    error_message = "The HTTPS listener gets the TLS 1.2 policy."
  }
  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.instance_from_load_balancer)) == toset(["tcp-8080", "tcp-22", "tcp-8081"])
    error_message = "Instance ports and the health check port."
  }
  assert {
    condition     = local.template.Resources.AutoScalingGroup.Properties.LoadBalancerNames == [aws_elb.this[0].name] && !contains(keys(local.template.Resources.AutoScalingGroup.Properties), "TargetGroupARNs") && local.template.Resources.AutoScalingGroup.Properties.HealthCheckType == "ELB"
    error_message = "The group registers with the Classic Load Balancer."
  }
  assert {
    condition     = one(aws_codedeploy_deployment_group.this[0].load_balancer_info[0].elb_info).name == aws_elb.this[0].name && length(aws_codedeploy_deployment_group.this[0].load_balancer_info[0].target_group_info) == 0
    error_message = "Deployments take the Classic Load Balancer's traffic away."
  }
  assert {
    condition     = output.metadata.elb.name == aws_elb.this[0].name && output.metadata.lb == null && keys(output.metadata.lb_ssl_negotiation_policy) == ["https"]
    error_message = "Unexpected metadata."
  }
}

# The default Classic health check: TCP on the first listener's instance port.
run "classic_default_health_check" {
  command = plan
  variables {
    load_balancer = {
      type              = "classic"
      subnet_ids        = ["subnet-0aaaaaaaaaaaaaaaa"]
      classic_listeners = { http = { lb_port = 80, lb_protocol = "HTTP", instance_port = 8080, instance_protocol = "HTTP" } }
    }
  }
  assert {
    condition     = aws_elb.this[0].health_check[0].target == "TCP:8080" && length(aws_lb_ssl_negotiation_policy.this) == 0
    error_message = "Expected TCP:8080 and no security policy."
  }
}

# A long name is shortened to fit the 32 characters a load balancer name allows.
run "long_names" {
  command = plan
  variables {
    details = { scope = "Automate the Cloud", purpose = "Instance Deployment Example", environment = "production" }
    load_balancer = {
      type          = "network"
      subnet_ids    = ["subnet-0aaaaaaaaaaaaaaaa"]
      target_groups = { web = { port = 80, protocol = "TCP" } }
      listeners     = { web = { port = 80, protocol = "TCP", target_group = "web" } }
    }
  }
  assert {
    condition     = aws_lb.this[0].name == "automatethecloud-i-production-lb" && length(aws_lb.this[0].name) <= 32
    error_message = "Unexpected load balancer name."
  }
}

run "name_override" {
  command = plan
  variables {
    load_balancer = {
      type          = "network"
      name          = "my-nlb"
      subnet_ids    = ["subnet-0aaaaaaaaaaaaaaaa"]
      target_groups = { web = { port = 80, protocol = "TCP" } }
      listeners     = { web = { port = 80, protocol = "TCP", target_group = "web" } }
    }
  }
  assert {
    condition     = aws_lb.this[0].name == "my-nlb"
    error_message = "The name must follow load_balancer.name."
  }
}
