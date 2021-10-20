set -eo pipefail

main () 
{ 
    # 3rd party repositories are needed for specific versions of PHP
    if [[ "8.0" != "" ]]; then
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


    # Safety check to make sure that Apache is not already installed
    if hash apache2 2>/dev/null; then
        apt remove --purge apache2
        # >&2 echo -e "${FONT_ERROR}Error${FONT_RESET}, unable to install nginx because Apache is already setup on this server."
        # exit $ERR_GENERAL
    fi

    # Install nginx and PHP
    apt_install 'nginx'
    ufw allow 'Nginx HTTP'    
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

main "$@"
exit $?