# Security

## Reporting a vulnerability

Report security problems privately, not in a public issue. On GitHub, open the repository's **Security** tab and choose **Report a vulnerability**. Only the maintainers can see the report.

Include what you found, how to reproduce it, and what an attacker could do with it.

## What counts

A security problem in this module is anything that makes the instances, their load balancer or their data more exposed than the inputs say they should be: for example, a default that allows inbound network access, a public address or an internet-facing load balancer, IMDSv1, an unencrypted volume or file system connection, a security group rule or IAM permission broader than documented, a boot command that runs something it should not, or a validation that lets an insecure value through.

## Supported versions

Fixes are made to the latest release.
