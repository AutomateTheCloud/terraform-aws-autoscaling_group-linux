# Pinned AMI and rolling updates

Three Amazon Linux 2023 instances on an AMI you choose, instead of the newest one, so they change only when you say so. Changing the AMI replaces the instances in a rolling update: one at a time, with at least two always in service, each new instance reporting that its setup succeeded before the next is replaced. If a new instance fails, the update stops and undoes itself, and the apply fails.

The instances also skip package updates at boot (`update_packages = false`), so every instance runs exactly what the AMI contains, whenever it was launched.

## Run it

Choose a VPC and private subnets in two or more Availability Zones, with outbound internet access, such as through a NAT gateway:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'ami_id=ami-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```
To find the newest Amazon Linux 2023 AMI in us-east-1:

```shell
aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text
```

## Things to try

**Roll out a new AMI.** Apply again with a newer `ami_id`. The apply takes about 5 minutes: CloudFormation replaces the three instances one at a time. Watch it in the stack's events, from another terminal:

```shell
aws cloudformation describe-stack-events --stack-name <stack> --query 'StackEvents[].[Timestamp,ResourceStatusReason]' --output text
```

**See a failed rollout undo itself.** Add a script that fails, such as `user_data_scripts = ["#!/bin/bash\nexit 1\n"]`, and apply. The first new instance reports a failure, CloudFormation puts back an instance with the previous configuration, and the apply fails with `Received 1 FAILURE signal(s)`. Remove the script, and the next plan shows no changes.

`terraform destroy`, with the same `-var` options, deletes everything the example created.

<!-- BEGIN_TF_DOCS -->
### Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement_terraform) (>= 1.9)

- <a name="requirement_aws"></a> [aws](#requirement_aws) (~> 6.0)

- <a name="requirement_random"></a> [random](#requirement_random) (~> 3.0)

### Required Inputs

The following input variables are required:

#### <a name="input_ami_id"></a> [ami_id](#input_ami_id)

Description: The AMI to run: an Amazon Linux 2023 AMI for x86_64 in us-east-1, such as the one aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 returns

Type: `string`

#### <a name="input_subnet_ids"></a> [subnet_ids](#input_subnet_ids)

Description: IDs of private subnets in two or more Availability Zones, with outbound internet access through a NAT gateway

Type: `list(string)`

#### <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id)

Description: ID of the VPC to launch the instances in

Type: `string`

### Outputs

The following outputs are exported:

#### <a name="output_auto_scaling_group"></a> [auto_scaling_group](#output_auto_scaling_group)

Description: The Auto Scaling group's name

#### <a name="output_stack"></a> [stack](#output_stack)

Description: The CloudFormation stack whose events show each rolling update
<!-- END_TF_DOCS -->
