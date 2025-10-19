#!/bin/bash

##########################################################################
# Script d'ajout d'un site .Net Core avec Nginx et HTTPS via Let's Encrypt
##########################################################################
# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Veuillez exécuter ce script en tant que root."
    exit 1
fi



echo ""
echo "#########################################################"
echo "# Script d'ajout d'un site .Net Core avec Nginx         #"
echo "# et HTTPS via Let's Encrypt                            #"
echo "#########################################################"



# Initialisation des variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADMIN_EMAIL="{email}"



# Demande du nom de domaine
echo ""
echo ""
echo "Entrez le nom de domaine (ex: domain.com): "
read DOMAIN



# Demande du nom du fichier DLL principal
echo ""
echo ""
echo "Entrez le nom du fichier DLL principal (ex: myapp.dll): "
read DLL



# Demande du port interne
echo ""
echo ""
echo "Entrez le port interne sur lequel l'application .Net Core écoutera (ex: 5000): "
read INTERNAL_PORT



# Demande de l'environnement
echo ""
echo ""
echo "Entrez l'environnement de l'application .Net Core (ex: Production) [Défaut: Production]: "
read ENVIRONMENT
if [ -z "$ENVIRONMENT" ]; then
    ENVIRONMENT="Production"
fi



# Demande si le site doit être protégé par un mot de passe
LOCK_SITE=false
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
echo "Les répertoires ont été créés :"
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



# Création du fichier de service systemd pour l'application .Net Core
echo ""
echo ""
echo "Création du service systemd pour l'application .Net Core..."
APP_NAME="${DOMAIN//./_}"
APP_DESCRIPTION="Service $APP_NAME pour l'application .Net Core $DOMAIN"
SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
cp "$SCRIPT_DIR/app.service" "$SERVICE_FILE"
sed -i "s/{description}/$APP_DESCRIPTION/g" "$SERVICE_FILE"
sed -i "s/{path}/$DOMAIN\/httpdocs/g" "$SERVICE_FILE"
sed -i "s/{dll}/$DLL/g" "$SERVICE_FILE"
sed -i "s/{environment}/$ENVIRONMENT/g" "$SERVICE_FILE"
sed -i "s/{port}/$INTERNAL_PORT/g" "$SERVICE_FILE"
sed -i "s/{identifier}/$APP_NAME/g" "$SERVICE_FILE"
sed -i "s/{name}/$DOMAIN/g" "$SERVICE_FILE"
echo ""
echo "Veuillez transférer votre application .Net Core dans le répertoire ${WEB_ROOT}."
echo "Le fichier principal de l'application doit être nommé $DLL."
echo "Le service systemd a été créé : $SERVICE_FILE"
read -p "   => Une fois les fichiers transférés, appuyez sur Entrée pour continuer..."
echo ""
echo "Activation et démarrage du service $APP_NAME..."
systemctl daemon-reload
systemctl enable "$APP_NAME"
systemctl start "$APP_NAME"
if [ $? -ne 0 ]; then
    echo ""
    echo "Erreur lors du démarrage du service $APP_NAME. Veuillez vérifier le journal avec la commande : journalctl -u $APP_NAME"
    exit 1
fi
echo ""
echo "Le service $APP_NAME a été activé et démarré avec succès."



# Configurer Nginx (http)
echo ""
echo ""
echo "Configuration de Nginx pour le site $DOMAIN (HTTP)..."
cp "$SCRIPT_DIR/site.temp.dotnet.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{internal_port}/$INTERNAL_PORT/g" /etc/nginx/sites-available/$DOMAIN.conf
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
cp "$SCRIPT_DIR/site.dotnet.conf" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{name}/$DOMAIN/g" /etc/nginx/sites-available/$DOMAIN.conf
sed -i "s/{internal_port}/$INTERNAL_PORT/g" /etc/nginx/sites-available/$DOMAIN.conf
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
