terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Public Subnet for VPN Endpoint
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# Private Subnet for Test Endpoints
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for VPN Endpoint
resource "aws_security_group" "vpn_endpoint" {
  name_prefix = "${var.project_name}-vpn-endpoint-"
  description = "Security group for Client VPN endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS for VPN connections"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-vpn-endpoint-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Test Endpoints
resource "aws_security_group" "test_endpoints" {
  name_prefix = "${var.project_name}-test-endpoints-"
  description = "Security group for test endpoints accessible via VPN"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.vpn_endpoint.id]
    description     = "Allow all traffic from VPN"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.client_vpn_cidr]
    description = "SSH from VPN clients"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.client_vpn_cidr]
    description = "HTTP from VPN clients"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.client_vpn_cidr]
    description = "HTTPS from VPN clients"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-test-endpoints-sg"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudWatch Log Group for VPN Connection Logs
resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${var.project_name}"
  retention_in_days = 30

  tags = {
    Name        = "${var.project_name}-vpn-logs"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_stream" "vpn_connections" {
  name           = "connection-logs"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

# ACM Certificate for VPN (self-signed for demo)
resource "aws_acm_certificate" "vpn_server" {
  private_key      = file("${path.module}/certs/server-key.pem")
  certificate_body = file("${path.module}/certs/server-cert.pem")
  certificate_chain = file("${path.module}/certs/ca-cert.pem")

  tags = {
    Name        = "${var.project_name}-vpn-server-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate" "vpn_client" {
  private_key      = file("${path.module}/certs/client-key.pem")
  certificate_body = file("${path.module}/certs/client-cert.pem")
  certificate_chain = file("${path.module}/certs/ca-cert.pem")

  tags = {
    Name        = "${var.project_name}-vpn-client-cert"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Client VPN Endpoint
resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "Client VPN for ${var.project_name}"
  server_certificate_arn = aws_acm_certificate.vpn_server.arn
  client_cidr_block      = var.client_vpn_cidr
  split_tunnel           = true
  
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.vpn_client.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn_connections.name
  }

  dns_servers = [cidrhost(var.vpc_cidr, 2)]

  security_group_ids = [aws_security_group.vpn_endpoint.id]
  vpc_id             = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-client-vpn"
    Environment = var.environment
  }
}

# Associate VPN endpoint with subnets
resource "aws_ec2_client_vpn_network_association" "main" {
  count                  = 2
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = aws_subnet.public[count.index].id
}

# Authorization rule for VPN access
resource "aws_ec2_client_vpn_authorization_rule" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = aws_vpc.main.cidr_block
  authorize_all_groups   = true
  description            = "Allow access to VPC"
}

# Route for VPN clients to access VPC
resource "aws_ec2_client_vpn_route" "main" {
  count                  = 2
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = aws_vpc.main.cidr_block
  target_vpc_subnet_id   = aws_subnet.public[count.index].id
}

# IAM Role for VPN CloudWatch Logging
resource "aws_iam_role" "vpn_cloudwatch" {
  name_prefix = "${var.project_name}-vpn-logs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpn.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-vpn-cloudwatch-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "vpn_cloudwatch" {
  name_prefix = "cloudwatch-logs-"
  role        = aws_iam_role.vpn_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.vpn.arn}:*"
      }
    ]
  })
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}
