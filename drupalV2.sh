#!/bin/bash

# Exit on error and log all commands
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

LOG_FILE="/var/log/drupal_setup_debug.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Drupal Infrastructure Setup..."

# Helper Functions
validate_command() {
    command -v "$1" &>/dev/null || { echo "Error: Command $1 not found"; exit 1; }
}

validate_file() {
    [[ -f "$1" ]] || { echo "Error: File $1 not found"; exit 1; }
}

validate_service() {
    sudo systemctl status "$1" &>/dev/null || { echo "Error: Service $1 is not running"; exit 1; }
}

validate_url() {
    curl -Is "$1" | head -n 1 | grep -q "200" || { echo "Error: URL $1 is not reachable"; exit 1; }
}

# Update Locale and Timezone
echo "Configuring locale and timezone..."
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
sudo timedatectl set-timezone UTC

sudo apt clean
sudo apt update || echo "Error during 'apt update'"
sudo apt --fix-broken install -y || echo "Error during 'apt --fix-broken install'"
# Archive old sources.list and fetch new high-quality sources
echo "Updating sources.list..."
sudo wget -O /etc/apt/sources.list.d/ubuntu.sources https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/ubuntu.sources
sudo chmod 644 /etc/apt/sources.list.d/ubuntu.sources

sudo apt clean
sudo apt update || echo "Error during 'apt update'"
sudo apt --fix-broken install -y || echo "Error during 'apt --fix-broken install'"

sudo rm -f /etc/apt/sources.list.d/*
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
sudo wget -O /etc/apt/sources.list https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/sources.list

sudo apt clean
sudo apt update || echo "Error during 'apt update'"
sudo apt --fix-broken install -y || echo "Error during 'apt --fix-broken install'"

sudo apt-add-repository main -y
sudo apt-add-repository restricted -y
sudo apt-add-repository universe -y
sudo apt-add-repository multiverse -y



sudo apt clean
sudo apt update || echo "Error during 'apt update'"
sudo apt --fix-broken install -y || echo "Error during 'apt --fix-broken install'"

# Install Required Packages
install_package() {
    PACKAGE=$1
    sudo apt install -y "$PACKAGE" || { echo "Error installing $PACKAGE"; exit 1; }
}

echo "Installing required packages..."
install_package libavif16
install_package libfontconfig1
install_package libheif1
install_package libimagequant0
install_package libjpeg8
install_package libraqm0
install_package libtiff6
install_package libwebp7
install_package libxpm4

# Apache Configuration
echo "Installing Apache and configuring virtual host..."
install_package apache2
sudo a2enmod rewrite ssl headers expires
sudo systemctl restart apache2
validate_service apache2

sudo tee /etc/apache2/sites-available/drupal.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/drupal/web

    <Directory /var/www/drupal/web>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/drupal-error.log
    CustomLog \${APACHE_LOG_DIR}/drupal-access.log combined
</VirtualHost>
EOF

sudo a2ensite drupal.conf
sudo systemctl reload apache2 || { echo "Error reloading Apache configuration"; exit 1; }

# Verify Drupal URL
echo "Validating Drupal site..."

# PHP and Extensions
echo "Installing PHP and required extensions..."
install_package software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
install_package php8.4
install_package php8.4-cli
install_package php8.4-curl
install_package php8.4-gd
install_package php8.4-mbstring
install_package php8.4-xml
install_package php8.4-mysql
install_package php8.4-zip
install_package php8.4-opcache
install_package php8.4-intl
php --version || echo "PHP installation failed"

# MariaDB
echo "Installing and configuring MariaDB..."
install_package mariadb-server
sudo systemctl enable mariadb
sudo systemctl start mariadb

sudo mysql_secure_installation || echo "MariaDB secure installation failed"

# Redis and Varnish
echo "Installing Redis and Varnish..."
install_package redis-server
install_package varnish
sudo systemctl start redis varnish


# Composer and Drush
echo "Installing Composer and Drush..."
install_package composer
sudo composer global require drush/drush:"13" || echo "Drush installation failed"
echo 'export PATH="$HOME/.composer/vendor/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

wget https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/composer.json -O composer.json
chmod +x composer.json


sudo apt install -y certbot python3-certbot-apache

echo "Downloading and setting up Drupal $DRUPAL_VERSION..."
sudo mkdir -p /var/www/$DOMAIN
sudo chown -R $USERNAME:$USERNAME /var/www/$DOMAIN
sudo chmod -R 755 /var/www/$DOMAIN

sudo -u $USERNAME composer create-project drupal/recommended-project /var/www/$DOMAIN
cd /var/www/$DOMAIN
sudo -u $USERNAME composer require drush/drush


sudo a2ensite $DOMAIN.conf
sudo systemctl reload apache2

# Firewall
echo "Configuring UFW Firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Apache Full'
sudo ufw allow 6379  # Redis
sudo ufw allow 6081  # Varnish
sudo ufw --force enable

# Final Validation
echo "Setup completed successfully!"
echo "Log file: $LOG_FILE"
