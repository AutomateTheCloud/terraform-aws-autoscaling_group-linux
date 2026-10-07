# Complete deployment

Two Ubuntu 24.04 web servers on AWS Graviton (`t4g.small`, or `t4g.medium` when no `t4g.small` capacity is available), behind an internal Application Load Balancer that anything in the VPC can reach on port 80. The example also creates:

- an Amazon EFS file system, with a mount target in each subnet and a file system policy that refuses connections without TLS. The module mounts it at `/efs` on every instance, through TLS;
- an AWS CodeDeploy application, the IAM role CodeDeploy uses, and, through the module, a deployment group for the Auto Scaling group, with a log group for the application.

Each instance gets a 10 GiB data volume, which the example leaves unformatted. A script in `user_data_scripts` installs nginx, adds a line to a file on the shared file system, and writes a page that shows which instance answered and that file as it was when the instance booted. A launch template change replaces one instance at a time and keeps the other in service.

## Run it

Choose a VPC and private subnets in two or more Availability Zones, with outbound internet access, such as through a NAT gateway:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

The apply takes about 10 minutes: it waits for both instances to finish their setup. Then, from anything in the VPC, such as a Session Manager shell on one of the instances:

```shell
curl <url>
```

Repeat it to see both instances answer. To deploy an application, give the instances' role read access to your revision bucket (`codedeploy.revision_bucket`), and run `aws deploy create-deployment` for the application `example-complete-web` and the `codedeploy_deployment_group` output.

`terraform destroy`, with the same `-var` options, deletes everything the example created, including the file system and its files.

<!-- BEGIN_TF_DOCS -->
### Requirements

The following requirements are needed by this module:

- <a name="requirement_terraform"></a> [terraform](#requirement_terraform) (>= 1.9)

- <a name="requirement_aws"></a> [aws](#requirement_aws) (~> 6.0)

- <a name="requirement_random"></a> [random](#requirement_random) (~> 3.0)

### Required Inputs

The following input variables are required:

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

#### <a name="output_codedeploy_deployment_group"></a> [codedeploy_deployment_group](#output_codedeploy_deployment_group)

Description: The CodeDeploy deployment group to deploy to

#### <a name="output_url"></a> [url](#output_url)

Description: The load balancer's address, reachable from inside the VPC
<!-- END_TF_DOCS -->
