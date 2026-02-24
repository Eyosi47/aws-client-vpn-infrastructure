# Test EC2 Instances representing endpoints
resource "aws_instance" "test_endpoint" {
  count                  = var.endpoint_count
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private[count.index % 2].id
  vpc_security_group_ids = [aws_security_group.test_endpoints.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Test Endpoint ${count.index + 1}</h1>" > /var/www/html/index.html
              echo "<p>Private IP: $(hostname -I)</p>" >> /var/www/html/index.html
              EOF

  tags = {
    Name        = "${var.project_name}-endpoint-${count.index + 1}"
    Environment = var.environment
    Type        = "test-endpoint"
    Endpoint    = count.index + 1
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Data source for Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "vpn_monitoring" {
  dashboard_name = "${var.project_name}-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ClientVPN", "ActiveConnectionsCount", {
              stat = "Average"
            }],
            [".", "AuthenticationFailures", {
              stat = "Sum"
            }],
            [".", "IngressBytes", {
              stat = "Sum"
            }],
            [".", "EgressBytes", {
              stat = "Sum"
            }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "VPN Metrics"
        }
      }
    ]
  })
}

# SNS Topic for VPN alerts
resource "aws_sns_topic" "vpn_alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Environment = var.environment
  }
}

# CloudWatch Alarm for VPN authentication failures
resource "aws_cloudwatch_metric_alarm" "auth_failures" {
  alarm_name          = "${var.project_name}-auth-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "AuthenticationFailures"
  namespace           = "AWS/ClientVPN"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when VPN authentication failures exceed threshold"
  alarm_actions       = [aws_sns_topic.vpn_alerts.arn]

  dimensions = {
    ClientVPNEndpoint = aws_ec2_client_vpn_endpoint.main.id
  }
}
