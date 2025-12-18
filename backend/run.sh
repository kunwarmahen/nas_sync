#!/bin/bash

################################################################################
#                                                                              #
#     USB Sync Manager - Run Locally or in Docker/Podman                      #
#                                                                              #
#     Usage: ./run.sh [local|docker|podman|help]                              #
#                                                                              #
#     - local:  Run natively on your machine (requires Python 3.11+)          #
#     - docker: Run in Docker container                                       #
#     - podman:  Run in Podman container                                      #
#                                                                              #
################################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="usb-sync-manager"
PORT="5000"
VENV_DIR=".venv"
API_URL="http://localhost:${PORT}"

################################################################################
# Helper Functions
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
        print_info "Creating .env file..."
        cat > .env << 'EOF'
# Email Configuration
SENDER_EMAIL=your-email@gmail.com
SENDER_PASSWORD=your-16-char-app-password

# For custom SMTP, uncomment and set:
# SMTP_SERVER=mail.your-domain.com
# SMTP_PORT=587
EOF
        print_success "Created .env file - please edit with your credentials"
        return 1
    fi
    return 0
}

show_help() {
    cat << 'HELP'

USB Sync Manager - Run Locally or in Containers

USAGE:
    ./run.sh [MODE] [COMMAND]

MODES:
    local       Run natively on your machine (Python venv)
    docker      Run in Docker container
    podman      Run in Podman container
    help        Show this help message

COMMANDS (with local mode):
    start       Start the service
    stop        Stop the service
    logs        Show service logs
    restart     Restart the service
    status      Show service status
    clean       Remove venv and logs

COMMANDS (with docker/podman):
    build       Build container image
    run         Run container
    stop        Stop container
    logs        Show container logs
    shell       Open shell in container
    clean       Remove container and volumes

EXAMPLES:

    # Run locally (simplest for development)
    ./run.sh local start
    ./run.sh local logs          # In another terminal
    ./run.sh local stop

    # Run in Docker
    ./run.sh docker build
    ./run.sh docker run
    ./run.sh docker logs

    # Run in Podman
    ./run.sh podman build
    ./run.sh podman run
    ./run.sh podman logs

QUICK START (Local):
    ./run.sh local start
    # Open browser: http://localhost:5000
    # Edit .env with your email credentials
    ./run.sh local restart
    ./run.sh local logs

QUICK START (Docker):
    ./run.sh docker build
    ./run.sh docker run
    # Open browser: http://localhost:5000
    # Edit .env with your email credentials
    ./run.sh docker stop
    ./run.sh docker run

REQUIREMENTS (Local):
    - Python 3.11+
    - pip
    - Git
    - rsync

REQUIREMENTS (Docker/Podman):
    - Docker or Podman installed
    - ~200 MB disk space for image

ENVIRONMENT:
    Create .env file with:
        SENDER_EMAIL=your-email@gmail.com
        SENDER_PASSWORD=your-16-char-app-password

    For Gmail:
        1. Enable 2-Factor Authentication
        2. Generate App Password: https://myaccount.google.com/apppasswords
        3. Use 16-character password as SENDER_PASSWORD

HELP
}

################################################################################
# Local Mode Functions
################################################################################

local_setup() {
    print_header "Setting Up Local Python Environment"
    
    # Check Python version
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed"
        echo "Install Python 3.11+ and try again"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    print_info "Python version: $PYTHON_VERSION"
    
    # Create virtual environment
    if [ ! -d "$VENV_DIR" ]; then
        print_info "Creating virtual environment..."
        python3 -m venv $VENV_DIR
        print_success "Virtual environment created"
    fi
    
    # Activate venv
    source $VENV_DIR/bin/activate
    
    # Install requirements
    print_info "Installing Python dependencies..."
    pip install --upgrade pip > /dev/null 2>&1
    pip install -r requirements.txt > /dev/null 2>&1
    print_success "Dependencies installed"
    
    print_success "Setup complete"
}

local_start() {
    print_header "Starting USB Sync Manager (Local)"
    
    check_env_file || true
    
    if [ ! -d "$VENV_DIR" ]; then
        local_setup
    fi
    
    # Activate venv
    source $VENV_DIR/bin/activate
    
    # Load environment variables from .env
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
    fi
    
    # Create config directory
    mkdir -p /etc/usb-sync-manager/logs
    
    # Check if already running
    if pgrep -f "usb_sync_backend.py" > /dev/null; then
        print_info "Service is already running"
        print_info "Dashboard: ${API_URL}"
        return
    fi
    
    print_info "Starting service..."
    
    # Run in background
    nohup python3 usb_sync_backend.py > /tmp/usb-sync.log 2>&1 &
    PID=$!
    
    # Wait for service to start
    sleep 2
    
    if ps -p $PID > /dev/null; then
        print_success "Service started (PID: $PID)"
        echo ""
        echo -e "${GREEN}Dashboard available at: ${API_URL}${NC}"
        echo -e "${GREEN}API available at: ${API_URL}/api${NC}"
        echo ""
        print_info "Useful commands:"
        echo "  View logs: ./run.sh local logs"
        echo "  Stop: ./run.sh local stop"
        echo "  Restart: ./run.sh local restart"
        echo ""
    else
        print_error "Failed to start service"
        cat /tmp/usb-sync.log
        exit 1
    fi
}

local_stop() {
    print_header "Stopping USB Sync Manager (Local)"
    
    if pgrep -f "usb_sync_backend.py" > /dev/null; then
        print_info "Stopping service..."
        pkill -f "usb_sync_backend.py"
        sleep 1
        print_success "Service stopped"
    else
        print_info "Service is not running"
    fi
}

local_restart() {
    print_header "Restarting USB Sync Manager (Local)"
    local_stop
    sleep 1
    local_start
}

local_logs() {
    print_header "Service Logs"
    
    if [ -f "/tmp/usb-sync.log" ]; then
        tail -f /tmp/usb-sync.log
    else
        print_error "No logs found"
        print_info "Start the service first: ./run.sh local start"
    fi
}

local_status() {
    print_header "Service Status"
    
    if pgrep -f "usb_sync_backend.py" > /dev/null; then
        print_success "Service is running"
        PID=$(pgrep -f "usb_sync_backend.py" | head -1)
        echo "Process ID: $PID"
        echo "Dashboard: ${API_URL}"
        
        # Check if API is responding
        if curl -s ${API_URL}/health > /dev/null 2>&1; then
            print_success "API is responding"
        else
            print_error "API is not responding"
        fi
    else
        print_error "Service is not running"
    fi
}

local_clean() {
    print_header "Cleaning Up (Local)"
    
    print_info "This will remove virtual environment and logs"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        return
    fi
    
    local_stop || true
    
    print_info "Removing virtual environment..."
    rm -rf $VENV_DIR
    
    print_info "Removing logs..."
    rm -f /tmp/usb-sync.log
    
    print_success "Cleanup complete"
}

################################################################################
# Docker/Podman Mode Functions
################################################################################

container_build() {
    local RUNTIME=$1
    print_header "Building $RUNTIME Image"
    
    if [ ! -f Dockerfile ]; then
        print_error "Dockerfile not found"
        exit 1
    fi
    
    print_info "Building image..."
    $RUNTIME build -t ${PROJECT_NAME}:latest .
    
    if [ $? -eq 0 ]; then
        print_success "Image built successfully"
        $RUNTIME images | grep ${PROJECT_NAME}
    else
        print_error "Build failed"
        exit 1
    fi
}

container_run() {
    local RUNTIME=$1
    print_header "Starting $RUNTIME Container"
    
    check_env_file || true
    
    # Check if container running
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
        print_info "Container already running"
        print_info "Dashboard: ${API_URL}"
        return
    fi
    
    # Remove stopped container if exists
    if $RUNTIME ps -a --format="{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
        print_info "Removing stopped container..."
        $RUNTIME rm ${PROJECT_NAME}
    fi
    
    # Check if image exists
    if ! $RUNTIME images --format="{{.Repository}}:{{.Tag}}" | grep -q "${PROJECT_NAME}:latest"; then
        print_info "Image not found, building first..."
        container_build $RUNTIME
    fi
    
    print_info "Starting container..."
    
    # Load environment from .env file
    local ENV_ARGS=""
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
        ENV_ARGS="-e SENDER_EMAIL=\"${SENDER_EMAIL}\" -e SENDER_PASSWORD=\"${SENDER_PASSWORD}\""
        [ -n "${SMTP_SERVER}" ] && ENV_ARGS="$ENV_ARGS -e SMTP_SERVER=\"${SMTP_SERVER}\""
        [ -n "${SMTP_PORT}" ] && ENV_ARGS="$ENV_ARGS -e SMTP_PORT=\"${SMTP_PORT}\""
    else
        print_warning ".env file not found, using environment variables"
    fi
    
    # Get host timezone
    local TZ_FILE="/etc/timezone"
    local HOST_TZ="UTC"
    if [ -f "$TZ_FILE" ]; then
        HOST_TZ=$(cat "$TZ_FILE")
        print_info "Using host timezone: $HOST_TZ"
    elif [ -f "/etc/localtime" ]; then
        # macOS or other systems
        HOST_TZ=$(ls -la /etc/localtime | grep -oE 'zoneinfo/.*' | sed 's|zoneinfo/||')
        print_info "Using host timezone: $HOST_TZ"
    fi
    
    # Run container with timezone
    eval "$RUNTIME run -d \
        --name ${PROJECT_NAME} \
        -p ${PORT}:5000 \
        -v ${PROJECT_NAME}-config:/etc/usb-sync-manager \
        -v /media:/media \
        -v /mnt:/mnt \
        -v /etc/timezone:/etc/timezone:ro \
        -v /etc/localtime:/etc/localtime:ro \
        -e TZ=\"${HOST_TZ}\" \
        $ENV_ARGS \
        -e PYTHONUNBUFFERED=1 \
        --restart unless-stopped \
        ${PROJECT_NAME}:latest"
    
    if [ $? -eq 0 ]; then
        print_success "Container started"
        sleep 2
        
        # Check health
        if curl -s ${API_URL}/health > /dev/null 2>&1; then
            print_success "Service is ready!"
            echo ""
            echo -e "${GREEN}Dashboard available at: ${API_URL}${NC}"
            echo -e "${GREEN}API available at: ${API_URL}/api${NC}"
            echo -e "${GREEN}Timezone: ${HOST_TZ}${NC}"
            echo ""
        else
            print_error "Service failed to start - check logs"
            $RUNTIME logs ${PROJECT_NAME}
            exit 1
        fi
    else
        print_error "Failed to start container"
        exit 1
    fi
}

container_stop() {
    local RUNTIME=$1
    print_header "Stopping $RUNTIME Container"
    
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
        print_info "Stopping container..."
        $RUNTIME stop ${PROJECT_NAME}
        print_success "Container stopped"
    else
        print_info "Container is not running"
    fi
}

container_logs() {
    local RUNTIME=$1
    print_header "Container Logs"
    
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
        print_info "Showing logs (press Ctrl+C to stop)"
        echo ""
        $RUNTIME logs -f ${PROJECT_NAME}
    else
        print_error "Container is not running"
        print_info "Recent logs:"
        $RUNTIME logs ${PROJECT_NAME} 2>/dev/null || echo "No logs available"
    fi
}

container_shell() {
    local RUNTIME=$1
    print_header "Container Shell"
    
    if $RUNTIME ps --format="{{.Names}}" | grep -q "^${PROJECT_NAME}$"; then
        $RUNTIME exec -it ${PROJECT_NAME} bash
    else
        print_error "Container is not running"
    fi
}

container_clean() {
    local RUNTIME=$1
    print_header "Cleaning Up ($RUNTIME)"
    
    print_info "Choose cleanup type:"
    echo "  1) Clean container & image only (keep schedules)"
    echo "  2) Full cleanup (remove everything including schedules)"
    read -p "Choose (1 or 2): " -n 1 -r CHOICE
    echo
    
    container_stop $RUNTIME || true
    
    print_info "Removing container..."
    $RUNTIME rm ${PROJECT_NAME} 2>/dev/null || true
    
    print_info "Removing image..."
    $RUNTIME rmi ${PROJECT_NAME}:latest 2>/dev/null || true
    
    if [[ $CHOICE =~ ^[2]$ ]]; then
        print_info "Removing volume (this will delete all schedules)..."
        $RUNTIME volume rm ${PROJECT_NAME}-config 2>/dev/null || true
        print_success "Full cleanup complete"
    else
        print_success "Cleanup complete (schedules preserved)"
    fi
}

################################################################################
# Main Script
################################################################################

MODE="${1:-help}"
COMMAND="${2:-help}"

case "$MODE" in
    local)
        case "$COMMAND" in
            start)
                local_start
                ;;
            stop)
                local_stop
                ;;
            restart)
                local_restart
                ;;
            logs)
                local_logs
                ;;
            status)
                local_status
                ;;
            clean)
                local_clean
                ;;
            *)
                echo "Usage: ./run.sh local [start|stop|restart|logs|status|clean]"
                exit 1
                ;;
        esac
        ;;
    
    docker)
        if ! command -v docker &> /dev/null; then
            print_error "Docker is not installed"
            exit 1
        fi
        
        case "$COMMAND" in
            build)
                container_build docker
                ;;
            run)
                container_run docker
                ;;
            stop)
                container_stop docker
                ;;
            logs)
                container_logs docker
                ;;
            shell)
                container_shell docker
                ;;
            clean)
                container_clean docker
                ;;
            *)
                echo "Usage: ./run.sh docker [build|run|stop|logs|shell|clean]"
                exit 1
                ;;
        esac
        ;;
    
    podman)
        if ! command -v podman &> /dev/null; then
            print_error "Podman is not installed"
            exit 1
        fi
        
        case "$COMMAND" in
            build)
                container_build podman
                ;;
            run)
                container_run podman
                ;;
            stop)
                container_stop podman
                ;;
            logs)
                container_logs podman
                ;;
            shell)
                container_shell podman
                ;;
            clean)
                container_clean podman
                ;;
            *)
                echo "Usage: ./run.sh podman [build|run|stop|logs|shell|clean]"
                exit 1
                ;;
        esac
        ;;
    
    help|-h|--help)
        show_help
        ;;
    
    *)
        print_error "Unknown mode: $MODE"
        echo ""
        show_help
        exit 1
        ;;
esac

exit 0