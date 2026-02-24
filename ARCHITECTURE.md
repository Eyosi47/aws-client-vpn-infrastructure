# Architecture Documentation

## Overview

This document provides detailed technical architecture information for the AWS Client VPN infrastructure.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Internet Users                              │
│                    (VPN Clients with Certificates)                   │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ TLS Encrypted Connection
                             │ (Port 443)
                             │
┌────────────────────────────▼────────────────────────────────────────┐
│                    AWS Client VPN Endpoint                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Certificate Authentication                                   │  │
│  │  - Root CA Verification                                       │  │
│  │  - Client Certificate Validation                              │  │
│  │  - TLS 1.2+ Encryption                                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  Client CIDR: 172.16.0.0/22 (1024 IPs)                              │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ Encrypted Tunnel
                             │
        ┌────────────────────┴─────────────────────┐
        │                                          │
        │         VPC: 10.0.0.0/16                │
        │                                          │
        │  ┌────────────────────────────────────┐ │
        │  │   Availability Zone A               │ │
        │  │                                     │ │
        │  │  ┌─────────────────────────────┐  │ │
        │  │  │ Public Subnet: 10.0.0.0/24  │  │ │
        │  │  │ - NAT Gateway (optional)     │  │ │
        │  │  │ - VPN Association           │  │ │
        │  │  └─────────────────────────────┘  │ │
        │  │                                     │ │
        │  │  ┌─────────────────────────────┐  │ │
        │  │  │ Private Subnet: 10.0.10.0/24│  │ │
        │  │  │ - Test Endpoints (25)        │  │ │
        │  │  │ - EC2 Instances             │  │ │
        │  │  └─────────────────────────────┘  │ │
        │  └────────────────────────────────────┘ │
        │                                          │
        │  ┌────────────────────────────────────┐ │
        │  │   Availability Zone B               │ │
        │  │                                     │ │
        │  │  ┌─────────────────────────────┐  │ │
        │  │  │ Public Subnet: 10.0.1.0/24  │  │ │
        │  │  │ - NAT Gateway (optional)     │  │ │
        │  │  │ - VPN Association           │  │ │
        │  │  └─────────────────────────────┘  │ │
        │  │                                     │ │
        │  │  ┌─────────────────────────────┐  │ │
        │  │  │ Private Subnet: 10.0.11.0/24│  │ │
        │  │  │ - Test Endpoints (25)        │  │ │
        │  │  │ - EC2 Instances             │  │ │
        │  │  └─────────────────────────────┘  │ │
        │  └────────────────────────────────────┘ │
        │                                          │
        └──────────────────────────────────────────┘
                             │
                             │
                ┌────────────▼────────────┐
                │   CloudWatch Logs       │
                │   - Connection Logs     │
                │   - 30-day Retention    │
                └─────────────────────────┘
```

## Network Architecture

### VPC Design

**CIDR Block**: 10.0.0.0/16
- **Usable IPs**: 65,536
- **Reserved**: 5 per subnet (AWS reserved)

### Subnet Design

#### Public Subnets (VPN Associations)
- **AZ-A**: 10.0.0.0/24 (251 usable IPs)
- **AZ-B**: 10.0.1.0/24 (251 usable IPs)
- Purpose: VPN endpoint network associations
- Internet Gateway: Attached
- Route to Internet: 0.0.0.0/0 → IGW

#### Private Subnets (Test Endpoints)
- **AZ-A**: 10.0.10.0/24 (251 usable IPs)
- **AZ-B**: 10.0.11.0/24 (251 usable IPs)
- Purpose: Host test EC2 instances
- No direct internet access
- Access via VPN only

### VPN Client CIDR

**Range**: 172.16.0.0/22
- **Total IPs**: 1024
- **Usable IPs**: 1020 (AWS reserves 4)
- Supports up to 1020 concurrent VPN connections

## Security Architecture

### Defense in Depth Layers

#### Layer 1: Network Perimeter
- Client VPN endpoint with certificate authentication
- TLS 1.2+ encryption mandatory
- No password-based authentication

#### Layer 2: Certificate Validation
```
Client Connection Attempt
    │
    ├──> Validate Client Certificate
    │    ├──> Check against Root CA
    │    ├──> Verify certificate not expired
    │    └──> Validate certificate chain
    │
    ├──> TLS Handshake
    │    ├──> Negotiate cipher suite
    │    └──> Establish encrypted tunnel
    │
    └──> Authorization Rules
         ├──> Check target CIDR permissions
         └──> Grant/Deny access
```

#### Layer 3: Security Groups

**VPN Endpoint Security Group**
```
Ingress:
- Port 443/TCP from 0.0.0.0/0 (VPN connections)

Egress:
- All traffic to 0.0.0.0/0
```

**Test Endpoints Security Group**
```
Ingress:
- All traffic from VPN Endpoint SG
- Port 22/TCP from 172.16.0.0/22 (SSH from VPN clients)
- Port 80/TCP from 172.16.0.0/22 (HTTP from VPN clients)
- Port 443/TCP from 172.16.0.0/22 (HTTPS from VPN clients)

Egress:
- All traffic to 0.0.0.0/0
```

#### Layer 4: Network ACLs
- Default VPC ACLs allow all traffic
- Can be customized for additional security

### Certificate Architecture

```
Certificate Authority (CA)
    │
    ├──> Server Certificate
    │    └──> Installed on VPN Endpoint
    │         - Subject: vpn.example.com
    │         - Valid: 10 years
    │         - Key: RSA 2048-bit
    │
    └──> Client Certificate(s)
         └──> Distributed to VPN Users
              - Subject: client
              - Valid: 10 years
              - Key: RSA 2048-bit
```

**Certificate Validation Flow:**
1. Client presents certificate during TLS handshake
2. VPN endpoint validates against Root CA
3. Check certificate validity period
4. Verify certificate hasn't been revoked
5. Establish encrypted tunnel if valid

### Encryption Specifications

**TLS Configuration:**
- Protocol: TLS 1.2 minimum
- Perfect Forward Secrecy: Enabled
- Cipher Suites: Strong ciphers only
  - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
  - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256

**Data Encryption:**
- All VPN traffic encrypted with AES-256
- Control channel: TLS 1.2+
- Data channel: AES-256-GCM

## High Availability Architecture

### Multi-AZ Deployment

```
Region: us-east-1
    │
    ├──> Availability Zone A (us-east-1a)
    │    ├──> Public Subnet: 10.0.0.0/24
    │    │    └──> VPN Association #1
    │    │
    │    └──> Private Subnet: 10.0.10.0/24
    │         └──> 25 Test Endpoints
    │
    └──> Availability Zone B (us-east-1b)
         ├──> Public Subnet: 10.0.1.0/24
         │    └──> VPN Association #2
         │
         └──> Private Subnet: 10.0.11.0/24
              └──> 25 Test Endpoints
```

### Redundancy Features

1. **Multiple VPN Associations**
   - 2 subnets across 2 AZs
   - Automatic failover
   - Load distribution

2. **Endpoint Distribution**
   - 50% in AZ-A
   - 50% in AZ-B
   - Survives single AZ failure

3. **Route Redundancy**
   - Routes configured per association
   - Automatic rerouting on failure

### Uptime Calculation

**SLA Components:**
- AWS VPN SLA: 99.95%
- EC2 SLA (per instance): 99.99%
- VPC SLA: 100% (availability within region)

**Achieved Uptime:**
```
Multi-AZ Deployment:
P(both AZs down) = (1 - 0.9995)² = 0.0000025
Expected Uptime = 99.9999% ≈ 100%
```

## Monitoring Architecture

### CloudWatch Integration

```
VPN Endpoint
    │
    ├──> CloudWatch Metrics
    │    ├──> ActiveConnectionsCount
    │    ├──> AuthenticationFailures
    │    ├──> IngressBytes
    │    ├──> EgressBytes
    │    └──> IngressPackets / EgressPackets
    │
    └──> CloudWatch Logs
         └──> /aws/vpn/<project-name>
              ├──> Connection Logs
              ├──> Authentication Events
              └──> Disconnection Logs
```

### Monitoring Dashboard

**Metrics Displayed:**
1. Active Connections (real-time)
2. Authentication Failures (last 24h)
3. Data Transfer (ingress/egress)
4. Connection Duration
5. Failed Connection Attempts

### Alerting Configuration

```
SNS Topic: <project>-alerts
    │
    ├──> CloudWatch Alarm: Auth Failures
    │    - Threshold: >10 failures in 5 minutes
    │    - Action: Send SNS notification
    │
    ├──> CloudWatch Alarm: Connection Drop
    │    - Threshold: All connections down
    │    - Action: Send SNS notification
    │
    └──> CloudWatch Alarm: High Data Transfer
         - Threshold: >10 GB in 1 hour
         - Action: Send SNS notification
```

## Routing Architecture

### VPN Routing Table

```
Destination         Target              Type
-------------------------------------------------
10.0.0.0/16        VPC                 NAT
172.16.0.0/22      Local (VPN)         Local
0.0.0.0/0          Internet (split)    Split Tunnel
```

**Split Tunnel Configuration:**
- Enabled by default
- Only VPC traffic routes through VPN
- Internet traffic uses client's local connection
- Reduces bandwidth costs

### Route Propagation

```
VPN Client
    │
    ├──> 10.0.0.0/16 traffic
    │    └──> Encrypted → VPN Endpoint → VPC
    │
    └──> Other traffic (e.g., 8.8.8.8)
         └──> Direct → Client ISP → Internet
```

## Capacity Planning

### Current Configuration

| Resource | Quantity | Max Capacity | Utilization |
|----------|----------|--------------|-------------|
| VPN Connections | Varies | 1020 | Variable |
| Test Endpoints | 50 | 251/subnet | 20% |
| VPC IPs | 65,536 | 65,536 | <1% |
| Subnet IPs (Private) | 502 | 502 | 10% |

### Scaling Considerations

**Horizontal Scaling:**
- Add more subnets for >500 endpoints
- Create additional VPN endpoints for >1000 connections
- Distribute across more AZs for higher redundancy

**Vertical Scaling:**
- Upgrade EC2 instance types (t3.micro → t3.small)
- Increase EBS volumes for storage
- Adjust VPC CIDR for more IP space

### Cost Optimization

**Recommendations:**
1. Use Reserved Instances for long-term endpoints
2. Enable auto-stop for non-production hours
3. Implement lifecycle policies for logs
4. Right-size EC2 instances based on actual usage

## Compliance & Security Standards

### Implemented Controls

#### Network Security
- ✅ Encryption in transit (TLS 1.2+)
- ✅ Network segmentation (public/private subnets)
- ✅ Security groups (least privilege)
- ✅ No default credentials

#### Access Control
- ✅ Certificate-based authentication
- ✅ Authorization rules per CIDR
- ✅ Multi-factor authentication ready (can add SAML)

#### Logging & Monitoring
- ✅ Connection logs (30-day retention)
- ✅ CloudWatch metrics
- ✅ Real-time alerting
- ✅ Audit trail

#### Availability
- ✅ Multi-AZ deployment
- ✅ Redundant network paths
- ✅ Automated failover
- ✅ 99.99%+ uptime target

### Compliance Mappings

**PCI DSS:**
- Requirement 1: Network Security → ✅ Firewall, Security Groups
- Requirement 4: Encryption → ✅ TLS 1.2+, AES-256
- Requirement 10: Logging → ✅ CloudWatch Logs

**HIPAA:**
- Access Controls → ✅ Certificate authentication
- Encryption → ✅ TLS for transit
- Audit Controls → ✅ Connection logging

**SOC 2:**
- Availability → ✅ Multi-AZ, Monitoring
- Confidentiality → ✅ Encryption, Access controls
- Processing Integrity → ✅ Logging, Validation

## Disaster Recovery

### Backup Strategy

**Configuration Backup:**
- Terraform state stored in S3 (backend config)
- Certificates backed up securely
- VPN configuration versioned in Git

**Recovery Objectives:**
- RTO (Recovery Time Objective): 15 minutes
- RPO (Recovery Point Objective): 0 minutes (infrastructure as code)

### Failure Scenarios

#### Scenario 1: Single AZ Failure
```
Detection: CloudWatch alarm
Impact: 50% capacity reduction
Recovery: Automatic (AWS managed)
Downtime: None (traffic routes to healthy AZ)
```

#### Scenario 2: VPN Endpoint Failure
```
Detection: Connection failures + CloudWatch
Impact: Complete VPN outage
Recovery: 
  1. Run: terraform destroy -target=aws_ec2_client_vpn_endpoint.main
  2. Run: terraform apply
  3. Update client configurations
Downtime: 10-15 minutes
```

#### Scenario 3: Certificate Expiration
```
Detection: 30 days before expiry (monitoring)
Prevention:
  1. Generate new certificates
  2. Import to ACM
  3. Update VPN endpoint
  4. Distribute new client configs
Downtime: None (if proactive)
```

## Performance Characteristics

### Throughput

**VPN Endpoint:**
- Max throughput: 5 Gbps per endpoint
- Per-client bandwidth: Limited by client's connection

**Test Endpoints (t3.micro):**
- Network: Up to 5 Gbps
- CPU: 2 vCPUs (burstable)
- Memory: 1 GB

### Latency

**Expected Latency:**
```
Client → VPN Endpoint: 1-5ms (TLS handshake)
VPN Endpoint → EC2: 1-3ms (intra-VPC)
Total Add-On: 2-8ms (vs direct connection)
```

### Concurrency

**Connection Limits:**
- VPN Endpoint: 1020 concurrent connections
- Security Group: No hard limit on connections
- EC2 Instance: 1024 connections (typical)

## Future Enhancements

### Planned Improvements

1. **IAM Authentication Integration**
   - Replace certificates with IAM SAML
   - Integrate with corporate SSO
   - Temporary credentials

2. **Enhanced Monitoring**
   - Custom CloudWatch dashboard
   - Lambda-based anomaly detection
   - Automated reporting

3. **Certificate Rotation**
   - Automated certificate renewal
   - Zero-downtime rotation
   - Client auto-update mechanism

4. **Traffic Analysis**
   - VPC Flow Logs integration
   - Traffic pattern analysis
   - Bandwidth optimization

5. **Multi-Region Support**
   - Deploy in multiple regions
   - Global accelerator integration
   - Disaster recovery in different region

### Scalability Roadmap

```
Phase 1 (Current): 50 endpoints, 1 region
    │
Phase 2: 200 endpoints, enhanced monitoring
    │
Phase 3: 500 endpoints, multi-region
    │
Phase 4: 1000+ endpoints, global deployment
```

## References

- [AWS Client VPN Documentation](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/)
- [VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [OpenVPN Protocol](https://openvpn.net/community-resources/reference-manual-for-openvpn-2-4/)
- [TLS 1.2 Specification](https://tools.ietf.org/html/rfc5246)
