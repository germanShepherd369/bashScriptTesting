#!/bin/bash

# Exit on error
set -e

echo "Starting Drupal Infrastructure Setup..."

echo "Archiving old sources.list; downloading high quality sources.list"
sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
sudo wget -O /etc/apt/sources.list https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/sources.list
sudo apt clean
sudo apt update


echo "Dynamic inputs:"
# Prompt for dynamic inputs
read -p "Enter your desired username: " USERNAME
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter your database root password: " DB_ROOT_PASS
read -p "Enter your database name for Drupal: " DB_NAME
read -p "Enter your Drupal database user: " DB_USER
read -p "Enter your Drupal database user password: " DB_PASS

# Variables
PHP_VERSION="8.4"
DRUSH_VERSION="13"
REDIS_VERSION="7.8.4-18"
VARNISH_VERSION="7.6.1"
MARIADB_VERSION="11.6.2"
APACHE_VERSION="2.4.62"
DRUPAL_VERSION="11"

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

# Create new user
echo "Creating user: $USERNAME"
sudo adduser --gecos "" $USERNAME
sudo usermod -aG sudo $USERNAME

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
echo 'export PATH="$HOME/.composer/vendor/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify Drush installation
drush --version

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
