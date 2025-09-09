#!/bin/bash
# NFS Testing Script for Infrastructure Project
# Run this script to test NFS server and client functionality

echo "=== NFS Infrastructure Testing ==="
echo "Testing NFS setup between Database Server (10.0.0.40) and clients (NextCloud: 10.0.0.20, Mail: 10.0.0.30)"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to run command on remote host
run_remote() {
    local host=$1
    local command=$2
    local description=$3

    echo -e "${YELLOW}Testing: $description on $host${NC}"
    ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@$host "$command"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SUCCESS${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
    fi
    echo
}

# Function to test file operations
test_file_operations() {
    local client_host=$1
    local test_file="nfs_test_$(date +%s).txt"

    echo -e "${YELLOW}Testing file operations on $client_host${NC}"

    # Create test file on client
    echo "Creating test file on client..."
    ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@$client_host "echo 'NFS test from $client_host at $(date)' > /mnt/nfs/$test_file"

    # Verify file exists on server
    echo "Verifying file exists on server..."
    server_result=$(ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@10.0.0.40 "ls -la /srv/nfs_share/$test_file 2>/dev/null")

    if [ ! -z "$server_result" ]; then
        echo -e "${GREEN}✓ File successfully created and visible on server${NC}"
        echo "File details: $server_result"

        # Clean up test file
        ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@$client_host "rm -f /mnt/nfs/$test_file"
        echo "Test file cleaned up"
    else
        echo -e "${RED}✗ File not found on server - NFS write failed${NC}"
    fi
    echo
}

echo "1. TESTING NFS SERVER (Database Server - 10.0.0.40)"
echo "=================================================="

# Test NFS server service
run_remote "10.0.0.40" "systemctl is-active nfs-kernel-server" "NFS server service status"

# Test NFS exports
run_remote "10.0.0.40" "exportfs -v" "NFS exports configuration"

# Test export directory exists and permissions
run_remote "10.0.0.40" "ls -la /srv/nfs_share" "NFS export directory permissions"

# Test if export directory is accessible
run_remote "10.0.0.40" "touch /srv/nfs_share/server_test.txt && rm /srv/nfs_share/server_test.txt" "NFS export directory write test"

echo
echo "2. TESTING NFS CLIENTS"
echo "======================"

# Test NextCloud NFS client (10.0.0.20)
echo -e "${YELLOW}Testing NextCloud NFS Client (10.0.0.20)${NC}"
run_remote "10.0.0.20" "systemctl is-active nfs-common" "NFS client service"
run_remote "10.0.0.20" "mount | grep nfs" "NFS mount status"
run_remote "10.0.0.20" "ls -la /mnt/nfs" "NFS mount directory"
run_remote "10.0.0.20" "df -h /mnt/nfs" "NFS mount disk usage"

test_file_operations "10.0.0.20"

echo -e "${YELLOW}Testing Mail Server NFS Client (10.0.0.30)${NC}"
run_remote "10.0.0.30" "systemctl is-active nfs-common" "NFS client service"
run_remote "10.0.0.30" "mount | grep nfs" "NFS mount status"
run_remote "10.0.0.30" "ls -la /mnt/nfs" "NFS mount directory"
run_remote "10.0.0.30" "df -h /mnt/nfs" "NFS mount disk usage"

test_file_operations "10.0.0.30"

echo
echo "3. CROSS-CLIENT TESTING"
echo "======================="
echo "Testing if files created by one client are visible to another..."

# Create file from NextCloud client
test_file="cross_test_$(date +%s).txt"
echo "Creating file from NextCloud client..."
ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@10.0.0.20 "echo 'Cross-client test from NextCloud' > /mnt/nfs/$test_file"

# Check if visible from Mail client
echo "Checking visibility from Mail client..."
mail_result=$(ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@10.0.0.30 "cat /mnt/nfs/$test_file 2>/dev/null")

if [ ! -z "$mail_result" ]; then
    echo -e "${GREEN}✓ Cross-client file sharing working${NC}"
    echo "File content: $mail_result"
else
    echo -e "${RED}✗ Cross-client file sharing failed${NC}"
fi

# Cleanup
ssh -i ssh_keys/project_key -o StrictHostKeyChecking=no ansible@10.0.0.20 "rm -f /mnt/nfs/$test_file"

echo
echo "4. NETWORK CONNECTIVITY TEST"
echo "============================"
echo "Testing network connectivity to NFS server..."

run_remote "10.0.0.20" "showmount -e 10.0.0.40" "NFS exports from NextCloud"
run_remote "10.0.0.30" "showmount -e 10.0.0.40" "NFS exports from Mail Server"

echo
echo "=== NFS TESTING COMPLETED ==="
echo "Review the results above to identify any issues."
echo "Expected results:"
echo "- All services should be active"
echo "- NFS mounts should be visible in mount output"
echo "- File operations should succeed"
echo "- Cross-client sharing should work"
