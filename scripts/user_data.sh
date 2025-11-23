#!/bin/bash
set -e

# Update system packages
echo "=== Updating system packages ==="
apt-get update -y

# Install dependencies
echo "=== Installing dependencies ==="
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    nginx \
    supervisor

# Create application user
echo "=== Creating application user ==="
useradd -m -s /bin/bash appuser || true

# Create application directory
APP_DIR="/opt/${project_name}"
echo "=== Creating application directory: $APP_DIR ==="
mkdir -p $APP_DIR
cd $APP_DIR

# Clone application repository
echo "=== Cloning application from ${github_repo} ==="
git clone -b ${github_branch} ${github_repo} .

# Create Python virtual environment
echo "=== Creating Python virtual environment ==="
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install Python dependencies
echo "=== Installing Python dependencies ==="
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
else
    pip install flask gunicorn python-dotenv
fi

# Create environment file
echo "=== Creating environment configuration ==="
cat > .env <<EOF
FLASK_APP=app.py
FLASK_ENV=${environment}
PORT=${app_port}
PROJECT_NAME=${project_name}
ENVIRONMENT=${environment}
EOF

# Initialize the database if the app has init-db command
echo "=== Initializing database ==="
export FLASK_APP=app.py
if flask --help 2>/dev/null | grep -q "init-db"; then
    echo "Found init-db command, initializing database..."
    flask init-db || echo "Database initialization failed or already initialized"
else
    echo "No init-db command found, skipping database initialization"
fi

# Set proper permissions
chown -R appuser:appuser $APP_DIR

# Create log directory
mkdir -p /var/log/${project_name}
chown appuser:appuser /var/log/${project_name}

# Configure Gunicorn with Supervisor
echo "=== Configuring Gunicorn ==="
cat > /etc/supervisor/conf.d/${project_name}.conf <<EOF
[program:${project_name}]
directory=$APP_DIR
command=$APP_DIR/venv/bin/gunicorn --bind 0.0.0.0:${app_port} --workers 4 --threads 2 --timeout 60 --access-logfile - --error-logfile - app:app
user=appuser
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/${project_name}/error.log
stdout_logfile=/var/log/${project_name}/access.log
environment=PATH="$APP_DIR/venv/bin"
EOF

# Configure Nginx
echo "=== Configuring Nginx ==="
cat > /etc/nginx/sites-available/${project_name} <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${app_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Enable Nginx site
ln -sf /etc/nginx/sites-available/${project_name} /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Start application services
echo "=== Starting application services ==="
supervisorctl reread
supervisorctl update
supervisorctl start ${project_name}

# Restart and enable Nginx
systemctl restart nginx
systemctl enable nginx
systemctl enable supervisor

echo "=== Deployment completed successfully ==="
echo "Application is running on port ${app_port}"
echo "Nginx is proxying requests on port 80"

# Final status check
sleep 10
curl -f http://localhost:${app_port} || echo "Warning: Application might not be responding yet"
curl -f http://localhost/health || echo "Warning: Nginx health check failed"