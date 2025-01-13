#!/bin/bash

# Exit on error and log all commands
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

LOG_FILE="/var/log/drupal_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Drupal Infrastructure Setup..."

# Archive old sources.list and fetch new high-quality sources
echo "Archiving and updating sources.list..."
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
sudo wget -O /etc/apt/sources.list https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/sources.list
sudo apt clean
sudo apt update

# Dynamic inputs with defaults
DEFAULT_USERNAME="drupaladmin"
DEFAULT_DOMAIN="example.com"
DEFAULT_DB_ROOT_PASS="rootpassword"
DEFAULT_DB_NAME="drupaldb"
DEFAULT_DB_USER="drupaluser"
DEFAULT_DB_PASS="drupalpass"

echo "Dynamic inputs (press Enter to use default values):"
read -p "Enter your desired username [${DEFAULT_USERNAME}]: " USERNAME
USERNAME=${USERNAME:-$DEFAULT_USERNAME}

read -p "Enter your domain name [${DEFAULT_DOMAIN}]: " DOMAIN
DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

read -p "Enter your database root password [${DEFAULT_DB_ROOT_PASS}]: " DB_ROOT_PASS
DB_ROOT_PASS=${DB_ROOT_PASS:-$DEFAULT_DB_ROOT_PASS}

read -p "Enter your database name for Drupal [${DEFAULT_DB_NAME}]: " DB_NAME
DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

read -p "Enter your Drupal database user [${DEFAULT_DB_USER}]: " DB_USER
DB_USER=${DB_USER:-$DEFAULT_DB_USER}

read -p "Enter your Drupal database user password [${DEFAULT_DB_PASS}]: " DB_PASS
DB_PASS=${DB_PASS:-$DEFAULT_DB_PASS}

# Variables
PHP_VERSION="8.4"
DRUSH_VERSION="13"
REDIS_VERSION="7.8.4-18"
VARNISH_VERSION="7.6.1"
MARIADB_VERSION="11.6.2"
APACHE_VERSION="2.4.62"
DRUPAL_VERSION="11"

# Update and upgrade system
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

# Create new user
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists. Skipping creation."
else
    echo "Creating user: $USERNAME"
    sudo adduser --gecos "" $USERNAME
    sudo usermod -aG sudo $USERNAME
fi

# Install Apache
echo "Installing Apache $APACHE_VERSION..."
sudo apt install -y apache2
sudo a2enmod rewrite ssl headers expires
sudo systemctl restart apache2

# Install PHP and extensions
echo "Installing PHP $PHP_VERSION and required extensions..."
sudo apt install -y software-properties-common
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install -y php${PHP_VERSION} php-cli php-curl php-gd php-mbstring php-xml php-mysql php-zip php-opcache php-intl

# Install MariaDB
echo "Installing MariaDB $MARIADB_VERSION..."
sudo apt install -y mariadb-server
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Secure MariaDB and create database/user
echo "Securing MariaDB and creating Drupal database..."
sudo mysql_secure_installation <<EOF

y
$DB_ROOT_PASS
$DB_ROOT_PASS
y
y
y
y
EOF

echo "Creating database and user..."
sudo mysql -u root -p"$DB_ROOT_PASS" <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Install Redis
echo "Installing Redis $REDIS_VERSION..."
sudo apt install -y redis-server php-redis
sudo systemctl enable redis
sudo systemctl start redis

# Install Varnish
echo "Installing Varnish $VARNISH_VERSION..."
sudo apt install -y varnish

# Install Composer and Drush
echo "Installing Composer..."
sudo apt install -y composer
echo "Installing Drush $DRUSH_VERSION..."
composer global require drush/drush:"$DRUSH_VERSION"
composer global require drush/drush-plugin-manager
echo 'export PATH="$HOME/.composer/vendor/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify Drush installation
if drush --version; then
    echo "Drush successfully installed."
else
    echo "Drush installation failed. Check logs for details."
    exit 1
fi

# Install Certbot for SSL
echo "Installing Certbot for SSL..."
sudo apt install -y certbot python3-certbot-apache
sudo certbot --apache -d $DOMAIN

# Install Ansible
echo "Installing Ansible..."
sudo apt install -y ansible

# Install Drupal
echo "Downloading and setting up Drupal $DRUPAL_VERSION..."
sudo mkdir -p /var/www/$DOMAIN
sudo chown -R $USERNAME:$USERNAME /var/www/$DOMAIN
sudo chmod -R 755 /var/www/$DOMAIN

sudo -u $USERNAME composer create-project drupal/recommended-project /var/www/$DOMAIN
cd /var/www/$DOMAIN
sudo -u $USERNAME composer require drush/drush

# Configure Apache Virtual Host
echo "Configuring Apache virtual host for $DOMAIN..."
sudo tee /etc/apache2/sites-available/$DOMAIN.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot /var/www/$DOMAIN/web

    <Directory /var/www/$DOMAIN/web>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

sudo a2ensite $DOMAIN.conf
sudo systemctl reload apache2

# Configure UFW Firewall
echo "Configuring UFW Firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 'Apache Full'
sudo ufw allow 6379  # Redis default port
sudo ufw allow 6081  # Varnish default port
sudo ufw --force enable

# Final Message
echo "Setup completed successfully!"
echo "Visit http://$DOMAIN to complete Drupal installation via the web interface."
echo "MariaDB credentials:"
echo "Database: $DB_NAME"
echo "Username: $DB_USER"
echo "Password: $DB_PASS"

# Debugging best practices
echo "For debugging, review the log file at: $LOG_FILE"
echo "Use 'journalctl -xe' to check for service errors if something doesn't work."
echo "Use 'drush status' for Drupal status and configuration checks."
