# Changelog

All notable changes to this module are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module uses [semantic versioning](https://semver.org/): a new major version means callers must change their code.

## [Unreleased]

## [1.0.1] - 2026-10-07

### Fixed

- On Ubuntu, a boot could fail when Ubuntu's automatic updates (`unattended-upgrades`, `apt-daily`) held apt's locks: `apt-get` failed at once, the CloudFormation helper scripts were not installed, and the instance never ran its setup or reported. The boot commands now pause those jobs' timers until they end, wait for a run in progress, and run every `apt-get`, including the setup steps' installs, with `DPkg::Lock::Timeout`. The CloudWatch agent's package is installed with `apt-get` instead of `dpkg`, so it waits for the lock too.
- On Ubuntu, a failed `apt-get upgrade` (`update_packages`) or a failed install of the helper scripts let the boot carry on, so an instance could run without its updates and report success. Both now stop the boot with a failure signal; the helper scripts are set up before the updates, so a failed update can send it.
- On an AMI that starts its own `cfn-hup` from an init script, `cfn-hup` never ran, so setup changes did not reach running instances. Without a configuration that script fails, but systemd still records `cfn-hup.service` as started, and the module's `systemctl start cfn-hup` then did nothing. The boot commands now stop it before the setup writes the module's `cfn-hup.service`.

### Changed

- On Ubuntu, an AMI's own CloudFormation helper scripts (such as in `/usr/local/bin`) are linked into `/opt/aws/cfn-bootstrap/bin` instead of being installed again.
- Changing to this version changes the Ubuntu user data and setup steps, which replaces Ubuntu instances in a rolling update. Amazon Linux 2023 instances are not changed.

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

[Unreleased]: https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/releases/tag/v1.0.0
