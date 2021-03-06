!/usr/bin/env bash

# =============================================================================
#
#  ------------------------------------------------------------------
#  Bash Script to Setup a Web Server
#  Install PHP, nginx, and Laravel Application
#  ------------------------------------------------------------------
#
#  Inspired by: https://raw.githubusercontent.com/fastsitephp/fastsitephp/master/scripts/shell/bash/create-fast-site.sh
#      Big parts of the script come from the source. Although it is changed a lot. Many thanks to Conrad Sollitt.
#
#  Author:   Mathis Hermann
#  Created:  2021
#  License:  MIT
#
#  Developed For Operating Systems:
#      Debian 10
#
#  This script works on a default OS when nothing is installed and is
#  expected to take between 2 minute to 5 minutes to
#  install. This script should work with any user however it requires
#  sudo access when running the install.
#
#  There are three steps involved. After the first step there is an automatic reboot of the system. 
#
#  Download and run this script:
#
#  Basic Usage:
#      curl -s https://raw.githubusercontent.com/MathisHermann/scripts/main/install_complete.sh | sudo bash -s -- -n
#      curl -s https://raw.githubusercontent.com/MathisHermann/scripts/main/install_complete.sh | bash -s -- -a
#      curl -s https://raw.githubusercontent.com/MathisHermann/scripts/main/install_complete.sh | sudo bash -s -- -c
#
#  Or download directly from GitHub and install (if wget is available):
#      wget https://raw.githubusercontent.com/MathisHermann/scripts/main/install_complete.sh
#      sudo bash create-fast-site.sh -n
#      bash create-fast-site.sh -a
#      sudo bash create-fast-site.sh -c
#
#  Options:
#      -h  Show Help
#      -n  Install nginx
#      -a  Install App
#      -c  Load config
#
#
#  This script is intended for a clean OS and one-time setup however it is
#  generally safe to run multiple times because it checks for if programs
#  such as php are already installed and prompts before overwriting an
#  existing site.
#
#  This script is not yet linted using:
#  https://www.shellcheck.net/
#
# =============================================================================
set -eo pipefail

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

PHP_VER="8.0"
user=$USER

main () 
{
    get_options "$@"
    

    if [[ "${installation_type}" == "nginx" ]]; then
        check_root
        install_nginx
    elif [[ "${installation_type}" == "app" ]]; then
        install_app
    elif [[ "${installation_type}" == "config" ]]; then
        check_root
        nginx_config
    fi
}

install_nginx ()
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
            apt_install "php8.0-bcmath"
            apt_install "php8.0-fpm"
            apt_install "php8.0-zip"
        fi
    fi

    apt_install "git"
    apt_install "unzip"
    curl -s https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer

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


    # Safety check to make sure that Apache is not already installed
    if hash apache2 2>/dev/null; then
        apt_remove "apache2"
    fi

    # Install nginx and PHP
    apt_install 'nginx'

    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Reboot now the machine and then run the second script.${FONT_RESET}"
    reboot
}

install_app ()
{
    # Get Data
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Downloading Repo${FONT_RESET}"
    git clone https://github.com/MathisHermann/dashi_3cx.git
    cd dashi_3cx/
    echo -e "${FONT_BOLD}Copying .env. Enter the credentials in here before the next step.${FONT_RESET}"
    cp .env.example .env
    
    # Install Composer dependencies
    echo -e "${FONT_BOLD}Install composer Dependencies${FONT_RESET}"
    cd dashi_3cx
    composer install
    php artisan key:generate
}

nginx_config ()
{  
    mv dashi_3cx /var/www/dashi
    cd /var/www/dashi

    # Set Permissions so that the main OS account expected to be used by a developer
    # exists and is granted access to create and update files on the site.
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Setting user permissions for ${user}${FONT_RESET}"
    adduser "${user}" www-data
    chown -R www-data.www-data /var/www/dashi/storage
    chown -R www-data.www-data /var/www/dashi/bootstrap/cache

    # Get the installed PHP major and minor version (example: 7.2)
    php_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

    # nginx Config
    # Create an nginx site file: [/etc/nginx/sites-available/app]
    # which is also linked from [/etc/nginx/sites-enabled/app]
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
SCRIPT_FILENAME='$realpath_root$fastcgi_script_name'
uri='$uri $uri/ /index.php?$query_string'
cat > /etc/nginx/sites-available/dashi <<EOF
server {
${tab}listen 80;
${tab}server_name _;
${tab}root /var/www/dashi/public;

${tab}add_header X-Frame-Options "SAMEORIGIN";
${tab}add_header X-XSS-Protection "1; mode=block";
${tab}add_header X-Content-Type-Options "nosniff";

${tab}index index.php index.html index.htm;

${tab}charset utf-8;

${tab}location / {
${tab}${tab}try_files ${uri};
${tab}}

${tab}location = /favicon.ico { access_log off; log_not_found off; }
${tab}location = /robots.txt  { access_log off; log_not_found off; }

${tab}error_page 404 /index.php;

${tab}location ~ \.php$ {
${tab}${tab}fastcgi_pass unix:/var/run/php/php${php_ver}-fpm.sock;
${tab}${tab}fastcgi_index index.php;
${tab}${tab}fastcgi_param SCRIPT_FILENAME ${SCRIPT_FILENAME};
${tab}${tab}include fastcgi_params;
${tab}}

${tab}location ~ /\.(?!well-known).* {
${tab}${tab}deny all;
${tab}}
}
EOF

        # For nginx sites under [sites-enabled] use a symbolic link to
        # [sites-available]. Create a link for [app] then remove the
        # symbolic link for [default]. The actual [default] file still exists
        # under [sites-available]. nginx recommends not editing the [default]
        # file in production servers. For more see comments in the file itself.
        ln -s /etc/nginx/sites-available/dashi /etc/nginx/sites-enabled/
        rm /etc/nginx/sites-enabled/default
    fi

    service php8.0-fpm stop
    service php8.0-fpm start

    # Restart nginx
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Restarting nginx${FONT_RESET}"
    systemctl reload nginx

        # If this script runs more than once the files will already be deleted
    if [[ -f /var/www/html/index.html ]]; then
        rm /var/www/html/index.html
    fi
    if [[ -f /var/www/html/index.nginx-debian.html ]]; then
        rm /var/www/html/index.nginx-debian.html
    fi

    echo "The app should be available now."
}

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

apt_remove ()
{
    if hash "$1" 2>/dev/null; then
        echo -e "Removing ${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET}"
        apt remove --purge -y "$1"
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET} has been installed"
    else
        echo -e "${FONT_BOLD}${FONT_UNDERLINE}${1}${FONT_RESET} is not installed"
    fi
}

get_options ()
{
    # If no parameters, prompt user for server type
    if [[ -z "$1" ]]; then
        while true; do
            echo "Which script would you like to run:"
            echo "  nginx (n)"
            echo "  app (a)"
            echo "  config (c)"
            echo "  exit (x)"
            echo "Enter n, a, c, or x:"
            read -r input
            case "$input" in
                c)
                    installation=config
                    break
                    ;;
                a)
                    installation=app
                    break
                    ;;
                n)
                    installation=nginx
                    break
                    ;;
                x)
                    echo 'Script Cancelled'
                    exit $ERR_GENERAL
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
            a) set_installation "app" ;;
            n) set_installation "nginx" ;;
            c) set_installation "config" ;;
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

check_root ()
{
    if (( EUID != 0 )); then
        >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, unable to install site. This script requires root or sudo access."
        >&2 echo "Install using the command below:"
        >&2 echo "    sudo bash ${SCRIPT_NAME}"
        exit $ERR_NOT_ROOT
    fi
}

set_installation ()
{
    installation_type="$1"
}

# -----------------------------------------------------------------------------
# Help Text, called when passing the [-h] option
# -----------------------------------------------------------------------------
show_help ()
{
    echo ""
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Bash Script to Setup an nginx Web Server${FONT_RESET}"
    echo "    Install nginx, Laravel app and load the ngingx config."
    echo ""
    echo "    This script works on a default OS when nothing is installed."
    echo "    Running this script requires root/sudo."
    echo ""
    echo "    There are 3 steps involved:"
    echo "        1) install nginx (${FONT_BOLD}run with sudo${FONT_RESET}) -n"
    echo "        2) install laravel app (${FONT_BOLD}run without sudo${FONT_RESET}) -a"
    echo "        3) load nginx config (${FONT_BOLD}run with sudo${FONT_RESET}) -c"
    echo ""
    echo -e "    ${FONT_UNDERLINE}https://github.com/MathisHermann/scripts${FONT_RESET}"
    echo ""
    echo -e "${FONT_BOLD}${FONT_UNDERLINE}Usage:${FONT_RESET}"
    sudo_script="    sudo bash ${SCRIPT_NAME}"
    script="    bash ${SCRIPT_NAME}"
    echo -e "${script}    ${FONT_DIM}# Use a prompt to select the Web Server${FONT_RESET}"
    echo -e "${sudo_script} ${FONT_BOLD}-n${FONT_RESET} ${FONT_DIM}# Install nginx${FONT_RESET}"
    echo -e "${script} ${FONT_BOLD}-a${FONT_RESET} ${FONT_DIM}# Install App${FONT_RESET}"
    echo -e "${sudo_script} ${FONT_BOLD}-c${FONT_RESET} ${FONT_DIM}# Load nginx config${FONT_RESET}"
    echo -e "${script} ${FONT_BOLD}-h${FONT_RESET} ${FONT_DIM}# Show help${FONT_RESET}"
    echo ""
}

main "$@"
exit $?
