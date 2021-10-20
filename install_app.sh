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

main () 
{ 
       
    if [[ "${PHP_VER}" == "" ]]; then
        apt_install 'php-fpm'
    else
        apt_install "php${PHP_VER}-fpm"
    fi

    # Get the installed PHP major and minor version (example: 7.2)
    php_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")


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

main "$@"
exit $?