#!/bin/bash

################################################################################
#                                                                              #
#     USB Sync Manager - Local Docker/Podman Test Script                      #
#                                                                              #
#     Usage: ./local-test.sh [build|run|stop|logs|clean|test-email]           #
#                                                                              #
################################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="usb-sync-manager"
IMAGE_NAME="usb-sync-manager"
IMAGE_TAG="latest"
CONTAINER_NAME="${PROJECT_NAME}"
PORT="5000"
API_URL="http://localhost:${PORT}"

# Detect Docker or Podman
RUNTIME=""
if command -v docker &> /dev/null; then
    RUNTIME="docker"
elif command -v podman &> /dev/null; then
    RUNTIME="podman"
else
    echo -e "${RED}Error: Neither Docker nor Podman is installed${NC}"
    exit 1
fi

echo -e "${BLUE}Using: ${RUNTIME}${NC}"

################################################################################
# Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_env_file() {
    if [ ! -f .env ]; then
        print_error ".env file not found"
        echo -e "${YELLOW}Creating .env file...${NC}"
        cat > .env << 'EOF'
# Gmail Configuration
SENDER_EMAIL=your-email@gmail.com
SENDER_PASSWORD=your-16-char-app-password

# For custom SMTP, uncomment and configure:
# SMTP_SERVER=mail.your-domain.com
# SMTP_PORT=587
# SENDER_EMAIL=noreply@your-domain.com
# SENDER_PASSWORD=your-password
EOF
        print_info "Created .env file - please edit with your email credentials"
        print_info "Gmail app password: https://myaccount.google.com/apppasswords"
        return 1
    fi
    return 0
}

build_image() {
    print_header "Building Docker Image"
    
    if [ ! -f Dockerfile ]; then
        print_error "Dockerfile not found in current directory"
        exit 1
    fi
    
    print_info "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
    $RUNTIME build -t ${IMAGE_NAME}:${IMAGE_TAG} .
    
    if [ $? -eq 0 ]; then
        print_success "Image built successfully"
        $RUNTIME images | grep ${IMAGE_NAME}
    else
        print_error "Build failed"
        exit 1
    fi
}

run_container() {
    print_header "Starting Container"
    
    if [ -z "$RUNTIME" ]; then
        print_error "Runtime not detected"
        exit 1
    fi
    
    # Check if container already running
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Container already running"
        print_info "Access dashboard at: ${API_URL}"
        return
    fi
    
    # Check if stopped container exists
    if $RUNTIME ps -a --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Removing stopped container..."
        $RUNTIME rm ${CONTAINER_NAME}
    fi
    
    print_info "Starting ${CONTAINER_NAME}..."
    
    # Load environment variables
    set -a
    source .env 2>/dev/null || true
    set +a
    
    $RUNTIME run -d \
        --name ${CONTAINER_NAME} \
        -p ${PORT}:5000 \
        -v ${CONTAINER_NAME}-config:/etc/usb-sync-manager \
        -v /media:/media:ro \
        -v /mnt:/mnt:ro \
        -e SENDER_EMAIL="${SENDER_EMAIL}" \
        -e SENDER_PASSWORD="${SENDER_PASSWORD}" \
        -e SMTP_SERVER="${SMTP_SERVER:-smtp.gmail.com}" \
        -e SMTP_PORT="${SMTP_PORT:-587}" \
        -e PYTHONUNBUFFERED=1 \
        --restart unless-stopped \
        ${IMAGE_NAME}:${IMAGE_TAG}
    
    if [ $? -eq 0 ]; then
        print_success "Container started"
        sleep 2
        print_info "Waiting for service to be ready..."
        sleep 3
        
        # Check health
        if curl -s ${API_URL}/health > /dev/null 2>&1; then
            print_success "Service is ready!"
            echo ""
            echo -e "${GREEN}Dashboard available at: ${API_URL}${NC}"
            echo -e "${GREEN}API available at: ${API_URL}/api${NC}"
            echo ""
            print_info "Useful commands:"
            echo "  View logs: $RUNTIME logs -f ${CONTAINER_NAME}"
            echo "  Stop: $RUNTIME stop ${CONTAINER_NAME}"
            echo "  Remove: $RUNTIME rm ${CONTAINER_NAME}"
            echo ""
        else
            print_error "Service failed to start - check logs"
            $RUNTIME logs ${CONTAINER_NAME}
            exit 1
        fi
    else
        print_error "Failed to start container"
        exit 1
    fi
}

stop_container() {
    print_header "Stopping Container"
    
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Stopping ${CONTAINER_NAME}..."
        $RUNTIME stop ${CONTAINER_NAME}
        print_success "Container stopped"
    else
        print_info "Container is not running"
    fi
}

remove_container() {
    print_header "Removing Container"
    
    if $RUNTIME ps -a --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        if $RUNTIME ps --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_info "Stopping ${CONTAINER_NAME}..."
            $RUNTIME stop ${CONTAINER_NAME}
        fi
        print_info "Removing ${CONTAINER_NAME}..."
        $RUNTIME rm ${CONTAINER_NAME}
        print_success "Container removed"
    else
        print_info "Container does not exist"
    fi
}

view_logs() {
    print_header "Container Logs"
    
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Showing logs for ${CONTAINER_NAME} (press Ctrl+C to stop)"
        echo ""
        $RUNTIME logs -f ${CONTAINER_NAME}
    else
        print_error "Container is not running"
        print_info "Recent logs:"
        $RUNTIME logs ${CONTAINER_NAME} 2>/dev/null || echo "No logs available"
    fi
}

check_status() {
    print_header "Service Status"
    
    echo -e "${BLUE}Container Status:${NC}"
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_success "Container is running"
        $RUNTIME ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        print_error "Container is not running"
    fi
    
    echo ""
    echo -e "${BLUE}Volumes:${NC}"
    $RUNTIME volume ls | grep ${CONTAINER_NAME} || echo "No volumes"
    
    echo ""
    echo -e "${BLUE}API Health:${NC}"
    if curl -s ${API_URL}/health > /dev/null 2>&1; then
        print_success "API is responding"
        curl -s ${API_URL}/health | grep -o '"status":"[^"]*"'
    else
        print_error "API is not responding"
    fi
    
    echo ""
    echo -e "${BLUE}Network:${NC}"
    echo "  Dashboard: ${API_URL}"
    echo "  API: ${API_URL}/api"
}

test_email() {
    print_header "Test Email Notification"
    
    if ! curl -s ${API_URL}/health > /dev/null 2>&1; then
        print_error "Service is not running"
        echo "Start container first: ./local-test.sh run"
        exit 1
    fi
    
    print_info "Send test email to:"
    read -p "Enter email address: " EMAIL
    
    if [ -z "$EMAIL" ]; then
        print_error "Email address required"
        exit 1
    fi
    
    print_info "Sending test email to ${EMAIL}..."
    
    RESPONSE=$(curl -s -X POST ${API_URL}/api/test-email \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"${EMAIL}\"}")
    
    if echo "$RESPONSE" | grep -q "success\|message"; then
        print_success "Test email sent!"
        echo "Response: $RESPONSE"
    else
        print_error "Failed to send email"
        echo "Response: $RESPONSE"
        echo ""
        print_info "Possible issues:"
        echo "  1. Check .env file has correct email credentials"
        echo "  2. Gmail: Use app-specific password, not account password"
        echo "  3. Gmail: Enable 2-Factor Authentication first"
        echo "  4. Check logs: ./local-test.sh logs"
    fi
}

test_api() {
    print_header "API Test"
    
    if ! curl -s ${API_URL}/health > /dev/null 2>&1; then
        print_error "Service is not running"
        exit 1
    fi
    
    print_info "Testing API endpoints..."
    echo ""
    
    print_info "GET /health"
    curl -s ${API_URL}/health | grep -o '"status":"[^"]*"'
    echo ""
    
    print_info "GET /api/schedules"
    curl -s ${API_URL}/api/schedules | head -c 100
    echo -e "\n"
    
    print_info "GET /api/usb-drives"
    curl -s ${API_URL}/api/usb-drives | head -c 100
    echo -e "\n"
    
    print_info "GET /api/system/status"
    curl -s ${API_URL}/api/system/status | head -c 200
    echo -e "\n"
    
    print_success "API endpoints are responding"
}

create_test_schedule() {
    print_header "Create Test Schedule"
    
    if ! curl -s ${API_URL}/health > /dev/null 2>&1; then
        print_error "Service is not running"
        exit 1
    fi
    
    print_info "Creating test schedule..."
    
    SCHEDULE=$(cat <<'SCHEDULE_JSON'
{
    "name": "Test Backup - Daily",
    "usbSource": "/media/usb/test",
    "nasDestination": "/backups/test",
    "frequency": "daily",
    "time": "23:30",
    "notificationEmail": "test@example.com",
    "isActive": true
}
SCHEDULE_JSON
)
    
    RESPONSE=$(curl -s -X POST ${API_URL}/api/schedules \
        -H "Content-Type: application/json" \
        -d "$SCHEDULE")
    
    if echo "$RESPONSE" | grep -q '"id"'; then
        print_success "Schedule created!"
        echo "Response:"
        echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
    else
        print_error "Failed to create schedule"
        echo "Response: $RESPONSE"
    fi
}

clean_up() {
    print_header "Cleanup"
    
    print_info "This will remove container and volumes"
    read -p "Are you sure? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        print_info "Cleanup cancelled"
        return
    fi
    
    print_info "Stopping container..."
    $RUNTIME stop ${CONTAINER_NAME} 2>/dev/null || true
    
    print_info "Removing container..."
    $RUNTIME rm ${CONTAINER_NAME} 2>/dev/null || true
    
    print_info "Removing volume..."
    $RUNTIME volume rm ${CONTAINER_NAME}-config 2>/dev/null || true
    
    print_success "Cleanup complete"
}

open_dashboard() {
    print_header "Opening Dashboard"
    
    if ! curl -s ${API_URL}/health > /dev/null 2>&1; then
        print_error "Service is not running"
        exit 1
    fi
    
    print_info "Opening ${API_URL} in default browser..."
    
    if command -v xdg-open &> /dev/null; then
        xdg-open ${API_URL}
    elif command -v open &> /dev/null; then
        open ${API_URL}
    else
        print_info "Please open in browser: ${API_URL}"
    fi
}

show_help() {
    cat << 'HELP'

USB Sync Manager - Local Test Script

USAGE:
    ./local-test.sh [COMMAND]

COMMANDS:
    build               Build Docker image
    run                 Start container (builds if needed)
    stop                Stop running container
    remove              Stop and remove container
    clean               Remove container and volumes
    logs                View container logs (live)
    status              Show service status
    test-email          Send test email notification
    test-api            Test API endpoints
    create-schedule     Create a test schedule
    open                Open dashboard in browser
    help                Show this help message

EXAMPLES:
    # First time setup
    ./local-test.sh build
    ./local-test.sh run

    # View logs
    ./local-test.sh logs

    # Test email
    ./local-test.sh test-email

    # Stop and cleanup
    ./local-test.sh clean

REQUIREMENTS:
    - Docker or Podman installed
    - .env file with email credentials (auto-created if missing)
    - Port 5000 available locally

ENVIRONMENT:
    Create .env file with:
        SENDER_EMAIL=your-email@gmail.com
        SENDER_PASSWORD=your-16-char-app-password

    For Gmail:
        1. Enable 2-Factor Authentication
        2. Generate App Password: https://myaccount.google.com/apppasswords
        3. Use 16-character password as SENDER_PASSWORD

USEFUL DOCKER/PODMAN COMMANDS:
    # View images
    docker images | grep usb-sync-manager

    # Inspect volume
    docker volume inspect usb-sync-manager-config

    # Backup config
    docker run --rm -v usb-sync-manager-config:/data \\
        -v $(pwd):/backup \\
        alpine tar czf /backup/config-backup.tar.gz -C /data .

    # Direct API calls
    curl http://localhost:5000/api/schedules
    curl http://localhost:5000/api/usb-drives
    curl http://localhost:5000/api/system/status

DASHBOARD:
    Open in browser: http://localhost:5000

For more information, see:
    - README.md (full documentation)
    - QUICKSTART.md (setup guide)

HELP
}

################################################################################
# Main Script
################################################################################

# Check if .env exists
if [ "$1" != "help" ] && [ "$1" != "-h" ] && [ "$1" != "--help" ]; then
    check_env_file
fi

case "${1:-help}" in
    build)
        build_image
        ;;
    run)
        if [ ! -f Dockerfile ]; then
            print_info "Dockerfile not found, building first..."
            build_image
        fi
        # Check if image exists
        if ! $RUNTIME images --format="{{.Repository}}:{{.Tag}}" | grep -q "${IMAGE_NAME}:${IMAGE_TAG}"; then
            print_info "Image not found, building..."
            build_image
        fi
        run_container
        ;;
    stop)
        stop_container
        ;;
    remove)
        remove_container
        ;;
    clean)
        clean_up
        ;;
    logs)
        view_logs
        ;;
    status)
        check_status
        ;;
    test-email)
        test_email
        ;;
    test-api)
        test_api
        ;;
    create-schedule)
        create_test_schedule
        ;;
    open)
        open_dashboard
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac

exit 0
