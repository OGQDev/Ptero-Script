#!/bin/bash

# Pterodactyl Panel & Wings Installation Script for Ubuntu 24.04
# Based on Official Pterodactyl Documentation v1.11
# Created by GitHub Copilot
# Date: September 25, 2025

set -e  # Exit on any error

# Global variables
RUNNING_AS_ROOT=false
PANEL_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_FIRSTNAME=""
ADMIN_LASTNAME=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
MYSQL_ROOT_PASSWORD=""

# Color definitions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        RUNNING_AS_ROOT=true
        print_status "Running as root user."
    else
        RUNNING_AS_ROOT=false
    fi
}

# Function to check if user has sudo privileges
check_sudo() {
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        return 0  # Root doesn't need sudo
    fi
    
    if ! sudo -l &>/dev/null; then
        print_error "Current user does not have sudo privileges."
        print_status "Please add your user to the sudo group:"
        print_status "  su - root"
        print_status "  usermod -aG sudo $(whoami)"
        print_status "  exit"
        print_status "  # Then log out and log back in"
        exit 1
    fi
}

# Function to check Ubuntu version
check_ubuntu_version() {
    if ! lsb_release -d | grep -q "Ubuntu 24.04"; then
        print_warning "This script is designed for Ubuntu 24.04. Continuing anyway..."
        read -p "Press Enter to continue or Ctrl+C to exit..."
    fi
}

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        apt update && apt upgrade -y
        apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release
    else
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release
    fi
}

# Function to add required repositories
add_repositories() {
    print_status "Adding required repositories..."
    
    # Add Redis repository
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
        apt update
    else
        curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
        sudo apt update
    fi
}

# Function to install Panel dependencies
install_panel_dependencies() {
    print_status "Installing Panel dependencies..."
    
    # Install PHP 8.3 and required extensions (from official docs)
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
            mariadb-server nginx tar unzip git redis-server
    else
        sudo apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
            mariadb-server nginx tar unzip git redis-server
    fi
}

# Function to configure MariaDB
configure_mariadb() {
    print_status "Configuring MariaDB..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        systemctl start mariadb
        systemctl enable mariadb
    else
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
        print_warning "Please run 'sudo mysql_secure_installation' after the script completes to secure MariaDB."
    fi
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        print_warning "Please run 'mysql_secure_installation' after the script completes to secure MariaDB."
    fi
    
    # Check if MariaDB root password is set
    echo -e "${CYAN}MariaDB Configuration:${NC}"
    read -s -p "Enter MariaDB root password (leave empty if not set): " mysql_root_password
    echo
    
    # Set MySQL command based on whether root password is set
    if [[ -z "$mysql_root_password" ]]; then
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            MYSQL_CMD="mysql -u root"
        else
            MYSQL_CMD="sudo mysql -u root"
        fi
    else
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            MYSQL_CMD="mysql -u root -p$mysql_root_password"
        else
            MYSQL_CMD="sudo mysql -u root -p$mysql_root_password"
        fi
    fi
    
    # Create database and user for Pterodactyl
    echo -e "${CYAN}Please enter the following database information:${NC}"
    read -p "Database name [pterodactyl]: " db_name
    db_name=${db_name:-pterodactyl}
    
    read -p "Database username [pterodactyl]: " db_user
    db_user=${db_user:-pterodactyl}
    
    read -s -p "Database password: " db_password
    echo
    
    # Check if database exists and handle accordingly
    print_status "Configuring database..."
    
    $MYSQL_CMD <<EOF
CREATE DATABASE IF NOT EXISTS ${db_name};
CREATE USER IF NOT EXISTS '${db_user}'@'127.0.0.1' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

    if [ $? -eq 0 ]; then
        print_status "Database configured successfully!"
    else
        print_error "Failed to configure database. Please check your MariaDB root password."
        exit 1
    fi
}

# Function to install Composer (from official docs)
install_composer() {
    print_status "Installing Composer..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    else
        curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    fi
}

# Function to configure MariaDB
configure_mariadb() {
    print_status "Starting and enabling MariaDB..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        systemctl start mariadb
        systemctl enable mariadb
    else
        sudo systemctl start mariadb
        sudo systemctl enable mariadb
    fi
    
    # Get database configuration
    echo -e "${CYAN}Database Configuration:${NC}"
    read -s -p "Enter MariaDB root password (leave empty if not set): " MYSQL_ROOT_PASSWORD
    echo
    
    read -p "Database name [panel]: " DB_NAME
    DB_NAME=${DB_NAME:-panel}
    
    read -p "Database username [pterodactyl]: " DB_USER
    DB_USER=${DB_USER:-pterodactyl}
    
    read -s -p "Database password: " DB_PASSWORD
    echo
    
    # Set MySQL command based on whether root password is set
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            MYSQL_CMD="mysql -u root"
        else
            MYSQL_CMD="sudo mysql -u root"
        fi
    else
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            MYSQL_CMD="mysql -u root -p$MYSQL_ROOT_PASSWORD"
        else
            MYSQL_CMD="sudo mysql -u root -p$MYSQL_ROOT_PASSWORD"
        fi
    fi
    
    # Create database and user (from official docs)
    print_status "Creating database and user..."
    $MYSQL_CMD <<EOF
CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
CREATE DATABASE IF NOT EXISTS $DB_NAME;
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

    if [ $? -eq 0 ]; then
        print_status "Database configured successfully!"
    else
        print_error "Failed to configure database. Please check your MariaDB root password."
        exit 1
    fi
}

# Function to download Pterodactyl Panel files
download_panel_files() {
    print_status "Creating Panel directory and downloading files..."
    
    # Create directory (from official docs)
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        mkdir -p /var/www/pterodactyl
        cd /var/www/pterodactyl
    else
        sudo mkdir -p /var/www/pterodactyl
        cd /var/www/pterodactyl
    fi
    
    # Check if directory has existing files and clean up
    if [[ -n "$(ls -A /var/www/pterodactyl 2>/dev/null)" ]]; then
        print_warning "Existing files found in /var/www/pterodactyl. Cleaning up..."
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            rm -rf /var/www/pterodactyl/*
        else
            sudo rm -rf /var/www/pterodactyl/*
        fi
    fi
    
    # Download panel files (from official docs)
    PANEL_VERSION=$(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    print_status "Downloading Panel version: $PANEL_VERSION"
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
        tar -xzf panel.tar.gz
        chmod -R 755 storage/* bootstrap/cache/
    else
        sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
        sudo tar -xzf panel.tar.gz
        sudo chmod -R 755 storage/* bootstrap/cache/
    fi
}

# Function to install Panel (following official docs exactly)
install_panel() {
    print_header "INSTALLING PTERODACTYL PANEL"
    
    # Get Panel configuration
    echo -e "${CYAN}Panel Configuration:${NC}"
    read -p "Enter your domain name (e.g., panel.example.com): " PANEL_DOMAIN
    read -p "Enter your email address: " ADMIN_EMAIL
    read -p "Enter admin first name: " ADMIN_FIRSTNAME
    read -p "Enter admin last name: " ADMIN_LASTNAME
    read -p "Enter admin username: " ADMIN_USERNAME
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo
    
    # Download Panel files
    download_panel_files
    
    # Copy environment file and install dependencies (EXACT order from official docs)
    print_status "Setting up environment and installing dependencies..."
    cd /var/www/pterodactyl
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        cp .env.example .env
        # CRITICAL: Run composer install BEFORE any artisan commands (from official docs)
        COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
        php artisan key:generate --force
    else
        sudo cp .env.example .env
        # CRITICAL: Run composer install BEFORE any artisan commands (from official docs)
        sudo COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
        sudo php artisan key:generate --force
    fi
    
    # Environment configuration (from official docs)
    print_status "Configuring environment..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        php artisan p:environment:setup \
            --author="$ADMIN_EMAIL" \
            --url="https://$PANEL_DOMAIN" \
            --timezone="UTC" \
            --cache="redis" \
            --session="redis" \
            --queue="redis" \
            --redis-host="127.0.0.1" \
            --redis-pass="" \
            --redis-port="6379"
        
        php artisan p:environment:database \
            --host="127.0.0.1" \
            --port="3306" \
            --database="$DB_NAME" \
            --username="$DB_USER" \
            --password="$DB_PASSWORD"
    else
        sudo php artisan p:environment:setup \
            --author="$ADMIN_EMAIL" \
            --url="https://$PANEL_DOMAIN" \
            --timezone="UTC" \
            --cache="redis" \
            --session="redis" \
            --queue="redis" \
            --redis-host="127.0.0.1" \
            --redis-pass="" \
            --redis-port="6379"
        
        sudo php artisan p:environment:database \
            --host="127.0.0.1" \
            --port="3306" \
            --database="$DB_NAME" \
            --username="$DB_USER" \
            --password="$DB_PASSWORD"
    fi
    
    # Database setup (from official docs)
    print_status "Setting up database..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        php artisan migrate --seed --force
    else
        sudo php artisan migrate --seed --force
    fi
    
    # Create first user (from official docs)
    print_status "Creating administrative user..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        php artisan p:user:make \
            --email="$ADMIN_EMAIL" \
            --username="$ADMIN_USERNAME" \
            --name-first="$ADMIN_FIRSTNAME" \
            --name-last="$ADMIN_LASTNAME" \
            --password="$ADMIN_PASSWORD" \
            --admin=1
    else
        sudo php artisan p:user:make \
            --email="$ADMIN_EMAIL" \
            --username="$ADMIN_USERNAME" \
            --name-first="$ADMIN_FIRSTNAME" \
            --name-last="$ADMIN_LASTNAME" \
            --password="$ADMIN_PASSWORD" \
            --admin=1
    fi
    
    # Set permissions (from official docs)
    print_status "Setting file permissions..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        chown -R www-data:www-data /var/www/pterodactyl/*
    else
        sudo chown -R www-data:www-data /var/www/pterodactyl/*
    fi
    
    # Setup crontab (from official docs)
    print_status "Setting up crontab..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        (crontab -u www-data -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -
    else
        (sudo crontab -u www-data -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -u www-data -
    fi
    
    # Create queue worker service (from official docs)
    create_queue_worker
    
    # Configure web server
    configure_nginx_panel
    
    print_status "Pterodactyl Panel installation completed!"
}

# Function to create queue worker service (from official docs)
create_queue_worker() {
    print_status "Creating queue worker service..."
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        tee /etc/systemd/system/pteroq.service > /dev/null <<EOF
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
        
        systemctl enable redis-server
        systemctl enable --now pteroq.service
    else
        sudo tee /etc/systemd/system/pteroq.service > /dev/null <<EOF
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
        
        sudo systemctl enable redis-server
        sudo systemctl enable --now pteroq.service
    fi
}

# Function to configure Nginx for Panel
configure_nginx_panel() {
    print_status "Configuring Nginx for Panel..."
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        tee /etc/nginx/sites-available/pterodactyl.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $PANEL_DOMAIN;

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

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
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
    else
        sudo tee /etc/nginx/sites-available/pterodactyl.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $PANEL_DOMAIN;

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

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
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
    fi

    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        systemctl reload nginx
    else
        sudo ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl reload nginx
    fi
    
    print_warning "SSL certificate is not configured. Please install Let's Encrypt SSL after the installation:"
    print_warning "  sudo apt install certbot python3-certbot-nginx"
    print_warning "  sudo certbot --nginx -d $PANEL_DOMAIN"
}

# Function to install Docker (for Wings)
install_docker() {
    print_status "Installing Docker..."
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        # Quick install from official docs
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash
        systemctl enable --now docker
    else
        # Quick install from official docs
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash
        sudo systemctl enable --now docker
        sudo usermod -aG docker $USER
    fi
    
    print_status "Docker installed successfully!"
}

# Function to install Wings
install_wings() {
    print_header "INSTALLING PTERODACTYL WINGS"
    
    # Create directory and download Wings (from official docs)
    print_status "Installing Wings..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        mkdir -p /etc/pterodactyl
        curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
        chmod u+x /usr/local/bin/wings
    else
        sudo mkdir -p /etc/pterodactyl
        sudo curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
        sudo chmod u+x /usr/local/bin/wings
    fi
    
    # Get Wings version
    WINGS_VERSION=$(curl -s https://api.github.com/repos/pterodactyl/wings/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    print_status "Installed Wings version: $WINGS_VERSION"
    
    # Create systemd service (from official docs)
    print_status "Creating Wings systemd service..."
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        tee /etc/systemd/system/wings.service > /dev/null <<EOF
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
    else
        sudo tee /etc/systemd/system/wings.service > /dev/null <<EOF
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
        
        sudo systemctl enable wings
    fi
    
    print_status "Wings installation completed!"
    print_warning "Wings is installed but not configured yet."
    print_warning "You need to:"
    print_warning "1. Create a node in your Panel"
    print_warning "2. Copy the configuration from the Panel to /etc/pterodactyl/config.yml"
    print_warning "3. Start Wings with: sudo systemctl start wings"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
        # Install UFW if not already installed
        apt install -y ufw
        
        # Configure firewall rules
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH
        ufw allow ssh
        
        # Allow HTTP and HTTPS
        ufw allow 80
        ufw allow 443
        
        # Allow Wings ports (if Wings is being installed)
        if [[ "$install_option" == "2" || "$install_option" == "3" ]]; then
            ufw allow 8080
            ufw allow 2022
        fi
        
        # Enable firewall
        ufw --force enable
    else
        # Install UFW if not already installed
        sudo apt install -y ufw
        
        # Configure firewall rules
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Allow SSH
        sudo ufw allow ssh
        
        # Allow HTTP and HTTPS
        sudo ufw allow 80
        sudo ufw allow 443
        
        # Allow Wings ports (if Wings is being installed)
        if [[ "$install_option" == "2" || "$install_option" == "3" ]]; then
            sudo ufw allow 8080
            sudo ufw allow 2022
        fi
        
        # Enable firewall
        sudo ufw --force enable
    fi
    
    print_status "Firewall configured successfully!"
}

# Function to show post-installation instructions
show_post_install() {
    print_header "INSTALLATION COMPLETED"
    
    echo -e "${GREEN}Installation Summary:${NC}"
    
    if [[ "$install_option" == "1" || "$install_option" == "3" ]]; then
        echo -e "${CYAN}Pterodactyl Panel:${NC}"
        echo -e "  URL: https://$PANEL_DOMAIN"
        echo -e "  Admin Email: $ADMIN_EMAIL"
        echo -e "  Admin Username: $ADMIN_USERNAME"
        echo -e "  Database: $DB_NAME"
        echo -e "  Database User: $DB_USER"
        echo ""
        echo -e "${YELLOW}IMPORTANT: Your APP_KEY has been generated and saved to /var/www/pterodactyl/.env${NC}"
        echo -e "${YELLOW}Please backup this key as it's required for data recovery!${NC}"
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            echo -e "  Run: grep APP_KEY /var/www/pterodactyl/.env"
        else
            echo -e "  Run: sudo grep APP_KEY /var/www/pterodactyl/.env"
        fi
        echo ""
    fi
    
    if [[ "$install_option" == "2" || "$install_option" == "3" ]]; then
        echo -e "${CYAN}Pterodactyl Wings:${NC}"
        echo -e "  Status: Installed but needs configuration"
        echo -e "  Config Location: /etc/pterodactyl/config.yml"
        echo ""
    fi
    
    echo -e "${YELLOW}Next Steps:${NC}"
    
    if [[ "$install_option" == "1" || "$install_option" == "3" ]]; then
        echo -e "1. Install SSL certificate:"
        echo -e "   sudo apt install certbot python3-certbot-nginx"
        echo -e "   sudo certbot --nginx -d $PANEL_DOMAIN"
        echo ""
        echo -e "2. Secure MariaDB:"
        echo -e "   sudo mysql_secure_installation"
        echo ""
    fi
    
    if [[ "$install_option" == "2" || "$install_option" == "3" ]]; then
        echo -e "3. Configure Wings:"
        echo -e "   - Create a node in your Panel"
        echo -e "   - Copy the auto-deploy command from Panel"
        if [[ "$RUNNING_AS_ROOT" == "true" ]]; then
            echo -e "   - Run: systemctl start wings"
        else
            echo -e "   - Run: sudo systemctl start wings"
        fi
        echo ""
    fi
    
    echo -e "4. Reboot your server to ensure all services start properly:"
    echo -e "   sudo reboot"
    echo ""
    
    print_status "Installation completed successfully! Please follow the next steps above."
}

# Main menu function
show_menu() {
    clear
    print_header "PTERODACTYL INSTALLATION SCRIPT"
    echo -e "${CYAN}Ubuntu 24.04 Compatible - Following Official Documentation${NC}"
    echo ""
    echo -e "${YELLOW}Installation Options:${NC}"
    echo -e "1) Install Pterodactyl Panel (Latest Version)"
    echo -e "2) Install Wings (Latest Version)"
    echo -e "3) Install Both Panel + Wings (Latest Version)"
    echo -e "4) Exit"
    echo ""
    read -p "Please select an option [1-4]: " install_option
}

# Main installation function
main() {
    # Initial checks
    check_root
    check_sudo
    check_ubuntu_version
    
    # Show menu
    show_menu
    
    case $install_option in
        1)
            print_header "INSTALLING PTERODACTYL PANEL ONLY"
            update_system
            add_repositories
            install_panel_dependencies
            install_composer
            configure_mariadb
            install_panel
            configure_firewall
            show_post_install
            ;;
        2)
            print_header "INSTALLING PTERODACTYL WINGS ONLY"
            update_system
            install_docker
            install_wings
            configure_firewall
            show_post_install
            ;;
        3)
            print_header "INSTALLING PTERODACTYL PANEL + WINGS"
            update_system
            add_repositories
            install_panel_dependencies
            install_composer
            install_docker
            configure_mariadb
            install_panel
            install_wings
            configure_firewall
            show_post_install
            ;;
        4)
            print_status "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option selected."
            exit 1
            ;;
    esac
}

# Trap to handle script interruption
trap 'print_error "Script interrupted. Exiting..."; exit 1' INT TERM

# Run main function
main
