#!/bin/bash

# Exit on error and log all commands
set -euo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

LOG_FILE="/var/log/drupal_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting Drupal Installation and Setup..."

# Ask for IP address
read -p "Enter the server IP address: " SERVER_IP

# Constants and Variables
DB_NAME="db"
DB_USER="admin"
DB_PASS="admin"
SITE_NAME="Drupal-ROPIM"
ADMIN_USER="admin"
ADMIN_PASS="admin"
ADMIN_EMAIL="admin@example.com"
DOMAIN="ropim.local"
DRUPAL_DIR="/var/www/ropim"
PHP_VERSION="8.4"
DRUSH_VERSION="13"
REDIS_VERSION="7.8.4-18"
VARNISH_VERSION="7.6.1"
MARIADB_VERSION="11.6.2"
APACHE_VERSION="2.4.62"
DRUPAL_VERSION="11"


update_sources_list() {
    echo "========================================"
    echo "Updating sources.list and preparing system..."
    echo "========================================"

    # Update Ubuntu sources list
    echo "Fetching custom sources.list.d configuration..."
    sudo wget -O /etc/apt/sources.list.d/ubuntu.sources https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/ubuntu.sources
    sudo chmod 644 /etc/apt/sources.list.d/ubuntu.sources

    # Backup and replace main sources.list
    echo "Backing up and replacing sources.list..."
    sudo rm -f /etc/apt/sources.list.d/*
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
    sudo wget -O /etc/apt/sources.list https://raw.githubusercontent.com/germanShepherd369/bashScriptTesting/main/sources.list

    # Add PHP repository
    echo "Installing required tools and adding PPA for PHP..."
    sudo apt install software-properties-common -y
    sudo add-apt-repository ppa:ondrej/php -y

    # Update package index
    echo "Updating package index..."
    sudo apt update
    echo "========================================"
    echo "Sources list updated successfully!"
    echo "========================================"
}

# Helper Functions
validate_command() {
    echo "Validating command: $1"
    if ! command -v "$1" &>/dev/null; then
        echo "Error: Command $1 not found"
        exit 1
    fi
}

validate_service() {
    echo "Checking service status: $1"
    if ! sudo systemctl status "$1" &>/dev/null; then
        echo "Error: Service $1 is not running"
        exit 1
    fi
}

# Configuration Functions
configure_locale_and_timezone() {
    echo "Configuring locale and timezone..."
    sudo locale-gen en_US.UTF-8 || echo "Failed to generate locale"
    sudo update-locale LANG=en_US.UTF-8
    sudo timedatectl set-timezone UTC || echo "Failed to set timezone"
}

update_and_prepare_system() {
    echo "Updating system packages..."
    sudo apt clean
    if ! sudo apt update -y; then
        echo "Error during 'apt update'"
    fi
    if ! sudo apt --fix-broken install -y; then
        echo "Error during 'apt --fix-broken install'"
    fi
}

install_required_packages() {
    echo "Installing required packages..."
    local packages=(
        apache2 software-properties-common certbot python3-certbot-apache \
        mariadb-server redis-server varnish composer \
        php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml \
        php${PHP_VERSION}-mysql php${PHP_VERSION}-zip php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-intl
    )
    if ! sudo apt install -y "${packages[@]}"; then
        echo "Error installing required packages"
        exit 1
    fi
}

configure_apache() {
    echo "Configuring Apache..."
    sudo a2enmod rewrite ssl headers expires
    sudo tee /etc/apache2/sites-available/$DOMAIN.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $SERVER_IP
    DocumentRoot $DRUPAL_DIR/web

    <Directory $DRUPAL_DIR/web>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/ropim-error.log
    CustomLog \${APACHE_LOG_DIR}/ropim-access.log combined
</VirtualHost>
EOF

    sudo a2dissite 000-default.conf
    sudo a2ensite $DOMAIN.conf
    sudo systemctl reload apache2 || echo "Failed to reload Apache"
    validate_service apache2
}

install_drupal() {
    echo "Setting up Drupal..."

    if [ -d "$DRUPAL_DIR" ] && [ "$(ls -A $DRUPAL_DIR)" ]; then
        echo "Directory $DRUPAL_DIR is not empty. Backing up existing contents."
        sudo mv "$DRUPAL_DIR" "${DRUPAL_DIR}_backup_$(date +%Y%m%d%H%M%S)"
        sudo mkdir -p $DRUPAL_DIR
    fi

    sudo mkdir -p $DRUPAL_DIR
    sudo chown -R www-data:www-data $DRUPAL_DIR
    sudo chmod -R 755 $DRUPAL_DIR

    cd $DRUPAL_DIR
    if ! sudo -u www-data composer create-project drupal/recommended-project .; then
        echo "Error downloading Drupal project"
        exit 1
    fi

    echo "Installing Drush..."
    if ! sudo -u www-data composer require drush/drush; then
        echo "Error installing Drush"
        exit 1
    fi

    echo "Running Drupal installation..."
    sudo -u www-data ./vendor/bin/drush site:install \
      --db-url=mysql://$DB_USER:$DB_PASS@localhost/$DB_NAME \
      --site-name="$SITE_NAME" \
      --account-name="$ADMIN_USER" \
      --account-pass="$ADMIN_PASS" \
      --account-mail="$ADMIN_EMAIL" || echo "Drupal installation failed"
}


finalize_permissions() {
    echo "Setting secure permissions for settings.php..."
    if ! sudo chmod 440 $DRUPAL_DIR/web/sites/default/settings.php; then
        echo "Error setting permissions for settings.php"
    fi
}

configure_firewall() {
    echo "Configuring the firewall..."
    sudo ufw allow OpenSSH
    sudo ufw allow 'Apache Full'
    sudo ufw allow 6379  # Redis
    sudo ufw allow 6081  # Varnish
    if ! sudo ufw --force enable; then
        echo "Failed to configure the firewall"
    fi
}
replace_composer_json() {
	sudo sed -i '/"minimum-stability":/c\    "minimum-stability": "dev",' $DRUPAL_DIR/composer.json
	echo "composer.json updated successfully!"
}
db_permissions() {
	echo "Creating database and user..."
	sudo mysql -u root -p -e "CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
	sudo mysql -u root -p -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}'; \
	GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'; \
	FLUSH PRIVILEGES;"

	echo "Database ${DB_NAME} and user ${DB_USER} created successfully!"
}


main() {
    echo "Starting main setup sequence..."
	update_sources_list
    configure_locale_and_timezone
    update_and_prepare_system
    install_required_packages
    configure_apache
    install_drupal
    finalize_permissions
    configure_firewall
	replace_composer_json
	db_permissions
	
    echo "Drupal installation and setup completed successfully!"
    echo "Log file: $LOG_FILE"
}

# Execute main function
main


## FinalCunt