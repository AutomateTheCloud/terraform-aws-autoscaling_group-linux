# Network Load Balancer

Two Ubuntu 24.04 web servers behind an internal Network Load Balancer. The load balancer accepts TCP connections on port 80 from anything in the VPC and passes them to the instances, which run nginx and answer with their own host name. It checks each instance's health over HTTP, so an instance whose web server stops is taken out of service even though its port still accepts connections.

The module creates the load balancer, its security group, the target group and the listener, and the rules that let the load balancer reach the instances on port 80 only. It also turns off client IP preservation for the target group: with it on, the instances would see each client's address instead of the load balancer's, and their security group would refuse the connections. To give the application the clients' addresses, set `preserve_client_ip = true` on the target group and allow the clients in the module's `security_group_ingress` too, or use `proxy_protocol_v2` if the application understands the proxy protocol.

## Run it

Choose a VPC and private subnets in two or more Availability Zones, with outbound internet access, such as through a NAT gateway:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

The apply takes about 3 minutes. The load balancer's first health checks take a few more minutes; then, from anything in the VPC, such as a Session Manager shell on one of the instances, repeat this to see both instances answer:

```shell
curl http://<address>/
```

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
