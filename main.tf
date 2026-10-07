# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

##-----------------------------------------------------------------------------
# Data
data "aws_region" "this" {
  region = var.region
}

data "aws_caller_identity" "this" {}

data "aws_partition" "this" {}

# The service principal for EC2 in the Region's partition, for the instance role's trust policy.
data "aws_service_principal" "ec2" {
  region       = var.region
  service_name = "ec2"
}

# The newest AMI for the operating system and architecture, from the public parameters that
# Amazon and Canonical keep up to date in every Region. It is read even when ami_id is set:
# whether an AMI created in the same run is null is not known until apply.
data "aws_ssm_parameter" "ami" {
  region = var.region
  name   = local.ami_parameters[var.os][var.architecture]
}

# The AMI, for its root device name: /dev/xvda on Amazon Linux, /dev/sda1 on Ubuntu.
data "aws_ami" "this" {
  region             = var.region
  include_deprecated = true

  filter {
    name   = "image-id"
    values = [local.ami_id]
  }
}

##-----------------------------------------------------------------------------
# Locals
locals {
  # An abbreviation override counts only when it is set and not empty.
  has_abbr = {
    scope       = var.details.scope_abbr != null && var.details.scope_abbr != ""
    purpose     = var.details.purpose_abbr != null && var.details.purpose_abbr != ""
    environment = var.details.environment_abbr != null && var.details.environment_abbr != ""
  }

  scope = {
    name    = var.details.scope
    abbr    = local.has_abbr.scope ? var.details.scope_abbr : lower(replace(replace(var.details.scope, "/[^0-9A-Za-z]/", " "), "/\\s{1,}/", "_"))
    machine = local.has_abbr.scope ? replace(var.details.scope_abbr, "/[^0-9A-Za-z]/", "") : lower(replace(var.details.scope, "/[^0-9A-Za-z]/", ""))
  }

  purpose = {
    name    = var.details.purpose
    abbr    = local.has_abbr.purpose ? var.details.purpose_abbr : lower(replace(replace(var.details.purpose, "/[^0-9A-Za-z]/", " "), "/\\s{1,}/", "_"))
    machine = local.has_abbr.purpose ? replace(var.details.purpose_abbr, "/[^0-9A-Za-z]/", "") : lower(replace(var.details.purpose, "/[^0-9A-Za-z]/", ""))
  }

  environment = {
    name    = var.details.environment
    abbr    = local.has_abbr.environment ? var.details.environment_abbr : lower(replace(replace(var.details.environment, "/[^0-9A-Za-z]/", " "), "/\\s{1,}/", "_"))
    machine = local.has_abbr.environment ? replace(var.details.environment_abbr, "/[^0-9A-Za-z]/", "") : lower(replace(var.details.environment, "/[^0-9A-Za-z]/", ""))
  }

  tags = merge(
    {
      "Scope"       = local.scope.name,
      "Purpose"     = local.purpose.name,
      "Environment" = local.environment.name,
    },
    var.details.additional_tags
  )

  aws = {
    account = {
      id = data.aws_caller_identity.this.account_id
    }
    region = {
      name        = data.aws_region.this.region
      abbr        = lookup(local.region_abbr_override, data.aws_region.this.region, local.region_abbr_computed)
      description = data.aws_region.this.description
    }
  }

  # Region abbreviation: the geography, the initials of the direction, then the number.
  # us-east-1 => use1, ap-southeast-2 => apse2, eu-central-1 => euc1. Regions that do not
  # follow that pattern are listed in region_abbr_override, so a new Region never fails a plan.
  region_parts = split("-", data.aws_region.this.region)
  region_direction_abbr = {
    north     = "n"
    northeast = "ne"
    northwest = "nw"
    south     = "s"
    southeast = "se"
    southwest = "sw"
    east      = "e"
    west      = "w"
    central   = "c"
  }
  region_abbr_computed = join("", concat(
    [local.region_parts[0]],
    [for p in slice(local.region_parts, 1, length(local.region_parts) - 1) : lookup(local.region_direction_abbr, p, substr(p, 0, 1))],
    [local.region_parts[length(local.region_parts) - 1]]
  ))
  region_abbr_override = {
    us-gov-east-1 = "uge1"
    us-gov-west-1 = "ugw1"
  }
}
