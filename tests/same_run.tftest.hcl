# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

# Inputs created in the same run: every ID is unknown at plan time. Keys taken from such IDs
# fail for_each ("Invalid for_each argument"), and a lookup of subnets by tag misses new ones.
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
  mock_data "aws_ami" {
    defaults = { root_device_name = "/dev/xvda" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/same-run" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/same-run" }
  }
}

run "same_run_plans" {
  command = plan
  module {
    source = "./tests/fixtures/same_run"
  }
}
