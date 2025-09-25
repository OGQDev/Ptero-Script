#!/bin/bash

# Pterodactyl Panel + Wings Installation Script
# Based on official Pterodactyl documentation
# Supports Ubuntu 20.04+ and Debian 10+

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_question() {
    echo -e "${BLUE}[QUESTION]${NC} $1"
}

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Function to detect timezone
detect_timezone() {
    # Try to get timezone from system
    if [[ -f /etc/timezone ]]; then
        TIMEZONE=$(cat /etc/timezone)
    elif [[ -L /etc/localtime ]]; then
        TIMEZONE=$(readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||')
    else
        # Fallback to UTC if detection fails
        TIMEZONE="UTC"
    fi
    
    # Validate timezone using PHP
    if ! php -r "new DateTimeZone('$TIMEZONE');" 2>/dev/null; then
        print_warning "Detected timezone '$TIMEZONE' is invalid, falling back to UTC"
        TIMEZONE="UTC"
    fi
    
    print_status "Auto-detected timezone: $TIMEZONE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi

    case $OS in
        "Ubuntu")
            if [[ $VER < "20.04" ]]; then
                print_error "Ubuntu 20.04 or higher is required"
                exit 1
            fi
            ;;
        "Debian GNU/Linux")
            if [[ $VER < "10" ]]; then
                print_error "Debian 10 or higher is required"
                exit 1
            fi
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    print_status "Detected OS: $OS $VER"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing system dependencies..."
    
    apt update && apt upgrade -y
    
    # Install basic dependencies
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg
    
    # Add PHP repository
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    
    apt update
}

# Function to install Panel dependencies
install_panel_dependencies() {
    print_status "Installing Panel dependencies..."
    
    # Install PHP and required extensions
    apt install -y php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

# Function to install Wings dependencies
install_wings_dependencies() {
    print_status "Installing Wings dependencies..."
    
    # Install Docker
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    
    # Install Docker Compose
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Enable swap accounting
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& swapaccount=1/' /etc/default/grub
    update-grub
}

# Function to setup database
setup_database() {
    print_status "Setting up database..."
    
    # Generate random password
    DB_PASSWORD=$(generate_password)
    
    # Secure MySQL installation
    mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
    mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mysql -u root -e "DROP DATABASE IF EXISTS test;"
    mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    
    # Drop existing pterodactyl database if it exists
    mysql -u root -e "DROP DATABASE IF EXISTS pterodactyl;" 2>/dev/null || true
    mysql -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null || true
    
    # Create database and user
    mysql -u root -e "CREATE DATABASE pterodactyl;"
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON pterodactyl.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"
    
    print_status "Database created with password: $DB_PASSWORD"
    echo "$DB_PASSWORD" > /root/pterodactyl_db_password.txt
    chmod 600 /root/pterodactyl_db_password.txt
}

# Function to install Pterodactyl Panel
install_panel() {
    print_status "Installing Pterodactyl Panel..."
    
    # Create directory and download Panel
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    
    # Setup environment first
    if [[ -f .env.example ]]; then
        cp .env.example .env
    else
        # Create minimal .env file if .env.example doesn't exist
        touch .env
    fi
    
    # Generate a proper app key and ensure it's set correctly
    APP_KEY=$(php -r "echo 'base64:'.base64_encode(random_bytes(32));")
    
    # Ensure we have a proper .env file with required settings
    cat > .env << EOF
APP_NAME=Pterodactyl
APP_ENV=production
APP_KEY=${APP_KEY}
APP_DEBUG=false
APP_URL=http://localhost
APP_TIMEZONE=UTC

LOG_CHANNEL=stack
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=pterodactyl
DB_USERNAME=pterodactyl
DB_PASSWORD=

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DRIVER=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

MEMCACHED_HOST=127.0.0.1

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379

MAIL_MAILER=smtp
MAIL_HOST=mailhog
MAIL_PORT=1025
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=null
MAIL_FROM_NAME="\${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=
AWS_USE_PATH_STYLE_ENDPOINT=false

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=
PUSHER_APP_CLUSTER=mt1

MIX_PUSHER_APP_KEY="\${PUSHER_APP_KEY}"
MIX_PUSHER_APP_CLUSTER="\${PUSHER_APP_CLUSTER}"
EOF
    
    # Export the APP_KEY as environment variable as backup
    export APP_KEY="${APP_KEY}"
    
    # Install composer dependencies
    composer install --no-dev --optimize-autoloader
    
    # Generate the final application key (this will overwrite the temporary one)
    php artisan key:generate --force
    
    # Configure environment
    DB_PASSWORD=$(cat /root/pterodactyl_db_password.txt)
    
    sed -i "s|APP_URL=.*|APP_URL=https://${DOMAIN}|g" .env
    sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|g" .env
    sed -i "s|DB_PORT=.*|DB_PORT=3306|g" .env
    sed -i "s|DB_DATABASE=.*|DB_DATABASE=pterodactyl|g" .env
    sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|g" .env
    sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" .env
    
    # Setup application
    php artisan p:environment:setup --author="$EMAIL" --url="https://$DOMAIN" --timezone="$TIMEZONE" --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=true
    
    # Setup database
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=pterodactyl --username=pterodactyl --password="$DB_PASSWORD"
    
    # Run migrations
    php artisan migrate --seed --force
    
    # Create admin user
    php artisan p:user:make --email="$EMAIL" --username="$ADMIN_USERNAME" --name-first="$FIRST_NAME" --name-last="$LAST_NAME" --password="$ADMIN_PASSWORD" --admin=1
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    # Setup cron
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    
    # Create systemd service for queue worker
    cat > /etc/systemd/system/pteroq.service << EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable --now pteroq.service
}

# Function to configure Nginx for Panel
configure_nginx_panel() {
    print_status "Configuring Nginx for Panel..."
    
    cat > /etc/nginx/sites-available/pterodactyl.conf << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    rm -f /etc/nginx/sites-enabled/default
    
    # Test Nginx configuration
    nginx -t
    systemctl reload nginx
}

# Function to install SSL certificate
install_ssl() {
    print_status "Installing SSL certificate with Certbot..."
    
    # Install Certbot
    apt install -y certbot python3-certbot-nginx
    
    # Generate certificate
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect
    
    # Setup auto-renewal
    systemctl enable certbot.timer
}

# Function to install Wings
install_wings() {
    print_status "Installing Pterodactyl Wings..."
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    # Create Wings systemd service
    cat > /etc/systemd/system/wings.service << EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable wings
    
    print_warning "Wings installed but not started. You need to configure it first:"
    print_warning "1. Create a node in the Panel"
    print_warning "2. Copy the configuration to /etc/pterodactyl/config.yml"
    print_warning "3. Start Wings with: systemctl start wings"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Install UFW if not installed
    apt install -y ufw
    
    # Reset UFW
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    if [[ "$INSTALL_TYPE" == "panel" || "$INSTALL_TYPE" == "both" ]]; then
        # Panel ports
        ufw allow 80/tcp
        ufw allow 443/tcp
    fi
    
    if [[ "$INSTALL_TYPE" == "wings" || "$INSTALL_TYPE" == "both" ]]; then
        # Wings ports
        ufw allow 8080/tcp
        ufw allow 2022/tcp
        # Game server ports (you may want to customize this range)
        ufw allow 25565:25665/tcp
        ufw allow 25565:25665/udp
    fi
    
    # Enable UFW
    ufw --force enable
}

# Function to display completion message
display_completion() {
    echo ""
    echo "========================================"
    print_status "Installation completed!"
    echo "========================================"
    
    if [[ "$INSTALL_TYPE" == "panel" || "$INSTALL_TYPE" == "both" ]]; then
        echo "Panel Information:"
        echo "  URL: https://$DOMAIN"
        echo "  Admin Email: $EMAIL"
        echo "  Admin Username: $ADMIN_USERNAME"
        echo "  Admin Password: $ADMIN_PASSWORD"
        echo "  Database Password: $(cat /root/pterodactyl_db_password.txt)"
        echo ""
    fi
    
    if [[ "$INSTALL_TYPE" == "wings" || "$INSTALL_TYPE" == "both" ]]; then
        echo "Wings Information:"
        echo "  Configuration file: /etc/pterodactyl/config.yml"
        echo "  Service: systemctl start wings"
        echo ""
        print_warning "Remember to configure Wings through the Panel before starting the service!"
    fi
    
    echo "Important files:"
    echo "  Database password: /root/pterodactyl_db_password.txt"
    echo "  Panel location: /var/www/pterodactyl"
    echo "  Wings config: /etc/pterodactyl/"
    echo ""
    print_warning "Please save this information securely!"
}

# Main installation function
main() {
    print_status "Starting Pterodactyl installation script..."
    
    # Check if running as root
    check_root
    
    # Detect OS
    detect_os
    
    # Get installation type
    echo ""
    print_question "What would you like to install?"
    echo "1) Panel only"
    echo "2) Wings only" 
    echo "3) Both Panel and Wings"
    read -p "Choose an option (1-3): " INSTALL_CHOICE
    
    case $INSTALL_CHOICE in
        1) INSTALL_TYPE="panel" ;;
        2) INSTALL_TYPE="wings" ;;
        3) INSTALL_TYPE="both" ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
    
    # Common inputs
    if [[ "$INSTALL_TYPE" == "panel" || "$INSTALL_TYPE" == "both" ]]; then
        echo ""
        read -p "Enter domain name (e.g., panel.example.com): " DOMAIN
        read -p "Enter email address: " EMAIL
        
        # Auto-detect timezone
        detect_timezone
        
        read -p "Enter admin username: " ADMIN_USERNAME
        read -p "Enter admin first name: " FIRST_NAME
        read -p "Enter admin last name: " LAST_NAME
        
        # Generate admin password
        ADMIN_PASSWORD=$(generate_password)
        print_status "Generated admin password: $ADMIN_PASSWORD"
    fi
    
    # Install dependencies
    install_dependencies
    
    if [[ "$INSTALL_TYPE" == "panel" || "$INSTALL_TYPE" == "both" ]]; then
        install_panel_dependencies
        setup_database
        install_panel
        configure_nginx_panel
        
        # Ask about SSL
        read -p "Do you want to install SSL certificate with Let's Encrypt? (y/n): " INSTALL_SSL_CHOICE
        if [[ "$INSTALL_SSL_CHOICE" =~ ^[Yy]$ ]]; then
            install_ssl
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "wings" || "$INSTALL_TYPE" == "both" ]]; then
        install_wings_dependencies
        install_wings
        
        if [[ "$INSTALL_TYPE" == "both" ]]; then
            print_warning "A reboot is recommended to enable swap accounting for Docker."
            read -p "Do you want to reboot now? (y/n): " REBOOT_CHOICE
            if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
                print_status "System will reboot in 5 seconds..."
                sleep 5
                reboot
            fi
        fi
    fi
    
    # Configure firewall
    configure_firewall
    
    # Display completion message
    display_completion
}

# Run main function
main "$@"
