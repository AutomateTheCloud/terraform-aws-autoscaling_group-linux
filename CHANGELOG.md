# Changelog

All notable changes to this module are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module uses [semantic versioning](https://semver.org/): a new major version means callers must change their code.

## [Unreleased]

## [1.0.0] - 2026-10-07

Initial release.

### Added

- Linux EC2 instances in an Auto Scaling group, from a launch template, both in an AWS CloudFormation stack: Amazon Linux 2023, Ubuntu 22.04 or Ubuntu 24.04, on x86_64 or AWS Graviton, with the newest AMI from AWS's public parameters or your own.
- Setup at boot that each instance reports to CloudFormation: package updates, a swap file, the Amazon CloudWatch agent with log groups the module creates, an Amazon EFS mount with TLS, the AWS CodeDeploy agent (installed when the AMI does not have it, and checked to be running), and your own scripts.
- Rolling replacement of the instances when the launch template changes, waiting for each new instance's setup and rolling back on failure; setup changes applied to running instances.
- Secure defaults: no public IP addresses, no inbound access, IMDSv2 only, encrypted volumes, and an IAM role limited to AWS Systems Manager (including Session Manager, session logging and the SSM Agent's AWS-owned S3 buckets in the Region) and the module's own log groups. The role's policies are attached before any instance launches.
- `session_manager`, for Session Manager features that need your own resources: an S3 bucket for session logs, and KMS keys for encrypted sessions.
- Parameter Store access by path, with decryption limited to those paths.
- Mixed On-Demand and Spot capacity across several instance types, with weights.
- An optional Application, Network or Classic Load Balancer, internal by default, with target groups, listeners, TLS 1.2 and 1.3 security policies, access logs and Elastic IP addresses, and security group rules limited to the target and health check ports.
- An optional CodeDeploy deployment group for the Auto Scaling group.
- `region`, to create everything in a Region other than the provider's.
- A `metadata` output with everything the module created.
- Offline tests, and examples for a basic deployment, a complete one, Network and Classic Load Balancers, Spot Instances, a pinned AMI with rolling updates, and Parameter Store.

[Unreleased]: https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/releases/tag/v1.0.0
