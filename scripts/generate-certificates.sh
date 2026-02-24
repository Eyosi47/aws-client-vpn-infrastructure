#!/bin/bash

# Script to generate self-signed certificates for AWS Client VPN
# This creates a CA and server/client certificates

set -e

CERT_DIR="./certs"
DOMAIN="vpn.example.com"

# Create certs directory
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "Generating certificates for AWS Client VPN..."

# 1. Generate CA private key and certificate
echo "1. Creating Certificate Authority (CA)..."
openssl genrsa -out ca-key.pem 2048
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=VPN-CA"

# 2. Generate server private key and certificate
echo "2. Creating Server Certificate..."
openssl genrsa -out server-key.pem 2048
openssl req -new -key server-key.pem -out server-req.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=$DOMAIN"
openssl x509 -req -days 3650 -in server-req.pem -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem

# 3. Generate client private key and certificate
echo "3. Creating Client Certificate..."
openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client-req.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=client"
openssl x509 -req -days 3650 -in client-req.pem -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out client-cert.pem

# Clean up CSR files
rm -f server-req.pem client-req.pem

echo ""
echo "✓ Certificate generation complete!"
echo ""
echo "Generated files in $CERT_DIR:"
ls -lh

echo ""
echo "IMPORTANT: Keep these files secure!"
echo "- ca-key.pem: CA private key (DO NOT SHARE)"
echo "- ca-cert.pem: CA certificate"
echo "- server-key.pem: Server private key"
echo "- server-cert.pem: Server certificate"
echo "- client-key.pem: Client private key (for VPN client)"
echo "- client-cert.pem: Client certificate (for VPN client)"

cd ..
