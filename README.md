# Sync Manager

A comprehensive backup solution for automated storage synchronization (USB/NAS to USB/NAS) with email notifications, scheduled backups, and web-based dashboard.

## 📁 Project Structure

```
usb-sync-manager/
├── backend/                  # Python Flask API server
│   ├── usb_sync_backend.py  # Main backend application
│   ├── requirements.txt       # Python dependencies
│   ├── Dockerfile            # Backend container configuration
│   ├── entrypoint.sh         # Backend startup script
│   └── run.sh               # Backend deployment script
│
├── frontend/                 # React web dashboard
│   ├── src/
│   │   ├── App.jsx          # Main React component
│   │   └── index.js         # React entry point
│   ├── public/
│   │   └── index.html       # HTML template with runtime config loader
│   ├── package.json         # Node.js dependencies
│   ├── frontend.sh          # Frontend deployment script
│
├── migrate.sh               # Podman to Docker migration tool
├── diagnose.sh              # API connectivity troubleshooting
└── README.md                # This file
```

## 🚀 Quick Start

### Prerequisites

- **Local Development:**

  - Node.js 16+ and npm
  - Python 3.11+
  - Podman or Docker

- **NAS Deployment:**
  - Docker/Podman runtime
  - Network access to USB drives/NAS storage

### Local Development

**Terminal 1: Start Backend**

```bash
cd backend
./run.sh local start
# Backend runs at http://localhost:5000
```

**Terminal 2: Start Frontend**

```bash
cd frontend
./frontend.sh dev
# Frontend runs at http://localhost:3000
# Hot reload enabled - changes auto-refresh
```

**Open in Browser:** `http://localhost:3000`

### NAS Deployment (Docker/Podman)

#### Option 1: Export from Podman + Import to Docker

If you have Podman locally and want to deploy to Docker on NAS:

```bash
# On local machine with Podman
./migrate.sh
# Select: 1 (Export from Podman)
# Choose: 1 (Both images)
# Enter: directory to save files

# Transfer files to NAS
scp migrate-usb-sync-manager-*.tar user@nas-ip:/tmp/

# On NAS with Docker
./migrate.sh
# Select: 2 (Import to Docker)
# Enter: /tmp (where files are)
# Choose: 1 (Both images)
# Answer: yes to all prompts
```

#### Option 2: Build Directly on NAS

```bash
# Backend
cd backend
./run.sh podman/docker build
./run.sh podman/docker run

# Frontend
cd frontend
./frontend.sh podman/docker build
./frontend.sh podman/docker run
# When prompted for API URL, press ENTER (auto-detects)
```

## 🔧 Configuration

### Backend (.env file)

Create `.env` in backend directory:

```bash
SENDER_EMAIL=your-email@gmail.com
SENDER_PASSWORD=your-app-password
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
```

**Gmail Setup:**

1. Enable 2-factor authentication
2. Generate app password: https://myaccount.google.com/apppasswords
3. Use the 16-character password in `SENDER_PASSWORD`

### Frontend (.env file for local dev)

Create `.env` in frontend directory:

```bash
REACT_APP_API_URL=http://localhost:5000
```

**Production (Docker):** Environment variables are set automatically at runtime.

## 📖 Usage Guide

### Web Dashboard

**Features:**

- ✅ View all backup schedules
- ✅ Create new schedules (USB source → NAS destination)
- ✅ Edit existing schedules
- ✅ Delete schedules
- ✅ Browse folder trees to select paths
- ✅ Test email notifications
- ✅ Manual backup execution (Test Now ⚡)
- ✅ View system status

### Creating a Backup Schedule

1. Click **"+ New Schedule"**
2. Enter schedule name
3. Select USB source (click folder icon to browse)
4. Select NAS destination (click folder icon to browse)
5. Choose frequency:
   - **Daily:** Run every day at specified time
   - **Weekly:** Run on selected day of week
   - **Monthly:** Run on selected day of month
6. Set time
7. Enter email for notifications (optional)
8. Click **Save**

### Testing

**Manual Backup:**

- Click **⚡ Test Now** button on any schedule
- Runs immediately in background
- Email notification sent with results

**Email Notification:**

- Click **Test Email** to verify email configuration

## 🔗 API Endpoints

### Schedules

- `GET /api/schedules` - List all schedules
- `POST /api/schedules` - Create new schedule
- `PUT /api/schedules/{id}` - Update schedule
- `DELETE /api/schedules/{id}` - Delete schedule
- `POST /api/schedules/{id}/test` - Run manual backup

### File Browser

- `POST /api/folders/search` - List folders in path
- `POST /api/folders/create` - Create new folder

### System

- `GET /api/usb-drives` - List connected USB drives
- `GET /api/system/status` - System information
- `GET /health` - Health check

### Email

- `POST /api/test-email` - Send test notification

## 🐛 Troubleshooting

### API Connection Issues

Run the diagnostic script:

```bash
./diagnose.sh
```

This checks:

- Container status
- Backend availability
- Frontend connectivity
- Docker network configuration
- Provides quick fixes

### CORS Errors

See `CORS_GUIDE.md` for detailed troubleshooting.

**Quick Fix:**

- Frontend auto-detects hostname from browser
- If accessing from `192.168.1.100:3000`, backend should be at `192.168.1.100:5000`
- Works automatically in most cases

### Schedules Lost After Rebuild

**Solution:** Schedules are stored in a Docker volume that persists.

```bash
# Clean WITHOUT removing volumes (schedules preserved)
cd backend
./run.sh podman/docker clean
# Select: 1 (Keep schedules)

# Rebuild
./run.sh podman/docker build
./run.sh podman/docker run
```

### Frontend Shows Localhost

**Solution:** Make sure to rebuild frontend after changes:

```bash
cd frontend
./frontend.sh podman/docker clean
./frontend.sh podman/docker build
./frontend.sh podman/docker run
# Press ENTER when asked for API URL (auto-detects)
```

## 🔄 Development Workflow

### Making Changes

**Backend Changes:**

```bash
cd backend
# Edit usb_sync_backend.py
# Changes apply immediately in local mode
# For Docker: rebuild with ./run.sh podman/docker build
```

**Frontend Changes:**

```bash
cd frontend
# Edit src/App.jsx
# Changes auto-refresh in dev mode (npm run dev)
# For Docker: rebuild with ./frontend.sh podman/docker build
```

### Running Tests

```bash
# Backend health check
curl http://localhost:5000/health

# Frontend API test (from browser console)
fetch('http://localhost:5000/api/schedules')
  .then(r => r.json())
  .then(d => console.log(d))
```

## 🚢 Deployment Checklist

### Before Going Live

- [ ] Test backend at http://nas-ip:5000/health
- [ ] Test frontend at http://nas-ip:3000
- [ ] Verify email notifications working
- [ ] Test at least one manual backup
- [ ] Confirm rsync permissions are correct
- [ ] Set up at least one scheduled backup
- [ ] Verify folder browser can access all paths

### Docker Compose (Optional)

Create `docker-compose.yml`:

```yaml
version: "3.8"

services:
  backend:
    image: usb-sync-manager-backend:latest
    container_name: usb-sync-manager-backend
    ports:
      - "5000:5000"
    volumes:
      - usb-sync-config:/etc/usb-sync-manager
      - /media:/media
      - /mnt:/mnt
    environment:
      - SENDER_EMAIL=${SENDER_EMAIL}
      - SENDER_PASSWORD=${SENDER_PASSWORD}
      - SMTP_SERVER=${SMTP_SERVER:-smtp.gmail.com}
      - SMTP_PORT=${SMTP_PORT:-587}
    restart: unless-stopped

  frontend:
    image: usb-sync-manager-frontend:latest
    container_name: usb-sync-manager-frontend
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://localhost:5000
    depends_on:
      - backend
    restart: unless-stopped

volumes:
  usb-sync-config:
```

Run with:

```bash
docker-compose up -d
```

## 📊 Backup Schedule Examples

### Daily Backup at 2 AM

- Frequency: Daily
- Time: 02:00
- Runs every day

### Weekly Backup (Sunday 3 AM)

- Frequency: Weekly
- Day: Sunday
- Time: 03:00
- Runs once per week

### Monthly Backup (1st of month)

- Frequency: Monthly
- Day: 1
- Time: 01:00
- Runs once per month

## 🔐 Security Considerations

- Email credentials stored in `.env` (not in Git/Docker)
- CORS configured to accept requests from all origins
- Rsync runs with elevated permissions - be careful with paths
- Schedule data persisted in Docker volume
- All API endpoints accessible without authentication (local network only)

### Recommended Setup

- Deploy on private/local network only
- Use firewall rules to restrict access
- Keep NAS IP/hostname internal
- Regularly monitor backup logs

## 📋 System Requirements

### Backend

- Python 3.11+
- APScheduler (task scheduling)
- Flask (REST API)
- Flask-CORS (cross-origin requests)
- psutil (system monitoring)

### Frontend

- Node.js 16+
- React 18
- Lucide Icons
- Tailwind CSS

### Storage

- Minimum 1GB for Docker images
- Varies based on backup size
- Docker volumes for schedule persistence

## 🤝 Common Tasks

### Add New USB Drive

1. Connect USB drive to NAS
2. Open frontend dashboard
3. Click folder icon to browse `/media` or `/mnt`
4. Select your drive
5. Create schedule

### Change Backend Port

```bash
# Edit backend/run.sh
# Change PORT="${REACT_PORT:-3000}" to your port
./run.sh docker run
```

### Move Schedules to New NAS

```bash
# Old NAS
docker volume inspect usb-sync-manager-backend-config

# New NAS
# Restore from backup or migrate volume
```

### View Backup Logs

```bash
# Backend logs
docker logs usb-sync-manager-backend

# Detailed rsync logs
docker exec usb-sync-manager-backend ls -la /etc/usb-sync-manager/logs/
```

## 🎯 Performance Notes

- Rsync is efficient for incremental backups
- Large initial backups may take time
- Network speed affects backup duration
- CPU/Memory usage minimal during off-hours

## 📝 License

MIT License - Feel free to use and modify

## 🆘 Support

**For API Connection Issues:**

```bash
./diagnose.sh
```

**For CORS/Frontend Issues:**
See `CORS_GUIDE.md`

**For Migration Help:**

```bash
./migrate.sh
```

## 🔗 Related Files

- `CORS_GUIDE.md` - Detailed CORS troubleshooting
- `backend/run.sh` - Backend deployment script
- `frontend/frontend.sh` - Frontend deployment script
- `migrate.sh` - Podman to Docker migration
- `diagnose.sh` - API connectivity diagnostic

## 📌 Version History

### Latest

- ✅ Runtime API URL configuration
- ✅ Auto-detection from hostname
- ✅ Docker/Podman support
- ✅ Persistent schedules
- ✅ Email notifications
- ✅ Folder browser
- ✅ Manual backup testing
- ✅ System status monitoring

---

**Last Updated:** December 18, 2025

**Made with ❤️ for NAS enthusiasts**
