#!/bin/bash

echo "=========================================="
echo "USB Sync Manager - API Connectivity Diagnostic"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

echo "Step 1: Check Docker Containers"
echo "=================================="
echo ""

if ! command -v docker &> /dev/null; then
    print_error "Docker not found"
    exit 1
fi

print_success "Docker found"
echo ""

echo "Running containers:"
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" | grep usb-sync-manager

echo ""
echo "Step 2: Check Backend Container"
echo "================================"
echo ""

if docker ps | grep -q "usb-sync-manager-backend"; then
    print_success "Backend container is running"
    
    # Get backend port
    BACKEND_PORT=$(docker port usb-sync-manager-backend 2>/dev/null | grep "5000/tcp" | cut -d: -f2 | head -1)
    if [ -z "$BACKEND_PORT" ]; then
        BACKEND_PORT="5000"
    fi
    print_info "Backend port: $BACKEND_PORT"
    
    # Get backend IP/hostname
    echo ""
    echo "Backend network info:"
    docker inspect usb-sync-manager-backend --format='{{range .NetworkSettings.Networks}}Network: {{.IPAddress}}{{end}}'
    echo ""
    
else
    print_error "Backend container is NOT running"
    echo ""
    print_warning "Start backend with: docker run usb-sync-manager-backend:latest"
    exit 1
fi

echo ""
echo "Step 3: Test Backend API Directly"
echo "=================================="
echo ""

# Test localhost
echo "Testing: http://localhost:${BACKEND_PORT}/health"
if curl -s http://localhost:${BACKEND_PORT}/health > /dev/null 2>&1; then
    print_success "Backend API responds on localhost:${BACKEND_PORT}"
else
    print_warning "Backend API NOT responding on localhost:${BACKEND_PORT}"
fi

echo ""

# Test 127.0.0.1
echo "Testing: http://127.0.0.1:${BACKEND_PORT}/health"
if curl -s http://127.0.0.1:${BACKEND_PORT}/health > /dev/null 2>&1; then
    print_success "Backend API responds on 127.0.0.1:${BACKEND_PORT}"
else
    print_warning "Backend API NOT responding on 127.0.0.1:${BACKEND_PORT}"
fi

echo ""

# Test actual response
echo "Backend API response:"
curl -s http://localhost:${BACKEND_PORT}/health | head -20
echo ""

echo ""
echo "Step 4: Check Frontend Container"
echo "================================="
echo ""

if docker ps | grep -q "usb-sync-manager-frontend"; then
    print_success "Frontend container is running"
    
    # Get frontend environment
    FRONTEND_API_URL=$(docker inspect usb-sync-manager-frontend --format='{{range .Config.Env}}{{if contains . "REACT_APP_API_URL"}}{{.}}{{end}}{{end}}' 2>/dev/null)
    
    if [ -n "$FRONTEND_API_URL" ]; then
        print_info "Frontend environment: $FRONTEND_API_URL"
    else
        print_warning "REACT_APP_API_URL not set in frontend!"
    fi
    
else
    print_error "Frontend container is NOT running"
fi

echo ""
echo "Step 5: Check Docker Network"
echo "============================"
echo ""

if docker network inspect usb-sync-network > /dev/null 2>&1; then
    print_success "Network 'usb-sync-network' exists"
    echo ""
    echo "Connected containers:"
    docker network inspect usb-sync-network --format='{{range .Containers}}Name: {{.Name}}, IP: {{.IPv4Address}}{{end}}'
else
    print_warning "Network 'usb-sync-network' does not exist"
    echo ""
    echo "Create it with:"
    echo "  docker network create usb-sync-network"
fi

echo ""
echo "Step 6: Test Frontend Container Network"
echo "========================================"
echo ""

if docker ps | grep -q "usb-sync-manager-frontend"; then
    echo "Testing backend connectivity FROM frontend container:"
    echo ""
    
    # Test from inside frontend container
    RESULT=$(docker exec usb-sync-manager-frontend sh -c 'wget -q -O - http://usb-sync-manager-backend:5000/api/health 2>&1' || echo "FAILED")
    
    if echo "$RESULT" | grep -q "FAILED\|Connection refused"; then
        print_error "Frontend cannot reach backend on docker network"
        echo ""
        print_warning "This is the problem!"
    else
        print_success "Frontend can reach backend on docker network"
        echo "Response: $(echo $RESULT | head -100)"
    fi
fi

echo ""
echo "Step 7: Browser Console Simulation"
echo "=================================="
echo ""

echo "To check what frontend sees in browser:"
echo "  1. Open http://localhost:3000 in browser"
echo "  2. Press F12 to open Developer Tools"
echo "  3. Click Console tab"
echo "  4. Paste this and press Enter:"
echo ""
echo "fetch('http://localhost:5000/api/schedules')"
echo "  .then(r => r.json())"
echo "  .then(d => console.log('SUCCESS:', d))"
echo "  .catch(e => console.error('ERROR:', e))"
echo ""

echo ""
echo "Step 8: Quick Fixes to Try"
echo "=========================="
echo ""

echo "If frontend can't reach backend:"
echo ""
echo "1. Stop and remove containers:"
echo "   docker stop usb-sync-manager-frontend usb-sync-manager-backend"
echo "   docker rm usb-sync-manager-frontend usb-sync-manager-backend"
echo ""

echo "2. Recreate network:"
echo "   docker network rm usb-sync-network 2>/dev/null || true"
echo "   docker network create usb-sync-network"
echo ""

echo "3. Restart backend first:"
echo "   docker run -d --name usb-sync-manager-backend --network usb-sync-network -p 5000:5000 -v /media:/media -v /mnt:/mnt usb-sync-manager-backend:latest"
echo ""

echo "4. Wait 3 seconds for backend to start:"
echo "   sleep 3"
echo ""

echo "5. Then restart frontend:"
echo "   docker run -d --name usb-sync-manager-frontend --network usb-sync-network -p 3000:3000 -e REACT_APP_API_URL=http://usb-sync-manager-backend:5000 usb-sync-manager-frontend:latest"
echo ""

echo "=========================================="
print_info "Diagnostics complete"
echo "=========================================="