#!/bin/bash

#############################################################################
# Script d'ajout d'un site PHP avec Nginx, PHP-FPM et HTTPS via Let's Encrypt
#############################################################################
# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter ce script en tant que root."
    exit 1
fi



echo ""
echo "###############################################"
echo "# Script d'ajout d'un site PHP avec Nginx     #"
echo "# et HTTPS via Let's Encrypt                  #"
echo "###############################################"



# Initialisation des variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_EMAIL="{email}"



# Demande du nom de domaine
echo ""
echo ""
echo "Entrez le nom de domaine (ex: domain.com): "
read DOMAIN



# Demande si le site doit être protégé par un mot de passe
LOCK_SITE = false
echo ""
echo ""
echo "Est-ce que le site doit être protégé par un mot de passe ? (o/n): "
read LOCK_SITE_ANSWER
if [[ "$LOCK_SITE_ANSWER" == "o" || "$LOCK_SITE_ANSWER" == "O" || "$LOCK_SITE_ANSWER" == "y" || "$LOCK_SITE_ANSWER" == "Y" ]]; then
    LOCK_SITE=true
    echo ""
    echo "Entrez le nom d'utilisateur pour la protection par mot de passe: "
    read USERNAME
    echo ""
    echo "Entrez le mot de passe pour la protection par mot de passe: "
    read -s PASSWORD
fi



# Demande si un utilisateur FTP doit être créé
FTP_ENABLED=false
echo ""
echo ""
echo "Voulez-vous créer un utilisateur FTP pour ce site ? (o/n): "
read FTP_ANSWER
if [[ "$FTP_ANSWER" == "o" || "$FTP_ANSWER" == "O" || "$FTP_ANSWER" == "y" || "$FTP_ANSWER" == "Y" ]]; then
    FTP_ENABLED=true
    echo ""
    echo "Entrez le nom d'utilisateur FTP: "
    read FTP_USER
    if id "$FTP_USER" &>/dev/null; then
        echo ""
        echo "L'utilisateur $FTP_USER existe déjà. Veuillez choisir un autre nom d'utilisateur."
        exit 1
    fi
    echo ""
    echo "Entrez le mot de passe FTP: "
    read -s FTP_PASSWORD
fi



# Définition des chemins
ROOT="/var/www/$DOMAIN"
WEB_ROOT="$ROOT/httpdocs"
WEB_LOGS="$ROOT/logs"



# Création des répertoires
echo ""
echo ""
echo "Création des répertoires pour le site $DOMAIN..."
mkdir -p "$WEB_ROOT"
mkdir -p "$WEB_LOGS"
chmod -R 774 "$ROOT"
chown -R www-data:www-data "$ROOT"
echo ""
echo "Les répertoires suivants ont été créés :"
echo " - $WEB_ROOT"
echo " - $WEB_LOGS"



# Création de l'utilisateur FTP si nécessaire
if [ "$FTP_ENABLED" = true ]; then
    echo ""
    echo ""
    echo "Création de l'utilisateur FTP $FTP_USER..."
    ENCRYPTED_FTP_PASSWORD=$(openssl passwd -1 "$FTP_PASSWORD")
    useradd -m -s /bin/bash --home $ROOT --shell /bin/false -p "$ENCRYPTED_FTP_PASSWORD" "$FTP_USER"
    usermod -aG www-data "$FTP_USER"
    chown -R $FTP_USER:www-data $ROOT
    echo ""
    echo "L'utilisateur FTP $FTP_USER a été créé avec le répertoire racine $ROOT."
    echo ""
    echo "Ajout de l'utilisateur $FTP_USER à la liste des utilisateurs SFTP autorisés..."
    echo "$FTP_USER" >> /etc/vsftpd.userlist
    echo ""
    echo "L'utilisateur $FTP_USER a été ajouté à la liste des utilisateurs SFTP autorisés."
fi



# Configurer Nginx (http)
echo ""
echo ""
echo "Configuration de Nginx pour le site $DOMAIN (HTTP)..."
cp "$SCRIPT_DIR/site.temp.php.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo ""
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi
echo ""
echo "Nginx a été configuré pour le site $DOMAIN (HTTP)."



# Configurer HTTPS avec Certbot
echo ""
echo ""
echo "Configuration de HTTPS pour le site $DOMAIN avec Certbot..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect --no-eff-email
if [ $? -ne 0 ]; then
    echo ""
    echo "Erreur lors de la configuration HTTPS avec Certbot."
    exit 1
fi
echo ""
echo "HTTPS a été configuré pour le site $DOMAIN."



# Configurer Nginx (https)
echo ""
echo ""
echo "Configuration de Nginx pour le site $DOMAIN (HTTPS)..."
cp "$SCRIPT_DIR/site.php.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo ""
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi
echo ""
echo "Nginx a été configuré pour le site $DOMAIN (HTTPS)."



# Restreindre l'accès avec htpasswd si nécessaire
if [ "$LOCK_SITE" = true ]; then
    echo ""
    echo ""
    echo "Configuration de la protection par mot de passe pour le site $DOMAIN..."
    htpasswd -cb "$ROOT/.htpasswd" "$USERNAME" "$PASSWORD"
    if [ $? -ne 0 ]; then
        echo ""
        echo "Erreur lors de la création du fichier .htpasswd."
        exit 1
    fi
    chown www-data:www-data "$ROOT/.htpasswd"
    chmod 640 "$ROOT/.htpasswd"
    echo ""
    echo "Le fichier .htpasswd a été créé à l'emplacement $ROOT/.htpasswd."
    sed -i "s/# auth_basic_user_file /auth_basic_user_file /g" /etc/nginx/sites-available/$DOMAIN.conf
    sed -i "s/# auth_basic /auth_basic /g" /etc/nginx/sites-available/$DOMAIN.conf
    echo ""
    echo "La protection par mot de passe a été configurée pour le site $DOMAIN."
fi



# Rechargement de Nginx
echo ""
echo ""
echo "Rechargement de Nginx..."
systemctl reload nginx
if [ $? -ne 0 ]; then
    echo ""
    echo "Erreur lors du rechargement de Nginx. Veuillez vérifier la configuration \"/etc/nginx/sites-available/$DOMAIN.conf\"."
    exit 1
fi
echo ""
echo "Nginx a été rechargé avec succès."



# Fin du script
echo ""
echo ""
echo "Le site $DOMAIN a été ajouté avec succès."
echo ""
exit 0
