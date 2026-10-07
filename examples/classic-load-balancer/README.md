# Classic Load Balancer

An Amazon Linux 2023 web server behind an internal Classic Load Balancer, the previous generation of Elastic Load Balancing. Use it for applications that already depend on a Classic Load Balancer; for new work, use an Application or Network Load Balancer, as in the [complete](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/complete) and [Network Load Balancer](https://github.com/AutomateTheCloud/terraform-aws-autoscaling_group-linux/tree/main/examples/network-load-balancer) examples.

The load balancer listens for HTTP on port 80, from anything in the VPC, and passes requests to nginx on the instance. It checks the instance with an HTTP request for `/`. The module turns on connection draining (300 seconds), so requests in progress finish when an instance is replaced, and, for `HTTPS` and `SSL` listeners, a security policy that accepts TLS 1.2 only.

## Run it

Choose a VPC and private subnets in two or more Availability Zones, with outbound internet access, such as through a NAT gateway:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

Then, from anything in the VPC, `curl http://<address>/`.

`terraform destroy`, with the same `-var` options, deletes everything the example created.

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

#### <a name="output_address"></a> [address](#output_address)

Description: The load balancer's DNS name, reachable from inside the VPC
<!-- END_TF_DOCS -->
