#!/bin/bash
# Postfix Mail Server Testing Script for Infrastructure Project
# Run this script to test Postfix configuration and functionality

echo "=== POSTFIX MAIL SERVER TESTING ==="
echo "Testing mail server configuration on 10.0.0.30"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MAIL_SERVER="10.0.0.30"
SSH_KEY="ssh_keys/project_key"

# Function to run command on mail server
run_mail_cmd() {
    local command=$1
    local description=$2

    echo -e "${YELLOW}Testing: $description${NC}"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "$command"
    local result=$?
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✓ SUCCESS${NC}"
    else
        echo -e "${RED}✗ FAILED (exit code: $result)${NC}"
    fi
    echo
    return $result
}

# Function to test mail sending
test_mail_send() {
    local recipient=$1
    local subject=$2
    local body=$3

    echo -e "${YELLOW}Testing: Sending test mail to $recipient${NC}"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "echo '$body' | mail -s '$subject' $recipient"
    local result=$?
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}✓ Mail command executed successfully${NC}"
    else
        echo -e "${RED}✗ Mail command failed${NC}"
    fi
    echo
}

echo "1. POSTFIX SERVICE STATUS"
echo "========================"

# Test service status
run_mail_cmd "systemctl is-active postfix" "Postfix service active status"
run_mail_cmd "systemctl is-enabled postfix" "Postfix service enabled status"

# Detailed service status
echo -e "${BLUE}Detailed service status:${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "systemctl status postfix --no-pager -l"
echo

echo "2. POSTFIX CONFIGURATION ANALYSIS"
echo "================================="

# Check key configuration parameters
echo -e "${BLUE}Current Postfix configuration:${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "postconf -n"
echo

# Check for configuration issues
echo -e "${YELLOW}Configuration Analysis:${NC}"

# Check hostname configuration
hostname_result=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "postconf myhostname")
echo "Hostname setting: $hostname_result"

if [[ $hostname_result == *"ubuntu"* ]]; then
    echo -e "${RED}⚠ WARNING: myhostname is set to 'ubuntu' - should be 'mail-server.example.local'${NC}"
else
    echo -e "${GREEN}✓ Hostname configuration looks good${NC}"
fi

# Check mydestination
mydest_result=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "postconf mydestination")
echo "Destination setting: $mydest_result"

# Check mynetworks
mynet_result=$(ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "postconf mynetworks")
echo "Network setting: $mynet_result"

if [[ $mynet_result == *"10.0.0.0/24"* ]]; then
    echo -e "${GREEN}✓ Local network properly configured${NC}"
else
    echo -e "${YELLOW}⚠ INFO: Consider adding 10.0.0.0/24 to mynetworks for local delivery${NC}"
fi

echo

echo "3. MAIL SYSTEM COMPONENTS"
echo "========================"

# Check if mail command is available
run_mail_cmd "which mail" "Mail command availability"
run_mail_cmd "which sendmail" "Sendmail command availability"

# Check aliases
run_mail_cmd "ls -la /etc/aliases*" "Alias files"

# Check mail directories
run_mail_cmd "ls -la /var/mail/" "Mail spool directory"
run_mail_cmd "ls -la /var/log/mail*" "Mail log files"

echo "4. NETWORK CONNECTIVITY"
echo "======================="

# Test SMTP port
run_mail_cmd "netstat -tlnp | grep :25" "SMTP port (25) listening"

# Test from other servers
echo -e "${YELLOW}Testing SMTP connectivity from other servers:${NC}"

# From NextCloud server
echo "From NextCloud (10.0.0.20):"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@10.0.0.20 "telnet 10.0.0.30 25 < /dev/null" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SMTP connection successful${NC}"
else
    echo -e "${RED}✗ SMTP connection failed${NC}"
fi

# From Database server
echo "From Database (10.0.0.40):"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@10.0.0.40 "telnet 10.0.0.30 25 < /dev/null" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SMTP connection successful${NC}"
else
    echo -e "${RED}✗ SMTP connection failed${NC}"
fi
echo

echo "5. DNS RESOLUTION TEST"
echo "====================="

# Test DNS resolution for mail server
run_mail_cmd "nslookup mail-server.example.local 10.0.0.10" "DNS resolution for mail server"
run_mail_cmd "dig @10.0.0.10 mail-server.example.local" "DNS dig test"

echo "6. MAIL DELIVERY TEST"
echo "===================="

# Install mailutils if not present
echo -e "${YELLOW}Ensuring mail utilities are installed...${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "sudo apt-get update && sudo apt-get install -y mailutils" 2>/dev/null

# Test local mail delivery
test_mail_send "ansible@localhost" "Test Mail - Local Delivery" "This is a test mail for local delivery at $(date)"

# Test mail to other servers (if configured)
test_mail_send "test@example.local" "Test Mail - Domain Delivery" "This is a test mail for domain delivery at $(date)"

# Check mail queue after sending
echo -e "${YELLOW}Checking mail queue after test:${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "mailq"
echo

echo "7. LOG ANALYSIS"
echo "==============="

echo -e "${YELLOW}Recent mail log entries:${NC}"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ansible@$MAIL_SERVER "sudo tail -20 /var/log/mail.log 2>/dev/null || sudo tail -20 /var/log/syslog | grep postfix"
echo

echo "8. CONFIGURATION RECOMMENDATIONS"
echo "==============================="

echo -e "${BLUE}Based on the test results, here are recommendations:${NC}"
echo
echo "1. Fix hostname configuration:"
echo "   sudo postconf -e 'myhostname = mail.infra.prog'"
echo
echo "2. Add local network to mynetworks:"
echo "   sudo postconf -e 'mynetworks = 127.0.0.0/8 10.0.0.0/24 [::ffff:127.0.0.0]/104 [::1]/128'"
echo
echo "3. Configure proper mydestination:"
echo "   sudo postconf -e 'mydestination = \$myhostname, mail.infra.prog, infra.prog, localhost.localdomain, localhost'"
echo
echo "4. Reload Postfix after changes:"
echo "   sudo systemctl reload postfix"
echo

echo "=== POSTFIX TESTING COMPLETED ==="
echo "Review the results above and apply recommended configuration changes."
