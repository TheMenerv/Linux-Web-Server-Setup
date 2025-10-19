#!/bin/bash

# Script d'ajout d'un site PHP avec Nginx, PHP-FPM et HTTPS via Let's Encrypt
# Options:
#   --domain=nom_de_domaine      : Spécifie le nom de domaine du site à ajouter (obligatoire)
#   --lock-username=utilisateur  : Spécifie le nom d'utilisateur pour htpasswd (optionnel)
#   --lock-password=mot_de_passe : Spécifie le mot de passe pour htpasswd (obligatoire si --lock-username est utilisé)
#   --ftp-username=utilisateur   : Spécifie le nom d'utilisateur FTP (optionnel)
#   --ftp-password=mot_de_passe  : Spécifie le mot de passe FTP (obligatoire si --ftp-username est utilisé)
# Remplacez example.com par le nom de domaine de votre site
# Assurez-vous que le domaine pointe vers l'adresse IP de votre serveur
# Assurez-vous que le script setup.sh a été exécuté avec succès avant d'exécuter ce script



# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter ce script en tant que root."
    exit 1
fi


# Initialisation des variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_EMAIL="{email}"



# Traitement des arguments
if [ "$#" -lt 1 ] || [ "$#" -eq 2 ] || [ "$#" -eq 4 ] || [ "$#" -gt 5 ]; then
    echo "Usage: $0 --domain=domain.com [--lock-username=user --lock-password=pass] [--ftp-username=user --ftp-password=pass]"
    exit 1
fi

# domain
if [ "$1" != "--domain="* ]; then
    DOMAIN="${1#--domain=}"
else
    echo "Le premier argument doit être --domain=nom_de_domaine"
    exit 1
fi

# lock
LOCK_SITE=false

if [[ $2 == --lock-username=* ]] && [[ "$3" == --lock-password=* ]]; then
    LOCK_SITE=true
    USERNAME="${2#--lock-username=}"
    PASSWORD="${3#--lock-password=}"
elif [[ "$4" == --lock-username=* ]] && [[ "$5" == --lock-password=* ]]; then
    LOCK_SITE=true
    USERNAME="${4#--lock-username=}"
    PASSWORD="${5#--lock-password=}"
fi

FTP_ENABLED=false

if [[ "$2" == --ftp-username=* ]] && [[ "$3" == --ftp-password=* ]]; then
    FTP_ENABLED=true
    FTP_USER="${2#--ftp-username=}"
    FTP_PASSWORD="${3#--ftp-password=}"
elif [[ "$4" == --ftp-username=* ]] && [[ "$5" == --ftp-password=* ]]; then
    FTP_ENABLED=true
    FTP_USER="${4#--ftp-username=}"
    FTP_PASSWORD="${5#--ftp-password=}"
fi



# Définition des chemins
ROOT="/var/www/$DOMAIN"
WEB_ROOT="$ROOT/httpdocs"
WEB_LOGS="$ROOT/logs"



# Création des répertoires
mkdir -p "$WEB_ROOT"
mkdir -p "$WEB_LOGS"
chmod -R 774 "$ROOT"
chown -R www-data:www-data "$ROOT"



# Création de l'utilisateur FTP si nécessaire
if [ "$FTP_ENABLED" = true ]; then
    if id "$FTP_USER" &>/dev/null; then
        echo "L'utilisateur FTP $FTP_USER existe déjà. Veuillez choisir un autre nom d'utilisateur."
        exit 1
    fi
    echo "Création de l'utilisateur FTP $FTP_USER."
    ENCRYPTED_FTP_PASSWORD=$(openssl passwd -1 "$FTP_PASSWORD")
    useradd -m -s /bin/bash --home $ROOT --shell /bin/false -p "$ENCRYPTED_FTP_PASSWORD" "$FTP_USER"
    usermod -aG www-data "$FTP_USER"
    chown -R $FTP_USER:www-data $ROOT
    echo "Ajout de l'utilisateur $FTP_USER à la liste des utilisateurs SFTP autorisés."
    echo "$FTP_USER" >> /etc/vsftpd.userlist
fi



# Configurer Nginx (http)
cp "$SCRIPT_DIR/site.temp.php.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi



# Configurer HTTPS avec Certbot
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect --no-eff-email
if [ $? -ne 0 ]; then
    echo "Erreur lors de la configuration HTTPS avec Certbot."
    exit 1
fi



# Configurer Nginx (https)
cp "$SCRIPT_DIR/site.php.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi



# Restreindre l'accès avec htpasswd si nécessaire
if [ "$LOCK_SITE" = true ]; then
    htpasswd -cb "$ROOT/.htpasswd" "$USERNAME" "$PASSWORD"
    if [ $? -ne 0 ]; then
        echo "Erreur lors de la création du fichier .htpasswd."
        exit 1
    fi
    chown www-data:www-data "$ROOT/.htpasswd"
    chmod 640 "$ROOT/.htpasswd"
    sed -i "s/# auth_basic_user_file /auth_basic_user_file /g" /etc/nginx/sites-available/$DOMAIN.conf
    sed -i "s/# auth_basic /auth_basic /g" /etc/nginx/sites-available/$DOMAIN.conf
fi



# Rechargement de Nginx
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi



# Fin du script
echo "Le site $DOMAIN a été ajouté avec succès."
exit 0