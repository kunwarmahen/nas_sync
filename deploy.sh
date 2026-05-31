#!/usr/bin/env bash
# deploy.sh — build and deploy the USB Sync Manager
#
# LOCAL (Docker / Podman):
#   ./deploy.sh local build          — build backend + frontend images
#   ./deploy.sh local up             — build + start (backend :5000, frontend :3000)
#   ./deploy.sh local down           — stop containers
#   ./deploy.sh local logs           — tail logs
#   ./deploy.sh local clean          — remove containers, volumes, images
#
# NAS (remote Docker over SSH):
#   ./deploy.sh nas deploy           — build locally, push images + compose to NAS, start
#   ./deploy.sh nas up               — (re)start on NAS without rebuilding
#   ./deploy.sh nas down             — stop on NAS
#   ./deploy.sh nas logs             — tail NAS logs
#   ./deploy.sh nas shell            — open shell on NAS backend container
#
# NAS configuration (env vars):
#   NAS_HOST           IP or hostname of your NAS          (required for nas commands)
#   NAS_USER           SSH user                            (default: current user)
#   NAS_PATH           Remote deploy directory             (default: ~/usb-sync-manager)
#   NAS_VOLUME_PATH    NAS storage path mounted in backend (default: /volume1)
#   NAS_SSH_KEY        Path to SSH private key             (default: SSH agent key)
#   NAS_SSH_PORT       SSH port                            (default: 22)
#
# Email credentials are read from backend/.env automatically during nas deploy.
# REACT_APP_API_URL defaults to http://<NAS_HOST>:5000 — override if needed.
#
# Examples:
#   ./deploy.sh local up
#   NAS_HOST=192.168.1.100 ./deploy.sh nas deploy
#   NAS_HOST=192.168.1.100 NAS_VOLUME_PATH=/volume1/homes ./deploy.sh nas deploy

set -euo pipefail
cd "$(dirname "$0")"

# ── colour helpers ────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
info()    { echo -e "${CYAN}[deploy]${RESET} $*"; }
ok()      { echo -e "${GREEN}[deploy]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[deploy]${RESET} $*"; }
die()     { echo -e "${RED}[deploy] ERROR:${RESET} $*" >&2; exit 1; }
banner()  { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${RESET}\n"; }

# ── config ────────────────────────────────────────────────────────────────────
BACKEND_IMAGE="usb-sync-manager:latest"
FRONTEND_IMAGE="usb-sync-manager-frontend:latest"

NAS_HOST="${NAS_HOST:-}"
NAS_USER="${NAS_USER:-$(whoami)}"
NAS_PATH="${NAS_PATH:-usb-sync-manager}"        # relative = home dir on NAS
NAS_CONFIG_PATH="${NAS_CONFIG_PATH:-/volume1/Docker/usb-sync-manager-config}"
NAS_VOLUME_PATH="${NAS_VOLUME_PATH:-/volume1}"  # mounted as /media inside container
NAS_SHARE_PATH="${NAS_SHARE_PATH:-/share}"      # mounted as /mnt inside container
NAS_SSH_KEY="${NAS_SSH_KEY:-}"
NAS_SSH_PORT="${NAS_SSH_PORT:-22}"
NAS_SSH_CTL="/tmp/.usb-sync-ssh-$$"            # ControlMaster socket

BACKEND_ENV="backend/.env"
COMPOSE_LOCAL="docker-compose.yml"
COMPOSE_NAS="docker-compose.nas.yml"

# ── runtime detection ─────────────────────────────────────────────────────────
detect_runtime() {
    if command -v podman &>/dev/null; then
        echo "podman"
    elif command -v docker &>/dev/null; then
        echo "docker"
    else
        die "Neither podman nor docker found. Install one and retry."
    fi
}

detect_compose() {
    local rt="$1"
    if [ "$rt" = "podman" ]; then
        if command -v podman-compose &>/dev/null; then
            echo "podman-compose"
        elif podman compose version &>/dev/null 2>&1; then
            echo "podman compose"
        else
            die "podman-compose not found. Install it: pip install podman-compose"
        fi
    else
        if docker compose version &>/dev/null 2>&1; then
            echo "docker compose"
        elif command -v docker-compose &>/dev/null; then
            echo "docker-compose"
        else
            die "docker compose plugin not found."
        fi
    fi
}

# ── env helpers ───────────────────────────────────────────────────────────────
load_backend_env() {
    if [ -f "$BACKEND_ENV" ]; then
        # Export only lines that look like KEY=VALUE (skip comments/blanks)
        set -a
        # shellcheck disable=SC1090
        source <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$BACKEND_ENV")
        set +a
    else
        warn "backend/.env not found — email notifications will be disabled on NAS."
        warn "Create backend/.env with SENDER_EMAIL and SENDER_PASSWORD to enable them."
    fi
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
require_nas_host() {
    [ -n "$NAS_HOST" ] || die "NAS_HOST is not set. Export it or pass NAS_HOST=<ip> before the command."
}

ssh_opts() {
    local opts="-p ${NAS_SSH_PORT} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    opts="$opts -o ControlMaster=auto -o ControlPath=${NAS_SSH_CTL} -o ControlPersist=120"
    [ -n "$NAS_SSH_KEY" ] && opts="$opts -i $NAS_SSH_KEY"
    echo "$opts"
}

nas_ssh_open() {
    info "Connecting to ${NAS_HOST} …"
    # shellcheck disable=SC2046
    ssh $(ssh_opts) -o ControlMaster=yes -fN "${NAS_USER}@${NAS_HOST}"
}

nas_ssh_close() {
    ssh -O exit -o "ControlPath=${NAS_SSH_CTL}" "${NAS_USER}@${NAS_HOST}" 2>/dev/null || true
    rm -f "${NAS_SSH_CTL}"
}

nas_ssh() {
    local tty_flag=""
    if [ "${1:-}" = "-t" ]; then
        tty_flag="-tt"   # force PTY so sudo can prompt for a password
        shift
    fi
    # shellcheck disable=SC2046
    ssh $(ssh_opts) $tty_flag "${NAS_USER}@${NAS_HOST}" "$@"
}

nas_scp() {
    local src="$1" dst="$2"
    local key_opt=""
    [ -n "$NAS_SSH_KEY" ] && key_opt="-i $NAS_SSH_KEY"
    # shellcheck disable=SC2046
    scp -P "${NAS_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o ControlMaster=auto \
        -o "ControlPath=${NAS_SSH_CTL}" \
        -o ControlPersist=120 \
        ${key_opt} \
        "$src" "${NAS_USER}@${NAS_HOST}:${dst}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  LOCAL  (Docker / Podman)
# ══════════════════════════════════════════════════════════════════════════════
local_build() {
    banner "Local build"
    local rt; rt=$(detect_runtime)
    local compose; compose=$(detect_compose "$rt")
    info "Runtime: $rt"
    load_backend_env
    $compose -f "$COMPOSE_LOCAL" build
    ok "Images built."
}

local_up() {
    banner "Local up"
    local rt; rt=$(detect_runtime)
    local compose; compose=$(detect_compose "$rt")
    info "Runtime: $rt  |  Compose: $compose"
    load_backend_env
    $compose -f "$COMPOSE_LOCAL" up --build -d
    echo ""
    ok "Containers started."
    ok "Backend  → http://localhost:5000"
    ok "Frontend → http://localhost:3000"
    echo ""
    info "Logs: ./deploy.sh local logs"
    info "Stop: ./deploy.sh local down"
}

local_down() {
    banner "Local down"
    local rt; rt=$(detect_runtime)
    local compose; compose=$(detect_compose "$rt")
    $compose -f "$COMPOSE_LOCAL" down 2>/dev/null || true
    ok "Containers stopped."
}

local_logs() {
    local rt; rt=$(detect_runtime)
    local compose; compose=$(detect_compose "$rt")
    $compose -f "$COMPOSE_LOCAL" logs -f
}

local_clean() {
    banner "Local clean"
    local rt; rt=$(detect_runtime)
    local compose; compose=$(detect_compose "$rt")
    warn "This will remove containers, volumes, and local images."
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
    $compose -f "$COMPOSE_LOCAL" down -v 2>/dev/null || true
    $rt rmi "$BACKEND_IMAGE" "$FRONTEND_IMAGE" 2>/dev/null && ok "Images removed." || warn "Images already removed."
    ok "Clean complete."
}

# ══════════════════════════════════════════════════════════════════════════════
#  NAS  (remote Docker)
# ══════════════════════════════════════════════════════════════════════════════
nas_deploy() {
    banner "NAS deploy"
    require_nas_host
    load_backend_env

    nas_ssh_open
    trap nas_ssh_close EXIT

    local rt; rt=$(detect_runtime)
    info "Runtime for build: $rt"

    # 1. Build both images locally
    info "Building backend image …"
    $rt build -t "$BACKEND_IMAGE" ./backend
    info "Building frontend image …"
    $rt build -t "$FRONTEND_IMAGE" ./frontend

    # 2. Export both images to temp tars
    local backend_tar="/tmp/usb-sync-manager-backend.tar.gz"
    local frontend_tar="/tmp/usb-sync-manager-frontend.tar.gz"
    info "Exporting backend image → ${backend_tar}"
    $rt save "$BACKEND_IMAGE"  | gzip > "$backend_tar"
    info "Exporting frontend image → ${frontend_tar}"
    $rt save "$FRONTEND_IMAGE" | gzip > "$frontend_tar"
    ok "Images exported (backend: $(du -sh "$backend_tar" | cut -f1), frontend: $(du -sh "$frontend_tar" | cut -f1))"

    # 3. Ensure remote directory exists
    info "Preparing remote path ${NAS_PATH} on ${NAS_HOST} …"
    nas_ssh "mkdir -p '${NAS_PATH}'"

    # 4. Transfer images to NAS
    info "Transferring backend image to NAS …"
    nas_scp "$backend_tar"  "${NAS_PATH}/"
    info "Transferring frontend image to NAS …"
    nas_scp "$frontend_tar" "${NAS_PATH}/"

    # 5. Copy compose file + write .env combining email creds and NAS config
    info "Syncing compose file + config …"
    nas_scp "$COMPOSE_NAS" "${NAS_PATH}/docker-compose.yml"

    local env_file="/tmp/.usb-sync-nas-$$.env"
    cat > "$env_file" <<EOF
SENDER_EMAIL=${SENDER_EMAIL:-}
SENDER_PASSWORD=${SENDER_PASSWORD:-}
SMTP_SERVER=${SMTP_SERVER:-smtp.gmail.com}
SMTP_PORT=${SMTP_PORT:-587}
REACT_APP_API_URL=${NAS_REACT_APP_API_URL:-http://${NAS_HOST}:5000}
NAS_CONFIG_PATH=${NAS_CONFIG_PATH}
NAS_VOLUME_PATH=${NAS_VOLUME_PATH}
NAS_SHARE_PATH=${NAS_SHARE_PATH}
EOF
    nas_scp "$env_file" "${NAS_PATH}/.env"
    rm -f "$env_file"

    # Ensure the config bind-mount directory exists on the NAS
    nas_ssh "mkdir -p '${NAS_CONFIG_PATH}'"

    # 6. Load images, tag (strips Podman's localhost/ prefix), and start
    info "Loading images on NAS and starting containers …"
    nas_ssh -t "
        set -e
        cd '${NAS_PATH}'
        echo '[nas] Loading backend image …'
        sudo docker load < usb-sync-manager-backend.tar.gz
        sudo docker tag localhost/usb-sync-manager:latest usb-sync-manager:latest 2>/dev/null || true
        echo '[nas] Loading frontend image …'
        sudo docker load < usb-sync-manager-frontend.tar.gz
        sudo docker tag localhost/usb-sync-manager-frontend:latest usb-sync-manager-frontend:latest 2>/dev/null || true
        echo '[nas] Stopping any existing containers (by name, any project) …'
        sudo docker stop usb-sync-manager usb-sync-manager-frontend 2>/dev/null || true
        sudo docker rm   usb-sync-manager usb-sync-manager-frontend 2>/dev/null || true
        sudo docker compose down 2>/dev/null || true
        echo '[nas] Releasing ports 5000 and 3000 …'
        sudo docker ps -q --filter publish=5000 | xargs -r sudo docker stop 2>/dev/null || true
        sudo docker ps -aq --filter publish=5000 | xargs -r sudo docker rm  2>/dev/null || true
        sudo docker ps -q --filter publish=3000 | xargs -r sudo docker stop 2>/dev/null || true
        sudo docker ps -aq --filter publish=3000 | xargs -r sudo docker rm  2>/dev/null || true
        echo '[nas] Starting services …'
        sudo docker compose up -d --remove-orphans
        echo '[nas] Running containers:'
        sudo docker compose ps
    "

    # 7. Cleanup local tars
    rm -f "$backend_tar" "$frontend_tar"
    nas_ssh_close
    trap - EXIT

    echo ""
    ok "Deployed to NAS (${NAS_HOST})"
    ok "Backend  → http://${NAS_HOST}:5000"
    ok "Frontend → http://${NAS_HOST}:3000"
    echo ""
    info "Config path on NAS : ${NAS_CONFIG_PATH}"
    info "Volume path (/media): ${NAS_VOLUME_PATH}"
    info "Share path (/mnt)   : ${NAS_SHARE_PATH}"
    info "Logs: ./deploy.sh nas logs"
    info "Stop: ./deploy.sh nas down"
}

nas_up() {
    banner "NAS up"
    require_nas_host
    nas_ssh_open
    info "(Re)starting containers on ${NAS_HOST} …"
    nas_ssh -t "cd '${NAS_PATH}' && sudo docker compose up -d --remove-orphans && sudo docker compose ps"
    nas_ssh_close
    ok "Done."
}

nas_down() {
    banner "NAS down"
    require_nas_host
    nas_ssh_open
    info "Stopping containers on ${NAS_HOST} …"
    nas_ssh -t "cd '${NAS_PATH}' && sudo docker compose down"
    nas_ssh_close
    ok "Done."
}

nas_logs() {
    require_nas_host
    nas_ssh_open
    info "Tailing logs on ${NAS_HOST} … (Ctrl-C to stop)"
    nas_ssh -t "cd '${NAS_PATH}' && sudo docker compose logs -f"
    nas_ssh_close
}

nas_shell() {
    require_nas_host
    nas_ssh_open
    info "Opening shell on NAS backend container …"
    nas_ssh -t "cd '${NAS_PATH}' && sudo docker compose exec backend /bin/sh"
    nas_ssh_close
}

# ══════════════════════════════════════════════════════════════════════════════
#  HELP
# ══════════════════════════════════════════════════════════════════════════════
usage() {
    cat <<EOF
${BOLD}USB Sync Manager — deploy.sh${RESET}

${BOLD}USAGE${RESET}
  ./deploy.sh <target> <command>

${BOLD}LOCAL (Docker / Podman)${RESET}
  ./deploy.sh local build           Build backend + frontend images
  ./deploy.sh local up              Build + start (backend :5000, frontend :3000)
  ./deploy.sh local down            Stop all local containers
  ./deploy.sh local logs            Tail container logs
  ./deploy.sh local clean           Remove containers, volumes, and images

${BOLD}NAS (remote Docker over SSH)${RESET}
  ./deploy.sh nas deploy            Build locally, ship to NAS, start
  ./deploy.sh nas up                (Re)start on NAS without rebuilding
  ./deploy.sh nas down              Stop containers on NAS
  ./deploy.sh nas logs              Tail NAS logs
  ./deploy.sh nas shell             Shell into the NAS backend container

${BOLD}NAS CONFIGURATION${RESET}  (env vars or export before running)
  NAS_HOST              IP or hostname of your NAS                (required for nas commands)
  NAS_USER              SSH user                                  (default: $(whoami))
  NAS_PATH              Remote deploy directory                   (default: ~/usb-sync-manager)
  NAS_CONFIG_PATH       Host path for config/schedules bind mount (default: /volume1/Docker/usb-sync-manager-config)
  NAS_VOLUME_PATH       NAS storage path → mounted as /media      (default: /volume1)
  NAS_SHARE_PATH        Secondary share path → mounted as /mnt    (default: /share)
  NAS_REACT_APP_API_URL Frontend→backend URL override             (default: http://\$NAS_HOST:5000)
  NAS_SSH_KEY           Path to SSH private key                   (default: SSH agent key)
  NAS_SSH_PORT          SSH port                                  (default: 22)

${BOLD}EMAIL CREDENTIALS${RESET}
  Read automatically from backend/.env (SENDER_EMAIL, SENDER_PASSWORD).
  Create that file if it doesn't exist — see backend/.env for the format.

${BOLD}EXAMPLES${RESET}
  ./deploy.sh local up
  NAS_HOST=192.168.1.100 ./deploy.sh nas deploy
  NAS_HOST=192.168.1.100 NAS_CONFIG_PATH=/volume1/Docker/usb-sync-manager-config NAS_VOLUME_PATH=/volume1 NAS_SHARE_PATH=/share ./deploy.sh nas deploy
  NAS_HOST=192.168.1.100 NAS_REACT_APP_API_URL=http://nas.local:5000 ./deploy.sh nas deploy
EOF
}

# ══════════════════════════════════════════════════════════════════════════════
#  DISPATCH
# ══════════════════════════════════════════════════════════════════════════════
TARGET="${1:-}"
COMMAND="${2:-}"

case "$TARGET" in
    local)
        case "$COMMAND" in
            build) local_build ;;
            up)    local_up ;;
            down)  local_down ;;
            logs)  local_logs ;;
            clean) local_clean ;;
            *)     die "Unknown local command: '$COMMAND'. Run ./deploy.sh for help." ;;
        esac
        ;;
    nas)
        case "$COMMAND" in
            deploy) nas_deploy ;;
            up)     nas_up ;;
            down)   nas_down ;;
            logs)   nas_logs ;;
            shell)  nas_shell ;;
            *)      die "Unknown nas command: '$COMMAND'. Run ./deploy.sh for help." ;;
        esac
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        die "Unknown target: '$TARGET'. Use 'local' or 'nas'."
        ;;
esac
