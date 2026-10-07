# Spot Instances

An Auto Scaling group that runs mostly on Spot Instances: spare EC2 capacity, often much cheaper than On-Demand, which AWS can take back with two minutes' notice. The group spreads across three instance types, so a shortage of one type does not stop it, and keeps one unit On-Demand, so something runs even when no Spot capacity is available.

**Weights.** Each instance type counts for its `weighted_capacity` in the group's sizes. Here a `t3.small`, with twice the memory of a `t3.micro`, counts as 2, so the minimum of 4 units can be four micro instances, two small ones, or a mix, such as one On-Demand `t3.micro`, one Spot `t3.micro` and one Spot `t3.small`. When the group is created, the apply waits for the fewest instances that can make up the capacity: 4 units divided by the largest weight, 2, is 2 instances.

**Choosing Spot capacity.** `price-capacity-optimized` picks the pools with the lowest price among those AWS considers least likely to be interrupted. When AWS takes a Spot Instance back, the group launches a replacement, which sets itself up like any other instance.

Use Spot Instances for work that tolerates an instance disappearing: stateless web servers behind a load balancer, or workers that pick up jobs from a queue.

## Run it

Choose a VPC and private subnets in two or more Availability Zones, with outbound internet access, such as through a NAT gateway:

```shell
terraform init
terraform apply -var 'vpc_id=vpc-0123456789abcdef0' -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0fedcba9876543210"]'
```

To see what the group launched:

```shell
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <auto_scaling_group> --query 'AutoScalingGroups[0].Instances[].[InstanceId,InstanceType,WeightedCapacity]'
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

#### <a name="output_auto_scaling_group"></a> [auto_scaling_group](#output_auto_scaling_group)

Description: The Auto Scaling group's name, to see which instances it launched
<!-- END_TF_DOCS -->
