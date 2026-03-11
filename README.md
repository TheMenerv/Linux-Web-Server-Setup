# Déploiement Serveur Linux Web

## Résumé

- Guide minimal pour déployer un serveur web Linux (Ubuntu/Debian) avec Nginx, HTTPS (Let's Encrypt), firewall et service systemd.
- Conventions : les commandes sont lancées en tant que `root` ou avec `sudo`.

---

## Prérequis

- Machine Ubuntu/Debian (Ubuntu 24.04+ recommendé).
- Accès SSH et droit sudo.
- Nom de domaine pointant vers l'IP publique.

---

## Que fait l'installateur `setup.sh` ?

1. Changement du nom d'hôte.
```bash
sudo hostnamectl set-hostname {{hostname}}
systemctl restart systemd-logind
```

2. Mise à jour le système
```bash
apt update
apt upgrade -y
apt autoremove -y
```

3. Création d'un utilisateur administrateur
```bash
useradd -m -s /bin/bash -p "{{password}}" "{{username}}"
usermod -aG sudo "{{username}}"
```

4. Installation des outils de base
```bash
apt install wget curl unzip nano htop -y
```

5. Configuration SSH
```bash
mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
cp {{script_directory}}/sshd_config /etc/ssh/sshd_config
sed -i "s/{port}/{{ssh_port}}/g" /etc/ssh/sshd_config
systemctl restart sshd
```

6. Installation et configuration du pare-feu
```bash
apt install ufw -y
ufw default deny incoming
ufw default allow outgoing
ufw allow {{ssh_port}}/tcp
ufw --force enable
```

7. Installation et configuration de Fail2Ban
```bash
apt install fail2ban -y
cp {{script_directory}}/jail.local /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl restart fail2ban
```

8. Installation de Nginx
```bash
apt install nginx -y
systemctl enable nginx
systemctl start nginx
```

9. Ouverture des ports HTTP et HTTPS dans le pare-feu
```bash
ufw allow 443/tcp
ufw allow 80/tcp
ufw reload
```

10. Installation de PHP 8.2 FPM et extensions courantes
```bash
apt install software-properties-common -y
add-apt-repository ppa:ondrej/php -y
apt update
apt install php8.2 php8.2-fpm php8.2-mysql php8.2-cli php8.2-curl php8.2-xml php8.2-mbstring -y
systemctl enable php8.2-fpm
systemctl start php8.2-fpm
```

11. Installation de .Net Core 9 Runtime
```bash
add-apt-repository ppa:dotnet/backports -y
apt update
apt install -y aspnetcore-runtime-9.0
```

12. Installation et configuration de MariaDB
```bash
apt install mariadb-server mariadb-client -y
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb mysql -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -e "CREATE USER IF NOT EXISTS '{{username}}'@'localhost' IDENTIFIED BY '{{password}}';"
mariadb -e "GRANT ALL PRIVILEGES ON *.* TO '{{username}}'@'localhost' WITH GRANT OPTION;"
mariadb -e "FLUSH PRIVILEGES;"
systemctl enable mariadb
systemctl start mariadb
```

13. Installation de Certbot pour Let's Encrypt
```bash
apt install certbot python3-certbot-nginx -y
```

14. Installation de phpMyAdmin
```bash
mkdir -p /var/www/phpmyadmin/httpdocs
chown -R www-data:www-data /var/www
chmod -R 774 /var/www
chmod g+s /var/www/
cp -r "{{script_directory}}/phpMyAdmin-5.2.2-all-languages"/* /var/www/phpmyadmin/httpdocs/
chown -R www-data:www-data /var/www/phpmyadmin/httpdocs
chmod -R 774 /var/www/phpmyadmin/httpdocs
mkdir -p /var/www/phpmyadmin/logs
chown -R www-data:www-data /var/www/phpmyadmin/logs
chmod -R 774 /var/www/phpmyadmin/logs
```

15. Configuration de Nginx pour phpMyAdmin en HTTP
```bash
cp "{{script_directory}}/phpmyadmin.temp.conf" /etc/nginx/sites-available/phpmyadmin.conf
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/phpmyadmin.conf
ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

16. Obtention du certificat HTTPS pour phpMyAdmin
```bash
certbot --nginx -d "{{domain}}" --non-interactive --agree-tos -m "{{email}}" --redirect --no-eff-email
```

17. Configuration de Nginx pour phpMyAdmin en HTTPS
```bash
cp "{{script_directory}}/phpmyadmin.conf" /etc/nginx/sites-available/
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/phpmyadmin.conf
ln -sf /etc/nginx/sites-available/phpmyadmin.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

18. Ajout d'une authentification HTPASSWD pour phpMyAdmin
```bash
apt install apache2-utils -y
htpasswd -cb /var/www/phpmyadmin/.htpasswd "{{username}}" "{{password}}"
systemctl reload nginx
```

19. Installation de VsFTPd
```bash
apt install vsftpd -y
```

20. Ouverture des ports FTP(S) et FTP(s) passif
```bash
ufw allow 21/tcp
ufw allow 40000:50000/tcp
```

21. Configuration de VsFTPd
```bash
cp "{{script_directory}}/vsftpd.conf" /etc/vsftpd.conf
touch /etc/vsftpd.userlist
systemctl restart vsftpd
```

22. Créer l'utilisateur racine FTP(S)
```bash
useradd -m -s /bin/bash --home /var/www --shell /bin/false -p "{{password}}" "{{username}}"
usermod -aG www-data "{{username}}"
chown -R "{{username}}":www-data /var/www
```

23. Configuration de logrotate
```bash
cat <<EOF > "/etc/logrotate.d/www_logs"
/var/www/*/logs/*.log {
    daily
    missingok
    rotate {{retention_days}}
    compress
    delaycompress
    notifempty
    copytruncate
    su www-data www-data
}
EOF
```

24. Configuration du site Nginx par défaut
```bash
rm /etc/nginx/sites-enabled/default
cp "{{script_directory}}/default_refuse" /etc/nginx/sites-available/
ln -s /etc/nginx/sites-available/default_refuse /etc/nginx/sites-enabled/
systemctl reload nginx
```

25. Installation de MSMTP
```bash
DEBIAN_FRONTEND=noninteractive apt install -y msmtp msmtp-mta
```

26. Configuration de MSMTP
```bash
cp "{{script_directory}}/msmtprc" /etc/msmtprc
chmod 600 /etc/msmtprc
chown root:root /etc/msmtprc
sed -i "s/{host}/{{smtp_host}}/g" /etc/msmtprc
sed -i "s/{port}/{{smtp_port}}/g" /etc/msmtprc
sed -i "s/{from}/{{smtp_from}}/g" /etc/msmtprc
sed -i "s/{user}/{{smtp_username}}/g" /etc/msmtprc
sed -i "s/{password}/{{smtp_password}}/g" /etc/msmtprc
if [[ "{{smtp_tls}}" =~ ^(true|True|1|yes|YES|Yes)$ ]]; then
    sed -i "s/{tls}/on/g" /etc/msmtprc
else
    sed -i "s/{tls}/off/g" /etc/msmtprc
fi
touch /var/log/msmtp.log
chmod 660 /var/log/msmtp.log
chown root:root /var/log/msmtp.log
```

27. Redémarrage du service SSH
```bash
systemctl restart ssh
```

28. Installation et configuration de la sauvegarde des sites
```bash
apt-get install -y sshpass
mkdir -p /etc/server_backup
cp "{{script_directory}}/backup.sh" /etc/server_backup/backup.sh
chmod 750 /etc/server_backup/backup.sh
chown root:root /etc/server_backup/backup.sh
touch /etc/server_backup/backup.conf
chmod 640 /etc/server_backup/backup.conf
chown root:root /etc/server_backup/backup.conf
echo "DB_ADMIN_USERNAME=\"{{db_admin_username}}\"" > /etc/server_backup/backup.conf
echo "DB_ADMIN_PASSWORD=\"{{db_admin_password}}\"" >> /etc/server_backup/backup.conf
echo "BACKUP_LOCAL_PATH={{local_save_path}}" >> /etc/server_backup/backup.conf
echo "BACKUP_KEEP_LOCAL={{local_save_keep}}" >> /etc/server_backup/backup.conf
echo "BACKUP_KEEP_REMOTE={{remote_save_keep}}" >> /etc/server_backup/backup.conf
echo "BACKUP_INCLUDE_ETC={{etc_save}}" >> /etc/server_backup/backup.conf
echo "BACKUP_TIME={{save_time}}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_HOST={{remote_save_host}}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_PORT={{remote_save_port}}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_USER={{remote_save_username}}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_PASS={{remote_save_password}}" >> /etc/server_backup/backup.conf
echo "BACKUP_SFTP_REMOTE_PATH={{remote_save_path}}" >> /etc/server_backup/backup.conf
echo "BACKUP_LOG_FILE={{remote_save_log}}" >> /etc/server_backup/backup.conf
echo "BACKUP_ALERT_EMAIL={{alert_email}}" >> /etc/server_backup/backup.conf
```

29. Ajout de la tâche CRON de sauvegarde des sites
```bash
cron_entry="{{munite}} {{hour}} * * * /etc/server_backup/backup.sh >> {{remote_save_log}} 2>&1"
(crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
```

30. Copie du script d'ajout d'un site PHP
```bash
mkdir -p /etc/server_setup
chmod 750 /etc/server_setup
chown root:root /etc/server_setup
cp "{{script_directory}}/add_php_site.sh" /etc/server_setup/add_php_site.sh
sed -i "s/{email}/{{email}}/g" /etc/server_setup/add_php_site.sh
chmod 750 /etc/server_setup/add_php_site.sh
chown root:root /etc/server_setup/add_php_site.sh
cp "{{script_directory}}/site.temp.php.conf" /etc/server_setup/site.temp.php.conf
chmod 640 /etc/server_setup/site.temp.php.conf
chown root:root /etc/server_setup/site.temp.php.conf
cp "{{script_directory}}/site.php.conf" /etc/server_setup/site.php.conf
chmod 640 /etc/server_setup/site.php.conf
chown root:root /etc/server_setup/site.php.conf
```

31. Copie du script d'ajout d'un site .Net Core
```bash
cp "{{script_directory}}/add_dotnetcore_site.sh" /etc/server_setup/add_dotnetcore_site.sh
sed -i "s/{email}/{{email}}/g" /etc/server_setup/add_dotnetcore_site.sh
chmod 750 /etc/server_setup/add_dotnetcore_site.sh
chown root:root /etc/server_setup/add_dotnetcore_site.sh
cp "{{script_directory}}/site.temp.dotnet.conf" /etc/server_setup/site.temp.dotnet.conf
chmod 640 /etc/server_setup/site.temp.dotnet.conf
chown root:root /etc/server_setup/site.temp.conf
cp "{{script_directory}}/site.dotnet.conf" /etc/server_setup/site.dotnet.conf
chmod 640 /etc/server_setup/site.dotnet.conf
chown root:root /etc/server_setup/site.dotnet.conf
cp "{{script_directory}}/app.service" /etc/server_setup/app.service
chmod 640 /etc/server_setup/app.service
chown root:root /etc/server_setup/app.service
```

32. Suppression des mots de passe dans le fichier de configuration
```bash
sed -i "s/ADMIN_PASSWORD=\"{{password}}\"/ADMIN_PASSWORD=\"\"/g" {{script_directory}}/setup.conf
sed -i "s/DB_ADMIN_PASSWORD=\"{{password}}\"/DB_ADMIN_PASSWORD=\"\"/g" {{script_directory}}/setup.conf
sed -i "s/PHPMA_PASSWORD=\"{{password}}\"/PHPMA_PASSWORD=\"\"\"/g" {{script_directory}}/setup.conf
sed -i "s/FTP_ADMIN_PASSWORD=\"{{password}}\"/FTP_ADMIN_PASSWORD=\"\"/g" {{script_directory}}/setup.conf
sed -i "s/BACKUP_SFTP_PASS=\"{{password}}\"/BACKUP_SFTP_PASS=\"\"/g" {{script_directory}}/setup.conf
sed -i "s/SMTP_PASSWORD=\"{{password}}\"/SMTP_PASSWORD=\"\"/g" {{script_directory}}/setup.conf
```

33. Conservation des fichiers de configuration
```bash
cp "{{script_directory}}/setup.conf" /etc/server_setup/setup.conf
chmod 640 /etc/server_setup/setup.conf
chown root:root /etc/server_setup/setup.conf
cp "{{script_directory}}/setup.sh" /etc/server_setup/setup.sh
chmod 750 /etc/server_setup/setup.sh
chown root:root /etc/server_setup/setup.sh
````

---

## Ajout d'un site PHP

```bash
bash /etc/server_setup/add_php_site.sh
```

### Que fait le script ?

1. Création des dossiers
```bash
mkdir -p "/var/www/{{domain}}/httpdocs"
mkdir -p "/var/www/{{domain}}/logs"
chmod -R 774 "/var/www/{{domain}}"
chown -R www-data:www-data "/var/www/{{domain}}"
```

2. Création du compte FTP (si demandé)
```bash
useradd -m -s /bin/bash --home /var/www/{{domain}} --shell /bin/false -p "{{password}}" "{{username}}"
usermod -aG www-data "{{username}}"
chown -R {{username}}:www-data /var/www/{{domain}}
```

3. Configuration de Nginx (hhtp)
```bash
cp "/etc/server_setup/site.temp.php.conf" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/{{domain}}.conf
ln -s /etc/nginx/sites-available/{{domain}}.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

4. Obtention du certificat HTTPS
```bash
certbot --nginx -d "{{domain}}" --non-interactive --agree-tos -m "{{email}}" --redirect --no-eff-email
```

5. Configuration de Nginx (https)
```bash
cp "/etc/server_setup/site.php.conf" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/{{domain}}.conf
ln -sf /etc/nginx/sites-available/{{domain}}.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

6. Ajout de l'authentification pour le site (si demandé)
```bash
htpasswd -cb "/var/www/{{domain}}/.htpasswd" "{{username}}" "{{password}}"
chown www-data:www-data "/var/www/{{domain}}/.htpasswd"
chmod 640 "/var/www/{{domain}}/.htpasswd"
sed -i "s/# auth_basic_user_file /auth_basic_user_file /g" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/# auth_basic /auth_basic /g" /etc/nginx/sites-available/{{domain}}.conf
```

7. Rechargement de Nginx
```bash
systemctl reload nginx
```

---

## Ajout d'un site .Net Core

```bash
bash /etc/server_setup/add_dotnetcore_site.sh
```

### Que fait le script ?

1. Création des dossiers
```bash
mkdir -p "/var/www/{{domain}}/httpdocs"
mkdir -p "/var/www/{{domain}}/logs"
chmod -R 774 "/var/www/{{domain}}"
chown -R www-data:www-data "/var/www/{{domain}}"
```

2. Création du compte FTP (si demandé)
```bash
useradd -m -s /bin/bash --home /var/www/{{domain}} --shell /bin/false -p "{{password}}" "{{username}}"
usermod -aG www-data "{{username}}"
chown -R {{username}}:www-data /var/www/{{domain}}
```

3. Création du service pour l'application .Net Core
```bash
cp "/etc/server_setup/app.service" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{description}/{{app_description/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{path}/{{domain}}\/httpdocs/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{dll}/{{app_dll}}/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{environment}/{{environment}}/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{port}/{{internal_port}}/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{identifier}/{{app_name}}/g" "/etc/systemd/system/{{app_name}}.service"
sed -i "s/{name}/{{domain}}/g" "/etc/systemd/system/{{app_name}}.service"
systemctl daemon-reload
systemctl enable "{{app_name}}"
systemctl start "{{app_name}}"
```

4. Configuration de Nginx (hhtp)
```bash
cp "/etc/server_setup/site.temp.php.conf" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{internal_port}/{{internal_port}}/g" /etc/nginx/sites-available/{{domain}}.conf
ln -s /etc/nginx/sites-available/{{domain}}.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

5. Obtention du certificat HTTPS
```bash
certbot --nginx -d "{{domain}}" --non-interactive --agree-tos -m "{{email}}" --redirect --no-eff-email
```

6. Configuration de Nginx (https)
```bash
cp "/etc/server_setup/site.php.conf" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{name}/{{domain}}/g" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/{internal_port}/{{internal_port}}/g" /etc/nginx/sites-available/{{domain}}.conf
lln -sf /etc/nginx/sites-available/{{domain}}.conf /etc/nginx/sites-enabled/
systemctl reload nginx
```

7. Ajout de l'authentification pour le site (si demandé)
```bash
htpasswd -cb "/var/www/{{domain}}/.htpasswd" "{{username}}" "{{password}}"
chown www-data:www-data "/var/www/{{domain}}/.htpasswd"
chmod 640 "/var/www/{{domain}}/.htpasswd"
sed -i "s/# auth_basic_user_file /auth_basic_user_file /g" /etc/nginx/sites-available/{{domain}}.conf
sed -i "s/# auth_basic /auth_basic /g" /etc/nginx/sites-available/{{domain}}.conf
```

8. Rechargement de Nginx
```bash
systemctl reload nginx
```

---
