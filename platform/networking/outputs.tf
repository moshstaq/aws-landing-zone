output "vpc_id" {
  description = "ID of the platform VPC"
  value       = aws_vpc.platform.id
}

output "vpc_cidr" {
  description = "CIDR block of the platform VPC"
  value       = aws_vpc.platform.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.platform.id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC Gateway Endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway (empty when disabled)"
  value       = var.nat_gateway_enabled ? aws_nat_gateway.platform[0].id : null
}
