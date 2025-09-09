#!/bin/bash
# Simple Load Balancer Test Script
echo "=== LOAD BALANCER TEST ==="

PROXY_IP="10.0.0.10"
SSH_KEY="ssh_keys/project_key"

echo "1. Testing HAProxy service status..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "systemctl status haproxy --no-pager"

echo
echo "2. Testing listening ports..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "ss -tlnp | grep -E ':(80|2525|5433)'"

echo
echo "3. Testing HTTP routing to NextCloud..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "curl -H 'Host: storage.infra.prog' http://localhost -I"

echo
echo "4. Testing backend connectivity..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "curl -s -o /dev/null -w 'NextCloud backend: %{http_code}\n' http://10.0.0.20"

echo
echo "5. Testing TCP proxies..."
echo "Mail proxy test (port 2525):"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "timeout 3 telnet localhost 2525 < /dev/null"

echo "Database proxy test (port 5433):"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "timeout 3 telnet localhost 5433 < /dev/null"

echo
echo "6. HAProxy configuration summary:"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$PROXY_IP "sudo grep -E '^(frontend|backend|server)' /etc/haproxy/haproxy.cfg"

echo
echo "=== TEST COMPLETED ==="
