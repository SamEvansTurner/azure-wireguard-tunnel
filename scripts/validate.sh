#!/bin/bash
# Azure WireGuard Secure Tunnel - Validation Script
# Tests the complete deployment

# Note: set -e is NOT used here - we want all tests to run even if some fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cleanup function for ssh-agent
cleanup() {
    if [ -n "$SSH_AGENT_PID" ]; then
        ssh-agent -k >/dev/null 2>&1
    fi
}
trap cleanup EXIT

# Setup ssh-agent to avoid multiple passphrase prompts
setup_ssh_agent() {
    # Check if key is already in an agent
    if ! ssh-add -l &>/dev/null 2>&1; then
        echo -e "${BLUE}Setting up SSH agent...${NC}"
        eval $(ssh-agent -s) >/dev/null
        # Try to add key, prompt if passphrase needed
        if ! ssh-add 2>/dev/null; then
            echo -e "${YELLOW}SSH key requires passphrase - you'll be prompted once:${NC}"
            ssh-add || {
                echo -e "${RED}Failed to add SSH key to agent${NC}"
                return 1
            }
        fi
        echo -e "${GREEN}✓ SSH agent configured${NC}"
        echo ""
    fi
}

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Deployment Validation Tests                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Check if running from project root
if [ ! -d "terraform" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    exit 1
fi

# Setup ssh-agent for cleaner SSH operations
setup_ssh_agent

cd terraform

# Get deployment info
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ Terraform state not found. Deploy infrastructure first.${NC}"
    exit 1
fi

VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null)
ADMIN_USER=$(terraform output -raw admin_username 2>/dev/null || grep "^admin_username" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
DOMAIN=$(terraform output -raw domain_name 2>/dev/null || grep "^domain_name" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

cd ..

echo -e "${BLUE}Testing:${NC} $DOMAIN ($VM_IP)"
echo ""

# Test 1: SSH Connectivity
echo -n "Test 1: SSH connectivity... "
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $ADMIN_USER@$VM_IP "echo 'OK'" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 2: WireGuard Running
echo -n "Test 2: WireGuard running... "
if ssh $ADMIN_USER@$VM_IP "sudo systemctl is-active wg-quick@wg0" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  NOT RUNNING${NC}"
    ((TESTS_FAILED++))
fi

# Test 3: WireGuard Peer
echo -n "Test 3: WireGuard peer configured... "
if ssh $ADMIN_USER@$VM_IP "sudo wg show wg0 | grep -q peer" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  NO PEER${NC}"
    echo "   Configure home WireGuard client"
    ((TESTS_FAILED++))
fi

# Test 4: Caddy Running
echo -n "Test 4: Caddy running... "
if ssh $ADMIN_USER@$VM_IP "sudo systemctl is-active caddy" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  NOT RUNNING${NC}"
    ((TESTS_FAILED++))
fi

# Test 5: Certificates Present
echo -n "Test 5: SSL certificates present... "
if ssh $ADMIN_USER@$VM_IP "sudo [ -f /etc/caddy/certs/$DOMAIN.crt ] && sudo [ -f /etc/caddy/certs/$DOMAIN.key ]" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  MISSING${NC}"
    echo "   Run: ./scripts/sync-certs.sh"
    ((TESTS_FAILED++))
fi

# Test 6: UFW Active
echo -n "Test 6: UFW firewall active... "
if ssh $ADMIN_USER@$VM_IP "sudo ufw status | grep -q 'Status: active'" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 7: Fail2Ban Running
echo -n "Test 7: Fail2Ban running... "
if ssh $ADMIN_USER@$VM_IP "sudo systemctl is-active fail2ban" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 8: HTTPS Port Open
echo -n "Test 8: HTTPS port 443 accessible... "
if timeout 5 bash -c "</dev/tcp/$VM_IP/443" 2>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 9: DNS Resolution (using public DNS to avoid split-DNS)
# Note: DNS record is for wildcard (*.domain), so we test a subdomain
echo -n "Test 9: DNS resolves correctly (public DNS)... "
TEST_DNS="test.$DOMAIN"
RESOLVED_IP=$(dig @1.1.1.1 +short $TEST_DNS A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)
if [ "$RESOLVED_IP" == "$VM_IP" ]; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  MISMATCH${NC}"
    echo "   Public DNS ($TEST_DNS): $RESOLVED_IP, Expected: $VM_IP"
    ((TESTS_FAILED++))
fi

# Test 10: HTTPS Response (bypassing local DNS)
# Note: Tests undefined subdomain - 403 response proves HTTPS/SSL/Caddy all working
echo -n "Test 10: HTTPS endpoint responding (test)... "
TEST_URL="test.$DOMAIN"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --resolve "$TEST_URL:443:$VM_IP" https://$TEST_URL 2>/dev/null)
if [ "$HTTP_CODE" == "403" ] || [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}✅ PASS${NC} (HTTP $HTTP_CODE)"
    ((TESTS_PASSED++))
elif [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    echo -e "${YELLOW}⚠️  Unexpected: HTTP $HTTP_CODE${NC}"
    ((TESTS_FAILED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

# Test 11: Security Headers (bypassing local DNS, using test subdomain)
# Note: Security headers are only set on wildcard subdomains, not base domain
echo -n "Test 11: Security headers present (test)... "
HEADERS=$(curl -sI --resolve "$TEST_URL:443:$VM_IP" https://$TEST_URL 2>/dev/null)
if echo "$HEADERS" | grep -qi "Strict-Transport-Security"; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}⚠️  MISSING${NC}"
    ((TESTS_FAILED++))
fi

# Test 12: Password Auth Disabled
echo -n "Test 12: SSH password auth disabled... "
if ssh $ADMIN_USER@$VM_IP "sudo grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config.d/99-hardening.conf" &>/dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}❌ FAIL${NC}"
    ((TESTS_FAILED++))
fi

echo ""
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Test Results${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "  Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      ✅ All Tests Passed!                          ║${NC}"
    echo -e "${GREEN}║      Your tunnel is fully operational!             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}🎉 Your secure tunnel is ready to use!${NC}"
    echo ""
    echo "Access your services at:"
    echo -e "  ${GREEN}https://<service>.$DOMAIN${NC}"
    echo ""
    echo "- If Services still aren't working, try checking the caddy logs with: ssh $ADMIN_USER@$VM_IP 'tail -f /var/log/caddy/access.log'"
    exit 0
else
    echo -e "${YELLOW}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║   ⚠️  Some Tests Failed                            ║${NC}"
    echo -e "${YELLOW}║   Review failed tests and troubleshoot             ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Common fixes:${NC}"
    echo ""
    echo "- WireGuard not running: Configure and start WireGuard"
    echo "- Certificates missing: Run ./scripts/sync-certs.sh"
    echo "- Caddy not running: ssh $ADMIN_USER@$VM_IP 'sudo systemctl start caddy'"
    echo "- DNS mismatch: Wait for DNS propagation or run DNS update manually"
    echo ""
    exit 1
fi
