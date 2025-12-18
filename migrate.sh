#!/bin/bash

# USB Sync Manager - Podman to Docker Migration Script
# This script exports images from Podman and imports to Docker (NAS)
# Supports exporting from Podman machine and deploying to Docker machine

set -e

echo "=========================================="
echo "USB Sync Manager - Podman to Docker Migration"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

echo "Step 1: What would you like to do?"
echo "==================================="
echo ""
echo "1) Export images FROM Podman (current machine has Podman)"
echo "2) Import images TO Docker (current machine has Docker/NAS)"
echo "3) Both - Export from Podman AND import to Docker (same machine)"
echo ""
read -p "Enter your choice (1-3): " operation_choice

case $operation_choice in
    1)
        OPERATION="export"
        print_success "Selected: Export from Podman"
        ;;
    2)
        OPERATION="import"
        print_success "Selected: Import to Docker"
        ;;
    3)
        OPERATION="both"
        print_success "Selected: Both export and import"
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# ==========================================
# EXPORT FROM PODMAN
# ==========================================

if [ "$OPERATION" = "export" ] || [ "$OPERATION" = "both" ]; then
    
    echo ""
    echo "Step 2a: Check Podman availability"
    echo "===================================="
    echo ""
    
    if ! command -v podman &> /dev/null; then
        print_error "Podman is not installed or not in PATH"
        exit 1
    fi
    
    print_success "Podman found"
    
    echo ""
    echo "Step 3a: Select images to export"
    echo "=================================="
    echo ""
    echo "Available Podman images:"
    podman images | grep -E "usb-sync-manager" || print_warning "No USB Sync Manager images found"
    
    echo ""
    echo "Which images do you want to export?"
    echo "1) Both (backend and frontend)"
    echo "2) Backend only"
    echo "3) Frontend only"
    echo ""
    read -p "Enter your choice (1-3): " image_choice
    
    case $image_choice in
        1)
            EXPORT_BACKEND=true
            EXPORT_FRONTEND=true
            print_success "Selected: Both images"
            ;;
        2)
            EXPORT_BACKEND=true
            EXPORT_FRONTEND=false
            print_success "Selected: Backend only"
            ;;
        3)
            EXPORT_BACKEND=false
            EXPORT_FRONTEND=true
            print_success "Selected: Frontend only"
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    echo "Step 4a: Enter export directory"
    echo "==============================="
    echo ""
    read -p "Enter the directory to save TAR files (default: current directory): " export_dir
    
    # Use current directory if not specified
    if [ -z "$export_dir" ]; then
        export_dir="."
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$export_dir"
    
    if [ ! -w "$export_dir" ]; then
        print_error "Directory is not writable: $export_dir"
        exit 1
    fi
    
    print_success "Export directory: $export_dir"
    
    echo ""
    echo "Step 5a: Exporting images from Podman"
    echo "====================================="
    echo ""
    
    # Export backend if selected
    if [ "$EXPORT_BACKEND" = true ]; then
        echo "Exporting backend image..."
        backend_file="$export_dir/usb-sync-manager-backend.tar"
        
        if podman save -o "$backend_file" localhost/usb-sync-manager:latest 2>/dev/null; then
            print_success "Backend image exported to: $backend_file"
            backend_size=$(du -h "$backend_file" | cut -f1)
            echo "  Size: $backend_size"
        else
            print_error "Failed to export backend image"
            exit 1
        fi
    fi
    
    # Export frontend if selected
    if [ "$EXPORT_FRONTEND" = true ]; then
        echo "Exporting frontend image..."
        frontend_file="$export_dir/usb-sync-manager-frontend.tar"
        
        if podman save -o "$frontend_file" localhost/usb-sync-manager-frontend:latest 2>/dev/null; then
            print_success "Frontend image exported to: $frontend_file"
            frontend_size=$(du -h "$frontend_file" | cut -f1)
            echo "  Size: $frontend_size"
        else
            print_error "Failed to export frontend image"
            exit 1
        fi
    fi
    
    echo ""
    echo "=========================================="
    print_success "Export completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Transfer TAR files to the Docker/NAS machine:"
    if [ "$EXPORT_BACKEND" = true ]; then
        echo "     - $backend_file"
    fi
    if [ "$EXPORT_FRONTEND" = true ]; then
        echo "     - $frontend_file"
    fi
    echo ""
    echo "  2. On the Docker/NAS machine, run this script again"
    echo "     and select option 2 (Import to Docker)"
    echo ""
    echo "  Example SCP command:"
    if [ "$EXPORT_BACKEND" = true ]; then
        echo "    scp $backend_file user@nas-ip:/path/to/save/"
    fi
    if [ "$EXPORT_FRONTEND" = true ]; then
        echo "    scp $frontend_file user@nas-ip:/path/to/save/"
    fi
    echo ""
    
    # Exit if only exporting
    if [ "$OPERATION" = "export" ]; then
        exit 0
    fi
fi

# ==========================================
# IMPORT TO DOCKER
# ==========================================

if [ "$OPERATION" = "import" ] || [ "$OPERATION" = "both" ]; then
    
    echo ""
    echo "Step 2b: Check Docker availability"
    echo "===================================="
    echo ""
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    print_success "Docker found"
    
    echo ""
    echo "Step 3b: Locate TAR files"
    echo "========================="
    echo ""
    read -p "Enter the directory containing TAR files: " tar_dir
    
    if [ ! -d "$tar_dir" ]; then
        print_error "Directory does not exist: $tar_dir"
        exit 1
    fi
    
    if [ ! -r "$tar_dir" ]; then
        print_error "Directory is not readable: $tar_dir"
        exit 1
    fi
    
    echo ""
    echo "TAR files found in $tar_dir:"
    ls -lh "$tar_dir"/*.tar 2>/dev/null || print_warning "No TAR files found"
    
    echo ""
    echo "Step 4b: Select TAR files to import"
    echo "===================================="
    echo ""
    
    # Check which files exist
    BACKEND_TAR="$tar_dir/usb-sync-manager-backend.tar"
    FRONTEND_TAR="$tar_dir/usb-sync-manager-frontend.tar"
    
    BACKEND_EXISTS=false
    FRONTEND_EXISTS=false
    
    if [ -f "$BACKEND_TAR" ]; then
        BACKEND_EXISTS=true
        echo "✓ Backend TAR found: $(du -h "$BACKEND_TAR" | cut -f1)"
    else
        echo "✗ Backend TAR not found"
    fi
    
    if [ -f "$FRONTEND_TAR" ]; then
        FRONTEND_EXISTS=true
        echo "✓ Frontend TAR found: $(du -h "$FRONTEND_TAR" | cut -f1)"
    else
        echo "✗ Frontend TAR not found"
    fi
    
    echo ""
    echo "Which images do you want to import?"
    
    if [ "$BACKEND_EXISTS" = true ] && [ "$FRONTEND_EXISTS" = true ]; then
        echo "1) Both (backend and frontend)"
    fi
    if [ "$BACKEND_EXISTS" = true ]; then
        echo "2) Backend only"
    fi
    if [ "$FRONTEND_EXISTS" = true ]; then
        echo "3) Frontend only"
    fi
    echo ""
    
    read -p "Enter your choice: " import_choice
    
    IMPORT_BACKEND=false
    IMPORT_FRONTEND=false
    
    case $import_choice in
        1)
            if [ "$BACKEND_EXISTS" = true ] && [ "$FRONTEND_EXISTS" = true ]; then
                IMPORT_BACKEND=true
                IMPORT_FRONTEND=true
                print_success "Selected: Both images"
            else
                print_error "Invalid choice"
                exit 1
            fi
            ;;
        2)
            if [ "$BACKEND_EXISTS" = true ]; then
                IMPORT_BACKEND=true
                print_success "Selected: Backend only"
            else
                print_error "Backend TAR not found"
                exit 1
            fi
            ;;
        3)
            if [ "$FRONTEND_EXISTS" = true ]; then
                IMPORT_FRONTEND=true
                print_success "Selected: Frontend only"
            else
                print_error "Frontend TAR not found"
                exit 1
            fi
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    echo "Step 5b: Stop Docker containers (if running)"
    echo "==========================================="
    echo ""
    
    read -p "Stop currently running USB Sync Manager containers? (y/n): " stop_choice
    
    if [[ $stop_choice =~ ^[Yy]$ ]]; then
        echo "Stopping Docker containers..."
        if [ "$IMPORT_BACKEND" = true ]; then
            docker stop usb-sync-manager-backend 2>/dev/null || print_warning "Backend container not running"
            docker rm usb-sync-manager-backend 2>/dev/null || true
        fi
        if [ "$IMPORT_FRONTEND" = true ]; then
            docker stop usb-sync-manager-frontend 2>/dev/null || print_warning "Frontend container not running"
            docker rm usb-sync-manager-frontend 2>/dev/null || true
        fi
        print_success "Containers stopped"
    else
        print_warning "Skipped stopping containers"
    fi
    
    echo ""
    echo "Step 6b: Remove old Docker images"
    echo "================================="
    echo ""
    
    read -p "Remove old Docker images? (y/n): " remove_choice
    
    if [[ $remove_choice =~ ^[Yy]$ ]]; then
        if [ "$IMPORT_BACKEND" = true ]; then
            echo "Removing old backend image..."
            docker rmi usb-sync-manager-backend:latest 2>/dev/null || print_warning "Backend image not found"
        fi
        
        if [ "$IMPORT_FRONTEND" = true ]; then
            echo "Removing old frontend image..."
            docker rmi usb-sync-manager-frontend:latest 2>/dev/null || print_warning "Frontend image not found"
        fi
        
        print_success "Old images removed (if they existed)"
    else
        print_warning "Skipped removing old images"
    fi
    
    echo ""
    echo "Step 7b: Load images into Docker"
    echo "==============================="
    echo ""
    
    # Load backend if importing
    if [ "$IMPORT_BACKEND" = true ]; then
        echo "Loading backend image into Docker..."
        if docker load -i "$BACKEND_TAR"; then
            print_success "Backend image loaded"
        else
            print_error "Failed to load backend image"
            exit 1
        fi
    fi
    
    # Load frontend if importing
    if [ "$IMPORT_FRONTEND" = true ]; then
        echo "Loading frontend image into Docker..."
        if docker load -i "$FRONTEND_TAR"; then
            print_success "Frontend image loaded"
        else
            print_error "Failed to load frontend image"
            exit 1
        fi
    fi
    
    echo ""
    echo "Step 8b: Verify Docker images"
    echo "============================="
    echo ""
    echo "Available Docker images:"
    docker images | grep usb-sync-manager || print_warning "No images found"
    
    echo ""
    echo "Step 9b: Start Docker containers"
    echo "==============================="
    echo ""
    
    read -p "Start Docker containers now? (y/n): " start_choice
    
    if [[ $start_choice =~ ^[Yy]$ ]]; then
        echo ""
        echo "Step 9b-i: Load environment configuration"
        echo "=========================================="
        echo ""
        
        # Load .env if exists
        if [ -f ".env" ]; then
            print_success "Found .env file - loading configuration"
            set -a
            source .env
            set +a
        else
            print_warning ".env file not found - using defaults"
            SMTP_SERVER="smtp.gmail.com"
            SMTP_PORT="587"
            SENDER_EMAIL=""
            SENDER_PASSWORD=""
        fi
        
        echo ""
        echo "Step 9b-ii: Enter Docker port configurations"
        echo "==========================================="
        echo ""
        read -p "Backend port (default: 5000): " backend_port
        if [ -z "$backend_port" ]; then
            backend_port="5000"
        fi
        
        read -p "Frontend port (default: 3000): " frontend_port
        if [ -z "$frontend_port" ]; then
            frontend_port="3000"
        fi
        
        print_success "Backend port: $backend_port"
        print_success "Frontend port: $frontend_port"
        
        echo ""
        echo "Starting Docker containers..."
        
        # Create network if it doesn't exist
        echo "Creating Docker network..."
        docker network create usb-sync-network 2>/dev/null || print_warning "Network already exists"
        
        # Start backend if imported
        if [ "$IMPORT_BACKEND" = true ]; then
            echo "Starting backend container..."
            if docker run -d \
                --name usb-sync-manager-backend \
                --network usb-sync-network \
                -p ${backend_port}:5000 \
                -v usb-sync-manager-config:/etc/usb-sync-manager \
                -v /media:/media \
                -v /mnt:/mnt \
                -e SENDER_EMAIL="${SENDER_EMAIL}" \
                -e SENDER_PASSWORD="${SENDER_PASSWORD}" \
                -e SMTP_SERVER="${SMTP_SERVER}" \
                -e SMTP_PORT="${SMTP_PORT}" \
                -e PYTHONUNBUFFERED=1 \
                --restart unless-stopped \
                usb-sync-manager-backend:latest; then
                print_success "Backend container started"
                echo "  API available at: http://localhost:${backend_port}/api"
            else
                print_error "Failed to start backend container"
                exit 1
            fi
        fi
        
        # Start frontend if imported
        if [ "$IMPORT_FRONTEND" = true ]; then
            echo "Starting frontend container..."
            echo ""
            echo "Frontend needs to know where backend API is located."
            echo "Examples:"
            echo "  - http://localhost:${backend_port}       (if accessing from local machine)"
            echo "  - http://nas-ip:${backend_port}          (if accessing from other machine)"
            echo "  - http://127.0.0.1:${backend_port}       (alternative localhost)"
            echo ""
            read -p "Enter backend API URL: " frontend_api_url
            
            if [ -z "$frontend_api_url" ]; then
                frontend_api_url="http://localhost:${backend_port}"
                print_warning "Using default: $frontend_api_url"
            fi
            
            if docker run -d \
                --name usb-sync-manager-frontend \
                --network usb-sync-network \
                -p ${frontend_port}:3000 \
                -e REACT_APP_API_URL="${frontend_api_url}" \
                --restart unless-stopped \
                usb-sync-manager-frontend:latest; then
                print_success "Frontend container started"
                echo "  Dashboard available at: http://localhost:${frontend_port}"
                echo "  Backend API URL: ${frontend_api_url}"
            else
                print_error "Failed to start frontend container"
                exit 1
            fi
        fi
        
        echo ""
        echo "Running containers:"
        docker ps | grep usb-sync-manager || echo "No containers running"
    else
        print_warning "Skipped starting containers"
        echo ""
        echo "To start containers manually:"
        echo ""
        echo "1. Create network:"
        echo "   docker network create usb-sync-network"
        echo ""
        if [ "$IMPORT_BACKEND" = true ]; then
            echo "2. Start backend:"
            echo "   docker run -d \\"
            echo "     --name usb-sync-manager-backend \\"
            echo "     --network usb-sync-network \\"
            echo "     -p 5000:5000 \\"
            echo "     -v usb-sync-manager-config:/etc/usb-sync-manager \\"
            echo "     -v /volume1:/media \\"
            echo "     -v /share:/mnt \\"
            echo "     -e SENDER_EMAIL=your-email \\"
            echo "     -e SENDER_PASSWORD=your-password \\"
            echo "     -e SMTP_SERVER=smtp.gmail.com \\"
            echo "     -e SMTP_PORT=587 \\"
            echo "     --restart unless-stopped \\"
            echo "     localhost/usb-sync-manager:latest"
            echo ""
        fi
        if [ "$IMPORT_FRONTEND" = true ]; then
            echo "3. Start frontend:"
            echo "   IMPORTANT: Replace 'http://nas-ip:5000' with actual NAS IP or hostname"
            echo ""
            echo "   docker run -d \\"
            echo "     --name usb-sync-manager-frontend \\"
            echo "     --network usb-sync-network \\"
            echo "     -p 3000:3000 \\"
            echo "     -e REACT_APP_API_URL=http://nas-ip:5000 \\"
            echo "     --restart unless-stopped \\"
            echo "     localhost/usb-sync-manager-frontend:latest"
            echo ""
            echo "   EXAMPLES:"
            echo "   - http://192.168.1.100:5000     (NAS IP address)"
            echo "   - http://nas.local:5000          (NAS hostname)"
            echo "   - http://localhost:5000          (if accessing from NAS)"
            echo ""
        fi
    fi
    
    echo ""
    echo "=========================================="
    print_success "Import completed successfully!"
    echo "=========================================="
    echo ""
    echo "Summary:"
    if [ "$IMPORT_BACKEND" = true ]; then
        echo "  - Backend: Imported from $BACKEND_TAR"
        echo "    Port: $backend_port"
    fi
    if [ "$IMPORT_FRONTEND" = true ]; then
        echo "  - Frontend: Imported from $FRONTEND_TAR"
        echo "    Port: $frontend_port"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Verify containers are running: docker ps"
    echo "  2. Check logs: docker logs usb-sync-manager-backend"
    echo "  3. Access dashboard: http://localhost:${frontend_port}"
    echo "  4. Check API: curl http://localhost:${backend_port}/api/schedules"
    echo ""
fi