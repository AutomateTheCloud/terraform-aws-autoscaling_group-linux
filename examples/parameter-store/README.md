# Configuration and secrets from Parameter Store

One Amazon Linux 2023 instance that loads its application's configuration and secrets from AWS Systems Manager Parameter Store when it boots. The parameters live under two paths, named after the deployment's `details` abbreviations:

- `/secrets/example/parameter_store/development`, for this environment: a database host name, and a database password stored as a `SecureString` encrypted with the example's own KMS key;
- `/secrets/example/parameter_store/global`, for values every environment of the application shares: a support email address.

`parameter_store.paths` lets the instance read everything under both paths, one parameter at a time or a whole path at once, and `parameter_store.kms_key_arns` lets it decrypt the password, only through Parameter Store. A script in `user_data_scripts` reads both paths with `aws ssm get-parameters-by-path` and writes each parameter to `/etc/example-app/config.env`, which only root can read, as `DATABASE_HOST=...`, `DATABASE_PASSWORD=...` and `SUPPORT_EMAIL=...`. The values never appear in the boot log.

Terraform creates the password with the placeholder `change-me` and ignores its value after that, so the real password is never in the Terraform state. Set it yourself:

```shell
aws ssm put-parameter --overwrite --type SecureString --name <database_password_parameter> --value '<password>'
```

The instance reads the parameters only when it boots. To load a new value, replace the instance, for example with `aws autoscaling start-instance-refresh --auto-scaling-group-name <auto_scaling_group>`.

## Run it

The subnets need outbound internet access, such as through a NAT gateway, for the updates and AWS services:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

Then open a shell on the instance with Session Manager and look at the file: `sudo cat /etc/example-app/config.env`.

`terraform destroy`, with the same `-var` options, deletes everything the example created. The KMS key is deleted after a 7-day waiting period.

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

#### <a name="output_database_password_parameter"></a> [database_password_parameter](#output_database_password_parameter)

Description: The parameter to put the real database password in
<!-- END_TF_DOCS -->
