# Terraform module for Linux instances in an Auto Scaling group

Runs a fleet of Linux servers on Amazon EC2 that sets itself up, heals itself, and updates itself safely. You describe the servers in Terraform: the operating system, how many, what they run at boot, and whether a load balancer sits in front of them. The module creates everything around them and keeps them running:

- An **Auto Scaling group** keeps the number of instances you ask for, replacing any that fail, across the Availability Zones of your subnets.
- Each instance **sets itself up at its first boot**: it installs updates, creates a swap file, starts the Amazon CloudWatch agent, mounts a shared file system, installs the AWS CodeDeploy agent, and runs your own scripts. Then it **reports whether all of that worked**, and Terraform waits for the answer.
- A change, such as a new AMI, **replaces the instances a few at a time**, keeps the rest in service, and **undoes itself** if the new instances fail.
- Optionally, an **Application, Network or Classic Load Balancer** sends traffic to the healthy instances, **AWS CodeDeploy** deploys your application to them, an **Amazon EFS** file system is shared between them, and **AWS Systems Manager Parameter Store** gives them their configuration and secrets.

Each instance runs Amazon Linux 2023, Ubuntu 22.04 or Ubuntu 24.04, on Intel and AMD (`x86_64`) or AWS Graviton (`arm64`) processors.

The defaults are the settings most deployments should have. Instances created with only the required inputs have no public IP address, accept no inbound connections, require IMDSv2, encrypt their volumes, and can be managed with AWS Systems Manager, including a shell through Session Manager, with no SSH key or open port.

## What the module creates

```
                         ┌───────────────────────── AWS CloudFormation stack ─────────────────────────┐
  clients in your VPC    │                                                                            │
          │              │   Launch template ──────────▶ Auto Scaling group                           │
          ▼              │   (AMI, volumes, IMDSv2,       (min/max/desired, On-Demand and Spot,       │
  ┌───────────────┐      │    user data, setup steps)      rolling updates, success signals)          │
  │ Load balancer │      │                                   │         │         │                    │
  │  (optional)   │──────┼──────────────────────────────▶ instance  instance  instance                │
  └───────────────┘      │                                                                            │
   security group        └────────────────────────────────────────────────────────────────────────────┘
                            instances' security group · IAM role and instance profile · log groups
                            CodeDeploy deployment group (optional) · EFS rules (optional)
```

Terraform creates the parts outside the box as ordinary Terraform resources: the security groups and their rules, the IAM role and instance profile the instances use, the CloudWatch log groups, the load balancer with its target groups and listeners, the CodeDeploy deployment group, and the rules that let the instances reach an EFS file system. It also creates the CloudFormation stack, which holds the launch template and the Auto Scaling group. The next section explains why those two are in a stack.

## Why a CloudFormation stack inside a Terraform module

Most Terraform modules for Auto Scaling groups create the launch template and the group as Terraform resources. This one puts those two in an AWS CloudFormation stack that Terraform creates and updates, and keeps everything around them as Terraform resources. You still define and change the whole deployment in Terraform, with one `terraform apply`; CloudFormation adds what only it does for instances:

- **Ready means the instance says it is ready.** Each instance runs its whole setup, including your `user_data_scripts`, and then reports success or failure to CloudFormation (`cfn-signal`). An instance that is running and passes its EC2 or load balancer health check, but whose setup failed, counts as failed. Terraform's own Auto Scaling group can wait for instances to be in service or healthy behind a load balancer, but cannot see whether your setup finished.
- **The apply waits for the rollout, and fails if it fails.** A change to the launch template, such as a new AMI, replaces the instances in batches as part of the stack update, and the Terraform apply finishes only when the last batch has reported success. With Terraform's own Auto Scaling group, an instance refresh starts when the group changes, and the AWS provider documents that it "does not wait for the instance refresh to complete": the apply succeeds even if the refresh fails later.
- **A failed rollout undoes itself.** When a batch fails or does not report in time, CloudFormation rolls the whole update back: it returns the group to the previous launch template and replaces the failed instances with new ones built from it. The apply fails with the reason, and Terraform still records the previous configuration, so the next plan shows your change again. When a new group's instances fail, the stack is rolled back, and the next apply creates it again.
- **Setup changes reach running instances without replacing them.** The setup (the swap file, the CloudWatch agent's configuration, the EFS mount, the CodeDeploy agent) is declared in the launch template's `AWS::CloudFormation::Init` metadata: files, commands and services, in named steps, which run the same way at first boot and on later changes. When only the setup changes, each instance's CloudFormation helper daemon (`cfn-hup`) applies it within minutes. Terraform has no equivalent for software on running instances.
- **Scaling does not fight a rollout.** During a rolling update, CloudFormation suspends health check replacement, Availability Zone rebalancing, alarm actions and scheduled actions, so they do not launch or terminate instances in the middle of it. A capacity that a scaling policy or a person set outside Terraform is kept when the stack is updated.
- **Every rollout has a record.** The stack's events, in the CloudFormation console or `aws cloudformation describe-stack-events`, list each batch, each instance's signal, and the reason for any failure or rollback.
- **More of AWS is available.** Features that exist only in CloudFormation can be added to the stack without changing how you deploy, such as rollback triggers that undo an update when a CloudWatch alarm fires during it, stack policies and termination protection.

The approach has costs too, which the rest of this README explains where they matter:

- The Terraform plan shows a change to the stack's template, not resource by resource changes to the launch template and the group. The rollout itself is in the stack events, not in Terraform's output.
- CloudFormation accepts a template of up to 51,200 bytes, which limits how much your scripts can hold (see [Size limits](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#size-limits)).
- Some changes do not start a rolling update: CloudFormation replaces instances only when the launch template changes (see [Changing a deployment](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#changing-a-deployment)).
- When something fails, the Terraform error names the stack; the details are in its events and in the instances' logs (see [Troubleshooting](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#troubleshooting)).

## What it configures

| Setting | Default | Input |
|---|---|---|
| Operating system and architecture | Required; `x86_64` | `os`, `architecture` |
| AMI | The newest for the operating system, from AWS's public parameters | `ami_id` |
| Instances | 1 (minimum and maximum), On-Demand | `auto_scaling_group`, `instance_types` |
| Waiting for each instance's setup | On, up to 15 minutes | `resource_signals` |
| Rolling replacement | One instance at a time | `rolling_update` |
| Public IP address | None | `associate_public_ip_address` |
| Inbound access | None, besides the load balancer | `security_group_ingress` |
| Outbound access | HTTPS and HTTP to anywhere | `security_group_egress` |
| Instance metadata | IMDSv2 only, hop limit 2 | `instance_metadata` |
| Volumes | 20 GiB `gp3` root, encrypted with the default EBS key | `volumes` |
| Swap file | 2048 MiB | `swap_size_mb` |
| Package updates at boot | On | `update_packages` |
| CloudWatch agent | Logs on (30 days), metrics off | `cloudwatch_agent` |
| IAM permissions | Systems Manager, including Session Manager, session logging and the SSM Agent's AWS-owned S3 buckets | `iam_role`, `session_manager` |
| Parameter Store paths | None, besides what Systems Manager grants | `parameter_store` |
| SSH key pair | None | `key_pair_name` |
| Detailed monitoring | On | `detailed_monitoring` |
| Load balancer | None; internal when set | `load_balancer` |
| EFS file system | None | `efs_file_system` |
| CodeDeploy | None | `codedeploy` |
| Your boot scripts | None | `user_data_scripts` |

## Before you start

You need:

- **Terraform 1.9 or later**, and AWS credentials that can create EC2, Auto Scaling, CloudFormation, IAM, CloudWatch Logs and, if you use them, Elastic Load Balancing, CodeDeploy and EFS resources.
- **A VPC with private subnets**, ideally one in each of two or more Availability Zones, so the group can keep running when a zone has trouble. Find their IDs in the VPC console, or with `aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc ID>`.
- **Outbound internet access from those subnets**, usually through a NAT gateway, because the instances install software at boot and report to AWS. [Network access](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#network-access) explains the alternative with VPC endpoints.
- **For a load balancer**, subnets for it too: the same private subnets for an internal one, or public subnets for an internet-facing one.

If some of the AWS terms are new:

| Term | What it is |
|---|---|
| Amazon Machine Image (AMI) | The disk image an instance starts from: the operating system and anything installed on it. |
| Launch template | The recipe for a new instance: its AMI, volumes, network settings, IAM role and user data. |
| Auto Scaling group | A set of instances launched from a launch template, kept at a size between a minimum and a maximum, across several Availability Zones. It replaces instances that fail their health checks. |
| User data | A script an instance runs at its first boot. The module writes it for you; your own scripts go in `user_data_scripts`. |
| CloudFormation stack | A set of AWS resources that AWS CloudFormation creates, updates and deletes together, from a template. |
| `cfn-init`, `cfn-signal`, `cfn-hup` | The CloudFormation helper scripts on each instance: `cfn-init` runs the setup steps, `cfn-signal` reports success or failure, and `cfn-hup` applies later changes to the setup. |
| Security group | A firewall around an instance or load balancer: it allows only the connections its rules list. |
| IAM role and instance profile | The AWS permissions the instances have. Programs on an instance, such as the AWS CLI, use them without stored keys. |
| Target group and listener | A listener is the port and protocol a load balancer accepts; it forwards to a target group, the instances that serve the traffic, which the load balancer health-checks. |
| Session Manager | A part of AWS Systems Manager that opens a shell on an instance through AWS, without SSH or an open port. |
| Parameter Store | A part of AWS Systems Manager that holds configuration and secrets, by path, optionally encrypted with a KMS key. |

## Usage

```hcl
module "web" {
  source  = "AutomateTheCloud/autoscaling_group-linux/aws"
  version = "~> 1.0"

  details = {
    scope       = "Automate the Cloud"
    purpose     = "Web Site"
    environment = "Production"
  }

  os             = "al2023"
  instance_types = [{ type = "t3.small" }]
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]

  auto_scaling_group = { min_size = 2, max_size = 4 }

  load_balancer = {
    type       = "application"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group_ingress = {
      vpc = { from_port = 80, cidr_ipv4 = "10.0.0.0/16" }
    }
    target_groups = { web = { port = 80, protocol = "HTTP" } }
    listeners     = { http = { port = 80, protocol = "HTTP", target_group = "web" } }
  }

  user_data_scripts = [file("${path.module}/install-web-server.sh")]
}
```

`details`, `os`, `instance_types`, `vpc_id` and `subnet_ids` are the only required inputs. `details` sets the `Scope`, `Purpose` and `Environment` tags on every resource, and the names of the resources the module creates.

The module uses your default `aws` provider and creates everything in that provider's Region. To create the instances somewhere else without configuring another provider, set `region`:

```hcl
module "web_us_west_2" {
  source  = "AutomateTheCloud/autoscaling_group-linux/aws"
  version = "~> 1.0"

  region         = "us-west-2"
  details        = { scope = "Automate the Cloud", purpose = "Web Site", environment = "Production" }
  os             = "ubuntu24"
  instance_types = [{ type = "t3.small" }]
  vpc_id         = "vpc-0fedcba9876543210"
  subnet_ids     = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
}
```

To use a provider configured for another account, pass it explicitly with `providers = { aws = aws.other_account }`.

Do not put `depends_on` on the module call. It makes Terraform read the module's data sources, such as the AMI and the Region, only at apply time, and then plan to replace the module's resources whenever the resource it names changes. To make the instances wait for something, such as a file system's mount targets, pass one of that resource's attributes into an input instead; the [complete example](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/complete) does that.

## The `details` input

Most modules ask only for what the resource itself needs. This one also requires `details`: three names that say what the instances belong to, what they are for, and which environment they are in. Every Automate the Cloud module takes the same input, and requiring it is deliberate.

```hcl
details = {
  scope       = "Automate the Cloud" # what it belongs to: an organization, team or project
  purpose     = "Web Site"           # what it is for
  environment = "Production"         # which environment
}
```

**Every resource can be traced.** The three names become the `Scope`, `Purpose` and `Environment` tags on every resource the module creates. Months later, anyone looking at an instance in the AWS console, or at a line on the bill, can see who it belongs to and why it exists. With cost allocation tags turned on in AWS Billing, the same tags split your bill by project and environment. Because the input is required and checked, no resource can be created without them.

**One definition for a whole stack.** Write `details` once and pass the same value to every module, so the instances, their load balancer's certificate, their file system and everything else are tagged alike. Tags you want everywhere, such as a cost center or the Terraform workspace, go in `additional_tags`:

```hcl
locals {
  details = {
    scope           = "Automate the Cloud"
    purpose         = "Web Site"
    environment     = "Production"
    additional_tags = { CostCenter = "1234", IaC = "true" }
  }
}

module "web" {
  source  = "AutomateTheCloud/autoscaling_group-linux/aws"
  version = "~> 1.0"

  details        = local.details
  os             = "al2023"
  instance_types = [{ type = "t3.small" }]
  vpc_id         = "vpc-0123456789abcdef0"
  subnet_ids     = ["subnet-0123456789abcdef0"]
}
```

**Consistent names.** The module turns each name into two short forms other resources can be named with: `abbr`, lowercase with words joined by underscores (`Web Site` becomes `web_site`), and `machine`, lowercase letters and numbers only (`website`), for resources that allow no underscores. It also works out a short form of the Region, such as `use1` for `us-east-1`. Every module derives these the same way, so names stay consistent across a stack. To choose your own short forms, set `scope_abbr`, `purpose_abbr` or `environment_abbr`, for example `environment_abbr = "prd"`.

**One output to reach everything.** All of it comes back in the `metadata` output, along with everything the module created, so a configuration needs only one reference: `module.web.metadata.auto_scaling_group.name` for the Auto Scaling group's name, or `module.web.metadata.aws.region.abbr` for the Region's short form.

## How a deployment works, step by step

What happens during `terraform apply` for a new deployment:

1. **Terraform reads** the Region, the account and the AMI (the newest for `os` and `architecture`, unless you set `ami_id`).
2. **Terraform creates the resources around the instances**: the security groups and their rules, the IAM role and instance profile, the log groups, and, if you asked for them, the load balancer, its target groups and listeners, and the rules for the EFS file system.
3. **Terraform creates the CloudFormation stack.** CloudFormation creates the launch template, then the Auto Scaling group, which launches `desired_capacity` (or `min_size`) instances across your subnets.
4. **Each instance boots and runs its user data**, which:
   1. installs the latest package updates (`update_packages`);
   2. on Ubuntu, installs the CloudFormation helper scripts, which Amazon Linux already has;
   3. runs `cfn-init`, which carries out the setup steps in the launch template's metadata, in order: start `cfn-hup`; write `/deploy/instance.dat`; create the swap file; install and start the CloudWatch agent; mount the EFS file system; install and start the CodeDeploy agent;
   4. runs each of your `user_data_scripts`, in order, as root;
   5. sends CloudFormation a success signal, or a failure signal as soon as any step fails.
5. **CloudFormation waits for a success signal from each instance**, up to `resource_signals.timeout`. Then the stack is complete.
6. **Terraform creates the CodeDeploy deployment group**, if you asked for one, and the apply finishes. The instances are set up, but a load balancer may take a few more minutes to mark them healthy: a Network Load Balancer's first health checks take a few minutes.

With the defaults, a new deployment takes about 3 minutes, on Amazon Linux 2023 or Ubuntu. Most of it is the instances' setup.

What runs at boot, by operating system:

| Step | Amazon Linux 2023 | Ubuntu 22.04 and 24.04 |
|---|---|---|
| Updates (`update_packages`) | `dnf upgrade` | `apt-get upgrade` |
| CloudFormation helper scripts | Included in the AMI | Installed from Amazon S3 into a Python environment in `/opt/aws/cfn-bootstrap` |
| `/deploy/instance.dat` | The `details` names and the Region, as shell variables | The same |
| Swap file (`swap_size_mb`) | `/var/swapfile` | The same |
| CloudWatch agent (`cloudwatch_agent`) | From the Amazon Linux repositories, with rsyslog for the log files | From the agent's Amazon S3 bucket in the Region |
| EFS file system (`efs_file_system`) | The Amazon EFS client (`amazon-efs-utils`), with TLS | `stunnel` for TLS and the NFS client, because the Amazon EFS client is not packaged for Ubuntu |
| CodeDeploy agent (`codedeploy`) | From the agent's Amazon S3 bucket in the Region, with Ruby | The same |
| Your scripts (`user_data_scripts`) | In order, as root | The same |

The setup runs at the first boot. The swap file and the file system mount are added to `/etc/fstab`, and the agents run as services, so all of them come back after a reboot.

Your scripts can read the deployment's names from `/deploy/instance.dat`, which is safe to `source` in a shell script:

```shell
#!/bin/bash
source /deploy/instance.dat
echo "This is ${INSTANCE_PURPOSE_NAME} in ${INSTANCE_ENVIRONMENT_NAME}, ${INSTANCE_REGION_NAME}"
```

It sets `INSTANCE_SCOPE_NAME`, `INSTANCE_SCOPE_ABBR`, `INSTANCE_PURPOSE_NAME`, `INSTANCE_PURPOSE_ABBR`, `INSTANCE_ENVIRONMENT_NAME`, `INSTANCE_ENVIRONMENT_ABBR`, `INSTANCE_REGION_NAME` and `INSTANCE_REGION_ABBR`. With `codedeploy`, `/deploy/codedeploy.dat` sets `CODEDEPLOY_APPLICATION_NAME` and a `CODEDEPLOY_LOG_GROUP_<NAME>` for each of `codedeploy.log_groups`.

## Changing a deployment

What happens to the running instances when you change an input and apply:

| You change | What happens | Running instances |
|---|---|---|
| `ami_id`, or a new AMI is published while `ami_id` is not set | Rolling update | Replaced in batches |
| `user_data_scripts`, `update_packages`, `resource_signals.enabled` | Rolling update: they are in the user data | Replaced in batches |
| `volumes`, `key_pair_name`, `instance_metadata`, `detailed_monitoring`, `credit_specification`, `associate_public_ip_address` | Rolling update: they are in the launch template | Replaced in batches |
| `swap_size_mb`, `cloudwatch_agent`, `efs_file_system`, `codedeploy` | The setup steps change; `cfn-hup` applies them on each instance within about 5 minutes | Kept |
| `instance_types`, the On-Demand and Spot settings | The group is updated | Kept; instances launched later use the new settings. To replace them now, run `aws autoscaling start-instance-refresh --auto-scaling-group-name <name>`, or change something in the launch template in the same apply |
| `min_size`, `max_size`, `desired_capacity` | The group is resized | Added or removed as needed |
| `auto_scaling_group` health checks, cooldown, lifetime, termination policies; `rolling_update` | The group or its update policy is updated | Kept |
| `security_group_ingress`, `security_group_egress`, `iam_role`, `parameter_store` | The rules or permissions change at once | Kept |
| A target group's `port`, `protocol` or `protocol_version` | A new target group is created, the listener and the group move to it, then the old one is deleted | Kept, registered with the new target group |
| The load balancer's `type`, `internal` or `name` | The load balancer is replaced; its DNS name changes | Kept, registered with the new one |
| `details` | Everything is renamed, which replaces it: the old stack, with its instances, is deleted, then the new one is created | Replaced, with downtime |
| `region` | Everything is created again in the new Region | Replaced |

A rolling update replaces `rolling_update.max_batch_size` instances at a time and keeps `min_instances_in_service` running: CloudFormation terminates each batch's old instances, launches new ones, and waits for their success signals before the next batch. With two or more instances behind a load balancer, set `min_instances_in_service` to at least 1 so the service stays up; the [pinned AMI example](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/pinned-ami) keeps two of three in service. The Terraform apply lasts as long as the update; raise `timeouts.update` for large groups.

By default, the AMI follows the newest that Amazon or Canonical publishes, so a plan made after a new release replaces every instance through a rolling update, even when nothing in your configuration changed. That keeps the instances patched. To choose when it happens, set `ami_id`.

Changes made to the group outside Terraform, such as by a scaling policy, a scheduled action or `aws autoscaling set-desired-capacity`, are kept when the stack is updated, until `desired_capacity`, `min_size` or `max_size` changes in the configuration. Use `metadata.auto_scaling_group.name` to attach scaling policies, scheduled actions and alarms to the group.

## Working with the instances

**Opening a shell.** The instances' role has the Systems Manager permissions, so Session Manager works with no SSH key or inbound rule. If your account's Session Manager preferences log sessions to CloudWatch Logs, the role can already write there; if they log to S3 or encrypt sessions with a KMS key, name the bucket and key in `session_manager` (see [Systems Manager permissions](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#systems-manager-permissions)). Find an instance and connect with the AWS CLI and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html), or from the EC2 console's **Connect** button:

```shell
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <metadata.auto_scaling_group.name> --query 'AutoScalingGroups[0].Instances[].InstanceId'
aws ssm start-session --target <instance ID>
```

**Running a command on every instance.** Systems Manager Run Command reaches them all at once, by the group's tag:

```shell
aws ssm send-command --document-name AWS-RunShellScript --targets Key=tag:aws:autoscaling:groupName,Values=<group name> --parameters 'commands=["uptime"]'
```

**Reading the logs.** With `cloudwatch_agent.logs` on, each instance sends four logs to CloudWatch, one stream per instance ID, in log groups named after `details`:

| Log group | What is in it |
|---|---|
| `/<scope>/<purpose>/<environment>/ec2/cloud-init` | The output of the user data: package updates, your scripts, the signal. Look here first when a boot fails. |
| `/<scope>/<purpose>/<environment>/ec2/cfn-init` | Each setup step and its output. |
| `/<scope>/<purpose>/<environment>/ec2/system` | The system log (`/var/log/messages` or `/var/log/syslog`). |
| `/<scope>/<purpose>/<environment>/ec2/auth` | Sign-ins and `sudo` (`/var/log/secure` or `/var/log/auth.log`). |

The `<scope>`, `<purpose>` and `<environment>` are the `abbr` forms. On the instance, the same logs are in `/var/log/cloud-init-output.log` and `/var/log/cfn-init.log`, and `cfn-hup` writes to `/var/log/cfn-hup.log`.

**Following a rollout.** `aws cloudformation describe-stack-events --stack-name <metadata.cloudformation_stack.name>`, or the stack's **Events** tab in the CloudFormation console, shows each batch, each instance's signal, and the reason for any failure.

## Examples

Each example is a complete configuration you can apply with your own VPC and subnets. Every one was applied and checked in a real AWS account before release.

- [Basic deployment](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/basic): one Amazon Linux 2023 instance with only the required inputs. Start here.
- [Complete deployment](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/complete): two Ubuntu 24.04 web servers on AWS Graviton behind an internal Application Load Balancer, with a shared EFS file system that requires TLS, a data volume each, and a CodeDeploy deployment group.
- [Network Load Balancer](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/network-load-balancer): two Ubuntu web servers behind an internal Network Load Balancer, with health checks over HTTP.
- [Classic Load Balancer](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/classic-load-balancer): a web server behind an internal Classic Load Balancer, for applications that still use one.
- [Spot Instances](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/spot-instances): a mix of On-Demand and Spot Instances of three instance types, with weights.
- [Pinned AMI](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/pinned-ami): three instances on an AMI you choose, replaced one at a time, with two always in service, when you change it.
- [Parameter Store](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/parameter-store): an instance that loads its configuration and secrets from two Parameter Store paths at boot, with the secrets encrypted by their own KMS key, and kept out of the Terraform state.

## Things to know

### Names

The module names what it creates after `details` and the Region: the CloudFormation stack `<scope>-<purpose>-<environment>-<region>` with the `machine` forms (`automatethecloud-website-production-use1`), and the launch template, the Auto Scaling group and the CodeDeploy deployment group `<scope>-<purpose>-<environment>-<region>` with the `abbr` forms (`automate_the_cloud-web_site-production-use1`). The security groups, IAM role and instance profile start with that name and end with a suffix AWS adds. The load balancer is named after the `machine` forms, shortened to fit 32 characters, unless you set `load_balancer.name`.

One deployment per `details` and Region: a second module call with the same `details` in the same Region fails on the names. Changing `details` renames everything, which replaces it, with downtime (see [Changing a deployment](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#changing-a-deployment)).

### Network access

The instances need outbound access at boot: to the package repositories for updates and packages, to AWS CloudFormation for their setup and signals, and to the Amazon CloudWatch, AWS Systems Manager and AWS CodeDeploy endpoints. The default `security_group_egress` allows HTTPS and HTTP to any IPv4 address; Ubuntu's package mirrors use HTTP. Put the instances in private subnets with a NAT gateway.

To keep the instances off the internet, give the VPC interface endpoints for `cloudformation`, `ssm`, `ssmmessages`, `ec2messages`, `logs` and, as needed, `monitoring`, `codedeploy` and `codedeploy-commands-secure`, and an Amazon S3 gateway endpoint, then set `security_group_egress` to HTTPS to the endpoints' security group and the S3 prefix list, and `update_packages = false`. Amazon Linux 2023 then installs its packages from repositories in Amazon S3. Ubuntu needs its packages from a mirror you run, and the CloudFormation helper scripts from Amazon S3 (`s3.amazonaws.com`).

Setting `security_group_egress` replaces the default rules. Keep HTTPS and HTTP in your map unless the instances reach everything through endpoints.

### Load balancers

The load balancer is internal unless `internal = false`, and its security group allows no clients until you list them in `security_group_ingress`. The module allows the load balancer to reach the instances on the target group and health check ports only, so your own `security_group_ingress` for the instances can stay empty.

A Network Load Balancer normally passes each client's own address on to the instances (client IP preservation), so the instances see traffic from the clients, not from the load balancer, and their security group, which allows only the load balancer, refuses it while the health checks still pass. The module turns preservation off for `TCP` and `TLS` target groups. If you turn it on, with `preserve_client_ip = true`, or use `UDP` or `TCP_UDP`, which always preserve it, also allow the clients in `security_group_ingress` on the target port. To keep the clients' addresses without that, use `proxy_protocol_v2`.

For HTTPS, add a certificate from AWS Certificate Manager to an `HTTPS` (Application Load Balancer) or `TLS` (Network Load Balancer) listener. Listeners use the `ELBSecurityPolicy-TLS13-1-2-2021-06` security policy unless you choose another, which accepts TLS 1.2 and 1.3 only. A common setup redirects HTTP to HTTPS:

```hcl
listeners = {
  https = { port = 443, protocol = "HTTPS", target_group = "web", certificate_arn = aws_acm_certificate.web.arn }
  http  = { port = 80, protocol = "HTTP", redirect = { protocol = "HTTPS", port = "443" } }
}
```

A change to a target group's `port`, `protocol` or `protocol_version` replaces it: the new one, with a new name suffix, is created first, the listeners and the Auto Scaling group move to it, and then the old one is deleted. The security group rules for the old port are removed while the new ones are added, so a request may fail for a few seconds. A change to the load balancer's `type`, `internal`, `name`, or the Elastic IP addresses of a Network Load Balancer replaces the load balancer, and its DNS name changes.

The Classic Load Balancer is the previous generation, kept for existing deployments. Its `HTTPS` and `SSL` listeners get the `ELBSecurityPolicy-TLS-1-2-2017-01` security policy instead of the older default, which allows TLS 1.0.

### Parameter Store

`parameter_store` lets the instances read configuration and secrets from AWS Systems Manager Parameter Store: everything under each path in `paths`, such as one path per environment and one shared by every environment,

```hcl
parameter_store = {
  paths = [
    "/secrets/automate_the_cloud/web_site/production",
    "/secrets/automate_the_cloud/web_site/global",
  ]
  kms_key_arns = [aws_kms_key.secrets.arn]
}
```

The instances may read each parameter by name (`ssm:GetParameter`, `ssm:GetParameters`) or a whole path at once (`ssm:GetParametersByPath`, which IAM checks against the path itself, so the module grants both the path and everything under it), and decrypt `SecureString` parameters under those paths with the keys in `kms_key_arns`, only through Parameter Store: a parameter elsewhere encrypted with the same key stays unreadable. Parameters encrypted with the AWS managed key `aws/ssm` need no key.

`AmazonSSMManagedInstanceCore`, which the module attaches unless `iam_role.ssm_managed_instance_core` is `false`, already lets the instances read any parameter in the account by its name. `paths` adds reading whole paths and decrypting with your own keys; it does not narrow what the managed policy allows.

The instances read the parameters when your scripts do, usually once at boot. The [Parameter Store example](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/parameter-store) shows a script that loads both paths into a file, and how to keep secret values out of the Terraform state.

### Systems Manager permissions

With `iam_role.ssm_managed_instance_core`, on by default, the instances' role has what AWS Systems Manager needs to manage them:

- the AWS managed policy `AmazonSSMManagedInstanceCore`: the agent registering, Run Command, State Manager, inventory and Session Manager's session channels;
- `s3:GetObject` on the AWS-owned buckets SSM Agent reads from in the instances' Region, for agent updates (`AWS-UpdateSSMAgent`), Distributor packages (`AWS-ConfigureAWSPackage`), patching (`AWS-RunPatchBaseline`) and the modules other AWS documents use. Without an identity the agent often reaches these anonymously, but a VPC endpoint policy, a bucket policy or a proxy can require one;
- for Session Manager session logging: writing to CloudWatch Logs log groups in the account and Region, and `s3:GetEncryptionConfiguration`, which Session Manager checks before it writes to an S3 bucket.

Two Session Manager settings need resources only you can name, through `session_manager`: writing session logs to an S3 bucket (`log_bucket`), and KMS keys for encrypted sessions or an SSE-KMS log bucket (`kms_key_arns`):

```hcl
session_manager = {
  log_bucket   = { arn = "arn:aws:s3:::my-session-logs", prefix = "sessions" }
  kms_key_arns = [aws_kms_key.sessions.arn]
}
```

The account's preferences, which decide what is needed, are in the `SSM-SessionManagerRunShell` document: `aws ssm get-document --name SSM-SessionManagerRunShell --query Content --output text`.

Terraform attaches every policy before the CloudFormation stack launches any instance, so the agent can register as soon as an instance boots.

### Other permissions

The instances' role has only what the module's own features need. For anything else your application does, such as reading an S3 bucket or a Secrets Manager secret, give it a policy limited to those resources:

```hcl
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

module "web" {
  # ...
  iam_role = { source_policy_documents = [data.aws_iam_policy_document.app.json] }
}
```

### Encryption keys

`volumes.kms_key_id` encrypts the volumes with your own KMS key. Amazon EC2 Auto Scaling launches the instances, so the key policy must allow its service-linked role, `AWSServiceRoleForAutoScaling`, to use the key and create grants; AWS documents that without it the instances fail to launch, so the apply would wait for `resource_signals.timeout` and fail. See [Required AWS KMS key policy for use with encrypted volumes](https://docs.aws.amazon.com/autoscaling/ec2/userguide/key-policy-requirements-EBS-encryption.html).

### CodeDeploy

The module creates a deployment group for the Auto Scaling group in your CodeDeploy application, and installs the CodeDeploy agent on each instance, unless the AMI already has it (in `/opt/codedeploy-agent` or as `/etc/init.d/codedeploy-agent`). Either way it starts the agent and checks that it is running; if it is not, the setup fails, so the instance does not wait silently for a deployment the agent never picks up. CodeDeploy then deploys the latest revision to every new instance before it enters service, through a lifecycle hook it adds to the group, including instances a rolling update or a scaling policy launches. The deployment group is created after the stack, so the instances launched when the stack is created get no revision; deploy once after the first apply.

The service role in `codedeploy.service_role_arn` needs `ec2:RunInstances`, `ec2:CreateTags` and `iam:PassRole` for the instances' role, besides the `AWSCodeDeployRole` managed policy, because the group uses a launch template. The [complete example](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/complete) shows the policy.

### EFS file systems

The module adds a rule to the file system's security group so the instances can reach it on NFS (TCP 2049), and mounts it with encryption in transit. If the file system has a policy, it must allow `elasticfilesystem:ClientMount` and `elasticfilesystem:ClientWrite`, and `elasticfilesystem:ClientRootAccess` for scripts that run as root, such as `user_data_scripts`: without it, EFS treats root as an anonymous user, who cannot write to the file system's top directory. The file system needs a mount target in each Availability Zone of `subnet_ids`.

### Size limits

EC2 accepts up to 16 KB of user data, which holds the module's boot commands and your `user_data_scripts`, and CloudFormation accepts a template of up to 51,200 bytes, which holds the user data again, encoded, and the setup. The plan fails with a clear message when either is too large. For a longer setup, have a short script download the rest, such as from Amazon S3.

## Troubleshooting

**The apply fails with "Received FAILURE signal".** An instance's setup or one of your scripts failed. The stack was rolled back. Read the `cloud-init` log group first: the last lines before `user_data_scripts[N] failed`, or the failed step in the `cfn-init` log group, give the reason. Fix it and apply again: after a failed creation, Terraform creates the stack again; after a failed update, the previous instances are still running.

**The apply waits about 15 minutes, then fails with "Failed to receive ... resource signal(s)".** An instance never reported. Common causes: the subnets have no outbound access, so the boot cannot install packages or reach CloudFormation; the volumes' KMS key does not allow the Auto Scaling service-linked role, so no instance launched (`aws autoscaling describe-scaling-activities --auto-scaling-group-name <name>` shows it); or the instance type is not offered in the subnets' Availability Zones.

**Clients of a Network Load Balancer time out, but the targets are healthy.** The target group preserves client addresses, and the instances' security group allows only the load balancer. Allow the clients in `security_group_ingress`, or leave `preserve_client_ip` unset. Right after an apply, the targets may also still be in their first health checks: wait a few minutes.

**A script cannot write to the EFS file system: "Permission denied".** The file system's policy does not allow `elasticfilesystem:ClientRootAccess` (see [EFS file systems](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#efs-file-systems)).

**Reading a parameter fails with "AccessDeniedException".** Reading a whole path needs the path in `parameter_store.paths`; decrypting with your own key needs the key in `parameter_store.kms_key_arns` and the parameter under one of the paths.

**Session Manager cannot start a session, or the SSM Agent reports no credentials or "AccessDenied".** Check that `iam_role.ssm_managed_instance_core` is on, and that the instance is registered: `aws ssm describe-instance-information --filters Key=InstanceIds,Values=<instance ID>`. If it is registered but sessions fail, the account's Session Manager preferences probably log to S3 or encrypt sessions with a KMS key: name the bucket and key in `session_manager`. The agent's own log is `/var/log/amazon/ssm/amazon-ssm-agent.log`. With IMDSv2 required, an AMI with a very old SSM Agent cannot read its credentials; update the agent, or set `instance_metadata = { http_tokens = "optional" }`.

**Every plan wants to replace the IAM role, the security groups and more.** The module call has a `depends_on`. Remove it and pass an attribute of the resource instead (see [Usage](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#usage)).

**A plan replaces every instance although nothing changed.** A new AMI was published. Set `ami_id` to decide when instances move to a new AMI.

**Changing `instance_types` did nothing to the running instances.** That is expected: see [Changing a deployment](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#changing-a-deployment).

## Contributing

Contributions are welcome, after review. Read [CONTRIBUTING.md](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/blob/main/CONTRIBUTING.md) before opening a pull request, and report security problems as described in [SECURITY.md](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/blob/main/SECURITY.md).

## Testing

The tests in `tests/` run offline against mocked AWS providers, so they need no AWS account:

```shell
terraform init
terraform test
```

## Reference

The sections below are generated from the code by [terraform-docs](https://terraform-docs.io). To update them, run `terraform-docs .`.

<!-- BEGIN_TF_DOCS -->
### Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement_terraform) (>= 1.9)

- <a name="requirement_aws"></a> [aws](#requirement_aws) (>= 6.0)

- <a name="requirement_random"></a> [random](#requirement_random) (>= 3.0)

### Required Inputs

The following input variables are required:

#### <a name="input_details"></a> [details](#input_details)

Description: Names and tags shared by every resource in the module. `scope`, `purpose` and `environment` become the `Scope`, `Purpose` and `Environment` tags, and are converted to abbreviations that name the resources the module creates (see the `metadata` output). [The `details` input](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux#the-details-input) explains why it is required.

- `scope` - (Required) What the resource belongs to, such as an organization or project: `Automate the Cloud`.
- `purpose` - (Required) What the resource is for: `Web Site`.
- `environment` - (Required) The environment: `Production`.
- `scope_abbr`, `purpose_abbr`, `environment_abbr` - (Optional) Abbreviations to use instead of the generated ones, which are lowercase with words joined by underscores (`Web Site` becomes `web_site`).
- `additional_tags` - (Optional) More tags for every resource, such as `{ CostCenter = "1234" }`.

Type:

```hcl
object({
    scope            = string
    scope_abbr       = optional(string)
    purpose          = string
    purpose_abbr     = optional(string)
    environment      = string
    environment_abbr = optional(string)
    additional_tags  = optional(map(string), {})
  })
```

#### <a name="input_instance_types"></a> [instance_types](#input_instance_types)

Description: The instance types the Auto Scaling group may launch, in order of preference for On-Demand Instances, such as `[{ type = "t3.micro" }]`. All must have the `architecture` and be offered in the Availability Zones of `subnet_ids`. A change applies to instances launched afterward; it does not replace running instances (see `rolling_update`).

- `type` - (Required) The instance type, such as `m7i.large`.
- `weighted_capacity` - (Optional) How many capacity units an instance of this type counts for in `auto_scaling_group`'s sizes, from 1 to 999. Defaults to `1`.

Type:

```hcl
list(object({
    type              = string
    weighted_capacity = optional(number, 1)
  }))
```

#### <a name="input_os"></a> [os](#input_os)

Description: The operating system of the AMI: `al2023` (Amazon Linux 2023), `ubuntu22` (Ubuntu 22.04 LTS) or `ubuntu24` (Ubuntu 24.04 LTS). It picks the AMI when `ami_id` is not set, and the commands the instances run at boot.

Type: `string`

#### <a name="input_subnet_ids"></a> [subnet_ids](#input_subnet_ids)

Description: IDs of the subnets to launch the instances in, in `vpc_id`, such as one private subnet per Availability Zone. The Auto Scaling group spreads the instances across their zones.

Type: `list(string)`

#### <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id)

Description: The ID of the VPC the instances are in, such as `vpc-0123456789abcdef0`: the VPC of `subnet_ids`. The module creates the instances' security group, and the load balancer's, in it.

Type: `string`

### Optional Inputs

The following input variables are optional (have default values):

#### <a name="input_ami_id"></a> [ami_id](#input_ami_id)

Description: The ID of the Amazon Machine Image (AMI) to launch, such as `ami-0123456789abcdef0`. Defaults to the newest AMI for `os` and `architecture`, from the public AWS Systems Manager parameters that Amazon and Canonical publish in every Region.

With the default, a plan picks up a new AMI as soon as one is published, and the apply then replaces every instance through a rolling update. Set an AMI ID to choose when that happens. The AMI must run the operating system named in `os`, which decides the boot commands. The module reads the public parameter even then, so it must exist in the Region.

Type: `string`

Default: `null`

#### <a name="input_architecture"></a> [architecture](#input_architecture)

Description: The processor architecture of the instances: `x86_64` (Intel and AMD) or `arm64` (AWS Graviton). Picks the AMI when `ami_id` is not set. Every type in `instance_types` must have this architecture. Defaults to `x86_64`.

Type: `string`

Default: `"x86_64"`

#### <a name="input_associate_public_ip_address"></a> [associate_public_ip_address](#input_associate_public_ip_address)

Description: Give each instance a public IPv4 address. Defaults to `false`, whatever the subnet's own setting. With `true`, in subnets with a route to an internet gateway, anyone that `security_group_ingress` allows can reach the instances from the internet, and AWS charges for each public IPv4 address. Prefer private subnets with a NAT gateway or VPC endpoints for outbound traffic, and a load balancer for inbound traffic.

Type: `bool`

Default: `false`

#### <a name="input_auto_scaling_group"></a> [auto_scaling_group](#input_auto_scaling_group)

Description: The size and behavior of the Auto Scaling group.

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

Type:

```hcl
object({
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
```

Default: `{}`

#### <a name="input_cloudwatch_agent"></a> [cloudwatch_agent](#input_cloudwatch_agent)

Description: What the Amazon CloudWatch agent on each instance sends to CloudWatch. The module installs and configures the agent when either is on.

- `logs` - (Optional) Send the system log, the authentication log, the cloud-init output log and the CloudFormation helper log to log groups the module creates, one stream per instance. Defaults to `true`. On Amazon Linux 2023, which keeps these logs only in the systemd journal, the module also installs rsyslog to write them to files.
- `log_retention_in_days` - (Optional) How long CloudWatch keeps the logs. Defaults to `30`. One of the values CloudWatch Logs accepts, such as `7`, `30`, `90`, `365`, or `0` to keep them forever.
- `log_kms_key_id` - (Optional) The ARN of a KMS key to encrypt the log groups with. Its key policy must allow the CloudWatch Logs service principal in the Region. Defaults to `null`: CloudWatch Logs encrypts them with its own key.
- `metrics` - (Optional) Send memory, disk and swap use, which EC2 does not measure, to the `CWAgent` namespace every minute, by Auto Scaling group and by instance. Defaults to `false`. CloudWatch charges for each custom metric.

The log groups are named `/<scope abbr>/<purpose abbr>/<environment abbr>/ec2/<log>`, where `<log>` is `system`, `auth`, `cloud-init` or `cfn-init`. The instances' role may write only to them.

Type:

```hcl
object({
    logs                  = optional(bool, true)
    log_retention_in_days = optional(number, 30)
    log_kms_key_id        = optional(string)
    metrics               = optional(bool, false)
  })
```

Default: `{}`

#### <a name="input_codedeploy"></a> [codedeploy](#input_codedeploy)

Description: Deploy applications to the instances with AWS CodeDeploy. The module creates a deployment group for the Auto Scaling group in an existing CodeDeploy application, and installs the CodeDeploy agent on each instance. New instances get the latest revision when they launch. Defaults to `null`: no CodeDeploy.

- `application_name` - (Required) The name of the CodeDeploy application, for the `Server` compute platform.
- `service_role_arn` - (Required) The ARN of the IAM role CodeDeploy uses. Because the Auto Scaling group uses a launch template, it needs `ec2:RunInstances`, `ec2:CreateTags` and `iam:PassRole` for the instances' role, besides the `AWSCodeDeployRole` managed policy.
- `deployment_config_name` - (Optional) How many instances deploy at once. Defaults to `CodeDeployDefault.OneAtATime`.
- `revision_bucket` - (Optional) The S3 bucket that holds the application's revisions: `arn` (Required) and `path` (Optional), the key prefix of the revisions, such as `codedeploy/web`; without it, the whole bucket. The instances' role may read the revisions. The `metadata.s3_bucket` output of the [CodeDeploy module](https://registry.terraform.io/modules/AutomateTheCloud/codedeploy/aws) has this shape. Defaults to `null`: grant read access yourself through `iam_role`.
- `log_groups` - (Optional) Names of log groups to create for the application, such as `["application", "access"]`. Each is created as `/<scope abbr>/<purpose abbr>/<environment abbr>/application/<application_name>/<name>`, the instances' role may write to it, and `/deploy/codedeploy.dat` on each instance names it as `CODEDEPLOY_LOG_GROUP_<NAME>`. Defaults to none. They use `cloudwatch_agent.log_retention_in_days` and `log_kms_key_id`.

With a load balancer, deployments stop sending traffic to each instance while it is updated.

Type:

```hcl
object({
    application_name       = string
    service_role_arn       = string
    deployment_config_name = optional(string, "CodeDeployDefault.OneAtATime")
    revision_bucket = optional(object({
      arn  = string
      path = optional(string)
    }))
    log_groups = optional(list(string), [])
  })
```

Default: `null`

#### <a name="input_credit_specification"></a> [credit_specification](#input_credit_specification)

Description: The CPU credit option for burstable instance types (T2, T3, T3a, T4g): `standard` or `unlimited`. Defaults to `null`: the instance type's default (`unlimited` for T3, T3a and T4g). Leave it `null` when `instance_types` has types that are not burstable.

Type: `string`

Default: `null`

#### <a name="input_detailed_monitoring"></a> [detailed_monitoring](#input_detailed_monitoring)

Description: Send each instance's EC2 metrics to CloudWatch every minute instead of every five minutes. Defaults to `true`. CloudWatch charges for detailed monitoring.

Type: `bool`

Default: `true`

#### <a name="input_efs_file_system"></a> [efs_file_system](#input_efs_file_system)

Description: An Amazon Elastic File System (EFS) file system to mount on every instance. The module allows NFS (TCP 2049) from the instances to the file system's security group, and mounts it with encryption in transit (TLS) through the Amazon EFS client, also on reboot. Defaults to `null`: no file system.

- `id` - (Required) The file system's ID, such as `fs-0123456789abcdef0`. It needs a mount target in each Availability Zone of `subnet_ids`.
- `security_group_id` - (Required) The ID of the security group on the file system's mount targets. The module adds an inbound rule to it.
- `mount_point` - (Optional) Where to mount it. Defaults to `/efs`.

Type:

```hcl
object({
    id                = string
    security_group_id = string
    mount_point       = optional(string, "/efs")
  })
```

Default: `null`

#### <a name="input_iam_role"></a> [iam_role](#input_iam_role)

Description: Permissions for the IAM role the module creates for the instances. Besides what is listed here, the role may write to the module's log groups and CloudWatch metrics when `cloudwatch_agent` sends them, and read the CodeDeploy revisions when `codedeploy.revision_bucket` is set.

- `ssm_managed_instance_core` - (Optional) Let AWS Systems Manager manage the instances, including Session Manager shell access without SSH or open ports. Defaults to `true`. It attaches the AWS managed policy `AmazonSSMManagedInstanceCore`, and adds to the inline policy what that policy leaves out:
  - `s3:GetObject` on the AWS-owned buckets SSM Agent reads from in the instances' Region, for agent updates, Distributor packages, patching and document modules: `aws-ssm-<region>`, `amazon-ssm-<region>`, `amazon-ssm-packages-<region>`, `<region>-birdwatcher-prod`, `aws-windows-downloads-<region>`, `patch-baseline-snapshot-<region>` (with or without a suffix) and `aws-patch-manager-<region>-<suffix>`;
  - for Session Manager session logging, if the account's Session Manager preferences turn it on: writing to CloudWatch Logs log groups in this account and Region (`logs:CreateLogStream`, `PutLogEvents`, `DescribeLogGroups`, `DescribeLogStreams`), and `s3:GetEncryptionConfiguration`. Writing session logs to S3, and KMS-encrypted sessions, also need `session_manager`.
- `source_policy_documents` - (Optional) IAM policy documents, as JSON, to give the role, such as the `json` of an `aws_iam_policy_document` that allows reading one S3 bucket or one Secrets Manager secret. They are combined into one inline policy. Defaults to none.
- `managed_policy_arns` - (Optional) Managed policies to attach to the role, as a map of names you choose to policy ARNs, such as `{ app = aws_iam_policy.app.arn }`. The names only identify each attachment, so a policy created in the same configuration can be used. Defaults to none.

The role's name, and its instance profile's, start with the deployment's name and end with a suffix AWS adds, because IAM names are unique in the account across Regions. Its trust policy lets only EC2 in this account use it.

Type:

```hcl
object({
    ssm_managed_instance_core = optional(bool, true)
    source_policy_documents   = optional(list(string), [])
    managed_policy_arns       = optional(map(string), {})
  })
```

Default: `{}`

#### <a name="input_instance_metadata"></a> [instance_metadata](#input_instance_metadata)

Description: How the instances may use the instance metadata service (IMDS).

- `http_tokens` - (Optional) `required` allows only IMDSv2, which needs a session token and protects against server-side request forgery; `optional` also allows IMDSv1. Defaults to `required`.
- `http_put_response_hop_limit` - (Optional) How many network hops the token response may travel, from 1 to 64. Defaults to `2`, so containers on the instance can reach IMDS; `1` keeps it to the instance itself.

Type:

```hcl
object({
    http_tokens                 = optional(string, "required")
    http_put_response_hop_limit = optional(number, 2)
  })
```

Default: `{}`

#### <a name="input_key_pair_name"></a> [key_pair_name](#input_key_pair_name)

Description: The name of an EC2 key pair to allow SSH access with. Defaults to `null`: no key pair. Session Manager (see `iam_role.ssm_managed_instance_core`) gives shell access without one, and without an inbound port.

Type: `string`

Default: `null`

#### <a name="input_load_balancer"></a> [load_balancer](#input_load_balancer)

Description: A load balancer in front of the instances. Defaults to `null`: none. The module creates the load balancer, a security group for it, and rules that let it reach the instances on the target ports and health check ports only.

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

Type:

```hcl
object({
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
```

Default: `null`

#### <a name="input_parameter_store"></a> [parameter_store](#input_parameter_store)

Description: AWS Systems Manager Parameter Store paths the instances may read, such as configuration and secrets an application loads at boot. Defaults to none.

- `paths` - (Optional) Paths such as `/secrets/automate_the_cloud/web_site/production`. The instances may read every parameter under each path, at any depth, one at a time (`ssm:GetParameter`), several by name (`ssm:GetParameters`), or the whole path at once (`ssm:GetParametersByPath`, which IAM checks against the path itself as well as the parameters under it). Each starts with `/`, does not end with `/`, and is not `/` alone. AWS reserves paths that start with `/aws` or `/ssm`.
- `kms_key_arns` - (Optional) ARNs of the KMS keys that encrypt `SecureString` parameters under those paths. The instances may decrypt with them only parameters under `paths`, only through Parameter Store, in this Region. Needs `paths`. Not needed for parameters encrypted with the AWS managed key `aws/ssm`. Each key's policy must let IAM policies in the account grant its use, as the default key policy does.

`AmazonSSMManagedInstanceCore` (see `iam_role`) already lets the instances read any parameter in the account by its name, and decrypt it with `aws/ssm`: AWS includes `ssm:GetParameter` and `ssm:GetParameters` on every parameter in it. `paths` adds reading a whole path and limits nothing. To limit reading to these paths, set `iam_role.ssm_managed_instance_core = false` and give the instances the Systems Manager permissions they need some other way.

Type:

```hcl
object({
    paths        = optional(list(string), [])
    kms_key_arns = optional(list(string), [])
  })
```

Default: `{}`

#### <a name="input_region"></a> [region](#input_region)

Description: The AWS Region to create the instances and everything else in, such as `us-west-2`. Defaults to the Region of the AWS provider passed to the module.

Type: `string`

Default: `null`

#### <a name="input_resource_signals"></a> [resource_signals](#input_resource_signals)

Description: Wait for each new instance to report that its setup at boot succeeded. Each instance runs the boot commands, then the scripts in `user_data_scripts`, and sends AWS CloudFormation a success or failure signal.

- `enabled` - (Optional) Defaults to `true`. When the group is created, the apply waits for a success signal from each instance in `desired_capacity` (or `min_size`) and fails if one fails or does not report in time. With weights in `instance_types`, it waits for the fewest instances that can make up that capacity: the capacity divided by the largest weight, rounded up. In a rolling update, each batch waits the same way, and a failure rolls the whole update back.
- `timeout` - (Optional) How long to wait for each instance, as an ISO 8601 duration from `PT1M` to `PT1H`, such as `PT15M`. Defaults to `PT15M`.

With `false`, the apply finishes as soon as the instances are launched, and a rolling update waits `rolling_update.pause_time` between batches.

Type:

```hcl
object({
    enabled = optional(bool, true)
    timeout = optional(string, "PT15M")
  })
```

Default: `{}`

#### <a name="input_rolling_update"></a> [rolling_update](#input_rolling_update)

Description: How AWS CloudFormation replaces the instances when the launch template changes: a new AMI, user data, volumes or any other setting in it. It replaces them in batches. A change to `instance_types` or the On-Demand and Spot settings alone does not replace running instances; only instances launched afterward use it.

- `max_batch_size` - (Optional) The most instances replaced at once. Defaults to `1`.
- `min_instances_in_service` - (Optional) How many instances must stay in service during the update. Defaults to `0`. Must be less than `auto_scaling_group.max_size`. CloudFormation terminates each batch's old instances before it launches their replacements.
- `min_successful_instances_percent` - (Optional) With `resource_signals`, the percentage of instances in each batch that must signal success, from 0 to 100. Defaults to `100`.
- `pause_time` - (Optional) Without `resource_signals`, how long to wait after each batch, as an ISO 8601 duration up to `PT1H`. Defaults to `PT0S`.

Type:

```hcl
object({
    max_batch_size                   = optional(number, 1)
    min_instances_in_service         = optional(number, 0)
    min_successful_instances_percent = optional(number, 100)
    pause_time                       = optional(string, "PT0S")
  })
```

Default: `{}`

#### <a name="input_security_group_egress"></a> [security_group_egress](#input_security_group_egress)

Description: Where the instances may connect to. The module creates a security group for the instances with these outbound rules, keyed by names you choose. Defaults to HTTPS (TCP 443) and HTTP (TCP 80) to any IPv4 address, which the boot commands need for package updates and to reach AWS services, unless the VPC has endpoints for them. Setting this replaces the defaults; include them if the instances still need them. Rules to the load balancer and the EFS file system are added on their own.

Each rule takes:

- `ip_protocol` - (Optional) `tcp`, `udp`, `icmp`, `icmpv6`, or `-1` for every protocol. Defaults to `tcp`.
- `from_port` - For `tcp` and `udp`, (Required) the first port. For `icmp` and `icmpv6`, (Optional) the ICMP type, defaults to `-1`, every type. Must be left out for `-1`.
- `to_port` - (Optional) For `tcp` and `udp`, the last port, defaults to `from_port`. For `icmp` and `icmpv6`, the ICMP code, defaults to `-1`.
- `description` - (Optional) Defaults to the key. Up to 255 characters: letters, numbers, spaces and `._-:/()#,@[]+=&;{}!$*`.

and exactly one destination: `cidr_ipv4`, such as `10.0.0.0/16`; `cidr_ipv6`, such as `2600:1f18:1234:5600::/56`; `prefix_list_id`, such as the AWS-managed list for Amazon S3; or `security_group_id`.

Type:

```hcl
map(object({
    ip_protocol       = optional(string, "tcp")
    from_port         = optional(number)
    to_port           = optional(number)
    description       = optional(string)
    cidr_ipv4         = optional(string)
    cidr_ipv6         = optional(string)
    prefix_list_id    = optional(string)
    security_group_id = optional(string)
  }))
```

Default:

```json
{
  "http": {
    "cidr_ipv4": "0.0.0.0/0",
    "description": "HTTP to anywhere",
    "from_port": 80,
    "ip_protocol": "tcp"
  },
  "https": {
    "cidr_ipv4": "0.0.0.0/0",
    "description": "HTTPS to anywhere",
    "from_port": 443,
    "ip_protocol": "tcp"
  }
}
```

#### <a name="input_security_group_ingress"></a> [security_group_ingress](#input_security_group_ingress)

Description: Who may connect to the instances directly, besides the load balancer, which the module allows on its own. Rules for the instances' security group, keyed by names you choose, with the same attributes as `security_group_egress`, each with exactly one source. Defaults to `{}`: nothing may connect directly. Session Manager needs no inbound rule.

Type:

```hcl
map(object({
    ip_protocol       = optional(string, "tcp")
    from_port         = optional(number)
    to_port           = optional(number)
    description       = optional(string)
    cidr_ipv4         = optional(string)
    cidr_ipv6         = optional(string)
    prefix_list_id    = optional(string)
    security_group_id = optional(string)
  }))
```

Default: `{}`

#### <a name="input_session_manager"></a> [session_manager](#input_session_manager)

Description: Permissions for Session Manager features that the account's Session Manager preferences turn on, besides what `iam_role.ssm_managed_instance_core` grants. Defaults to none.

- `log_bucket` - (Optional) The S3 bucket that session logs are written to: `arn` (Required), the bucket's ARN, and `prefix` (Optional), the key prefix the preferences name; without it, the whole bucket. The instances may write objects there (`s3:PutObject`).
- `kms_key_arns` - (Optional) ARNs of KMS keys the instances use for Session Manager: the key that encrypts session data, and the key of an S3 log bucket encrypted with SSE-KMS. The instances may use them with `kms:Decrypt` and `kms:GenerateDataKey`. Each key's policy must let IAM policies in the account grant its use, as the default key policy does.

`aws ssm get-document --name SSM-SessionManagerRunShell --query Content --output text` shows the preferences: `s3BucketName`, `s3KeyPrefix`, `cloudWatchLogGroupName` and `kmsKeyId`.

Type:

```hcl
object({
    log_bucket = optional(object({
      arn    = string
      prefix = optional(string)
    }))
    kms_key_arns = optional(list(string), [])
  })
```

Default: `{}`

#### <a name="input_swap_size_mb"></a> [swap_size_mb](#input_swap_size_mb)

Description: The size of a swap file to create on each instance at `/var/swapfile`, in MiB. Defaults to `2048`. `0` creates none.

Type: `number`

Default: `2048`

#### <a name="input_timeouts"></a> [timeouts](#input_timeouts)

Description: How long Terraform waits for the CloudFormation stack, which holds the launch template and the Auto Scaling group, to be created, updated or deleted, such as `45m`. A rolling update of many instances can take longer than the defaults: `30m` to create, `60m` to update, `30m` to delete.

Type:

```hcl
object({
    create = optional(string, "30m")
    update = optional(string, "60m")
    delete = optional(string, "30m")
  })
```

Default: `{}`

#### <a name="input_update_packages"></a> [update_packages](#input_update_packages)

Description: Install the latest updates of every package when an instance boots (`dnf upgrade` or `apt-get upgrade`). Defaults to `true`. It makes boots slower, and two instances launched days apart may run different package versions; with `false`, the instances run what the AMI has.

Type: `bool`

Default: `true`

#### <a name="input_user_data_scripts"></a> [user_data_scripts](#input_user_data_scripts)

Description: Your own scripts to run on each instance at its first boot, as root, in order, after the module's own setup, such as `[file("${path.module}/setup.sh")]`. Each is the full text of a script and starts with `#!`, such as `#!/bin/bash`. If one exits with an error, the rest do not run and, with `resource_signals`, the instance reports a failure. Defaults to none.

Changing a script replaces every instance through a rolling update. User data, with the module's own commands, may be up to 16 KB.

Type: `list(string)`

Default: `[]`

#### <a name="input_volumes"></a> [volumes](#input_volumes)

Description: The EBS volumes of each instance. Every volume is encrypted, and deleted with the instance.

- `root` - (Optional) The root volume: `size_gb` (defaults to `20`), `type` (`gp3`, the default, `gp2`, `io1` or `io2`), `iops` and `throughput` (MiB/s, `gp3` only). Defaults to `{}`.
- `data` - (Optional) Empty data volumes, attached as `/dev/sdb`, `/dev/sdc` and so on (Linux may name them `/dev/nvme1n1` and up): `count` (from 0 to 25, defaults to `0`), and `size_gb`, `type` (also `st1` and `sc1`), `iops` and `throughput` as for `root`. The module does not format or mount them; do that in `user_data_scripts`.
- `kms_key_id` - (Optional) The ARN of the KMS key to encrypt the volumes with. Defaults to `null`: the account's default EBS key. Its key policy must allow the `AWSServiceRoleForAutoScaling` service-linked role to use it and create grants, or no instance can launch.

Type:

```hcl
object({
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
```

Default: `{}`

### Outputs

The following outputs are exported:

#### <a name="output_metadata"></a> [metadata](#output_metadata)

Description: Everything the module created, in one object, so that other configurations need only one reference:

- `details` - The scope, purpose and environment, each with its `name`, `abbr` (lowercase, words joined by underscores) and `machine` (lowercase letters and numbers only) forms, and the `tags` applied to every resource.
- `aws` - The `account.id`, and the `region` `name`, `abbr` (such as `use1` for `us-east-1`) and `description`.
- `ami` - The AMI the launch template uses: its `id`, `name`, `architecture` and `root_device_name`.
- `auto_scaling_group` - The Auto Scaling group's `name`. Use it for scaling policies, scheduled actions and alarms.
- `launch_template` - The launch template's `id`, `name` and latest `version`.
- `cloudformation_stack` - The CloudFormation stack that holds the launch template and the Auto Scaling group: its `id`, `name`, `outputs` and the rest of its attributes, except the template itself.
- `iam_role` - The instances' IAM role, with its `name` and `arn`. Attach more policies to it by `name`.
- `iam_instance_profile` - The instance profile, with its `name` and `arn`.
- `iam_role_policy` - The role's inline policy, or `null` when it has none.
- `iam_role_policy_attachment` - The managed policies attached to the role: `ssm`, or `null` when `iam_role.ssm_managed_instance_core` is `false`, and `custom`, keyed like `iam_role.managed_policy_arns`.
- `security_group` - The security groups: `instance`, and `load_balancer` (`null` without a load balancer), each with its `id`, `arn` and `name`. Use the `instance` group's `id` as a source in other groups' rules, such as a database's.
- `vpc_security_group_ingress_rule` - The inbound rules, each a map keyed by rule: `instance` (keyed like `security_group_ingress`), `instance_from_load_balancer` and `load_balancer` (keyed like `load_balancer.security_group_ingress`), and `efs` (`null` without `efs_file_system`).
- `vpc_security_group_egress_rule` - The outbound rules: `instance` (keyed like `security_group_egress`), `instance_to_efs` (`null` without `efs_file_system`) and `load_balancer_to_instance`.
- `cloudwatch_log_group` - The log groups, each with its `name` and `arn`: `system` (keyed `system`, `auth`, `cloud-init` and `cfn-init`; empty when `cloudwatch_agent.logs` is `false`) and `codedeploy` (keyed like `codedeploy.log_groups`).
- `codedeploy_deployment_group` - The CodeDeploy deployment group, or `null` without `codedeploy`.
- `lb` - The Application or Network Load Balancer, with its `arn`, `dns_name`, `zone_id` and the rest of its attributes, or `null`.
- `lb_target_group` - The target groups, keyed like `load_balancer.target_groups`, each with its `arn` and `name`.
- `lb_listener` - The listeners, keyed like `load_balancer.listeners`, each with its `arn`.
- `eip` - The Network Load Balancer's Elastic IP addresses, one per subnet in the order of `load_balancer.subnet_ids`, each with its `public_ip` and `allocation_id`; empty without `elastic_ip_addresses`.
- `elb` - The Classic Load Balancer, with its `name`, `dns_name`, `zone_id` and the rest of its attributes, or `null`.
- `lb_ssl_negotiation_policy` - The Classic Load Balancer's security policies, keyed like the `HTTPS` and `SSL` entries of `load_balancer.classic_listeners`.

Left out because they change after the apply, without any change in the configuration: the Classic Load Balancer's `instances` and the target groups' `load_balancer_arns`, which the Auto Scaling group and the listeners fill in, and the security groups' inline `ingress` and `egress`.
<!-- END_TF_DOCS -->

## License

This module is licensed under the [Apache License 2.0](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/blob/main/LICENSE). See [NOTICE](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/blob/main/NOTICE) for the copyright notice.

The Automate the Cloud name and logo are not covered by this license.

---

Maintained by [Automate the Cloud](https://automatethe.cloud), a Kentucky 501(c)(3) that teaches cloud infrastructure and helps nonprofits run theirs.
