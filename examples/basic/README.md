# Basic deployment

One Amazon Linux 2023 `t3.micro` instance, launched and kept running by an Auto Scaling group, in private subnets you give. At its first boot it installs the latest updates, creates a 2 GiB swap file and starts the Amazon CloudWatch agent, which sends its system, authentication and boot logs to four log groups kept for 30 days. Then it reports success to AWS CloudFormation, and the apply finishes.

Everything else uses the module's defaults: IMDSv2 only, an encrypted 20 GiB root volume, no public IP address, no inbound rules, outbound HTTP and HTTPS only, and an IAM role with only the AWS Systems Manager permissions.

## Run it

The subnets need outbound internet access, such as through a NAT gateway, for the updates and AWS services:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

The apply takes about 5 minutes: it waits for the instance to finish its setup. Then find the instance and open a shell on it with Session Manager (the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the AWS CLI is needed):

```shell
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <auto_scaling_group> --query 'AutoScalingGroups[0].Instances[].InstanceId'
aws ssm start-session --target <instance ID>
```

`terraform destroy`, with the same `-var` options, terminates the instance and deletes everything the example created.

<!-- BEGIN_TF_DOCS -->
### Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement_terraform) (>= 1.9)

- <a name="requirement_aws"></a> [aws](#requirement_aws) (~> 6.0)

- <a name="requirement_random"></a> [random](#requirement_random) (~> 3.0)

### Required Inputs

The following input variables are required:

#### <a name="input_subnet_ids"></a> [subnet_ids](#input_subnet_ids)

Description: IDs of private subnets for the instance, with outbound internet access through a NAT gateway

Type: `list(string)`

#### <a name="input_vpc_id"></a> [vpc_id](#input_vpc_id)

Description: ID of the VPC to launch the instance in

Type: `string`

### Outputs

The following outputs are exported:

#### <a name="output_auto_scaling_group"></a> [auto_scaling_group](#output_auto_scaling_group)

Description: The Auto Scaling group's name, to find the instance
<!-- END_TF_DOCS -->
