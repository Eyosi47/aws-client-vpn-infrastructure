# Deployment Guide

## Prerequisites Checklist

Before deploying this infrastructure, ensure you have:

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured (`aws --version`)
- [ ] Terraform >= 1.0 installed (`terraform --version`)
- [ ] OpenSSL installed (`openssl version`)
- [ ] Git installed (`git --version`)

## Step-by-Step Deployment

### 1. Initial Setup (5 minutes)

```bash
# Clone the repository
git clone <your-repo-url>
cd aws-client-vpn-project

# Verify prerequisites
aws sts get-caller-identity  # Should show your AWS account
terraform --version          # Should show 1.0+
openssl version             # Should show OpenSSL
```

### 2. Generate Certificates (2 minutes)

```bash
# Generate all required certificates
./scripts/generate-certificates.sh

# Verify certificates were created
ls -la certs/
# Should show: ca-cert.pem, ca-key.pem, server-cert.pem, 
#              server-key.pem, client-cert.pem, client-key.pem
```

**⚠️ IMPORTANT**: These certificates are sensitive! Never commit them to Git.

### 3. Configure Environment (3 minutes)

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars  # or use your preferred editor
```

Customize these values:
```hcl
aws_region     = "us-east-1"        # Your preferred region
project_name   = "my-vpn-project"   # Your project name
environment    = "production"        # dev, staging, or production
vpc_cidr       = "10.0.0.0/16"      # VPC CIDR block
client_vpn_cidr = "172.16.0.0/22"   # VPN client IP range
endpoint_count = 50                  # Number of test endpoints
```

### 4. Initialize Terraform (2 minutes)

```bash
# Initialize Terraform and download providers
terraform init

# Expected output:
# Terraform has been successfully initialized!
```

### 5. Review Infrastructure Plan (5 minutes)

```bash
# Generate and review the execution plan
terraform plan

# Review the output carefully. It should show:
# - VPC creation
# - Subnets (public and private)
# - Security groups
# - VPN endpoint
# - 50 EC2 instances (test endpoints)
# - CloudWatch resources
```

### 6. Deploy Infrastructure (10-15 minutes)

```bash
# Apply the configuration
terraform apply

# Type 'yes' when prompted

# Wait for completion. This will create:
# - 1 VPC
# - 4 Subnets (2 public, 2 private)
# - 1 Internet Gateway
# - Route tables and associations
# - Security groups
# - 1 Client VPN endpoint
# - 50 EC2 instances
# - CloudWatch logs and dashboard
# - SNS topics and alarms
```

### 7. Capture Outputs (1 minute)

```bash
# Save important outputs
terraform output > infrastructure-outputs.txt

# Display key information
terraform output client_vpn_endpoint_id
terraform output client_vpn_endpoint_dns
terraform output vpc_id
```

### 8. Download VPN Configuration (3 minutes)

```bash
# Get VPN endpoint ID
VPN_ENDPOINT_ID=$(terraform output -raw client_vpn_endpoint_id)

# Export VPN client configuration
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $VPN_ENDPOINT_ID \
  --output text > client-config.ovpn

# Add client certificates to the configuration
cat >> client-config.ovpn << 'EOF'

<cert>
EOF
cat certs/client-cert.pem >> client-config.ovpn
cat >> client-config.ovpn << 'EOF'
</cert>

<key>
EOF
cat certs/client-key.pem >> client-config.ovpn
cat >> client-config.ovpn << 'EOF'
</key>
EOF

echo "VPN configuration file created: client-config.ovpn"
```

### 9. Validate Deployment (5 minutes)

```bash
# Run comprehensive validation
./scripts/validate-vpn.sh

# This checks:
# ✓ VPN endpoint status
# ✓ Network associations
# ✓ Authorization rules
# ✓ Route configurations
# ✓ CloudWatch logging
# ✓ TLS encryption
```

Expected output:
```
========================================
AWS Client VPN Validation Script
========================================

[1/6] Checking VPN Endpoint Status...
  ✓ VPN endpoint is available

[2/6] Verifying Network Associations...
  ✓ Subnet subnet-xxx: associated
  ✓ Subnet subnet-yyy: associated

[3/6] Checking Authorization Rules...
  ✓ Rule for 10.0.0.0/16: active

[4/6] Validating VPN Routes...
  ✓ Route to 10.0.0.0/16 (NAT): active

[5/6] Checking CloudWatch Logs Configuration...
  ✓ Connection logging: enabled
  ✓ Log group: /aws/vpn/my-vpn-project

[6/6] Verifying Encryption Configuration...
  ✓ Server certificate: configured
  ✓ TLS encryption: enabled

========================================
Validation Summary
========================================

Uptime: 100%
Access Risk Reduction: 70%
Active Connections: 0
Managed Endpoints: 50

✓ All validations completed successfully!
```

### 10. Test VPN Connection (5 minutes)

#### On macOS:
```bash
# Install Tunnelblick (if not already installed)
brew install --cask tunnelblick

# Import configuration
open client-config.ovpn
```

#### On Linux:
```bash
# Install OpenVPN client
sudo apt-get install openvpn  # Ubuntu/Debian
sudo yum install openvpn      # CentOS/RHEL

# Connect to VPN
sudo openvpn --config client-config.ovpn
```

#### On Windows:
```powershell
# Download and install OpenVPN GUI from:
# https://openvpn.net/community-downloads/

# Import client-config.ovpn into OpenVPN GUI
# Right-click system tray icon -> Import -> Select client-config.ovpn
```

### 11. Verify Connectivity (3 minutes)

Once connected to VPN:

```bash
# Check your VPN IP address
ip addr show tun0  # Linux/Mac
ipconfig           # Windows

# You should have an IP from 172.16.0.0/22 range

# Test connectivity to a private endpoint
# Get a test endpoint IP
ENDPOINT_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Type,Values=test-endpoint" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

echo "Testing endpoint: $ENDPOINT_IP"
curl http://$ENDPOINT_IP

# Expected output:
# <h1>Test Endpoint 1</h1>
# <p>Private IP: 10.0.10.X</p>
```

## Post-Deployment Tasks

### Set Up Monitoring

```bash
# View CloudWatch dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(terraform output -raw aws_region)#dashboards:name=$(terraform output -raw project_name)-monitoring"
```

### Configure Alerts

```bash
# Subscribe to SNS alerts
SNS_TOPIC=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `vpn-alerts`)].TopicArn' --output text)

aws sns subscribe \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint your-email@example.com

# Confirm subscription via email
```

### Enable CloudWatch Logs Insights

```bash
# View connection logs
aws logs tail /aws/vpn/$(terraform output -raw project_name) --follow
```

## Troubleshooting

### Issue: Terraform apply fails

**Solution:**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify region
aws configure get region

# Check Terraform state
terraform state list
```

### Issue: Certificates not found

**Solution:**
```bash
# Regenerate certificates
./scripts/generate-certificates.sh

# Verify they exist
ls -la certs/
```

### Issue: VPN endpoint stuck in "pending"

**Solution:**
```bash
# Check VPN endpoint status
aws ec2 describe-client-vpn-endpoints \
  --client-vpn-endpoint-ids $(terraform output -raw client_vpn_endpoint_id)

# Wait 5-10 minutes for AWS to complete provisioning
```

### Issue: Cannot connect to test endpoints

**Solution:**
```bash
# Verify security group rules
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*test-endpoints*" \
  --query 'SecurityGroups[0].IpPermissions'

# Check if instances are running
aws ec2 describe-instances \
  --filters "Name=tag:Type,Values=test-endpoint" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
```

## Cost Estimation

Approximate monthly costs (us-east-1):

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| Client VPN Endpoint | 1 | $0.05/hour | ~$36 |
| VPN Connection Hours | 720 | $0.05/hour | ~$36 |
| EC2 t3.micro | 50 | $0.0104/hour | ~$374 |
| Data Transfer | Variable | $0.09/GB | Variable |
| CloudWatch Logs | Variable | $0.50/GB | ~$5 |

**Total Estimated Monthly Cost: ~$450-500**

To reduce costs:
- Reduce `endpoint_count` to 10-20 for testing
- Use t3.nano instead of t3.micro
- Enable auto-stop for non-business hours

## Cleanup

To destroy all resources:

```bash
# Review what will be deleted
terraform plan -destroy

# Destroy infrastructure
terraform destroy

# Type 'yes' when prompted

# Verify cleanup
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*vpn*"
```

## Next Steps

1. ✅ Infrastructure deployed
2. ✅ VPN validated and tested
3. 🔲 Configure IAM users for VPN access
4. 🔲 Set up automated certificate rotation
5. 🔲 Enable enhanced monitoring
6. 🔲 Configure backup and disaster recovery
7. 🔲 Document team onboarding procedures

## Support

For issues or questions:
1. Check the [README.md](README.md)
2. Review CloudWatch logs
3. Run validation script: `./scripts/validate-vpn.sh`
4. Check AWS VPC and EC2 console

## Additional Resources

- [AWS Client VPN Documentation](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [OpenVPN Documentation](https://openvpn.net/community-resources/)
