output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "client_vpn_endpoint_id" {
  description = "ID of the Client VPN endpoint"
  value       = aws_ec2_client_vpn_endpoint.main.id
}

output "client_vpn_endpoint_dns" {
  description = "DNS name of the Client VPN endpoint"
  value       = aws_ec2_client_vpn_endpoint.main.dns_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for VPN connections"
  value       = aws_cloudwatch_log_group.vpn.name
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "test_endpoints_sg_id" {
  description = "Security group ID for test endpoints"
  value       = aws_security_group.test_endpoints.id
}

output "vpn_configuration_download_command" {
  description = "AWS CLI command to download VPN configuration"
  value       = "aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id ${aws_ec2_client_vpn_endpoint.main.id} --output text > client-config.ovpn"
}
