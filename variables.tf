# Copyright 2026 Automate the Cloud Inc.
# SPDX-License-Identifier: Apache-2.0

variable "ami_id" {
  description = <<-EOT
    The ID of the Amazon Machine Image (AMI) to launch, such as `ami-0123456789abcdef0`. Defaults to the newest AMI for `os` and `architecture`, from the public AWS Systems Manager parameters that Amazon and Canonical publish in every Region.

    With the default, a plan picks up a new AMI as soon as one is published, and the apply then replaces every instance through a rolling update. Set an AMI ID to choose when that happens. The AMI must run the operating system named in `os`, which decides the boot commands. The module reads the public parameter even then, so it must exist in the Region.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]{8,17}$", coalesce(var.ami_id, "-")))
    error_message = "ami_id must be an AMI ID, such as ami-0123456789abcdef0."
  }
}

variable "architecture" {
  description = <<-EOT
    The processor architecture of the instances: `x86_64` (Intel and AMD) or `arm64` (AWS Graviton). Picks the AMI when `ami_id` is not set. Every type in `instance_types` must have this architecture. Defaults to `x86_64`.
  EOT
  type        = string
  default     = "x86_64"
  nullable    = false

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "associate_public_ip_address" {
  description = <<-EOT
    Give each instance a public IPv4 address. Defaults to `false`, whatever the subnet's own setting. With `true`, in subnets with a route to an internet gateway, anyone that `security_group_ingress` allows can reach the instances from the internet, and AWS charges for each public IPv4 address. Prefer private subnets with a NAT gateway or VPC endpoints for outbound traffic, and a load balancer for inbound traffic.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "auto_scaling_group" {
  description = <<-EOT
    The size and behavior of the Auto Scaling group.

    - `min_size` - (Optional) The fewest instances (capacity units, with weights in `instance_types`). Defaults to `1`.
    - `max_size` - (Optional) The most instances. Defaults to `1`. Must be more than `rolling_update.min_instances_in_service`.
    - `desired_capacity` - (Optional) How many instances to run. Defaults to `min_size`. After the group exists, a change made outside Terraform, such as by a scaling policy, is kept until this value changes.
    - `on_demand_base_capacity` - (Optional) How many instances are always On-Demand. Defaults to `0`.
    - `on_demand_percentage_above_base_capacity` - (Optional) The percentage of instances above the base that are On-Demand; the rest are Spot Instances. Defaults to `100`: no Spot Instances.
    - `spot_allocation_strategy` - (Optional) How Spot Instances are chosen: `price-capacity-optimized`, `capacity-optimized`, `capacity-optimized-prioritized` or `lowest-price`. Defaults to `price-capacity-optimized`. With `lowest-price`, Spot Instances are spread over as many pools as `instance_types` has types.
    - `health_check_type` - (Optional) `EC2` or `ELB`. Defaults to `ELB` with a load balancer, so an instance that fails the load balancer's health check is replaced, and `EC2` without one.
    - `health_check_grace_period` - (Optional) Seconds after launch before health checks count. Defaults to `300`.
    - `default_cooldown` - (Optional) Seconds between scaling activities. Defaults to `300`.
    - `max_instance_lifetime` - (Optional) Seconds after which an instance is replaced, from `86400` (1 day) to `31536000` (365 days). Defaults to `null`: no limit.
    - `termination_policies` - (Optional) Which instances to terminate first when scaling in. Defaults to `["OldestInstance", "Default"]`.
  EOT
  type = object({
    min_size                                 = optional(number, 1)
    max_size                                 = optional(number, 1)
    desired_capacity                         = optional(number)
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 100)
    spot_allocation_strategy                 = optional(string, "price-capacity-optimized")
    health_check_type                        = optional(string)
    health_check_grace_period                = optional(number, 300)
    default_cooldown                         = optional(number, 300)
    max_instance_lifetime                    = optional(number)
    termination_policies                     = optional(list(string), ["OldestInstance", "Default"])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for n in [var.auto_scaling_group.min_size, var.auto_scaling_group.max_size, var.auto_scaling_group.on_demand_base_capacity, var.auto_scaling_group.health_check_grace_period, var.auto_scaling_group.default_cooldown] :
      n >= 0 && floor(n) == n
    ])
    error_message = "auto_scaling_group: min_size, max_size, on_demand_base_capacity, health_check_grace_period and default_cooldown must be whole numbers, 0 or more."
  }

  validation {
    condition     = var.auto_scaling_group.min_size <= var.auto_scaling_group.max_size && var.auto_scaling_group.max_size >= 1
    error_message = "auto_scaling_group: max_size must be at least 1 and at least min_size."
  }

  validation {
    condition = var.auto_scaling_group.desired_capacity == null || try(
      var.auto_scaling_group.desired_capacity >= var.auto_scaling_group.min_size &&
      var.auto_scaling_group.desired_capacity <= var.auto_scaling_group.max_size &&
      floor(var.auto_scaling_group.desired_capacity) == var.auto_scaling_group.desired_capacity,
    false)
    error_message = "auto_scaling_group: desired_capacity must be a whole number from min_size to max_size."
  }

  validation {
    condition     = var.auto_scaling_group.on_demand_percentage_above_base_capacity >= 0 && var.auto_scaling_group.on_demand_percentage_above_base_capacity <= 100
    error_message = "auto_scaling_group: on_demand_percentage_above_base_capacity must be from 0 to 100."
  }

  validation {
    condition     = contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], var.auto_scaling_group.spot_allocation_strategy)
    error_message = "auto_scaling_group: spot_allocation_strategy must be price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price."
  }

  validation {
    condition     = var.auto_scaling_group.health_check_type == null || contains(["EC2", "ELB"], coalesce(var.auto_scaling_group.health_check_type, "-"))
    error_message = "auto_scaling_group: health_check_type must be EC2 or ELB."
  }

  validation {
    condition     = var.auto_scaling_group.max_instance_lifetime == null || try(var.auto_scaling_group.max_instance_lifetime >= 86400 && var.auto_scaling_group.max_instance_lifetime <= 31536000, false)
    error_message = "auto_scaling_group: max_instance_lifetime must be from 86400 (1 day) to 31536000 (365 days) seconds, or null for no limit."
  }

  validation {
    condition = length(var.auto_scaling_group.termination_policies) > 0 && alltrue([
      for p in var.auto_scaling_group.termination_policies :
      contains(["Default", "AllocationStrategy", "OldestLaunchTemplate", "OldestLaunchConfiguration", "ClosestToNextInstanceHour", "NewestInstance", "OldestInstance"], p) || startswith(p, "arn:")
    ])
    error_message = "auto_scaling_group: termination_policies must list one or more of Default, AllocationStrategy, OldestLaunchTemplate, OldestLaunchConfiguration, ClosestToNextInstanceHour, NewestInstance and OldestInstance, or a Lambda function ARN."
  }
}

variable "cloudwatch_agent" {
  description = <<-EOT
    What the Amazon CloudWatch agent on each instance sends to CloudWatch. The module installs and configures the agent when either is on.

    - `logs` - (Optional) Send the system log, the authentication log, the cloud-init output log and the CloudFormation helper log to log groups the module creates, one stream per instance. Defaults to `true`. On Amazon Linux 2023, which keeps these logs only in the systemd journal, the module also installs rsyslog to write them to files.
    - `log_retention_in_days` - (Optional) How long CloudWatch keeps the logs. Defaults to `30`. One of the values CloudWatch Logs accepts, such as `7`, `30`, `90`, `365`, or `0` to keep them forever.
    - `log_kms_key_id` - (Optional) The ARN of a KMS key to encrypt the log groups with. Its key policy must allow the CloudWatch Logs service principal in the Region. Defaults to `null`: CloudWatch Logs encrypts them with its own key.
    - `metrics` - (Optional) Send memory, disk and swap use, which EC2 does not measure, to the `CWAgent` namespace every minute, by Auto Scaling group and by instance. Defaults to `false`. CloudWatch charges for each custom metric.

    The log groups are named `/<scope abbr>/<purpose abbr>/<environment abbr>/ec2/<log>`, where `<log>` is `system`, `auth`, `cloud-init` or `cfn-init`. The instances' role may write only to them.
  EOT
  type = object({
    logs                  = optional(bool, true)
    log_retention_in_days = optional(number, 30)
    log_kms_key_id        = optional(string)
    metrics               = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_agent.log_retention_in_days)
    error_message = "cloudwatch_agent: log_retention_in_days must be 0 (forever) or one of 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 and 3653."
  }

  validation {
    condition     = var.cloudwatch_agent.log_kms_key_id == null || startswith(coalesce(var.cloudwatch_agent.log_kms_key_id, "-"), "arn:")
    error_message = "cloudwatch_agent: log_kms_key_id must be the ARN of a KMS key."
  }
}

variable "codedeploy" {
  description = <<-EOT
    Deploy applications to the instances with AWS CodeDeploy. The module creates a deployment group for the Auto Scaling group in an existing CodeDeploy application, and installs the CodeDeploy agent on each instance. New instances get the latest revision when they launch. Defaults to `null`: no CodeDeploy.

    - `application_name` - (Required) The name of the CodeDeploy application, for the `Server` compute platform.
    - `service_role_arn` - (Required) The ARN of the IAM role CodeDeploy uses. Because the Auto Scaling group uses a launch template, it needs `ec2:RunInstances`, `ec2:CreateTags` and `iam:PassRole` for the instances' role, besides the `AWSCodeDeployRole` managed policy.
    - `deployment_config_name` - (Optional) How many instances deploy at once. Defaults to `CodeDeployDefault.OneAtATime`.
    - `revision_bucket` - (Optional) The S3 bucket that holds the application's revisions: `arn` (Required) and `path` (Optional), the key prefix of the revisions, such as `codedeploy/web`; without it, the whole bucket. The instances' role may read the revisions. The `metadata.s3_bucket` output of the [CodeDeploy module](https://registry.terraform.io/modules/AutomateTheCloud/codedeploy/aws) has this shape. Defaults to `null`: grant read access yourself through `iam_role`.
    - `log_groups` - (Optional) Names of log groups to create for the application, such as `["application", "access"]`. Each is created as `/<scope abbr>/<purpose abbr>/<environment abbr>/application/<application_name>/<name>`, the instances' role may write to it, and `/deploy/codedeploy.dat` on each instance names it as `CODEDEPLOY_LOG_GROUP_<NAME>`. Defaults to none. They use `cloudwatch_agent.log_retention_in_days` and `log_kms_key_id`.

    With a load balancer, deployments stop sending traffic to each instance while it is updated.
  EOT
  type = object({
    application_name       = string
    service_role_arn       = string
    deployment_config_name = optional(string, "CodeDeployDefault.OneAtATime")
    revision_bucket = optional(object({
      arn  = string
      path = optional(string)
    }))
    log_groups = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.codedeploy == null || try(trimspace(var.codedeploy.application_name) != "" && length(var.codedeploy.application_name) <= 100, false)
    error_message = "codedeploy: application_name must be 1 to 100 characters."
  }

  validation {
    condition     = var.codedeploy == null || try(startswith(var.codedeploy.service_role_arn, "arn:") && strcontains(var.codedeploy.service_role_arn, ":role/"), false)
    error_message = "codedeploy: service_role_arn must be the ARN of an IAM role."
  }

  validation {
    condition     = try(var.codedeploy.revision_bucket, null) == null ? true : can(regex("^arn:[a-z-]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.codedeploy.revision_bucket.arn))
    error_message = "codedeploy: revision_bucket.arn must be the ARN of an S3 bucket, such as arn:aws:s3:::my-revisions."
  }

  validation {
    condition     = var.codedeploy == null || try(alltrue([for g in var.codedeploy.log_groups : can(regex("^[A-Za-z0-9_.-]{1,64}$", g))]) && length(distinct(var.codedeploy.log_groups)) == length(var.codedeploy.log_groups), false)
    error_message = "codedeploy: each of log_groups must be 1 to 64 letters, digits, dots, hyphens and underscores, listed once."
  }
}

variable "credit_specification" {
  description = <<-EOT
    The CPU credit option for burstable instance types (T2, T3, T3a, T4g): `standard` or `unlimited`. Defaults to `null`: the instance type's default (`unlimited` for T3, T3a and T4g). Leave it `null` when `instance_types` has types that are not burstable.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.credit_specification == null || contains(["standard", "unlimited"], coalesce(var.credit_specification, "-"))
    error_message = "credit_specification must be standard or unlimited."
  }
}

variable "detailed_monitoring" {
  description = <<-EOT
    Send each instance's EC2 metrics to CloudWatch every minute instead of every five minutes. Defaults to `true`. CloudWatch charges for detailed monitoring.
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "details" {
  description = <<-EOT
    Names and tags shared by every resource in the module. `scope`, `purpose` and `environment` become the `Scope`, `Purpose` and `Environment` tags, and are converted to abbreviations that name the resources the module creates (see the `metadata` output). [The `details` input](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#the-details-input) explains why it is required.

    - `scope` - (Required) What the resource belongs to, such as an organization or project: `Automate the Cloud`.
    - `purpose` - (Required) What the resource is for: `Web Site`.
    - `environment` - (Required) The environment: `Production`.
    - `scope_abbr`, `purpose_abbr`, `environment_abbr` - (Optional) Abbreviations to use instead of the generated ones, which are lowercase with words joined by underscores (`Web Site` becomes `web_site`).
    - `additional_tags` - (Optional) More tags for every resource, such as `{ CostCenter = "1234" }`.
  EOT
  type = object({
    scope            = string
    scope_abbr       = optional(string)
    purpose          = string
    purpose_abbr     = optional(string)
    environment      = string
    environment_abbr = optional(string)
    additional_tags  = optional(map(string), {})
  })
  nullable = false

  validation {
    condition     = trimspace(var.details.scope) != ""
    error_message = "Scope not specified."
  }

  validation {
    condition     = trimspace(var.details.purpose) != ""
    error_message = "Purpose not specified."
  }

  validation {
    condition     = trimspace(var.details.environment) != ""
    error_message = "Environment not specified."
  }
}

variable "efs_file_system" {
  description = <<-EOT
    An Amazon Elastic File System (EFS) file system to mount on every instance. The module allows NFS (TCP 2049) from the instances to the file system's security group, and mounts it with encryption in transit (TLS) through the Amazon EFS client, also on reboot. Defaults to `null`: no file system.

    - `id` - (Required) The file system's ID, such as `fs-0123456789abcdef0`. It needs a mount target in each Availability Zone of `subnet_ids`.
    - `security_group_id` - (Required) The ID of the security group on the file system's mount targets. The module adds an inbound rule to it.
    - `mount_point` - (Optional) Where to mount it. Defaults to `/efs`.
  EOT
  type = object({
    id                = string
    security_group_id = string
    mount_point       = optional(string, "/efs")
  })
  default = null

  validation {
    condition     = var.efs_file_system == null || try(can(regex("^fs-[0-9a-f]{8,40}$", var.efs_file_system.id)) && can(regex("^sg-[0-9a-f]{8,17}$", var.efs_file_system.security_group_id)), false)
    error_message = "efs_file_system: id must be a file system ID, such as fs-0123456789abcdef0, and security_group_id a security group ID, such as sg-0123456789abcdef0."
  }

  validation {
    condition     = var.efs_file_system == null || try(can(regex("^/[A-Za-z0-9._/-]*[A-Za-z0-9._-]$", var.efs_file_system.mount_point)), false)
    error_message = "efs_file_system: mount_point must be an absolute path, such as /efs, of letters, digits, dots, hyphens, underscores and slashes."
  }
}

variable "iam_role" {
  description = <<-EOT
    Permissions for the IAM role the module creates for the instances. Besides what is listed here, the role may write to the module's log groups and CloudWatch metrics when `cloudwatch_agent` sends them, and read the CodeDeploy revisions when `codedeploy.revision_bucket` is set.

    - `ssm_managed_instance_core` - (Optional) Let AWS Systems Manager manage the instances, including Session Manager shell access without SSH or open ports. Defaults to `true`. It attaches the AWS managed policy `AmazonSSMManagedInstanceCore`, and adds to the inline policy what that policy leaves out:
      - `s3:GetObject` on the AWS-owned buckets SSM Agent reads from in the instances' Region, for agent updates, Distributor packages, patching and document modules: `aws-ssm-<region>`, `amazon-ssm-<region>`, `amazon-ssm-packages-<region>`, `<region>-birdwatcher-prod`, `aws-windows-downloads-<region>`, `patch-baseline-snapshot-<region>` (with or without a suffix) and `aws-patch-manager-<region>-<suffix>`;
      - for Session Manager session logging, if the account's Session Manager preferences turn it on: writing to CloudWatch Logs log groups in this account and Region (`logs:CreateLogStream`, `PutLogEvents`, `DescribeLogGroups`, `DescribeLogStreams`), and `s3:GetEncryptionConfiguration`. Writing session logs to S3, and KMS-encrypted sessions, also need `session_manager`.
    - `source_policy_documents` - (Optional) IAM policy documents, as JSON, to give the role, such as the `json` of an `aws_iam_policy_document` that allows reading one S3 bucket or one Secrets Manager secret. They are combined into one inline policy. Defaults to none.
    - `managed_policy_arns` - (Optional) Managed policies to attach to the role, as a map of names you choose to policy ARNs, such as `{ app = aws_iam_policy.app.arn }`. The names only identify each attachment, so a policy created in the same configuration can be used. Defaults to none.

    The role's name, and its instance profile's, start with the deployment's name and end with a suffix AWS adds, because IAM names are unique in the account across Regions. Its trust policy lets only EC2 in this account use it.
  EOT
  type = object({
    ssm_managed_instance_core = optional(bool, true)
    source_policy_documents   = optional(list(string), [])
    managed_policy_arns       = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.iam_role.managed_policy_arns) : startswith(a, "arn:") && strcontains(a, ":policy/")])
    error_message = "iam_role: managed_policy_arns must be IAM policy ARNs."
  }
}

variable "instance_metadata" {
  description = <<-EOT
    How the instances may use the instance metadata service (IMDS).

    - `http_tokens` - (Optional) `required` allows only IMDSv2, which needs a session token and protects against server-side request forgery; `optional` also allows IMDSv1. Defaults to `required`.
    - `http_put_response_hop_limit` - (Optional) How many network hops the token response may travel, from 1 to 64. Defaults to `2`, so containers on the instance can reach IMDS; `1` keeps it to the instance itself.
  EOT
  type = object({
    http_tokens                 = optional(string, "required")
    http_put_response_hop_limit = optional(number, 2)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["required", "optional"], var.instance_metadata.http_tokens)
    error_message = "instance_metadata: http_tokens must be required or optional."
  }

  validation {
    condition     = var.instance_metadata.http_put_response_hop_limit >= 1 && var.instance_metadata.http_put_response_hop_limit <= 64 && floor(var.instance_metadata.http_put_response_hop_limit) == var.instance_metadata.http_put_response_hop_limit
    error_message = "instance_metadata: http_put_response_hop_limit must be a whole number from 1 to 64."
  }
}

variable "instance_types" {
  description = <<-EOT
    The instance types the Auto Scaling group may launch, in order of preference for On-Demand Instances, such as `[{ type = "t3.micro" }]`. All must have the `architecture` and be offered in the Availability Zones of `subnet_ids`. A change applies to instances launched afterward; it does not replace running instances (see `rolling_update`).

    - `type` - (Required) The instance type, such as `m7i.large`.
    - `weighted_capacity` - (Optional) How many capacity units an instance of this type counts for in `auto_scaling_group`'s sizes, from 1 to 999. Defaults to `1`.
  EOT
  type = list(object({
    type              = string
    weighted_capacity = optional(number, 1)
  }))
  nullable = false

  validation {
    condition     = length(var.instance_types) >= 1 && length(var.instance_types) <= 40
    error_message = "instance_types must list 1 to 40 instance types."
  }

  validation {
    condition     = alltrue([for t in var.instance_types : can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9-]+$", t.type))]) && length(distinct([for t in var.instance_types : t.type])) == length(var.instance_types)
    error_message = "instance_types: each type must be an instance type, such as m7i.large, listed once."
  }

  validation {
    condition     = alltrue([for t in var.instance_types : t.weighted_capacity >= 1 && t.weighted_capacity <= 999 && floor(t.weighted_capacity) == t.weighted_capacity])
    error_message = "instance_types: weighted_capacity must be a whole number from 1 to 999."
  }
}

variable "key_pair_name" {
  description = <<-EOT
    The name of an EC2 key pair to allow SSH access with. Defaults to `null`: no key pair. Session Manager (see `iam_role.ssm_managed_instance_core`) gives shell access without one, and without an inbound port.
  EOT
  type        = string
  default     = null
}

variable "load_balancer" {
  description = <<-EOT
    A load balancer in front of the instances. Defaults to `null`: none. The module creates the load balancer, a security group for it, and rules that let it reach the instances on the target ports and health check ports only.

    For every type:

    - `type` - (Required) `application` (Application Load Balancer, HTTP and HTTPS), `network` (Network Load Balancer, TCP, TLS and UDP) or `classic` (Classic Load Balancer, the previous generation; prefer the other two for new work).
    - `subnet_ids` - (Required) The subnets for the load balancer, in `vpc_id`, one per Availability Zone. An Application Load Balancer needs two or more zones.
    - `internal` - (Optional) Reachable only from inside the VPC and connected networks. Defaults to `true`. Set `false` for an internet-facing load balancer in public subnets, and allow its clients in `security_group_ingress`.
    - `name` - (Optional) The load balancer's name: 1 to 32 letters, digits and hyphens, not starting or ending with a hyphen or starting with `internal-`. Defaults to `<scope>-<purpose>-<environment>` (machine abbreviations, shortened to fit) followed by `-lb`.
    - `security_group_ingress` - (Optional) Who may connect to the load balancer, as a map of rules keyed by names you choose. Defaults to `{}`: no one. Each rule takes `ip_protocol` (`tcp`, the default, or `udp`), `from_port` (Required), `to_port` (defaults to `from_port`), `description` (defaults to the key), and exactly one source: `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id` or `security_group_id`.
    - `idle_timeout` - (Optional) Seconds a connection may be idle, for Application and Classic Load Balancers. Defaults to `60`.
    - `access_logs` - (Optional) Write access logs to S3: `bucket` (Required), the bucket's name, whose policy must allow Elastic Load Balancing to write; `prefix` (Optional); and, for a Classic Load Balancer, `interval` (`5` or `60` minutes, defaults to `60`). Defaults to `null`: no access logs. Network Load Balancers log only TLS listeners.

    For Application and Network Load Balancers:

    - `ip_address_type` - (Optional) `ipv4` or `dualstack`. Defaults to `ipv4`.
    - `deletion_protection` - (Optional) Refuse to delete the load balancer until this is turned off. Defaults to `false`.
    - `cross_zone_load_balancing` - (Optional) For a Network Load Balancer, spread traffic over the targets in every zone. Defaults to `false`; AWS charges for traffic between zones. Application Load Balancers always do.
    - `drop_invalid_header_fields` - (Optional) For an Application Load Balancer, drop HTTP headers that are not valid, a defense against request smuggling. Defaults to `true`.
    - `http2` - (Optional) For an Application Load Balancer, accept HTTP/2. Defaults to `true`.
    - `elastic_ip_addresses` - (Optional) For an internet-facing Network Load Balancer, give it one new Elastic IP address per subnet, so its addresses never change. Defaults to `false`. Turning it on or off replaces the load balancer.
    - `target_groups` - (Required) A map of target groups, keyed by names you choose. The Auto Scaling group registers its instances with every one. Each takes `port` (Required) and `protocol` (Required: `HTTP` or `HTTPS` for an Application Load Balancer; `TCP`, `TLS`, `UDP` or `TCP_UDP` for a Network Load Balancer), the port and protocol of the instances; and optionally `protocol_version` (`HTTP1`, `HTTP2` or `GRPC`), `deregistration_delay` (seconds, defaults to `300`), `slow_start` (seconds), `load_balancing_algorithm_type` (`round_robin` or `least_outstanding_requests`), `preserve_client_ip` (Network Load Balancers; defaults to `false` for `TCP` and `TLS`, see below), `proxy_protocol_v2`, `stickiness` (`type`, Required: `lb_cookie`, `app_cookie` or `source_ip`; `cookie_name`; `cookie_duration`) and `health_check` (`protocol`, `port`, defaults to `traffic-port`, `path`, `matcher`, `interval`, `timeout`, `healthy_threshold`, `unhealthy_threshold`). Changing `port`, `protocol` or `protocol_version` replaces the target group: the new one is created and the listeners moved to it first.
    - `listeners` - (Required) A map of listeners, keyed by names you choose. Each takes `port` (Required) and `protocol` (Required: `HTTP` or `HTTPS`; `TCP`, `TLS`, `UDP` or `TCP_UDP`), and exactly one action: `target_group`, the key of the target group to forward to; or, for an Application Load Balancer, `redirect` (`protocol`, `port`, `host`, `path`, `query`, and `status_code`, `HTTP_301` or `HTTP_302`, defaults to `HTTP_301`) or `fixed_response` (`content_type`, Required; `message_body`; `status_code`, defaults to `200`). `HTTPS` and `TLS` listeners also take `certificate_arn` (Required), `ssl_policy` (defaults to `ELBSecurityPolicy-TLS13-1-2-2021-06`, TLS 1.2 and 1.3 only) and, for `TLS`, `alpn_policy`.

    For a Classic Load Balancer:

    - `classic_listeners` - (Required) A map of listeners, keyed by names you choose. Each takes `lb_port` and `lb_protocol` (`HTTP`, `HTTPS`, `TCP` or `SSL`), `instance_port` and `instance_protocol`, all Required, and, for `HTTPS` and `SSL`, `ssl_certificate_id` (Required), the ARN of the certificate.
    - `classic_health_check` - (Optional) `target`, such as `HTTP:80/health` or `TCP:22`, defaults to `TCP:<first listener's instance_port>`; `interval` (defaults to `30`), `timeout` (`5`), `healthy_threshold` (`10`), `unhealthy_threshold` (`2`).
    - `classic_ssl_policy` - (Optional) The predefined security policy for `HTTPS` and `SSL` listeners. Defaults to `ELBSecurityPolicy-TLS-1-2-2017-01`, TLS 1.2 only.
    - `cross_zone_load_balancing` - (Optional) Spread traffic over the instances in every zone. Defaults to `true`.
    - `connection_draining_timeout` - (Optional) Seconds to let requests to a deregistering instance finish, from 1 to 3600, or `0` to stop at once. Defaults to `300`.

    Changing `type`, `internal`, `name` or `subnet_ids` of a Network Load Balancer with Elastic IP addresses replaces the load balancer, and its DNS name changes.

    With `preserve_client_ip`, which `UDP` and `TCP_UDP` target groups always have, the instances see each client's own address instead of the load balancer's, and their security group, which allows only the load balancer, refuses the traffic: also allow the clients in `security_group_ingress`, on the target port.
  EOT
  type = object({
    type                       = string
    subnet_ids                 = list(string)
    internal                   = optional(bool, true)
    name                       = optional(string)
    idle_timeout               = optional(number, 60)
    ip_address_type            = optional(string, "ipv4")
    deletion_protection        = optional(bool, false)
    cross_zone_load_balancing  = optional(bool)
    drop_invalid_header_fields = optional(bool, true)
    http2                      = optional(bool, true)
    elastic_ip_addresses       = optional(bool, false)
    access_logs = optional(object({
      bucket   = string
      prefix   = optional(string)
      interval = optional(number, 60)
    }))
    security_group_ingress = optional(map(object({
      ip_protocol       = optional(string, "tcp")
      from_port         = number
      to_port           = optional(number)
      description       = optional(string)
      cidr_ipv4         = optional(string)
      cidr_ipv6         = optional(string)
      prefix_list_id    = optional(string)
      security_group_id = optional(string)
    })), {})
    target_groups = optional(map(object({
      port                          = number
      protocol                      = string
      protocol_version              = optional(string)
      deregistration_delay          = optional(number, 300)
      slow_start                    = optional(number)
      load_balancing_algorithm_type = optional(string)
      preserve_client_ip            = optional(bool)
      proxy_protocol_v2             = optional(bool)
      stickiness = optional(object({
        type            = string
        cookie_name     = optional(string)
        cookie_duration = optional(number)
      }))
      health_check = optional(object({
        protocol            = optional(string)
        port                = optional(string, "traffic-port")
        path                = optional(string)
        matcher             = optional(string)
        interval            = optional(number)
        timeout             = optional(number)
        healthy_threshold   = optional(number)
        unhealthy_threshold = optional(number)
      }), {})
    })), {})
    listeners = optional(map(object({
      port            = number
      protocol        = string
      target_group    = optional(string)
      certificate_arn = optional(string)
      ssl_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
      alpn_policy     = optional(string)
      redirect = optional(object({
        protocol    = optional(string)
        port        = optional(string)
        host        = optional(string)
        path        = optional(string)
        query       = optional(string)
        status_code = optional(string, "HTTP_301")
      }))
      fixed_response = optional(object({
        content_type = string
        message_body = optional(string)
        status_code  = optional(string, "200")
      }))
    })), {})
    classic_listeners = optional(map(object({
      lb_port            = number
      lb_protocol        = string
      instance_port      = number
      instance_protocol  = string
      ssl_certificate_id = optional(string)
    })), {})
    classic_health_check = optional(object({
      target              = optional(string)
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 10)
      unhealthy_threshold = optional(number, 2)
    }), {})
    classic_ssl_policy          = optional(string, "ELBSecurityPolicy-TLS-1-2-2017-01")
    connection_draining_timeout = optional(number, 300)
  })
  default = null

  validation {
    condition     = var.load_balancer == null || try(contains(["application", "network", "classic"], var.load_balancer.type), false)
    error_message = "load_balancer: type must be application, network or classic."
  }

  validation {
    condition = var.load_balancer == null || try(
      length(var.load_balancer.subnet_ids) >= (var.load_balancer.type == "application" ? 2 : 1) &&
      alltrue([for s in var.load_balancer.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) &&
      length(distinct(var.load_balancer.subnet_ids)) == length(var.load_balancer.subnet_ids),
    false)
    error_message = "load_balancer: subnet_ids must list subnet IDs, such as subnet-0123456789abcdef0, each once: two or more, in different Availability Zones, for an Application Load Balancer."
  }

  validation {
    condition = var.load_balancer == null || try(
      var.load_balancer.name == null ? true : (
        can(regex("^[A-Za-z0-9]([A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.load_balancer.name)) &&
        !startswith(lower(var.load_balancer.name), "internal-")
      ),
    false)
    error_message = "load_balancer: name must be 1 to 32 letters, digits and hyphens, not starting or ending with a hyphen, and not starting with internal-."
  }

  validation {
    condition     = var.load_balancer == null || try(contains(["ipv4", "dualstack"], var.load_balancer.ip_address_type), false)
    error_message = "load_balancer: ip_address_type must be ipv4 or dualstack."
  }

  validation {
    condition     = var.load_balancer == null || try(var.load_balancer.idle_timeout >= 1 && var.load_balancer.idle_timeout <= 4000, false)
    error_message = "load_balancer: idle_timeout must be from 1 to 4000 seconds."
  }

  validation {
    condition = var.load_balancer == null || try(
      !var.load_balancer.elastic_ip_addresses || (var.load_balancer.type == "network" && !var.load_balancer.internal),
    false)
    error_message = "load_balancer: elastic_ip_addresses needs an internet-facing (internal = false) Network Load Balancer."
  }

  validation {
    condition = var.load_balancer == null || try(
      var.load_balancer.access_logs == null ? true : (
        can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.load_balancer.access_logs.bucket)) &&
        contains([5, 60], var.load_balancer.access_logs.interval)
      ),
    false)
    error_message = "load_balancer: access_logs.bucket must be an S3 bucket name (not an ARN), and access_logs.interval 5 or 60."
  }

  # Rules for who may reach the load balancer.
  validation {
    condition = var.load_balancer == null || try(alltrue([
      for r in values(var.load_balancer.security_group_ingress) :
      length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.security_group_id] : v if v != null]) == 1 &&
      contains(["tcp", "udp"], r.ip_protocol) &&
      r.from_port >= 0 && r.from_port <= 65535 && floor(r.from_port) == r.from_port &&
      (r.to_port == null || try(r.to_port >= r.from_port && r.to_port <= 65535 && floor(r.to_port) == r.to_port, false)) &&
      (r.cidr_ipv4 == null || try(cidrsubnet(r.cidr_ipv4, 0, 0) == r.cidr_ipv4 && !strcontains(r.cidr_ipv4, ":"), false)) &&
      (r.cidr_ipv6 == null || try(cidrsubnet(r.cidr_ipv6, 0, 0) == r.cidr_ipv6 && strcontains(r.cidr_ipv6, ":"), false)) &&
      (r.prefix_list_id == null || can(regex("^pl-[0-9a-f]+$", r.prefix_list_id))) &&
      (r.security_group_id == null || can(regex("^sg-[0-9a-f]+$", r.security_group_id)))
    ]), false)
    error_message = "load_balancer: each security_group_ingress rule needs ip_protocol tcp or udp, from_port from 0 to 65535, to_port (if set) from from_port to 65535, and exactly one source: cidr_ipv4 (such as 10.0.0.0/16, starting at its first address), cidr_ipv6 (short lowercase form, such as 2600:1f18:1234:5600::/56), prefix_list_id (pl-...) or security_group_id (sg-...)."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for k, r in var.load_balancer.security_group_ingress :
      can(regex("^[A-Za-z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", coalesce(r.description, k)))
    ]), false)
    error_message = "load_balancer: each security_group_ingress description (the key, when description is not set) must be 1 to 255 characters: letters, numbers, spaces and ._-:/()#,@[]+=&;{}!$*."
  }

  # Application and Network Load Balancers.
  validation {
    condition = var.load_balancer == null || try(
      var.load_balancer.type == "classic" ? length(var.load_balancer.target_groups) == 0 && length(var.load_balancer.listeners) == 0 : (
        length(var.load_balancer.target_groups) >= 1 && length(var.load_balancer.listeners) >= 1 && length(var.load_balancer.classic_listeners) == 0
      ),
    false)
    error_message = "load_balancer: an application or network load balancer needs target_groups and listeners, and no classic_listeners; a classic one needs classic_listeners, and no target_groups or listeners."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for tg in values(var.load_balancer.target_groups) :
      tg.port >= 1 && tg.port <= 65535 && floor(tg.port) == tg.port &&
      contains(var.load_balancer.type == "application" ? ["HTTP", "HTTPS"] : ["TCP", "TLS", "UDP", "TCP_UDP"], tg.protocol) &&
      (tg.protocol_version == null ? true : var.load_balancer.type == "application" && contains(["HTTP1", "HTTP2", "GRPC"], tg.protocol_version)) &&
      (tg.load_balancing_algorithm_type == null ? true : var.load_balancer.type == "application" && contains(["round_robin", "least_outstanding_requests"], tg.load_balancing_algorithm_type)) &&
      (tg.proxy_protocol_v2 == null || var.load_balancer.type == "network") &&
      (tg.preserve_client_ip == null || var.load_balancer.type == "network") &&
      (tg.preserve_client_ip != false || !contains(["UDP", "TCP_UDP"], tg.protocol)) &&
      tg.deregistration_delay >= 0 && tg.deregistration_delay <= 3600
    ]), false)
    error_message = "load_balancer: each target group needs port from 1 to 65535 and protocol HTTP or HTTPS (application) or TCP, TLS, UDP or TCP_UDP (network); protocol_version (HTTP1, HTTP2, GRPC) and load_balancing_algorithm_type (round_robin, least_outstanding_requests) are for application, preserve_client_ip and proxy_protocol_v2 for network, and UDP and TCP_UDP target groups cannot turn preserve_client_ip off; deregistration_delay is 0 to 3600."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for tg in values(var.load_balancer.target_groups) :
      tg.stickiness == null ? true : contains(var.load_balancer.type == "application" ? ["lb_cookie", "app_cookie"] : ["source_ip"], tg.stickiness.type)
    ]), false)
    error_message = "load_balancer: target group stickiness.type must be lb_cookie or app_cookie (application) or source_ip (network)."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for tg in values(var.load_balancer.target_groups) :
      tg.health_check.port == "traffic-port" || try(tonumber(tg.health_check.port) >= 1 && tonumber(tg.health_check.port) <= 65535 && can(regex("^[0-9]+$", tg.health_check.port)), false)
    ]), false)
    error_message = "load_balancer: target group health_check.port must be traffic-port or a port number from 1 to 65535."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for l in values(var.load_balancer.listeners) :
      l.port >= 1 && l.port <= 65535 && floor(l.port) == l.port &&
      contains(var.load_balancer.type == "application" ? ["HTTP", "HTTPS"] : ["TCP", "TLS", "UDP", "TCP_UDP"], l.protocol)
    ]), false)
    error_message = "load_balancer: each listener needs port from 1 to 65535 and protocol HTTP or HTTPS (application) or TCP, TLS, UDP or TCP_UDP (network)."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for l in values(var.load_balancer.listeners) :
      length([for a in [l.target_group, l.redirect, l.fixed_response] : a if a != null]) == 1 &&
      (l.target_group == null || contains(keys(var.load_balancer.target_groups), coalesce(l.target_group, "-"))) &&
      (var.load_balancer.type == "application" || l.target_group != null)
    ]), false)
    error_message = "load_balancer: each listener needs exactly one action: target_group, naming a key of target_groups, or (application only) redirect or fixed_response."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for l in values(var.load_balancer.listeners) :
      contains(["HTTPS", "TLS"], l.protocol) ? (l.certificate_arn != null && startswith(coalesce(l.certificate_arn, "-"), "arn:")) : (l.certificate_arn == null && l.alpn_policy == null)
    ]), false)
    error_message = "load_balancer: HTTPS and TLS listeners need certificate_arn, the ARN of a certificate; other listeners take no certificate_arn or alpn_policy."
  }

  validation {
    condition = var.load_balancer == null || try(alltrue([
      for l in values(var.load_balancer.listeners) :
      (l.alpn_policy == null ? true : l.protocol == "TLS" && contains(["HTTP1Only", "HTTP2Only", "HTTP2Optional", "HTTP2Preferred", "None"], l.alpn_policy)) &&
      (l.redirect == null ? true : contains(["HTTP_301", "HTTP_302"], l.redirect.status_code)) &&
      (l.fixed_response == null ? true : contains(["text/plain", "text/css", "text/html", "application/javascript", "application/json"], l.fixed_response.content_type))
    ]), false)
    error_message = "load_balancer: alpn_policy (TLS listeners only) must be HTTP1Only, HTTP2Only, HTTP2Optional, HTTP2Preferred or None; redirect.status_code HTTP_301 or HTTP_302; fixed_response.content_type text/plain, text/css, text/html, application/javascript or application/json."
  }

  validation {
    condition = var.load_balancer == null || try(
      length(distinct([for l in values(var.load_balancer.listeners) : l.port])) == length(var.load_balancer.listeners) &&
      length(distinct([for l in values(var.load_balancer.classic_listeners) : l.lb_port])) == length(var.load_balancer.classic_listeners),
    false)
    error_message = "load_balancer: two listeners use the same port."
  }

  # Classic Load Balancers.
  validation {
    condition = var.load_balancer == null || try(var.load_balancer.type != "classic" || (
      length(var.load_balancer.classic_listeners) >= 1 &&
      alltrue([
        for l in values(var.load_balancer.classic_listeners) :
        alltrue([for p in [l.lb_port, l.instance_port] : p >= 1 && p <= 65535 && floor(p) == p]) &&
        contains(["HTTP", "HTTPS", "TCP", "SSL"], l.lb_protocol) && contains(["HTTP", "HTTPS", "TCP", "SSL"], l.instance_protocol) &&
        (contains(["HTTPS", "SSL"], l.lb_protocol) ? startswith(coalesce(l.ssl_certificate_id, "-"), "arn:") : l.ssl_certificate_id == null)
      ])
    ), false)
    error_message = "load_balancer: a classic load balancer needs one or more classic_listeners, each with lb_port and instance_port from 1 to 65535, lb_protocol and instance_protocol HTTP, HTTPS, TCP or SSL, and ssl_certificate_id (a certificate ARN) only and always for HTTPS and SSL."
  }

  validation {
    condition = var.load_balancer == null || try(
      var.load_balancer.classic_health_check.target == null || can(regex("^(TCP|SSL):[0-9]{1,5}$|^(HTTP|HTTPS):[0-9]{1,5}/.*$", var.load_balancer.classic_health_check.target)),
    false)
    error_message = "load_balancer: classic_health_check.target must be TCP:<port>, SSL:<port>, HTTP:<port>/<path> or HTTPS:<port>/<path>, such as HTTP:80/health."
  }

  validation {
    condition     = var.load_balancer == null || try(var.load_balancer.connection_draining_timeout >= 0 && var.load_balancer.connection_draining_timeout <= 3600, false)
    error_message = "load_balancer: connection_draining_timeout must be from 0 to 3600 seconds."
  }
}

variable "os" {
  description = <<-EOT
    The operating system of the AMI: `al2023` (Amazon Linux 2023), `ubuntu22` (Ubuntu 22.04 LTS) or `ubuntu24` (Ubuntu 24.04 LTS). It picks the AMI when `ami_id` is not set, and the commands the instances run at boot.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = contains(["al2023", "ubuntu22", "ubuntu24"], var.os)
    error_message = "os must be al2023, ubuntu22 or ubuntu24."
  }
}

variable "parameter_store" {
  description = <<-EOT
    AWS Systems Manager Parameter Store paths the instances may read, such as configuration and secrets an application loads at boot. Defaults to none.

    - `paths` - (Optional) Paths such as `/secrets/automate_the_cloud/web_site/production`. The instances may read every parameter under each path, at any depth, one at a time (`ssm:GetParameter`), several by name (`ssm:GetParameters`), or the whole path at once (`ssm:GetParametersByPath`, which IAM checks against the path itself as well as the parameters under it). Each starts with `/`, does not end with `/`, and is not `/` alone. AWS reserves paths that start with `/aws` or `/ssm`.
    - `kms_key_arns` - (Optional) ARNs of the KMS keys that encrypt `SecureString` parameters under those paths. The instances may decrypt with them only parameters under `paths`, only through Parameter Store, in this Region. Needs `paths`. Not needed for parameters encrypted with the AWS managed key `aws/ssm`. Each key's policy must let IAM policies in the account grant its use, as the default key policy does.

    `AmazonSSMManagedInstanceCore` (see `iam_role`) already lets the instances read any parameter in the account by its name, and decrypt it with `aws/ssm`: AWS includes `ssm:GetParameter` and `ssm:GetParameters` on every parameter in it. `paths` adds reading a whole path and limits nothing. To limit reading to these paths, set `iam_role.ssm_managed_instance_core = false` and give the instances the Systems Manager permissions they need some other way.
  EOT
  type = object({
    paths        = optional(list(string), [])
    kms_key_arns = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for p in var.parameter_store.paths :
      can(regex("^(/[A-Za-z0-9_.-]+)+$", p)) && !can(regex("^/(aws|ssm)", lower(p)))
    ]) && length(distinct(var.parameter_store.paths)) == length(var.parameter_store.paths)
    error_message = "parameter_store: each path must start with /, contain only letters, numbers, periods, hyphens, underscores and single slashes between names, not end with /, and not start with /aws or /ssm (reserved by AWS), and appear once."
  }

  validation {
    condition     = alltrue([for k in var.parameter_store.kms_key_arns : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", k))])
    error_message = "parameter_store: kms_key_arns must be KMS key ARNs, such as arn:aws:kms:us-east-1:123456789012:key/<key id>. Aliases are not accepted."
  }

  validation {
    condition     = length(var.parameter_store.kms_key_arns) == 0 || length(var.parameter_store.paths) > 0
    error_message = "parameter_store: kms_key_arns needs paths: the instances may decrypt only parameters under them."
  }
}

variable "region" {
  description = <<-EOT
    The AWS Region to create the instances and everything else in, such as `us-west-2`. Defaults to the Region of the AWS provider passed to the module.
  EOT
  type        = string
  default     = null
}

variable "resource_signals" {
  description = <<-EOT
    Wait for each new instance to report that its setup at boot succeeded. Each instance runs the boot commands, then the scripts in `user_data_scripts`, and sends AWS CloudFormation a success or failure signal.

    - `enabled` - (Optional) Defaults to `true`. When the group is created, the apply waits for a success signal from each instance in `desired_capacity` (or `min_size`) and fails if one fails or does not report in time. With weights in `instance_types`, it waits for the fewest instances that can make up that capacity: the capacity divided by the largest weight, rounded up. In a rolling update, each batch waits the same way, and a failure rolls the whole update back.
    - `timeout` - (Optional) How long to wait for each instance, as an ISO 8601 duration from `PT1M` to `PT1H`, such as `PT15M`. Defaults to `PT15M`.

    With `false`, the apply finishes as soon as the instances are launched, and a rolling update waits `rolling_update.pause_time` between batches.
  EOT
  type = object({
    enabled = optional(bool, true)
    timeout = optional(string, "PT15M")
  })
  default  = {}
  nullable = false

  validation {
    condition = can(regex("^PT([0-9]+H)?([0-9]+M)?([0-9]+S)?$", var.resource_signals.timeout)) && var.resource_signals.timeout != "PT" && try(
      sum([for u in regexall("([0-9]+)([HMS])", var.resource_signals.timeout) : tonumber(u[0]) * { H = 3600, M = 60, S = 1 }[u[1]]]) >= 60 &&
      sum([for u in regexall("([0-9]+)([HMS])", var.resource_signals.timeout) : tonumber(u[0]) * { H = 3600, M = 60, S = 1 }[u[1]]]) <= 3600,
    false)
    error_message = "resource_signals: timeout must be an ISO 8601 duration from PT1M to PT1H, such as PT15M."
  }
}

variable "rolling_update" {
  description = <<-EOT
    How AWS CloudFormation replaces the instances when the launch template changes: a new AMI, user data, volumes or any other setting in it. It replaces them in batches. A change to `instance_types` or the On-Demand and Spot settings alone does not replace running instances; only instances launched afterward use it.

    - `max_batch_size` - (Optional) The most instances replaced at once. Defaults to `1`.
    - `min_instances_in_service` - (Optional) How many instances must stay in service during the update. Defaults to `0`. Must be less than `auto_scaling_group.max_size`. CloudFormation terminates each batch's old instances before it launches their replacements.
    - `min_successful_instances_percent` - (Optional) With `resource_signals`, the percentage of instances in each batch that must signal success, from 0 to 100. Defaults to `100`.
    - `pause_time` - (Optional) Without `resource_signals`, how long to wait after each batch, as an ISO 8601 duration up to `PT1H`. Defaults to `PT0S`.
  EOT
  type = object({
    max_batch_size                   = optional(number, 1)
    min_instances_in_service         = optional(number, 0)
    min_successful_instances_percent = optional(number, 100)
    pause_time                       = optional(string, "PT0S")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.rolling_update.max_batch_size >= 1 && floor(var.rolling_update.max_batch_size) == var.rolling_update.max_batch_size && var.rolling_update.min_instances_in_service >= 0 && floor(var.rolling_update.min_instances_in_service) == var.rolling_update.min_instances_in_service
    error_message = "rolling_update: max_batch_size must be a whole number, 1 or more, and min_instances_in_service a whole number, 0 or more."
  }

  validation {
    condition     = var.rolling_update.min_instances_in_service < var.auto_scaling_group.max_size
    error_message = "rolling_update: min_instances_in_service must be less than auto_scaling_group.max_size."
  }

  validation {
    condition     = var.rolling_update.min_successful_instances_percent >= 0 && var.rolling_update.min_successful_instances_percent <= 100
    error_message = "rolling_update: min_successful_instances_percent must be from 0 to 100."
  }

  validation {
    condition = can(regex("^PT([0-9]+H)?([0-9]+M)?([0-9]+S)?$", var.rolling_update.pause_time)) && var.rolling_update.pause_time != "PT" && try(
      sum(concat([0], [for u in regexall("([0-9]+)([HMS])", var.rolling_update.pause_time) : tonumber(u[0]) * { H = 3600, M = 60, S = 1 }[u[1]]])) <= 3600,
    false)
    error_message = "rolling_update: pause_time must be an ISO 8601 duration up to PT1H, such as PT5M."
  }
}

variable "security_group_egress" {
  description = <<-EOT
    Where the instances may connect to. The module creates a security group for the instances with these outbound rules, keyed by names you choose. Defaults to HTTPS (TCP 443) and HTTP (TCP 80) to any IPv4 address, which the boot commands need for package updates and to reach AWS services, unless the VPC has endpoints for them. Setting this replaces the defaults; include them if the instances still need them. Rules to the load balancer and the EFS file system are added on their own.

    Each rule takes:

    - `ip_protocol` - (Optional) `tcp`, `udp`, `icmp`, `icmpv6`, or `-1` for every protocol. Defaults to `tcp`.
    - `from_port` - For `tcp` and `udp`, (Required) the first port. For `icmp` and `icmpv6`, (Optional) the ICMP type, defaults to `-1`, every type. Must be left out for `-1`.
    - `to_port` - (Optional) For `tcp` and `udp`, the last port, defaults to `from_port`. For `icmp` and `icmpv6`, the ICMP code, defaults to `-1`.
    - `description` - (Optional) Defaults to the key. Up to 255 characters: letters, numbers, spaces and `._-:/()#,@[]+=&;{}!$*`.

    and exactly one destination: `cidr_ipv4`, such as `10.0.0.0/16`; `cidr_ipv6`, such as `2600:1f18:1234:5600::/56`; `prefix_list_id`, such as the AWS-managed list for Amazon S3; or `security_group_id`.
  EOT
  type = map(object({
    ip_protocol       = optional(string, "tcp")
    from_port         = optional(number)
    to_port           = optional(number)
    description       = optional(string)
    cidr_ipv4         = optional(string)
    cidr_ipv6         = optional(string)
    prefix_list_id    = optional(string)
    security_group_id = optional(string)
  }))
  default = {
    https = { ip_protocol = "tcp", from_port = 443, cidr_ipv4 = "0.0.0.0/0", description = "HTTPS to anywhere" }
    http  = { ip_protocol = "tcp", from_port = 80, cidr_ipv4 = "0.0.0.0/0", description = "HTTP to anywhere" }
  }
  nullable = false

  validation {
    condition = alltrue([
      for r in values(var.security_group_egress) :
      length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.security_group_id] : v if v != null]) == 1
    ])
    error_message = "Each security_group_egress rule needs exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or security_group_id."
  }

  validation {
    condition = alltrue([
      for r in values(var.security_group_egress) :
      contains(["tcp", "udp"], r.ip_protocol) ? (
        r.from_port != null && try(r.from_port >= 0 && r.from_port <= 65535 && floor(r.from_port) == r.from_port, false) &&
        (r.to_port == null || try(r.to_port >= r.from_port && r.to_port <= 65535 && floor(r.to_port) == r.to_port, false))
        ) : contains(["icmp", "icmpv6"], r.ip_protocol) ? alltrue([for p in [r.from_port, r.to_port] : p == null || try(p >= -1 && p <= 255 && floor(p) == p, false)]) : (
        r.ip_protocol == "-1" && r.from_port == null && r.to_port == null
      )
    ])
    error_message = "security_group_egress: ip_protocol must be tcp, udp, icmp, icmpv6 or -1. tcp and udp rules need from_port, from 0 to 65535, and to_port, if set, from from_port to 65535; icmp and icmpv6 ports are from -1 to 255; -1 takes no ports."
  }

  validation {
    condition = alltrue([
      for r in values(var.security_group_egress) :
      (r.cidr_ipv4 == null || try(cidrsubnet(r.cidr_ipv4, 0, 0) == r.cidr_ipv4 && !strcontains(r.cidr_ipv4, ":"), false)) &&
      (r.cidr_ipv6 == null || try(cidrsubnet(r.cidr_ipv6, 0, 0) == r.cidr_ipv6 && strcontains(r.cidr_ipv6, ":"), false)) &&
      (r.prefix_list_id == null || can(regex("^pl-[0-9a-f]+$", r.prefix_list_id))) &&
      (r.security_group_id == null || can(regex("^sg-[0-9a-f]+$", r.security_group_id)))
    ])
    error_message = "security_group_egress: cidr_ipv4 must be an IPv4 range starting at its first address, such as 10.0.0.0/16; cidr_ipv6 an IPv6 range in the short lowercase form, such as 2600:1f18:1234:5600::/56; prefix_list_id a prefix list ID (pl-...); security_group_id a security group ID (sg-...)."
  }

  validation {
    condition = alltrue([
      for k, r in var.security_group_egress :
      can(regex("^[A-Za-z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", coalesce(r.description, k)))
    ])
    error_message = "security_group_egress: each description (the key, when description is not set) must be 1 to 255 characters: letters, numbers, spaces and ._-:/()#,@[]+=&;{}!$*."
  }
}

variable "security_group_ingress" {
  description = <<-EOT
    Who may connect to the instances directly, besides the load balancer, which the module allows on its own. Rules for the instances' security group, keyed by names you choose, with the same attributes as `security_group_egress`, each with exactly one source. Defaults to `{}`: nothing may connect directly. Session Manager needs no inbound rule.
  EOT
  type = map(object({
    ip_protocol       = optional(string, "tcp")
    from_port         = optional(number)
    to_port           = optional(number)
    description       = optional(string)
    cidr_ipv4         = optional(string)
    cidr_ipv6         = optional(string)
    prefix_list_id    = optional(string)
    security_group_id = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for r in values(var.security_group_ingress) :
      length([for v in [r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.security_group_id] : v if v != null]) == 1
    ])
    error_message = "Each security_group_ingress rule needs exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id or security_group_id."
  }

  validation {
    condition = alltrue([
      for r in values(var.security_group_ingress) :
      contains(["tcp", "udp"], r.ip_protocol) ? (
        r.from_port != null && try(r.from_port >= 0 && r.from_port <= 65535 && floor(r.from_port) == r.from_port, false) &&
        (r.to_port == null || try(r.to_port >= r.from_port && r.to_port <= 65535 && floor(r.to_port) == r.to_port, false))
        ) : contains(["icmp", "icmpv6"], r.ip_protocol) ? alltrue([for p in [r.from_port, r.to_port] : p == null || try(p >= -1 && p <= 255 && floor(p) == p, false)]) : (
        r.ip_protocol == "-1" && r.from_port == null && r.to_port == null
      )
    ])
    error_message = "security_group_ingress: ip_protocol must be tcp, udp, icmp, icmpv6 or -1. tcp and udp rules need from_port, from 0 to 65535, and to_port, if set, from from_port to 65535; icmp and icmpv6 ports are from -1 to 255; -1 takes no ports."
  }

  validation {
    condition = alltrue([
      for r in values(var.security_group_ingress) :
      (r.cidr_ipv4 == null || try(cidrsubnet(r.cidr_ipv4, 0, 0) == r.cidr_ipv4 && !strcontains(r.cidr_ipv4, ":"), false)) &&
      (r.cidr_ipv6 == null || try(cidrsubnet(r.cidr_ipv6, 0, 0) == r.cidr_ipv6 && strcontains(r.cidr_ipv6, ":"), false)) &&
      (r.prefix_list_id == null || can(regex("^pl-[0-9a-f]+$", r.prefix_list_id))) &&
      (r.security_group_id == null || can(regex("^sg-[0-9a-f]+$", r.security_group_id)))
    ])
    error_message = "security_group_ingress: cidr_ipv4 must be an IPv4 range starting at its first address, such as 10.0.0.0/16; cidr_ipv6 an IPv6 range in the short lowercase form, such as 2600:1f18:1234:5600::/56; prefix_list_id a prefix list ID (pl-...); security_group_id a security group ID (sg-...)."
  }

  validation {
    condition = alltrue([
      for k, r in var.security_group_ingress :
      can(regex("^[A-Za-z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", coalesce(r.description, k)))
    ])
    error_message = "security_group_ingress: each description (the key, when description is not set) must be 1 to 255 characters: letters, numbers, spaces and ._-:/()#,@[]+=&;{}!$*."
  }
}

variable "session_manager" {
  description = <<-EOT
    Permissions for Session Manager features that the account's Session Manager preferences turn on, besides what `iam_role.ssm_managed_instance_core` grants. Defaults to none.

    - `log_bucket` - (Optional) The S3 bucket that session logs are written to: `arn` (Required), the bucket's ARN, and `prefix` (Optional), the key prefix the preferences name; without it, the whole bucket. The instances may write objects there (`s3:PutObject`).
    - `kms_key_arns` - (Optional) ARNs of KMS keys the instances use for Session Manager: the key that encrypts session data, and the key of an S3 log bucket encrypted with SSE-KMS. The instances may use them with `kms:Decrypt` and `kms:GenerateDataKey`. Each key's policy must let IAM policies in the account grant its use, as the default key policy does.

    `aws ssm get-document --name SSM-SessionManagerRunShell --query Content --output text` shows the preferences: `s3BucketName`, `s3KeyPrefix`, `cloudWatchLogGroupName` and `kmsKeyId`.
  EOT
  type = object({
    log_bucket = optional(object({
      arn    = string
      prefix = optional(string)
    }))
    kms_key_arns = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.session_manager.log_bucket == null ? true : can(regex("^arn:[a-z-]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.session_manager.log_bucket.arn))
    error_message = "session_manager: log_bucket.arn must be the ARN of an S3 bucket, such as arn:aws:s3:::my-session-logs."
  }

  validation {
    condition     = alltrue([for k in var.session_manager.kms_key_arns : can(regex("^arn:[a-z-]+:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", k))])
    error_message = "session_manager: kms_key_arns must be KMS key ARNs, such as arn:aws:kms:us-east-1:123456789012:key/<key id>. Aliases are not accepted."
  }
}

variable "subnet_ids" {
  description = <<-EOT
    IDs of the subnets to launch the instances in, in `vpc_id`, such as one private subnet per Availability Zone. The Auto Scaling group spreads the instances across their zones.
  EOT
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0 && alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) && length(distinct(var.subnet_ids)) == length(var.subnet_ids)
    error_message = "subnet_ids must list one or more subnet IDs, such as subnet-0123456789abcdef0, each once."
  }
}

variable "swap_size_mb" {
  description = <<-EOT
    The size of a swap file to create on each instance at `/var/swapfile`, in MiB. Defaults to `2048`. `0` creates none.
  EOT
  type        = number
  default     = 2048
  nullable    = false

  validation {
    condition     = var.swap_size_mb >= 0 && var.swap_size_mb <= 1048576 && floor(var.swap_size_mb) == var.swap_size_mb
    error_message = "swap_size_mb must be a whole number from 0 to 1048576."
  }
}

variable "timeouts" {
  description = <<-EOT
    How long Terraform waits for the CloudFormation stack, which holds the launch template and the Auto Scaling group, to be created, updated or deleted, such as `45m`. A rolling update of many instances can take longer than the defaults: `30m` to create, `60m` to update, `30m` to delete.
  EOT
  type = object({
    create = optional(string, "30m")
    update = optional(string, "60m")
    delete = optional(string, "30m")
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for t in [var.timeouts.create, var.timeouts.update, var.timeouts.delete] : can(regex("^[0-9]+(s|m|h)$", t))])
    error_message = "timeouts values must be durations such as 90m or 2h."
  }
}

variable "update_packages" {
  description = <<-EOT
    Install the latest updates of every package when an instance boots (`dnf upgrade` or `apt-get upgrade`). Defaults to `true`. It makes boots slower, and two instances launched days apart may run different package versions; with `false`, the instances run what the AMI has.
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "user_data_scripts" {
  description = <<-EOT
    Your own scripts to run on each instance at its first boot, as root, in order, after the module's own setup, such as `[file("$${path.module}/setup.sh")]`. Each is the full text of a script and starts with `#!`, such as `#!/bin/bash`. If one exits with an error, the rest do not run and, with `resource_signals`, the instance reports a failure. Defaults to none.

    Changing a script replaces every instance through a rolling update. User data, with the module's own commands, may be up to 16 KB.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.user_data_scripts : startswith(s, "#!")])
    error_message = "Each of user_data_scripts must start with #!, such as #!/bin/bash."
  }
}

variable "volumes" {
  description = <<-EOT
    The EBS volumes of each instance. Every volume is encrypted, and deleted with the instance.

    - `root` - (Optional) The root volume: `size_gb` (defaults to `20`), `type` (`gp3`, the default, `gp2`, `io1` or `io2`), `iops` and `throughput` (MiB/s, `gp3` only). Defaults to `{}`.
    - `data` - (Optional) Empty data volumes, attached as `/dev/sdb`, `/dev/sdc` and so on (Linux may name them `/dev/nvme1n1` and up): `count` (from 0 to 25, defaults to `0`), and `size_gb`, `type` (also `st1` and `sc1`), `iops` and `throughput` as for `root`. The module does not format or mount them; do that in `user_data_scripts`.
    - `kms_key_id` - (Optional) The ARN of the KMS key to encrypt the volumes with. Defaults to `null`: the account's default EBS key. Its key policy must allow the `AWSServiceRoleForAutoScaling` service-linked role to use it and create grants, or no instance can launch.
  EOT
  type = object({
    root = optional(object({
      size_gb    = optional(number, 20)
      type       = optional(string, "gp3")
      iops       = optional(number)
      throughput = optional(number)
    }), {})
    data = optional(object({
      count      = optional(number, 0)
      size_gb    = optional(number, 20)
      type       = optional(string, "gp3")
      iops       = optional(number)
      throughput = optional(number)
    }), {})
    kms_key_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.volumes.root.type) && contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], var.volumes.data.type)
    error_message = "volumes: root.type must be gp3, gp2, io1 or io2, and data.type one of those, st1 or sc1."
  }

  validation {
    condition     = alltrue([for v in [var.volumes.root, var.volumes.data] : v.size_gb >= 1 && v.size_gb <= 65536 && floor(v.size_gb) == v.size_gb])
    error_message = "volumes: size_gb must be a whole number from 1 to 65536."
  }

  validation {
    condition = alltrue([
      for v in [var.volumes.root, var.volumes.data] :
      (v.iops == null || contains(["gp3", "io1", "io2"], v.type)) && (v.throughput == null || v.type == "gp3") && (contains(["io1", "io2"], v.type) ? v.iops != null : true)
    ])
    error_message = "volumes: iops is for gp3, io1 and io2 volumes, and required for io1 and io2; throughput is for gp3 only."
  }

  validation {
    condition     = var.volumes.data.count >= 0 && var.volumes.data.count <= 25 && floor(var.volumes.data.count) == var.volumes.data.count
    error_message = "volumes: data.count must be a whole number from 0 to 25."
  }

  validation {
    condition     = var.volumes.kms_key_id == null || startswith(coalesce(var.volumes.kms_key_id, "-"), "arn:")
    error_message = "volumes: kms_key_id must be the ARN of a KMS key."
  }
}

variable "vpc_id" {
  description = <<-EOT
    The ID of the VPC the instances are in, such as `vpc-0123456789abcdef0`: the VPC of `subnet_ids`. The module creates the instances' security group, and the load balancer's, in it.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID, such as vpc-0123456789abcdef0."
  }
}
