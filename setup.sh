#!/bin/bash

echo "##############################################"
echo "# Script d'installation et de configuration  #"
echo "# d'un serveur web Ubuntu 22.04 avec Nginx,  #"
echo "# PHP 8.2 FPM, MariaDB, phpMyAdmin et VsFTPd #"
echo "# Auteur : Y. Benhayoun                      #"
echo "##############################################"
echo ""
echo ""

# Répertoire où se trouve le script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/setup.conf"

# Vérifier que l'on est bien root
if [ "$EUID" -ne 0 ]; then
    echo "=> Merci de lancer ce script avec sudo"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

# Vérifier que le fichier existe
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "=> Fichier de configuration introuvable : $CONFIG_FILE"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

echo "=> Configuration chargée :"
echo " - Hostname : $HOSTNAME"
echo " - Port SSH : $SSH_PORT"
echo " - Admin système : $ADMIN_USERNAME"
echo " - Email admin : $ADMIN_EMAIL"
echo " - Admin MariaDB : $DB_ADMIN_USERNAME"
echo " - Domaine phpMyAdmin : $PHPMA_DOMAIN"
echo " - Accès phpMyAdmin : $PHPMA_USERNAME"
echo " - FTP Admin : $FTP_ADMIN_USERNAME"
echo " - Rétention des logs : $LOG_RETENTION_DAYS jour(s)"
echo " - Nombre de sauvegardes locales : $BACKUP_KEEP_LOCAL"
echo " - Nombre de sauvegardes distantes : $BACKUP_KEEP_REMOTE"
echo " - Sauvegardes dans : $BACKUP_LOCAL_PATH"
echo " - Sauvegardes SFTP : $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST"
echo " - Heure des sauvegardes : $BACKUP_TIME"
echo " - Inclure /etc dans les sauvegardes : $BACKUP_INCLUDE_ETC"
echo " - Fichier log des sauvegardes : $BACKUP_LOG_FILE"
echo " - Email d'alerte des sauvegardes : $BACKUP_ALERT_EMAIL"
echo " - Serveur SMTP : $SMTP_SERVER:$SMTP_PORT (TLS: $SMTP_TLS)"
echo " - Email d'envoi : $SMTP_FROM"
echo ""
read -p "=> Les informations sont-elles correctes ? (Entrez pour continuer, Ctrl+C pour annuler)"
echo ""
echo ""


# -----------------------------
# Changer le hostname
# -----------------------------
echo ""
echo ""
echo "=> Changement du hostname..."
echo ""
echo ""
hostnamectl set-hostname "$HOSTNAME"
systemctl restart systemd-logind
echo ""
echo ""
echo "=> Hostname changé en $HOSTNAME"
echo ""
echo ""



# -----------------------------
# Mettre à jour les composants logiciels
# -----------------------------
echo ""
echo ""
echo "=> Mise à jour des composants logiciels..."
echo ""
echo ""
apt update
apt upgrade -y
apt autoremove -y
echo ""
echo ""
echo "=> Mises à jour terminées"
echo ""
echo ""



# -----------------------------
# Créer l’utilisateur administrateur système
# -----------------------------
echo ""
echo ""
echo "=> Création de l'utilisateur administrateur système..."
echo ""
echo ""
# Générer le mot de passe chiffré pour useradd
ENCRYPTED_PASSWORD=$(openssl passwd -1 "$ADMIN_PASSWORD")

# Créer l'utilisateur si il n'existe pas
if id "$ADMIN_USERNAME" &>/dev/null; then
    usermod -aG sudo "$ADMIN_USERNAME"
    echo ""
    echo ""
    echo "=> L'utilisateur $ADMIN_USERNAME existe déjà"
    echo ""
    echo ""
else
    useradd -m -s /bin/bash -p "$ENCRYPTED_PASSWORD" "$ADMIN_USERNAME"
    usermod -aG sudo "$ADMIN_USERNAME"
    echo ""
    echo ""
    echo "=> Utilisateur administrateur $ADMIN_USERNAME créé"
    echo ""
    echo ""
fi



# -----------------------------
# Installer les outils de base
# -----------------------------
echo ""
echo ""
echo "=> Installation des outils de base..."
echo ""
echo ""
apt install wget curl unzip nano htop -y
echo ""
echo ""
echo "=> Outils de base installés"
echo ""
echo ""



# -----------------------------
# SSH : configuration
# -----------------------------
echo ""
echo ""
echo "=> Configuration de SSH..."
echo ""
echo ""
# Détecter l'IP du serveur automatiquement
SERVER_IP=$(hostname -I | awk '{print $1}')

# Copier la clé SSH (à exécuter depuis l'ordinateur local)
# Ex: ssh-copy-id -i ~/.ssh/id_rsa.pub "$ADMIN_USERNAME@$DOMAIN"
echo ""
echo ""
echo "=> Veuillez copier votre clé SSH sur le serveur depuis votre ordinateur local :"
echo "     ssh-copy-id -i ~/.ssh/id_rsa.pub $ADMIN_USERNAME@$SERVER_IP"
read -p "   Appuyez sur Entrée une fois la clé copiée pour continuer..."
echo ""
echo ""

# Configurer SSH
SSHD_CONFIG_SRC="$SCRIPT_DIR/sshd_config"

if [ -f "$SSHD_CONFIG_SRC" ]; then
    mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    cp "$SSHD_CONFIG_SRC" /etc/ssh/sshd_config

    # Remplacer le port SSH dans sshd_config
    if [ -n "$SSH_PORT" ]; then
        sed -i "s/{port}/$SSH_PORT/g" /etc/ssh/sshd_config
        echo ""
        echo ""
        echo "=> Port SSH changé en $SSH_PORT dans sshd_config"
        echo ""
        echo ""
    else
        echo ""
        echo ""
        echo "=> Variable SSH_PORT non définie dans setup.conf"
        echo ""
        echo ""
        echo "#############################################"
        echo "#       Installation interrompue !          #"
        echo "#############################################"
        echo ""
        exit 1
    fi

    systemctl restart ssh
    echo ""
    echo ""
    echo "=> Configuration SSH appliquée"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Fichier sshd_config introuvable dans $SCRIPT_DIR, passez cette étape"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi



# -----------------------------
# Configuration de base du pare-feu (UFW)
# -----------------------------
echo ""
echo ""
echo "=> Configuration du pare-feu UFW..."
echo ""
echo ""
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing

# Autoriser ssh sur le port personnalisé
ufw allow $SSH_PORT/tcp

ufw --force enable
echo ""
echo ""
echo "=> Pare-feu configuré et activé"
echo ""
echo ""



# -----------------------------
# Installer et configurer Fail2Ban
# -----------------------------
echo ""
echo ""
echo "=> Installation et configuration de Fail2Ban..."
echo ""
echo ""
apt install fail2ban -y

JAIL_LOCAL_SRC="$SCRIPT_DIR/jail.local"
if [ -f "$JAIL_LOCAL_SRC" ]; then
    cp "$JAIL_LOCAL_SRC" /etc/fail2ban/jail.local
    systemctl restart fail2ban
    echo ""
    echo ""
    echo "=> Fail2Ban configuré et redémarré"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Fichier jail.local introuvable dans $SCRIPT_DIR, passez cette étape"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi



# -----------------------------
# Installer Nginx
# -----------------------------
echo ""
echo ""
echo "=> Installation de Nginx..."
echo ""
echo ""
apt install nginx -y
systemctl enable nginx
systemctl start nginx
echo ""
echo ""
echo "=> Nginx installé et activé"
echo ""
echo ""



# -----------------------------
# Ouvrir les ports pour Nginx
# -----------------------------
echo ""
echo ""
echo "=> Ouverture des ports Nginx dans le pare-feu..."
echo ""
echo ""
# HTTPS
ufw allow 443/tcp

# HTTP
ufw allow 80/tcp

echo ""
echo ""
echo "=> Ports Nginx ouverts dans le pare-feu"
echo ""
echo ""



# -----------------------------
# Installer PHP 8.2 FPM et extensions
# -----------------------------
echo ""
echo ""
echo "=> Installation de PHP 8.2 FPM et extensions..."
echo ""
echo ""
apt install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt update

apt install php8.2 php8.2-fpm php8.2-mysql php8.2-cli php8.2-curl php8.2-xml php8.2-mbstring -y
systemctl enable php8.2-fpm
systemctl start php8.2-fpm

echo ""
echo ""
echo "=> PHP 8.2 FPM et extensions installés et activés"
echo ""
echo ""



# -----------------------------
# Installer ASP.NET Core 9 Runtime
# -----------------------------
echo ""
echo ""
echo "=> Installation de ASP.NET Core 9 Runtime..."
echo ""
echo ""
add-apt-repository ppa:dotnet/backports -y
apt update
apt install -y aspnetcore-runtime-9.0

echo ""
echo ""
echo "=> ASP.NET Core 9 Runtime installé"
echo ""
echo ""



# -----------------------------
# Installer MariaDB et configurer l'utilisateur admin
# -----------------------------
apt install mariadb-server mariadb-client -y

# Sécuriser MariaDB : suppression des utilisateurs anonymes et base test
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb mysql -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"

# Créer l'utilisateur administrateur MariaDB avec les variables du setup.conf
mariadb -e "CREATE USER IF NOT EXISTS '$DB_ADMIN_USERNAME'@'localhost' IDENTIFIED BY '$DB_ADMIN_PASSWORD';"
mariadb -e "GRANT ALL PRIVILEGES ON *.* TO '$DB_ADMIN_USERNAME'@'localhost' WITH GRANT OPTION;"
mariadb -e "FLUSH PRIVILEGES;"

# Activer le service MariaDB
systemctl enable mariadb
systemctl start mariadb

echo ""
echo ""
echo "=> MariaDB installé et utilisateur $DB_ADMIN_USERNAME configuré"
echo ""
echo ""



# -----------------------------
# Installer Certbot pour Let’s Encrypt
# -----------------------------
echo ""
echo ""
echo "=> Installation de Certbot pour Nginx..."
echo ""
echo ""
apt install certbot python3-certbot-nginx -y
echo ""
echo ""
echo "=> Certbot installé pour Nginx"
echo ""
echo ""



# -----------------------------
# Installer phpMyAdmin
# -----------------------------
echo ""
echo ""
echo "=> Installation et configuration de phpMyAdmin..."
echo ""
echo ""
# Créer l’arborescence
mkdir -p /var/www/phpmyadmin/httpdocs
chown -R www-data:www-data /var/www
chmod -R 774 /var/www
udo chmod g+s /var/www/
echo ""
echo ""
echo "=> Arborescence phpMyAdmin créée"
echo ""
echo ""

# Copier les fichiers de phpMyAdmin depuis le dossier setup
PHPMA_SRC="$SCRIPT_DIR/phpMyAdmin-5.2.2-all-languages"
if [ -d "$PHPMA_SRC" ]; then
    cp -r "$PHPMA_SRC"/* /var/www/phpmyadmin/httpdocs/
    chown -R www-data:www-data /var/www/phpmyadmin/httpdocs
    chmod -R 774 /var/www/phpmyadmin/httpdocs

    mkdir -p /var/www/phpmyadmin/logs
    chown -R www-data:www-data /var/www/phpmyadmin/logs
    chmod -R 774 /var/www/phpmyadmin/logs
    echo ""
    echo ""
    echo "=> Fichiers phpMyAdmin copiés et permissions appliquées"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Dossier phpMyAdmin introuvable : $PHPMA_SRC"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

# Configurer Nginx (http)
NGINX__TEMP_CONF_SRC="$SCRIPT_DIR/phpmyadmin.temp.conf"
if [ -f "$NGINX__TEMP_CONF_SRC" ]; then
    cp "$NGINX__TEMP_CONF_SRC" /etc/nginx/sites-available/phpmyadmin.conf
    sed -i "s/{name}/$PHPMA_DOMAIN/g" /etc/nginx/sites-available/phpmyadmin.conf
    ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
    systemctl reload nginx
    echo ""
    echo ""
    echo "=> Configuration temporaire Nginx pour phpMyAdmin appliquée"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Fichier phpmyadmin.temp.conf introuvable dans $SCRIPT_DIR"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

# Configurer HTTPS avec Certbot
certbot --nginx -d "$PHPMA_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect --no-eff-email
echo ""
echo ""
echo "=> HTTPS configuré pour phpMyAdmin"
echo ""
echo ""

# Configurer Nginx (https)
NGINX__CONF_SRC="$SCRIPT_DIR/phpmyadmin.conf"
if [ -f "$NGINX__CONF_SRC" ]; then
    cp "$NGINX__CONF_SRC" /etc/nginx/sites-available/
    sed -i "s/{name}/$PHPMA_DOMAIN/g" /etc/nginx/sites-available/phpmyadmin.conf
    ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
    systemctl reload nginx
    echo ""
    echo ""
    echo "=> Configuration définitive Nginx pour phpMyAdmin appliquée"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Fichier phpmyadmin.conf introuvable dans $SCRIPT_DIR"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

# Restreindre l’accès avec htpasswd
apt install apache2-utils -y
htpasswd -cb /var/www/phpmyadmin/.htpasswd "$PHPMA_USERNAME" "$PHPMA_PASSWORD"
echo ""
echo ""
echo "=> Accès phpMyAdmin protégé par htpasswd"
echo ""
echo ""

# Activer le site dans Nginx
systemctl reload nginx
echo ""
echo ""
echo "=> Site phpMyAdmin activé dans Nginx"
echo ""
echo ""



# -----------------------------
# Installer et configurer VsFTPd
# -----------------------------
echo ""
echo ""
echo "=> Installation et configuration de VsFTPd..."
echo ""
echo ""
apt install vsftpd -y
echo ""
echo ""
echo "=> VsFTPd installé"
echo ""
echo ""

# Ouvrir les ports pour FTP et FTP passif
ufw allow 21/tcp
ufw allow 40000:50000/tcp
echo ""
echo ""
echo "=> Ports FTP ouverts dans le pare-feu"
echo ""
echo ""

# Configurer VsFTPd
VSFTPD_CONF_SRC="$SCRIPT_DIR/vsftpd.conf"
if [ -f "$VSFTPD_CONF_SRC" ]; then
    cp "$VSFTPD_CONF_SRC" /etc/vsftpd.conf
    touch /etc/vsftpd.userlist
    systemctl restart vsftpd
    echo ""
    echo ""
    echo "=> VsFTPd configuré avec le fichier de setup"
    echo ""
    echo ""
else
    echo ""
    echo ""
    echo "=> Fichier vsftpd.conf introuvable dans $SCRIPT_DIR"
    echo ""
    echo ""
    echo "#############################################"
    echo "#       Installation interrompue !          #"
    echo "#############################################"
    echo ""
    exit 1
fi

# Créer le compte FTP admin web
ENCRYPTED_FTP_PASSWORD=$(openssl passwd -1 "$FTP_ADMIN_PASSWORD")

if id "$FTP_ADMIN_USERNAME" &>/dev/null; then
    usermod -aG www-data "$FTP_ADMIN_USERNAME"
    chown -R "$FTP_ADMIN_USERNAME":www-data /var/www
    echo ""
    echo ""
    echo "=> $FTP_ADMIN_USERNAME" >> /etc/vsftpd.userlist
    echo "=> Utilisateur FTP $FTP_ADMIN_USERNAME existe déjà, mais ajouté à la liste des utilisateurs"
    echo ""
    echo ""
else
    useradd -m -s /bin/bash --home /var/www --shell /bin/false -p "$ENCRYPTED_FTP_PASSWORD" "$FTP_ADMIN_USERNAME"
    usermod -aG www-data "$FTP_ADMIN_USERNAME"
    chown -R "$FTP_ADMIN_USERNAME":www-data /var/www
    echo ""
    echo ""
    echo "$FTP_ADMIN_USERNAME" >> /etc/vsftpd.userlist
    echo "=> Compte FTP admin $FTP_ADMIN_USERNAME créé et ajouté à la liste des utilisateurs"
    echo ""
    echo ""
fi



# -----------------------------
# Configurer logrotate pour /var/www/**/logs/*.log
# -----------------------------
echo ""
echo ""
echo "=> Configuration de logrotate pour /var/www/**/logs/*.log..."
echo ""
echo ""
LOGROTATE_FILE="/etc/logrotate.d/www_logs"

cat <<EOF > "$LOGROTATE_FILE"
/var/www/*/logs/*.log {
    daily
    missingok
    rotate $LOG_RETENTION_DAYS
    compress
    delaycompress
    notifempty
    copytruncate
    su www-data www-data
}
EOF



echo ""
echo ""
echo "=> Logrotate configuré pour /var/www/**/logs/*.log (conservation : $LOG_RETENTION_DAYS jours)"
echo ""
echo ""



# -----------------------------
# Configurer le site par défaut Nginx
# -----------------------------
echo ""
echo ""
echo "=> Configuration du site par défaut Nginx pour refuser les connexions..."
echo ""
echo ""
rm /etc/nginx/sites-enabled/default
cp "$SCRIPT_DIR/default_refuse" /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/default_refuse /etc/nginx/sites-enabled/
systemctl reload nginx
echo ""
echo ""
echo "=> Site par défaut Nginx configuré pour refuser les connexions"
echo ""
echo ""


# -----------------------------
# Installation de MSMTP
# -----------------------------
echo ""
echo ""
echo "=> Installation de MSMTP pour l'envoi d'emails..."
echo ""
echo ""
DEBIAN_FRONTEND=noninteractive apt install -y msmtp msmtp-mta
echo ""
echo ""
echo "=> MSMTP installé"
echo ""
echo ""



# ------------------------------
# Configurer MSMTP
# ------------------------------
echo ""
echo ""
echo "=> Configuration de MSMTP..."
echo ""
echo ""
cp "$SCRIPT_DIR/msmtprc" /etc/msmtprc
chmod 600 /etc/msmtprc
chown root:root /etc/msmtprc
sed -i "s/{host}/$SMTP_SERVER/g" /etc/msmtprc
sed -i "s/{port}/$SMTP_PORT/g" /etc/msmtprc
sed -i "s/{from}/$SMTP_FROM/g" /etc/msmtprc
sed -i "s/{user}/$SMTP_USERNAME/g" /etc/msmtprc
sed -i "s/{password}/$SMTP_PASSWORD/g" /etc/msmtprc
if [[ "$SMTP_TLS" =~ ^(true|True|1|yes|YES|Yes)$ ]]; then
    sed -i "s/{tls}/on/g" /etc/msmtprc
else
    sed -i "s/{tls}/off/g" /etc/msmtprc
fi
touch /var/log/msmtp.log
chmod 660 /var/log/msmtp.log
chown root:root /var/log/msmtp.log
echo ""
echo ""
echo "=> MSMTP configuré"
echo ""
echo ""



# -----------------------------
# Redémarrage du service SSH
# -----------------------------
echo ""
echo ""
echo "=> Redémarrage du service SSH..."
echo ""
echo ""
systemctl restart ssh
echo ""
echo ""
echo "=> Redémarrage du service SSH effectué"
echo ""
echo ""



# -----------------------------
# Sauvegarde des sites
# -----------------------------
echo ""
echo ""
echo "=> Installation et configuration du script de sauvegarde..."
echo ""
echo ""
apt-get install -y sshpass
mkdir -p /etc/server_backup
cp "$SCRIPT_DIR/backup.sh" /etc/server_backup/backup.sh
chmod 750 /etc/server_backup/backup.sh
chown root:root /etc/server_backup/backup.sh
touch /etc/server_backup/backup.conf
chmod 640 /etc/server_backup/backup.conf
chown root:root /etc/server_backup/backup.conf
echo "DB_ADMIN_USERNAME=\"${DB_ADMIN_USERNAME}\"" > /etc/server_backup/backup.conf
echo "DB_ADMIN_PASSWORD=\"${DB_ADMIN_PASSWORD}\"" >> /etc/server_backup/backup.conf
echo "BACKUP_LOCAL_PATH=${BACKUP_LOCAL_PATH}" >> /etc/server_backup/backup.conf
echo "BACKUP_KEEP_LOCAL=${BACKUP_KEEP_LOCAL}" >> /etc/server_backup/backup.conf
echo "BACKUP_KEEP_REMOTE=${BACKUP_KEEP_REMOTE}" >> /etc/server_backup/backup.conf
echo "BACKUP_INCLUDE_ETC=${BACKUP_INCLUDE_ETC}" >> /etc/server_backup/backup.conf
echo "BACKUP_TIME=${BACKUP_TIME}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_HOST=${BACKUP_SFTP_HOST}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_PORT=${BACKUP_SFTP_PORT}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_USER=${BACKUP_SFTP_USER}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_PASS=${BACKUP_SFTP_PASS}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_REMOTE_PATH=${BACKUP_SFTP_REMOTE_PATH}" >> /etc/server_backup/backup.conf
echo "BACKUP_LOG_FILE=${BACKUP_LOG_FILE}" >> /etc/server_backup/backup.conf
echo "BACKUP_ALERT_EMAIL=${BACKUP_ALERT_EMAIL}" >> /etc/server_backup/backup.conf

# Ajouter une tâche cron pour les sauvegardes
if [[ "$BACKUP_TIME" =~ ^([0-1][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
    hh="${BASH_REMATCH[1]}"
    mm="${BASH_REMATCH[2]}"
else
    echo "Format BACKUP_TIME invalide (${BACKUP_TIME}), utilisation 03:00 par défaut."
    hh="03"
    mm="00"
fi
cron_entry="${mm} ${hh} * * * /etc/server_backup/backup.sh >> ${BACKUP_LOG_FILE} 2>&1"
(crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
echo ""
echo ""
echo "=> Script de sauvegarde configuré"
echo ""
echo ""



# -----------------------------
# Copie du script add_php_site.sh
# -----------------------------
echo ""
echo ""
echo "=> Copie du script add_php_site.sh dans /etc/server_setup/"
echo ""
echo ""
mkdir -p /etc/server_setup
chmod 750 /etc/server_setup
chown root:root /etc/server_setup
cp "$SCRIPT_DIR/add_php_site.sh" /etc/server_setup/add_php_site.sh
sed -i "s/{email}/$ADMIN_EMAIL/g" /etc/server_setup/add_php_site.sh
chmod 750 /etc/server_setup/add_php_site.sh
chown root:root /etc/server_setup/add_php_site.sh
cp "$SCRIPT_DIR/site.temp.conf" /etc/server_setup/site.temp.conf
chmod 640 /etc/server_setup/site.temp.conf
chown root:root /etc/server_setup/site.temp.conf
cp "$SCRIPT_DIR/site.conf" /etc/server_setup/site.conf
chmod 640 /etc/server_setup/site.conf
chown root:root /etc/server_setup/site.conf
echo ""
echo ""
echo "=> Script add_php_site.sh copié dans /etc/server_setup/"
echo ""
echo ""



# -----------------------------
# Suppression des mots de passe du fichier setup.conf
# -----------------------------
echo ""
echo ""
echo "=> Suppression des mots de passe du fichier setup.conf..."
echo ""
echo ""
sed -i "s/ADMIN_PASSWORD=\"$ADMIN_PASSWORD\"/ADMIN_PASSWORD=\"\"/g" $SCRIPT_DIR/setup.conf
sed -i "s/DB_ADMIN_PASSWORD=\"$DB_ADMIN_PASSWORD\"/DB_ADMIN_PASSWORD=\"\"/g" $SCRIPT_DIR/setup.conf
sed -i "s/PHPMA_PASSWORD=\"$PHPMA_PASSWORD\"/PHPMA_PASSWORD=\"\"\"/g" $SCRIPT_DIR/setup.conf
sed -i "s/FTP_ADMIN_PASSWORD=\"$FTP_ADMIN_PASSWORD\"/FTP_ADMIN_PASSWORD=\"\"/g" $SCRIPT_DIR/setup.conf
sed -i "s/BACKUP_SFTP_PASS=\"$BACKUP_SFTP_PASS\"/BACKUP_SFTP_PASS=\"\"/g" $SCRIPT_DIR/setup.conf
sed -i "s/SMTP_PASSWORD=\"$SMTP_PASSWORD\"/SMTP_PASSWORD=\"\"/g" $SCRIPT_DIR/setup.conf
echo ""
echo ""
echo "=> Mots de passe supprimés du fichier setup.conf"
echo ""
echo ""



# -----------------------------
# Copie des fichiers de configuration dans /etc/server_setup
# -----------------------------
echo ""
echo ""
echo "=> Copie des fichiers de configuration dans /etc/server_setup..."
echo ""
echo ""
cp "$SCRIPT_DIR/setup.conf" /etc/server_setup/setup.conf
chmod 640 /etc/server_setup/setup.conf
chown root:root /etc/server_setup/setup.conf
cp "$SCRIPT_DIR/setup.sh" /etc/server_setup/setup.sh
chmod 750 /etc/server_setup/setup.sh
chown root:root /etc/server_setup/setup.sh
echo ""
echo ""
echo "=> Fichiers de configuration copiés dans /etc/server_setup"
echo ""
echo ""



echo "#############################################"
echo "#       Installation terminée !             #"
echo "#############################################"
echo ""
exit 0