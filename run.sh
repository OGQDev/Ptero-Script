#!/bin/bash

# Pterodactyl Panel & Wings Installation Script for Ubuntu 24.04
# Created by GitHub Copilot
# Date: September 25, 2025

set -e  # Exit on any error

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
        print_error "This script should not be run as root for security reasons."
        print_warning "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check if user has sudo privileges
check_sudo() {
    if ! sudo -l &>/dev/null; then
        print_error "Current user does not have sudo privileges."
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
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release
}

# Function to install required dependencies
install_dependencies() {
    print_status "Installing required dependencies..."
    sudo apt install -y php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl,sqlite3,redis} \
        mariadb-server nginx tar unzip git redis-server cron
}

# Function to configure MariaDB
configure_mariadb() {
    print_status "Configuring MariaDB..."
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    
    print_warning "Please run 'sudo mysql_secure_installation' after the script completes to secure MariaDB."
    
    # Create database and user for Pterodactyl
    echo -e "${CYAN}Please enter the following database information:${NC}"
    read -p "Database name [pterodactyl]: " db_name
    db_name=${db_name:-pterodactyl}
    
    read -p "Database username [pterodactyl]: " db_user
    db_user=${db_user:-pterodactyl}
    
    read -s -p "Database password: " db_password
    echo
    
    sudo mysql -u root <<EOF
CREATE DATABASE ${db_name};
CREATE USER '${db_user}'@'127.0.0.1' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

    print_status "Database created successfully!"
}

# Function to install Composer
install_composer() {
    print_status "Installing Composer..."
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

# Function to install Pterodactyl Panel
install_panel() {
    print_header "INSTALLING PTERODACTYL PANEL"
    
    # Get domain information
    echo -e "${CYAN}Panel Configuration:${NC}"
    read -p "Enter your domain name (e.g., panel.example.com): " panel_domain
    read -p "Enter your email address: " admin_email
    read -p "Enter admin first name: " admin_firstname
    read -p "Enter admin last name: " admin_lastname
    read -p "Enter admin username: " admin_username
    read -s -p "Enter admin password: " admin_password
    echo
    
    # Create directory and download panel
    print_status "Downloading Pterodactyl Panel..."
    sudo mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    
    # Get latest version
    PANEL_VERSION=$(curl -s https://api.github.com/repos/pterodactyl/panel/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    print_status "Installing Panel version: $PANEL_VERSION"
    
    sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    sudo tar -xzf panel.tar.gz
    sudo chmod -R 755 storage/* bootstrap/cache/
    
    # Set permissions
    sudo chown -R www-data:www-data /var/www/pterodactyl/*
    
    # Install dependencies
    print_status "Installing Panel dependencies..."
    sudo -u www-data composer install --no-dev --optimize-autoloader
    
    # Environment setup
    print_status "Setting up environment..."
    sudo -u www-data cp .env.example .env
    sudo -u www-data php artisan key:generate --force
    
    # Configure environment file
    sudo -u www-data php artisan p:environment:setup \
        --author="$admin_email" \
        --url="https://$panel_domain" \
        --timezone="UTC" \
        --cache="redis" \
        --session="redis" \
        --queue="redis" \
        --redis-host="127.0.0.1" \
        --redis-pass="" \
        --redis-port="6379"
    
    sudo -u www-data php artisan p:environment:database \
        --host="127.0.0.1" \
        --port="3306" \
        --database="$db_name" \
        --username="$db_user" \
        --password="$db_password"
    
    # Run migrations and create user
    print_status "Running database migrations..."
    sudo -u www-data php artisan migrate --seed --force
    
    print_status "Creating admin user..."
    sudo -u www-data php artisan p:user:make \
        --email="$admin_email" \
        --username="$admin_username" \
        --name-first="$admin_firstname" \
        --name-last="$admin_lastname" \
        --password="$admin_password" \
        --admin=1
    
    # Set up crontab
    print_status "Setting up crontab..."
    (sudo crontab -u www-data -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -u www-data -
    
    # Configure Nginx
    configure_nginx_panel "$panel_domain"
    
    print_status "Pterodactyl Panel installation completed!"
}

# Function to configure Nginx for Panel
configure_nginx_panel() {
    local domain=$1
    
    print_status "Configuring Nginx for Panel..."
    
    sudo tee /etc/nginx/sites-available/pterodactyl.conf > /dev/null <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;

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

    sudo ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    sudo systemctl reload nginx
    
    print_warning "SSL certificate is not configured. Please install Let's Encrypt SSL after the installation:"
    print_warning "sudo apt install certbot python3-certbot-nginx"
    print_warning "sudo certbot --nginx -d $domain"
}

# Function to install Docker (required for Wings)
install_docker() {
    print_status "Installing Docker..."
    
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    print_status "Docker installed successfully!"
}

# Function to install Wings
install_wings() {
    print_header "INSTALLING PTERODACTYL WINGS"
    
    print_status "Creating Wings directory..."
    sudo mkdir -p /etc/pterodactyl
    
    # Download Wings
    WINGS_VERSION=$(curl -s https://api.github.com/repos/pterodactyl/wings/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    print_status "Installing Wings version: $WINGS_VERSION"
    
    sudo curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    sudo chmod u+x /usr/local/bin/wings
    
    # Create systemd service
    print_status "Creating Wings systemd service..."
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
    
    print_warning "Wings is installed but not configured yet."
    print_warning "You need to:"
    print_warning "1. Create a node in your Panel"
    print_warning "2. Copy the configuration from the Panel to /etc/pterodactyl/config.yml"
    print_warning "3. Start Wings with: sudo systemctl start wings"
    
    print_status "Wings installation completed!"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
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
    
    print_status "Firewall configured successfully!"
}

# Function to show post-installation instructions
show_post_install() {
    print_header "INSTALLATION COMPLETED"
    
    echo -e "${GREEN}Installation Summary:${NC}"
    
    if [[ "$install_option" == "1" || "$install_option" == "3" ]]; then
        echo -e "${CYAN}Pterodactyl Panel:${NC}"
        echo -e "  URL: https://$panel_domain"
        echo -e "  Admin Email: $admin_email"
        echo -e "  Admin Username: $admin_username"
        echo -e "  Database: $db_name"
        echo -e "  Database User: $db_user"
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
        echo -e "   sudo certbot --nginx -d $panel_domain"
        echo ""
        echo -e "2. Secure MariaDB:"
        echo -e "   sudo mysql_secure_installation"
        echo ""
    fi
    
    if [[ "$install_option" == "2" || "$install_option" == "3" ]]; then
        echo -e "3. Configure Wings:"
        echo -e "   - Create a node in your Panel"
        echo -e "   - Copy the auto-deploy command from Panel"
        echo -e "   - Run: sudo systemctl start wings"
        echo ""
    fi
    
    echo -e "4. Reboot your server to ensure all services start properly:"
    echo -e "   sudo reboot"
    echo ""
    
    print_status "Installation guide completed!"
}

# Main menu function
show_menu() {
    clear
    print_header "PTERODACTYL INSTALLATION SCRIPT"
    echo -e "${CYAN}Ubuntu 24.04 Compatible${NC}"
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
            install_dependencies
            configure_mariadb
            install_composer
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
            install_dependencies
            configure_mariadb
            install_composer
            install_docker
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
