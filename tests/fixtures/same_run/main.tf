# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Test fixture: the VPC, subnets, source security group, EFS file system, KMS key, AMI and
# CodeDeploy application (and so the revision bucket's name) are created in the same run as
# the instances, so their IDs are not known until apply.
terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "a" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "b" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_security_group" "client" {
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group" "efs" {
  vpc_id = aws_vpc.this.id
}

resource "aws_efs_file_system" "this" {
  encrypted = true
}

resource "aws_kms_key" "this" {
  enable_key_rotation = true
}

resource "aws_ami_copy" "this" {
  name              = "copy"
  source_ami_id     = "ami-0123456789abcdef0"
  source_ami_region = "us-east-1"
}

resource "aws_codedeploy_app" "this" {
  name = "app"
}

resource "aws_iam_role" "codedeploy" {
  assume_role_policy = "{}"
}

module "instances" {
  source = "../../.."

  details        = { scope = "Test", purpose = "Web", environment = "test" }
  vpc_id         = aws_vpc.this.id
  subnet_ids     = [aws_subnet.a.id, aws_subnet.b.id]
  os             = "al2023"
  ami_id         = aws_ami_copy.this.id
  instance_types = [{ type = "t3.micro" }]
  volumes        = { kms_key_id = aws_kms_key.this.arn }

  security_group_ingress = {
    client = { from_port = 443, security_group_id = aws_security_group.client.id }
  }
  efs_file_system = { id = aws_efs_file_system.this.id, security_group_id = aws_security_group.efs.id }
  codedeploy = {
    application_name = aws_codedeploy_app.this.name
    service_role_arn = aws_iam_role.codedeploy.arn
    revision_bucket  = { arn = "arn:aws:s3:::revisions-${aws_codedeploy_app.this.application_id}" }
  }
  load_balancer = {
    type                   = "application"
    subnet_ids             = [aws_subnet.a.id, aws_subnet.b.id]
    security_group_ingress = { client = { from_port = 80, security_group_id = aws_security_group.client.id } }
    target_groups          = { web = { port = 80, protocol = "HTTP" } }
    listeners              = { web = { port = 80, protocol = "HTTP", target_group = "web" } }
  }
}
