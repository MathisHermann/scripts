#!/usr/bin/env bash

# =============================================================================
#
#  ------------------------------------------------------------------
#  Bash Script to Setup a Web Server
#  Install Apache or nginx, PHP, and FastSitePHP with a Starter Site
#  ------------------------------------------------------------------
#
#  https://www.fastsitephp.com
#  https://github.com/fastsitephp/starter-site
#
#  Author:   Conrad Sollitt
#  Created:  2019 to 2020
#  License:  MIT
#
#  Supported Operating Systems:
#      Ubuntu 20.04 LTS
#      Ubuntu 18.04 LTS
#      Ubuntu 16.04 LTS
#
#  Confirmed Cloud Enviroments:
#      [Amazon AWS Lightsail] with user [ubuntu]
#      [DigitalOcean] with user [root]
#
#  This script works on a default OS when nothing is installed and is
#  expected to take between 1 minute to a 1 and a half minutes to
#  install. This script should work with any user however it requires
#  sudo access when running the install.
#
#  Download and run this script:
#
#  Basic Usage:
#      wget https://www.fastsitephp.com/downloads/create-fast-site.sh
#      sudo bash create-fast-site.sh
#
#  Or download directly from GitHub and install:
#      wget https://raw.githubusercontent.com/fastsitephp/fastsitephp/master/scripts/shell/bash/create-fast-site.sh
#      sudo bash create-fast-site.sh
#
#  Options:
#      -h  Show Help
#      -a  Install using Apache
#      -n  Install using nginx
#
#  Example:
#      sudo bash create-fast-site.sh -a
#
#  This script is intended for a clean OS and one-time setup however it is
#  generally safe to run multiple times because it checks for if programs
#  such as php are already installed and prompts before overwriting an
#  existing site.
#
#  This script is linted using:
#  https://www.shellcheck.net/
#
# =============================================================================

# Set Bash Options for this Script
#   e - Exit if a command fails
#   o pipefail - Exit if any command in a pipe fails
set -eo pipefail

# Error Codes
# Output for errors is sent to STDERR by using the
# redirection command [>&2] before calling "echo".
ERR_GENERAL=1
ERR_NOT_ROOT=2
ERR_MISSING_APT=3
ERR_MISSING_USER=4
ERR_INVALID_OPT=5

# Font Formatting for Output
FONT_RESET="\x1B[0m"
FONT_BOLD="\x1B[1m"
FONT_DIM="\x1B[2m"
FONT_UNDERLINE="\x1B[4m"
FONT_WHITE="\x1B[97m"
FONT_BG_RED="\x1B[41m"
FONT_BG_GREEN="\x1B[42m"
FONT_SUCCESS="${FONT_BG_GREEN}${FONT_WHITE}"
FONT_ERROR="${FONT_BG_RED}${FONT_WHITE}"

# Get Path and Name of the Script
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_NAME=$(basename "${SCRIPT_PATH}")

# By default apt-get on Ubuntu only installs PHP 7.2, in order to use newer
# versions a 3rd party repository is required. To use the default version
# use an empty string and to use the 3rd party repository specify the version.
# The selected 3rd party repository is widely used and safe. PHP 7.3 or higher
# is needed in order to use the security [SameSite] attribute for Cookies.
#
# PHP_VER=""
PHP_VER="8.0"

# ---------------------------------------------------------
# Main function, this gets called from bottom of the file
# ---------------------------------------------------------
main ()
{
    # Declare local variables
    local user time_taken ip

    # Parse script params or get user input for server type
    get_options "$@"

    # Environment Validation
    # These function will terminate the script if there is an error
    check_root
    user=$USER
    check_apt

    # Install Web Server (Apache or nginx) and PHP
    if [[ "${server_type}" == "Apache" ]]; then
        install_apache
    else
        install_nginx
    fi


    # If this script runs more than once the files will already be deleted
    if [[ -f /var/www/html/index.html ]]; then
        rm /var/www/html/index.html
    fi
    if [[ -f /var/www/html/index.nginx-debian.html ]]; then
        rm /var/www/html/index.nginx-debian.html
    fi


    # Set Permissions so that the main OS account expected to be used by a developer
    # exists and is granted access to create and update files on the site.
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Setting user permissions for ${user}${FONT_RESET}"
    adduser "${user}" www-data
    chown -R "${user}.www-data" /var/www/html
    chown -R "www-data.www-data" /var/www/html

    # Get Data
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Downloading Repo${FONT_RESET}"
    git clone https://github.com/MathisHermann/dashi_3cx.git /var/www/html/dashi

    chmod 0775 -R /var/www/html/dashi

    # Install Composer dependencies
    composer install
    cp .env.example .env
    php artisan key:generate

    # Success, print summary
    echo ""
    echo ""
    echo -e "${FONT_SUCCESS}Success!${FONT_RESET}"
    echo "${server_type} has been installed and the FastSitePHP Starter Site is setup and ready to use."
    time_taken=$(format_time $SECONDS)
    echo "Time Taken to Install: [${time_taken}]"

    # Get public IP for the server from Google and show to the user
    # From: https://www.cyberciti.biz/faq/how-to-find-my-public-ip-address-from-command-line-on-a-linux/
    ip=$(dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | awk -F'"' '{ print $2}')
    echo -e "View your site at: ${FONT_BOLD}${FONT_UNDERLINE}http://${ip}${FONT_RESET}"
}

# ---------------------------------------------------------
# Install Apache and PHP
# ---------------------------------------------------------
install_apache ()
{
    local php_ver file

    # Safety check to make sure that nginx is not already installed
    if hash nginx 2>/dev/null; then
        >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, unable to install Apache because nginx is already setup on this server."
        exit $ERR_GENERAL
    fi

    # Install Apache, PHP, then enable PHP for Apache with libapache2-mod-php
    apt_install 'apache2'
    if [[ "${PHP_VER}" == "" ]]; then
        apt_install 'php'
        apt_install 'libapache2-mod-php'
    else
        apt_install "php${PHP_VER}"
        apt_install "libapache2-mod-php${PHP_VER}"
    fi

    # Get the installed PHP major and minor version (example: 7.2)
    php_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    # Add PHP Extensions. A large number of extensions exist and the
    # installed PHP version number needs to be included. The extensions
    # below are needed for all FastSitePHP common features to work and
    # for all Unit Tests to succeed, however they are not required
    # in order to use FastSitePHP.
    apt_install "php${php_ver}-sqlite3"
    apt_install "php${php_ver}-gd"
    apt_install "php${php_ver}-bcmath"
    apt_install "php${php_ver}-simplexml"

    # The zip extension is required in order for the FastSitePHP
    # install script to run.
    apt_install "php${php_ver}-zip"

    # Enable a Fallback page so that [index.php] does not show in the URL.
    #
    # Instructions for manually performing this step:
    #     sudo nano /etc/apache2/apache2.conf
    # Scroll through the file and look for line:
    #     <Directory /var/www/>
    # Under it add the line:
    #     FallbackResource /index.php
    # Save using:
    #     {control+s} -> {control+x}
    #     or {control+x} -> {y} -> {enter}
    file='/etc/apache2/apache2.conf'
    echo -e "Checking file ${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET}"
    if grep "FallbackResource \/index.php" $file; then
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET} already contains FallbackResource"
    else
        # Note, the "\\t" is used to insert 1 tab and will not work with sed on all OS's
        # Only OS's at listed at the top of this file are known to work.
        echo -e "Updating ${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET} for FallbackResource"
        sed -i '/<Directory \/var\/www\/>/a \\tFallbackResource \/index.php' $file
    fi

    # Enable Gzip Compression for JSON Responses.
    # This is not enabled by default on Apache.
    #
    # Instructions for manually performing this step:
    #     sudo nano /etc/apache2/mods-available/deflate.conf
    # Add the following under similar commands:
    #     AddOutputFilterByType DEFLATE application/json
    file='/etc/apache2/mods-available/deflate.conf'
    echo -e "Checking file ${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET}"
    if grep "AddOutputFilterByType DEFLATE application\/json" $file; then
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET} already contains DEFLATE with json"
    else
        # Note, the "\\t\t" is used to insert 2 tabs, see related comments in above code block
        echo -e "Updating ${FONT_BOLD}${FONT_UNDERLINE}${file}${FONT_RESET} for DEFLATE with json"
        sed -i '/<IfModule mod_filter.c>/a \\t\tAddOutputFilterByType DEFLATE application\/json' $file
    fi

    # Restart Apache
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Restarting Apache${FONT_RESET}"
    service apache2 restart
}

# ---------------------------------------------------------
# Install nginx and PHP
# ---------------------------------------------------------
install_nginx ()
{
    local php_ver file tab

    # Safety check to make sure that Apache is not already installed
    if hash apache2 2>/dev/null; then
        apt remove --purge apache2
        # >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, unable to install nginx because Apache is already setup on this server."
        # exit $ERR_GENERAL
    fi

    # Install nginx and PHP
    apt_install 'nginx'
    ufw allow 'Nginx HTTP'
    if [[ "${PHP_VER}" == "" ]]; then
        apt_install 'php-fpm'
    else
        apt_install "php${PHP_VER}-fpm"
    fi

    # Get the installed PHP major and minor version (example: 7.2)
    php_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")


    # The zip extension is required in order for the FastSitePHP
    # install script to run.
    apt_install "php${php_ver}-zip"

    # nginx Config
    # Create an nginx site file: [/etc/nginx/sites-available/fastsitephp]
    # which is also linked from [/etc/nginx/sites-enabled/fastsitephp]
    if [[ -f /etc/nginx/sites-enabled/dashi ]]; then
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}nginx config already exists for dashi${FONT_RESET}"
    else
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}Setting up nginx config for dashi${FONT_RESET}"
        # This is based on the the default [/etc/nginx/sites-available/default]
        # and includes the following changes:
        #    index index.php ...
        #    try_files $uri $uri/ /index.php$is_args$args;
        #    Added section "location ~ \.php$ { ... }" based on nginx default
        tab="$(printf '\t')"

# bash heredoc "multi-line string"
cat > /etc/nginx/sites-available/dashi <<EOF
server {
${tab}listen 80;
${tab}server_name _;
${tab}root /var/www/html/dashi/public;

${tab}add_header X-Frame-Options "SAMEORIGIN";
${tab}add_header X-Content-Type-Options "nosniff";

${tab}index index.php;

${tab}charset utf-8;

${tab}location / {
${tab}try_files $uri $uri/ /index.php?$query_string;
${tab}}

${tab}location = /favicon.ico { access_log off; log_not_found off; }
${tab}location = /robots.txt  { access_log off; log_not_found off; }

${tab}error_page 404 /index.php;

${tab}location ~ \.php$ {
${tab}fastcgi_pass unix:/var/run/php/php${php_ver}-fpm.sock;
${tab}fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
${tab}include fastcgi_params;
${tab}}

${tab}location ~ /\.(?!well-known).* {
${tab}deny all;
${tab}}
}
EOF

        # For nginx sites under [sites-enabled] use a symbolic link to
        # [sites-available]. Create a link for [fastsitephp] then remove the
        # symbolic link for [default]. The actual [default] file still exists
        # under [sites-available]. nginx recommends not editing the [default]
        # file in production servers. For more see comments in the file itself.
        ln -s /etc/nginx/sites-available/dashi /etc/nginx/sites-enabled/
        rm /etc/nginx/sites-enabled/default
        service php8.0-fpm stop
        service php8.0-fpm start
    fi

    # Restart nginx
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Restarting nginx${FONT_RESET}"
    systemctl reload nginx
}

# ---------------------------------------------------------
# Make sure this script is running as root
# ---------------------------------------------------------
check_root ()
{
    if (( EUID != 0 )); then
        >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, unable to install site. This script requires root or sudo access."
        >&2 echo "Install using the command below:"
        >&2 echo "    sudo bash ${SCRIPT_NAME}"
        exit $ERR_NOT_ROOT
    fi
}

# ---------------------------------------------------------
# Make sure APT is installed and then run an update
# ---------------------------------------------------------
check_apt ()
{
    # 3rd party repositories are needed for specific versions of PHP
    if [[ "${PHP_VER}" != "" ]]; then
        if hash "php" 2>/dev/null; then    
            PHP_VER_INSTALLED=sh php -v
            if [[ ${PHP_VER_INSTALLED} == "8.0"* ]]; then
                echo -e "PHP 8.0 already installed"
            fi
        else
            echo -e "Updating apt"
            sudo apt update
            apt_install "wget"
            apt_install "lsb-release"
            apt_install "ca-certificates"
            apt_install "apt-transport-https"
            apt_install "software-properties-common"
            echo -e "Installing dependencies"  
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/sury-php.list
            wget -qO - https://packages.sury.org/php/apt.gpg | sudo apt-key add -
            sudo apt update
            apt_install "php8.0"
            apt_install "php8.0-mbstring"
            apt_install "php8.0-xml"
            apt_install "php8.0-fpm"
            apt_install "php8.0-zip"
            apt_install "php8.0-common"
            apt_install "php8.0-cli"
        fi
    fi

    apt_install "git"
    apt_install "unzip"
    apt_install "ufw"
    sudo curl -s https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer

    if hash apt 2>/dev/null; then
        # Update [apt] Package Manager
        echo -e "Updating APT using ${FONT_BOLD}${FONT_UNDERLINE}apt update${FONT_RESET}"
        apt update
        # The [upgrade] is not required but often recommend.
        # However, it takes many minutes so it is commented out by default.
        # apt upgrade
    else
        >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, This script requires Advanced Package Tool (APT) and currently only runs on"
        >&2 echo "Ubuntu, Debian, and related Linux distributions"
        exit $ERR_MISSING_APT
    fi
}

# -----------------------------------------------------------------------------
# Get Command Line Options
# This function uses [getopts] to read script parameters, this only works here
# because "$@" is passed to the function, otherwise this code would have
# to be at the top script level outside of a function. This method is used
# to keep the code organized into separate functions. [local OPTIND] and the
# ending [shift...] commands are only needed if this function is being called
# twice and this script doesn't call it twice; however, it's good practice to
# have if using [getopts] in a function.
# -----------------------------------------------------------------------------
get_options ()
{
    # If no parameters, prompt user for server type
    if [[ -z "$1" ]]; then
        while true; do
            echo "Which server would you like to install:"
            echo "  Apache (a)"
            echo "  nginx (n)"
            echo "  Cancel Script (c)"
            echo "Enter a, n, or c:"
            read -r input
            case "$input" in
                c)
                    echo 'Script Cancelled'
                    exit $ERR_GENERAL
                    ;;
                a)
                    server_type=Apache
                    break
                    ;;
                n)
                    server_type=nginx
                    break
                    ;;
                *) continue ;;
            esac
        done
        return 0
    fi

    # Get options
    local OPTIND opt
    while getopts ":canh" opt; do
        case "${opt}" in
            a) set_server_type "Apache" ;;
            n) set_server_type "nginx" ;;
            h)
                show_help
                exit 0
                ;;
            *)
                >&2 echo ""
                >&2 echo -e "${FONT_ERROR}Error, option is invalid: [-$OPTARG]${FONT_RESET}"
                >&2 echo -e "${FONT_ERROR}To see help with valid options run:${FONT_RESET}"
                >&2 echo -e "${FONT_ERROR}bash ${SCRIPT_NAME} -h${FONT_RESET}"
                >&2 echo ""
                exit $ERR_INVALID_OPT
                ;;
        esac
    done
    shift $((OPTIND-1))
}

# ---------------------------------------------------------
# Called when using options [-a] and [-n]
# ---------------------------------------------------------
set_server_type ()
{
    # Make sure server_type is not already set
    if [[ -n "${server_type}" ]]; then
        >&2 echo ""
        >&2 echo -e "${FONT_ERROR}Error, cannot install both Apache and nginx.${FONT_RESET}"
        >&2 echo -e "${FONT_ERROR}Specify only [-a] or only [-n] but not both.${FONT_RESET}"
        >&2 echo -e "${FONT_ERROR}To see help with valid options run:${FONT_RESET}"
        >&2 echo -e "${FONT_ERROR}bash ${SCRIPT_NAME} -h${FONT_RESET}"
        >&2 echo ""
        exit $ERR_INVALID_OPT
    fi

    # Set server_type first time this function is called
    server_type="$1"
}

# -----------------------------------------------------------------------------
# Help Text, called when passing the [-h] option
# -----------------------------------------------------------------------------
show_help ()
{
    echo ""
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Bash Script to Setup a Web Server${FONT_RESET}"
    echo "    Install Apache or nginx, PHP, and FastSitePHP with a Starter Site"
    echo ""
    echo "    This script works on a default OS when nothing is installed."
    echo "    Running this script requires root/sudo."
    echo ""
    echo -e "    ${FONT_UNDERLINE}https://www.fastsitephp.com${FONT_RESET}"
    echo -e "    ${FONT_UNDERLINE}https://github.com/fastsitephp/starter-site${FONT_RESET}"
    echo ""
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Usage:${FONT_RESET}"
    script="    sudo bash ${SCRIPT_NAME}"
    echo -e "${script}    ${FONT_DIM}# Use a prompt to select the Web Server${FONT_RESET}"
    echo -e "${script} ${FONT_BOLD}-a${FONT_RESET} ${FONT_DIM}# Install Apache${FONT_RESET}"
    echo -e "${script} ${FONT_BOLD}-n${FONT_RESET} ${FONT_DIM}# Install nginx${FONT_RESET}"
    echo -e "         bash ${SCRIPT_NAME} ${FONT_BOLD}-h${FONT_RESET} ${FONT_DIM}# Show help${FONT_RESET}"
    echo ""
}

# -----------------------------------------------------------------------------
# Check for a Command and install using APT if missing
#   @param  $1  Command
# -----------------------------------------------------------------------------
apt_install ()
{
    if hash "$1" 2>/dev/null; then
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET} is already installed"
    else
        echo -e "Installing ${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET}"
        apt install -y "$1"
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET} has been installed"
    fi
}

# -----------------------------------------------------------------------------
# Copy a Directory and prompt the user if it already exists
#   @param  $1  src
#   @param  $2  dest
# -----------------------------------------------------------------------------
copy_dir ()
{
    local input
    if [[ -d "$2" ]]; then
        echo "Directory [$2] already exists, overwrite existing files? [y, n]"
        read -r input
        if [[ "${input}" == 'y' || ${input} == 'Y' ]]; then
            cp -r "$1" "$2"
        fi
    else
        cp -r "$1" "$2"
    fi
}

# ---------------------------------------------------------
# Check the OS and return the current user that will be
# granted access to the Web Root Directory:
# ---------------------------------------------------------
get_user ()
{
    # NOTE - If you are modifying this script for a custom
    # setup and want to check if a specific user exists and
    # assign permissions to that user the following logic
    # can be used:
    #
    # if id -u ubuntu >/dev/null 2>&1; then
    #     printf 'ubuntu'

    if [[ "$(uname -a)" == *"mat"* ]]; then
       printf '%s' $(logname)
    else
        >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, This script currently only runs on Ubuntu."
        >&2 echo "To run modify the function [get_user ()] for your OS."
        exit $ERR_MISSING_USER
    fi
}

# -----------------------------------------------------------------------------
# Format time in "mm:ss" or "hh:mm:ss" from the first parameter in seconds
# -----------------------------------------------------------------------------
format_time ()
{
    local h m s
    ((h=$1/3600))
    ((m=$1/60))
    ((s=$1%60))
    if (( h > 0 )); then
        printf "%02d:%02d:%02d" "$h" "$m" "$s"
    else
        printf "%02d:%02d" "$m" "$s"
    fi
}

# --------------------------------------------------------------
# Run the main() function and exit with the result. "$@" is
# used to pass the script parameters to the main function
# and "$?" returns the exit code of the last command to run.
# --------------------------------------------------------------
main "$@"
exit $?

# Check if new 3
