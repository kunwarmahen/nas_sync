#!/usr/bin/env python3
"""
USB Sync Manager - Backend API Service
Flask + APScheduler for managing scheduled rsync backups
"""

import os
import json
import subprocess
import smtplib
import logging
from datetime import datetime
from pathlib import Path
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

from flask import Flask, request, jsonify
from flask_cors import CORS
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
import psutil

# ===========================
# Configuration
# ===========================

CONFIG_DIR = Path('/etc/usb-sync-manager')
SCHEDULES_FILE = CONFIG_DIR / 'schedules.json'
LOGS_DIR = CONFIG_DIR / 'logs'

# Email Configuration from environment
SMTP_SERVER = os.getenv('SMTP_SERVER', 'smtp.gmail.com')
SMTP_PORT = int(os.getenv('SMTP_PORT', '587'))
SENDER_EMAIL = os.getenv('SENDER_EMAIL', '')
SENDER_PASSWORD = os.getenv('SENDER_PASSWORD', '')

# ===========================
# Logging Setup
# ===========================

LOGS_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOGS_DIR / 'usb-sync.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ===========================
# Flask App Setup
# ===========================

app = Flask(__name__)

# Configure CORS to allow all origins
CORS(app, 
     resources={r"/api/*": {"origins": "*"}},
     allow_headers=["Content-Type", "Authorization"],
     methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])

scheduler = BackgroundScheduler()

# Configure scheduler to use system timezone
import pytz
try:
    # Get system timezone from environment
    system_tz_str = os.environ.get('TZ', 'UTC')
    scheduler.configure(timezone=pytz.timezone(system_tz_str))
    logger.info(f"Scheduler configured with timezone: {system_tz_str}")
except Exception as e:
    logger.warning(f"Could not configure scheduler timezone: {e}, using UTC")
    scheduler.configure(timezone=pytz.UTC)

# ===========================
# Helper Functions
# ===========================

def ensure_config_exists():
    """Ensure configuration directory and files exist"""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    
    if not SCHEDULES_FILE.exists():
        SCHEDULES_FILE.write_text(json.dumps([], indent=2))

def load_schedules():
    """Load schedules from JSON file"""
    try:
        if SCHEDULES_FILE.exists():
            return json.loads(SCHEDULES_FILE.read_text())
    except Exception as e:
        logger.error(f"Error loading schedules: {e}")
    return []

def save_schedules(schedules):
    """Save schedules to JSON file"""
    try:
        ensure_config_exists()
        SCHEDULES_FILE.write_text(json.dumps(schedules, indent=2))
        return True
    except Exception as e:
        logger.error(f"Error saving schedules: {e}")
        return False

def get_next_schedule_id():
    """Generate next schedule ID"""
    schedules = load_schedules()
    if not schedules:
        return '1'
    return str(max(int(s.get('id', 0)) for s in schedules) + 1)

def send_email(recipient, subject, body, is_error=False):
    """Send notification email"""
    if not SENDER_EMAIL or not SENDER_PASSWORD:
        logger.warning(f"Email not configured. Would send to {recipient}: {subject}")
        return False
    
    try:
        message = MIMEMultipart()
        message['From'] = SENDER_EMAIL
        message['To'] = recipient
        message['Subject'] = subject

        html_body = f"""
        <html>
            <body style="font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px;">
                <div style="max-width: 600px; margin: 0 auto; background-color: white; padding: 20px; border-radius: 8px;">
                    <h2 style="color: {'#d32f2f' if is_error else '#388e3c'}; margin-top: 0;">
                        {'❌ Sync Failed' if is_error else '✅ Sync Completed'}
                    </h2>
                    <div style="line-height: 1.6; color: #333;">
                        {body}
                    </div>
                    <hr style="margin: 20px 0; border: none; border-top: 1px solid #eee;">
                    <p style="color: #999; font-size: 12px; margin-bottom: 0;">
                        USB Sync Manager<br>
                        {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                    </p>
                </div>
            </body>
        </html>
        """

        message.attach(MIMEText(html_body, 'html'))

        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            server.send_message(message)

        logger.info(f"Email sent to {recipient}")
        return True
    except Exception as e:
        logger.error(f"Error sending email to {recipient}: {e}")
        return False

def execute_rsync(schedule):
    """Execute rsync backup operation"""
    schedule_id = schedule['id']
    schedule_name = schedule['name']
    source = schedule['usbSource']
    destination = schedule['nasDestination']
    notification_email = schedule['notificationEmail']

    logger.info(f"[{schedule_name}] Starting rsync: {source} -> {destination}")

    # Validate paths
    source_path = Path(source)
    if not source_path.exists():
        error_msg = f"Source path does not exist: {source}"
        logger.error(f"[{schedule_name}] {error_msg}")
        send_email(notification_email, 
                   f"❌ Sync Failed: {schedule_name}",
                   f"<strong>Error:</strong> {error_msg}",
                   is_error=True)
        return False

    # Create destination if it doesn't exist
    Path(destination).mkdir(parents=True, exist_ok=True)

    # Build rsync command
    rsync_cmd = [
        'rsync',
        '-av',
        '--delete',
        '--no-perms',
        '--no-owner',
        '--no-group',
        '--ignore-times',
        '--log-file', str(LOGS_DIR / f'rsync-{schedule_id}.log'),
        f'{source}/',
        destination
    ]

    try:
        result = subprocess.run(
            rsync_cmd,
            capture_output=True,
            text=True,
            timeout=3600*10  # 10 hour timeout
        )

        # Rsync exit codes:
        # 0 = success
        # 23 = partial transfer (files transferred but some attributes couldn't be set)
        # This is normal in containers where permissions can't be set
        if result.returncode in [0, 23]:
            success_msg = f"""
            <p><strong>Backup completed successfully</strong></p>
            <p><strong>Source:</strong> {source}</p>
            <p><strong>Destination:</strong> {destination}</p>
            <p><strong>Completed at:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            """
            logger.info(f"[{schedule_name}] Sync completed successfully")
            send_email(notification_email,
                       f"✅ Sync Completed: {schedule_name}",
                       success_msg,
                       is_error=False)
            return True
        else:
            error_msg = result.stderr or result.stdout
            logger.error(f"[{schedule_name}] Rsync failed: {error_msg}")
            send_email(notification_email,
                       f"❌ Sync Failed: {schedule_name}",
                       f"<strong>Error:</strong> {error_msg}",
                       is_error=True)
            return False

    except subprocess.TimeoutExpired:
        error_msg = "Rsync operation timed out (exceeded 1 hour)"
        logger.error(f"[{schedule_name}] {error_msg}")
        send_email(notification_email,
                   f"❌ Sync Failed: {schedule_name}",
                   f"<strong>Error:</strong> {error_msg}",
                   is_error=True)
        return False
    except Exception as e:
        logger.error(f"[{schedule_name}] Exception: {e}")
        send_email(notification_email,
                   f"❌ Sync Failed: {schedule_name}",
                   f"<strong>Error:</strong> {str(e)}",
                   is_error=True)
        return False

def schedule_job(schedule):
    """Add a job to the scheduler"""
    schedule_id = schedule['id']
    frequency = schedule['frequency']
    
    # Remove existing job if it exists
    try:
        scheduler.remove_job(f'sync-{schedule_id}')
    except:
        pass

    if not schedule['isActive']:
        return

    try:
        if frequency == 'daily':
            hour, minute = map(int, schedule['time'].split(':'))
            trigger = CronTrigger(hour=hour, minute=minute, timezone=pytz.timezone(os.environ.get('TZ', 'UTC')))
        elif frequency == 'weekly':
            hour, minute = map(int, schedule['time'].split(':'))
            day_map = {'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3, 
                      'friday': 4, 'saturday': 5, 'sunday': 6}
            day = day_map.get(schedule['dayOfWeek'].lower(), 0)
            trigger = CronTrigger(day_of_week=day, hour=hour, minute=minute, timezone=pytz.timezone(os.environ.get('TZ', 'UTC')))
        elif frequency == 'monthly':
            hour, minute = map(int, schedule['time'].split(':'))
            day = int(schedule['dayOfMonth'])
            trigger = CronTrigger(day=day, hour=hour, minute=minute, timezone=pytz.timezone(os.environ.get('TZ', 'UTC')))
        else:
            logger.error(f"Unknown frequency: {frequency}")
            return

        scheduler.add_job(
            execute_rsync,
            trigger=trigger,
            args=[schedule],
            id=f'sync-{schedule_id}',
            name=schedule['name']
        )
        logger.info(f"✓ Scheduled job: {schedule['name']}")
        logger.info(f"  ID: {schedule_id}")
        logger.info(f"  Frequency: {frequency}")
        logger.info(f"  Time: {schedule['time']} (system timezone: {os.environ.get('TZ', 'UTC')})")
        logger.info(f"  Source: {schedule['usbSource']}")
        logger.info(f"  Destination: {schedule['nasDestination']}")
    except Exception as e:
        logger.error(f"Error scheduling job: {e}")

def reload_schedules():
    """Reload all schedules from storage"""
    schedules = load_schedules()
    
    # Remove all existing jobs
    for job in scheduler.get_jobs():
        scheduler.remove_job(job.id)
    
    # Add all active schedules
    for schedule in schedules:
        schedule_job(schedule)

# ===========================
# API Routes
# ===========================

@app.route('/api/schedules', methods=['GET'])
def get_schedules():
    """Get all schedules"""
    schedules = load_schedules()
    return jsonify(schedules)

@app.route('/api/schedules', methods=['POST'])
def create_schedule():
    """Create a new schedule"""
    data = request.json
    
    # Validate required fields
    required = ['name', 'usbSource', 'nasDestination', 'frequency', 'time', 'notificationEmail']
    if not all(field in data for field in required):
        return jsonify({'error': 'Missing required fields'}), 400

    schedule = {
        'id': get_next_schedule_id(),
        'name': data['name'],
        'usbSource': data['usbSource'],
        'nasDestination': data['nasDestination'],
        'frequency': data['frequency'],
        'dayOfWeek': data.get('dayOfWeek', 'monday'),
        'dayOfMonth': data.get('dayOfMonth', '1'),
        'time': data['time'],
        'notificationEmail': data['notificationEmail'],
        'isActive': data.get('isActive', True),
        'createdAt': datetime.now().isoformat()
    }

    schedules = load_schedules()
    schedules.append(schedule)
    
    if save_schedules(schedules):
        schedule_job(schedule)
        return jsonify(schedule), 201
    
    return jsonify({'error': 'Failed to save schedule'}), 500

@app.route('/api/schedules/<schedule_id>', methods=['GET'])
def get_schedule(schedule_id):
    """Get a specific schedule"""
    schedules = load_schedules()
    for schedule in schedules:
        if schedule['id'] == schedule_id:
            return jsonify(schedule)
    return jsonify({'error': 'Schedule not found'}), 404

@app.route('/api/schedules/<schedule_id>', methods=['PUT'])
def update_schedule(schedule_id):
    """Update a schedule"""
    data = request.json
    schedules = load_schedules()
    
    for i, schedule in enumerate(schedules):
        if schedule['id'] == schedule_id:
            updated = {**schedule, **data}
            updated['modifiedAt'] = datetime.now().isoformat()
            schedules[i] = updated
            
            if save_schedules(schedules):
                reload_schedules()
                return jsonify(updated)
            return jsonify({'error': 'Failed to update schedule'}), 500
    
    return jsonify({'error': 'Schedule not found'}), 404

@app.route('/api/schedules/<schedule_id>', methods=['DELETE'])
def delete_schedule(schedule_id):
    """Delete a schedule"""
    schedules = load_schedules()
    schedules = [s for s in schedules if s['id'] != schedule_id]
    
    if save_schedules(schedules):
        try:
            scheduler.remove_job(f'sync-{schedule_id}')
        except:
            pass
        return jsonify({'message': 'Schedule deleted'}), 200
    
    return jsonify({'error': 'Failed to delete schedule'}), 500

@app.route('/api/schedules/<schedule_id>/test', methods=['POST'])
def test_schedule_now(schedule_id):
    """Manually trigger a schedule test - runs immediately"""
    try:
        schedules = load_schedules()
        schedule = None
        for s in schedules:
            if s['id'] == schedule_id:
                schedule = s
                break
        
        if not schedule:
            return jsonify({
                'success': False,
                'error': 'Schedule not found'
            }), 404
        
        # Start test in background
        def run_test():
            try:
                logger.info(f'[TEST] Starting manual test for schedule: {schedule_id} - {schedule["name"]}')
                
                source = schedule['usbSource']
                destination = schedule['nasDestination']
                
                if not os.path.exists(source):
                    raise Exception(f'Source path does not exist: {source}')
                
                # Create destination if needed
                os.makedirs(destination, exist_ok=True)
                
                # Run rsync with detailed output
                cmd = [
                    'rsync',
                    '-av',
                    '--delete',
                    '--no-perms',
                    '--no-owner',
                    '--no-group',
                    '--ignore-times',
                    f'{source}/',
                    f'{destination}/'
                ]
                
                logger.info(f'[TEST] Running command: {" ".join(cmd)}')
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
                
                # Rsync code 23 = partial transfer (normal in containers)
                success = result.returncode in [0, 23]
                output = result.stdout + result.stderr
                
                log_message = f'[TEST] Rsync completed: {"SUCCESS" if success else "FAILED"}'
                logger.info(log_message)
                
                # Send notification if email configured
                if schedule.get('notificationEmail'):
                    subject = f'[TEST] USB Sync - {schedule["name"]}'
                    body = f'''
Test execution for schedule: {schedule["name"]}

Status: {"✓ SUCCESS" if success else "✗ FAILED"}
Source: {source}
Destination: {destination}

Command output:
{output[-1000:]}  # Last 1000 chars

Timestamp: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
                    '''
                    
                    try:
                        send_email(schedule['notificationEmail'], subject, body)
                        logger.info(f'[TEST] Notification email sent to {schedule["notificationEmail"]}')
                    except Exception as email_error:
                        logger.error(f'[TEST] Failed to send email: {email_error}')
            
            except Exception as e:
                logger.error(f'[TEST] Error in manual test: {str(e)}')
                if schedule.get('notificationEmail'):
                    try:
                        send_email(
                            schedule['notificationEmail'],
                            f'[TEST FAILED] USB Sync - {schedule["name"]}',
                            f'Test execution failed:\n{str(e)}'
                        )
                    except:
                        pass
        
        # Run in thread so response returns immediately
        import threading
        thread = threading.Thread(target=run_test)
        thread.daemon = True
        thread.start()
        
        return jsonify({
            'success': True,
            'message': f'Test started for schedule: {schedule["name"]}',
            'schedule_id': schedule_id,
            'notification': 'Check logs and email for results'
        })
    
    except Exception as e:
        logger.error(f'Test schedule error: {str(e)}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/usb-drives', methods=['GET'])
def get_usb_drives():
    """Get connected USB drives"""
    drives = []
    try:
        partitions = psutil.disk_partitions()
        for partition in partitions:
            if 'removable' in partition.opts or '/media' in partition.mountpoint or '/mnt' in partition.mountpoint:
                drives.append({
                    'device': partition.device,
                    'path': partition.mountpoint,
                    'fstype': partition.fstype
                })
    except Exception as e:
        logger.error(f"Error getting USB drives: {e}")
    
    return jsonify(drives)

@app.route('/api/folders/search', methods=['POST'])
def search_folders():
    """Get immediate child folders from a path (not recursive)"""
    try:
        data = request.json
        base_path = data.get('path', '/')
        
        if not os.path.exists(base_path):
            return jsonify({
                'success': False,
                'error': f'Path does not exist: {base_path}'
            }), 404
        
        if not os.path.isdir(base_path):
            return jsonify({
                'success': False,
                'error': f'Path is not a directory: {base_path}'
            }), 400
        
        folders = []
        
        try:
            for item in sorted(os.listdir(base_path)):
                item_path = os.path.join(base_path, item)
                if os.path.isdir(item_path):
                    try:
                        # Check if readable
                        os.listdir(item_path)
                        folders.append({
                            'name': item,
                            'path': item_path,
                            'isFolder': True
                        })
                    except PermissionError:
                        # Still show folder but mark as restricted
                        folders.append({
                            'name': item + ' (restricted)',
                            'path': item_path,
                            'isFolder': True,
                            'restricted': True
                        })
        except (PermissionError, OSError):
            return jsonify({
                'success': False,
                'error': f'Permission denied reading: {base_path}'
            }), 403
        
        return jsonify({
            'success': True,
            'folders': folders,
            'currentPath': base_path,
            'count': len(folders),
            'parentPath': os.path.dirname(base_path) if base_path != '/' else '/'
        })
    
    except Exception as e:
        logger.error(f'Folder search error: {str(e)}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/folders/create', methods=['POST'])
def create_folder():
    """Create a new folder at specified path"""
    try:
        data = request.json
        path = data.get('path')
        
        if not path:
            return jsonify({
                'success': False,
                'error': 'Path is required'
            }), 400
        
        # Security check - don't allow creating outside safe paths
        safe_paths = ['/media', '/mnt', '/volume', '/Volumes', '/backups']
        is_safe = any(path.startswith(safe_path) for safe_path in safe_paths)
        
        if not is_safe:
            return jsonify({
                'success': False,
                'error': 'Can only create folders in USB/backup paths'
            }), 403
        
        if os.path.exists(path):
            return jsonify({
                'success': False,
                'error': 'Folder already exists'
            }), 409
        
        # Create with parents
        os.makedirs(path, exist_ok=True)
        
        logger.info(f'Created folder: {path}')
        
        return jsonify({
            'success': True,
            'path': path,
            'message': f'Folder created: {path}'
        })
    
    except Exception as e:
        logger.error(f'Folder creation error: {str(e)}')
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/system/status', methods=['GET'])
def get_system_status():
    """Get system status"""
    try:
        disk_usage = psutil.disk_usage('/')
        memory = psutil.virtual_memory()
        
        return jsonify({
            'timestamp': datetime.now().isoformat(),
            'disk': {
                'total': disk_usage.total,
                'used': disk_usage.used,
                'free': disk_usage.free,
                'percent': disk_usage.percent
            },
            'memory': {
                'total': memory.total,
                'used': memory.used,
                'free': memory.free,
                'percent': memory.percent
            },
            'jobs_scheduled': len(scheduler.get_jobs()),
            'jobs': [
                {'id': job.id, 'name': job.name, 'next_run': job.next_run_time.isoformat() if job.next_run_time else None}
                for job in scheduler.get_jobs()
            ]
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/timezone', methods=['GET'])
def get_system_timezone():
    """Get system timezone"""
    try:
        import time
        # Get timezone from system
        tz_name = time.tzname[0] if time.daylight == 0 else time.tzname[1]
        
        # Get timezone offset
        import os
        tz_env = os.environ.get('TZ', 'UTC')
        
        return jsonify({
            'timezone': tz_env,
            'system_tz': tz_name,
            'utc_offset': datetime.now().astimezone().strftime('%z')
        })
    except Exception as e:
        return jsonify({
            'timezone': 'UTC',
            'error': str(e)
        }), 200

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})

@app.route('/api/test-email', methods=['POST'])
def test_email():
    """Test email configuration"""
    data = request.json
    email = data.get('email')
    
    if not email:
        return jsonify({'error': 'Email required'}), 400
    
    success = send_email(
        email,
        "✅ USB Sync Manager - Test Email",
        "<p>This is a test email to verify your notification settings are working correctly.</p>",
        is_error=False
    )
    
    if success:
        return jsonify({'message': 'Test email sent successfully'})
    else:
        return jsonify({'error': 'Failed to send test email. Check email configuration.'}), 500

# ===========================
# Application Startup
# ===========================

def init_app():
    """Initialize application"""
    ensure_config_exists()
    
    # Start scheduler
    scheduler.start()
    
    # Load all schedules
    reload_schedules()
    
    logger.info("=" * 70)
    logger.info("USB Sync Manager initialized")
    logger.info(f"Configuration directory: {CONFIG_DIR}")
    logger.info(f"Schedules loaded: {len(load_schedules())}")
    logger.info(f"Scheduler running: {scheduler.running}")
    logger.info(f"Email configured: {bool(SENDER_EMAIL)}")
    logger.info("=" * 70)

if __name__ == '__main__':
    init_app()
    # Run with debug=False for production
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)