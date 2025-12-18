#!/bin/bash

################################################################################
#                                                                              #
#     USB Sync Manager - React Frontend Development & Deployment              #
#                                                                              #
#     Usage: ./frontend.sh [COMMAND] [SUBCOMMAND]                             #
#                                                                              #
#     LOCAL:                                                                  #
#     - dev:    Development mode with hot reload                              #
#     - build:  Production build                                              #
#     - start:  Serve production build locally                                #
#     - stop:   Kill development server                                       #
#                                                                              #
#     DOCKER/PODMAN:                                                          #
#     - docker build / run / stop / clean                                     #
#     - podman build / run / stop / clean                                     #
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
PROJECT_NAME="usb-sync-manager-frontend"
NODE_VERSION_MIN="16"
PORT="${REACT_PORT:-3000}"
API_URL="${REACT_APP_API_URL:-http://localhost:5000}"
NODE_MODULES_DIR="node_modules"
PACKAGE_JSON="package.json"
DOCKERFILE_FRONTEND="Dockerfile.frontend"
DOCKER_PORT="${DOCKER_PORT:-3000}"

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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

show_help() {
    cat << 'HELP'

USB Sync Manager - React Frontend Development & Deployment

USAGE:
    ./frontend.sh [COMMAND] [SUBCOMMAND]

LOCAL COMMANDS:
    dev         Start development server (hot reload)
    build       Build for production
    start       Serve production build locally
    stop        Kill development server
    clean       Clean node_modules and build
    status      Show frontend status
    
DOCKER DEPLOYMENT:
    docker build    Build Docker image
    docker run      Start Docker container
    docker stop     Stop Docker container
    docker clean    Remove Docker container and image
    
PODMAN DEPLOYMENT:
    podman build    Build Podman image
    podman run      Start Podman container
    podman stop     Stop Podman container
    podman clean    Remove Podman container and image

    help        Show this help message

EXAMPLES:

    ═══ LOCAL DEVELOPMENT ═══
    
    # Terminal 1: Start backend
    ./run.sh local start

    # Terminal 2: Start frontend with hot reload
    ./frontend.sh dev
    # Open: http://localhost:3000

    # Stop development server
    ./frontend.sh stop

    ═══ LOCAL PRODUCTION ═══
    
    # Build production version
    ./frontend.sh build

    # Serve it locally
    ./frontend.sh start
    # Open: http://localhost:3000

    ═══ DOCKER DEPLOYMENT TO NAS ═══
    
    # Build Docker image
    ./frontend.sh docker build

    # Start Docker container
    ./frontend.sh docker run
    # Open: http://nas-ip:3000

    # Stop container
    ./frontend.sh docker stop

    # Clean up
    ./frontend.sh docker clean

    ═══ PODMAN DEPLOYMENT TO NAS ═══
    
    # Build Podman image
    ./frontend.sh podman build

    # Start Podman container
    ./frontend.sh podman run
    # Open: http://nas-ip:3000

CONFIGURATION:

    Change local port:
       REACT_PORT=8080 ./frontend.sh dev

    Change API URL:
       REACT_APP_API_URL=http://nas-ip:5000 ./frontend.sh dev

    Change Docker port:
       DOCKER_PORT=8080 ./frontend.sh docker run

    Both:
       DOCKER_PORT=8080 REACT_APP_API_URL=http://nas-ip:5000 ./frontend.sh docker run

WORKFLOW:

    DEVELOPMENT:
    1. Terminal 1: ./run.sh local start
    2. Terminal 2: ./frontend.sh dev
    3. Edit code → auto-reload in browser
    4. ./frontend.sh stop

    PRODUCTION (Local):
    1. ./frontend.sh build
    2. ./frontend.sh start
    3. Open http://localhost:3000

    PRODUCTION (Docker on NAS):
    1. ./frontend.sh docker build
    2. ./frontend.sh docker run
    3. Open http://nas-ip:3000

HELP
}

################################################################################
# Frontend Setup Functions
################################################################################

check_node() {
    print_header "Checking Node.js Installation"
    
    if ! command -v node &> /dev/null; then
        print_error "Node.js not found"
        echo ""
        echo "Install from: https://nodejs.org/ (v${NODE_VERSION_MIN}+)"
        exit 1
    fi
    
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    
    if [ "$NODE_VERSION" -lt "$NODE_VERSION_MIN" ]; then
        print_error "Node.js version $NODE_VERSION_MIN+ required (you have v${NODE_VERSION})"
        exit 1
    fi
    
    print_success "Node.js $(node -v)"
    print_success "npm $(npm -v)"
}

install_dependencies() {
    if [ ! -d "$NODE_MODULES_DIR" ]; then
        print_info "Installing dependencies..."
        npm install
        print_success "Dependencies installed"
    else
        print_info "Dependencies already installed"
    fi
}

check_env_file() {
    if [ -f .env ]; then
        print_success ".env file found"
        return 0
    else
        print_warning ".env file not found (optional)"
        return 1
    fi
}

################################################################################
# Local Development Functions
################################################################################

dev_server() {
    print_header "Starting Development Server"
    
    check_node
    install_dependencies
    
    # Kill any existing process on same port
    if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port ${PORT} is already in use"
        print_info "Killing existing process..."
        lsof -ti:${PORT} | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
    
    print_info "Starting development server on port ${PORT}..."
    
    # Load environment from .env if exists
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
        print_info "API URL: ${REACT_APP_API_URL}"
    else
        print_info "API URL: ${API_URL}"
    fi
    
    echo ""
    echo -e "${GREEN}Development server started!${NC}"
    echo -e "${GREEN}Open in browser: http://localhost:${PORT}${NC}"
    echo ""
    print_info "Hot reload enabled - changes will auto-refresh"
    print_info "Press Ctrl+C to stop"
    echo ""
    
    # Set environment and start dev server
    export REACT_APP_API_URL="${REACT_APP_API_URL:-$API_URL}"
    npm start
}

build_production() {
    print_header "Building Production Version"
    
    check_node
    install_dependencies
    
    print_info "Building optimized production version..."
    
    # Load environment from .env if exists
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
    fi
    
    export REACT_APP_API_URL="${REACT_APP_API_URL:-$API_URL}"
    npm run build
    
    if [ -d "build" ]; then
        SIZE=$(du -sh build | cut -f1)
        print_success "Production build complete!"
        echo ""
        echo "Build directory: ./build"
        echo "Build size: $SIZE"
        echo ""
        print_info "To serve locally:"
        echo "  npm install -g serve"
        echo "  serve -s build"
        echo ""
        print_info "To deploy to Docker:"
        echo "  ./frontend.sh docker build"
        echo "  ./frontend.sh docker run"
    else
        print_error "Build failed - build directory not created"
        exit 1
    fi
}

start_production() {
    print_header "Starting Production Server"
    
    if [ ! -d "build" ]; then
        print_error "Build directory not found - run './frontend.sh build' first"
        exit 1
    fi
    
    # Check if serve is installed globally
    if ! command -v serve &> /dev/null; then
        print_info "Installing 'serve' globally..."
        npm install -g serve
    fi
    
    print_info "Starting production server on port ${PORT}..."
    print_info "Open: http://localhost:${PORT}"
    echo ""
    
    # Load environment from .env if exists
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
    fi
    
    serve -s build -p ${PORT}
}

stop_server() {
    print_header "Stopping Frontend Server"
    
    if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_info "Killing process on port ${PORT}..."
        lsof -ti:${PORT} | xargs kill -9 2>/dev/null || true
        print_success "Server stopped"
    else
        print_warning "No server running on port ${PORT}"
    fi
}

clean_build() {
    print_header "Cleaning Build Files"
    
    if [ -d "$NODE_MODULES_DIR" ]; then
        print_info "Removing node_modules..."
        rm -rf "$NODE_MODULES_DIR"
    fi
    
    if [ -d "build" ]; then
        print_info "Removing build directory..."
        rm -rf build
    fi
    
    print_success "Clean complete"
}

show_status() {
    print_header "Frontend Status"
    
    echo "Project: $PROJECT_NAME"
    echo "Dev Port: $PORT"
    echo "API URL: $API_URL"
    echo ""
    
    if lsof -Pi :${PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_success "Development server is running on port $PORT"
    else
        print_warning "Development server is not running"
    fi
    
    if [ -d "build" ]; then
        SIZE=$(du -sh build | cut -f1)
        print_success "Production build exists ($SIZE)"
    else
        print_warning "Production build not found"
    fi
    
    if [ -d "$NODE_MODULES_DIR" ]; then
        print_success "Dependencies installed"
    else
        print_warning "Dependencies not installed"
    fi
}

################################################################################
# Docker/Podman Functions
################################################################################

create_dockerfile() {
    print_info "Creating Dockerfile with runtime API URL support..."
    
    cat > "$DOCKERFILE_FRONTEND" << 'EOF'
# Build stage
FROM node:18-alpine as builder

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# IMPORTANT: Don't copy .env or use it during build
# API URL will be set at runtime only
RUN npm run build

# Production stage - Nginx with runtime config
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Remove default nginx config
RUN rm -rf ./* /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy built app from builder
COPY --from=builder /app/build .

# Create entrypoint script
COPY entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]
EOF
    
    print_success "Dockerfile created with runtime config support"
    
    # Create the entrypoint script separately
    print_info "Creating entrypoint.sh..."
    cat > entrypoint.sh << 'SCRIPT'
#!/bin/sh
set -e

# Get API URL from environment or use default
API_URL=${REACT_APP_API_URL:-"http://localhost:5000"}

# Create config.json that frontend can read at runtime
cat > /usr/share/nginx/html/config.json <<JSON
{
  "API_URL": "$API_URL"
}
JSON

echo "✓ Frontend started"
echo "✓ API URL: $API_URL"
echo "✓ Config file created at /config.json"

# Start nginx
exec nginx -g 'daemon off;'
SCRIPT
    
    chmod +x entrypoint.sh
    print_success "entrypoint.sh created"
}

create_nginx_config() {
    print_info "Creating nginx config with config.json support..."
    
    cat > nginx.conf << 'EOF'
server {
    listen 3000;
    server_name _;
    
    root /usr/share/nginx/html;
    index index.html;
    
    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss;
    
    # Serve config.json with proper headers
    location = /config.json {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
        add_header Content-Type "application/json";
    }
    
    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # React router - serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF
    
    print_success "nginx config created"
}

container_build() {
    local RUNTIME=$1
    print_header "Building $RUNTIME Image"
    
    # Build production version
    if [ ! -d "build" ]; then
        print_info "Production build not found, building..."
        build_production
    fi
    
    # Create Docker config files if not exists
    if [ ! -f "$DOCKERFILE_FRONTEND" ]; then
        create_dockerfile
    fi
    
    if [ ! -f "nginx.conf" ]; then
        create_nginx_config
    fi
    
    print_info "Building image: ${PROJECT_NAME}:latest"
    
    $RUNTIME build -t ${PROJECT_NAME}:latest -f ${DOCKERFILE_FRONTEND} .
    
    if [ $? -eq 0 ]; then
        print_success "Image built successfully"
        echo ""
        print_info "Next: ./frontend.sh $RUNTIME run"
    else
        print_error "Build failed"
        exit 1
    fi
}

container_run() {
    local RUNTIME=$1
    print_header "Starting $RUNTIME Container"
    
    # Check if container running
    if $RUNTIME ps --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        print_info "Container already running"
        print_info "Dashboard: http://localhost:${DOCKER_PORT}"
        return
    fi
    
    # Remove stopped container if exists
    if $RUNTIME ps -a --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        print_info "Removing stopped container..."
        $RUNTIME rm ${PROJECT_NAME}
    fi
    
    # Check if image exists
    if ! $RUNTIME images --format="{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "${PROJECT_NAME}:latest"; then
        print_info "Image not found, building first..."
        container_build $RUNTIME
    fi
    
    print_info "Starting container on port ${DOCKER_PORT}..."
    
    # Load environment from .env file
    local ENV_ARGS=""
    if [ -f .env ]; then
        set -a
        source .env
        set +a
        print_success "Loaded .env file"
        ENV_ARGS="-e REACT_APP_API_URL=\"${REACT_APP_API_URL:-http://localhost:5000}\""
    else
        ENV_ARGS="-e REACT_APP_API_URL=\"${API_URL}\""
    fi
    
    # Run container
    eval "$RUNTIME run -d \
        --name ${PROJECT_NAME} \
        -p ${DOCKER_PORT}:3000 \
        $ENV_ARGS \
        --restart unless-stopped \
        ${PROJECT_NAME}:latest"
    
    if [ $? -eq 0 ]; then
        print_success "Container started"
        sleep 2
        
        # Check if running
        if $RUNTIME ps --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
            print_success "Frontend is ready!"
            echo ""
            echo -e "${GREEN}Open in browser: http://localhost:${DOCKER_PORT}${NC}"
            echo ""
            print_info "Useful commands:"
            echo "  View logs: $RUNTIME logs ${PROJECT_NAME}"
            echo "  Stop: ./frontend.sh $RUNTIME stop"
            echo "  Clean: ./frontend.sh $RUNTIME clean"
        else
            print_error "Container failed to start"
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
    
    if $RUNTIME ps --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        print_info "Stopping container..."
        $RUNTIME stop ${PROJECT_NAME}
        print_success "Container stopped"
    else
        print_warning "Container is not running"
    fi
}

container_clean() {
    local RUNTIME=$1
    print_header "Cleaning $RUNTIME Resources"
    
    # Stop if running
    if $RUNTIME ps --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        print_info "Stopping container..."
        $RUNTIME stop ${PROJECT_NAME}
    fi
    
    # Remove container if exists
    if $RUNTIME ps -a --format="{{.Names}}" 2>/dev/null | grep -q "^${PROJECT_NAME}$"; then
        print_info "Removing container..."
        $RUNTIME rm ${PROJECT_NAME}
    fi
    
    # Remove image if exists
    if $RUNTIME images --format="{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -q "${PROJECT_NAME}:latest"; then
        print_info "Removing image..."
        $RUNTIME rmi ${PROJECT_NAME}:latest
    fi
    
    # Remove build folder
    if [ -d "build" ]; then
        print_info "Removing build folder..."
        rm -rf build
    fi
    
    # Remove Dockerfile
    if [ -f "$DOCKERFILE_FRONTEND" ]; then
        print_info "Removing Dockerfile..."
        rm -f "$DOCKERFILE_FRONTEND"
    fi
    
    # Remove nginx config
    if [ -f "nginx.conf" ]; then
        print_info "Removing nginx.conf..."
        rm -f nginx.conf
    fi
    
    print_success "Cleanup complete"
}

################################################################################
# Main Script
################################################################################

COMMAND="${1:-dev}"
SUBCOMMAND="${2:-}"

case "$COMMAND" in
    dev)
        dev_server
        ;;
    
    build)
        build_production
        ;;
    
    start)
        start_production
        ;;
    
    stop)
        stop_server
        ;;
    
    clean)
        clean_build
        ;;
    
    status)
        show_status
        ;;
    
    docker)
        if [ -z "$SUBCOMMAND" ]; then
            print_error "Subcommand required: build, run, stop, clean"
            exit 1
        fi
        
        case "$SUBCOMMAND" in
            build)
                container_build "docker"
                ;;
            run)
                container_run "docker"
                ;;
            stop)
                container_stop "docker"
                ;;
            clean)
                container_clean "docker"
                ;;
            *)
                print_error "Unknown docker subcommand: $SUBCOMMAND"
                exit 1
                ;;
        esac
        ;;
    
    podman)
        if [ -z "$SUBCOMMAND" ]; then
            print_error "Subcommand required: build, run, stop, clean"
            exit 1
        fi
        
        case "$SUBCOMMAND" in
            build)
                container_build "podman"
                ;;
            run)
                container_run "podman"
                ;;
            stop)
                container_stop "podman"
                ;;
            clean)
                container_clean "podman"
                ;;
            *)
                print_error "Unknown podman subcommand: $SUBCOMMAND"
                exit 1
                ;;
        esac
        ;;
    
    help|-h|--help)
        show_help
        ;;
    
    *)
        print_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac

exit 0