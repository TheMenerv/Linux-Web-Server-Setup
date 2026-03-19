#!/bin/bash
# backup.sh
# Script de sauvegarde local + envoi SFTP + rotation
# - Lit la configuration depuis backup.conf
# - Dump SQL par base, sauvegarde /var/www et option /etc
# - Crée une archive unique backup_<hostname>_YYYY-MM-DD-HH-MM.tar.gz
# - Rotation locale et distante
# - Planification via cron
# - Log dans /var/log/backup.log
#
# Usage: sudo /etc/server_backups/backup.sh
set -o pipefail
IFS=$'\n\t'
HOSTNAME_SIMPLE="$(hostname -s)"
EMAIL_BODY=()



# --- Charger la configuration ---
BACKUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$BACKUP_SCRIPT_DIR/backup.conf"
source "$CONFIG_FILE"
if [[ $? -ne 0 ]]; then
  echo "Erreur: impossible de lire le fichier de configuration $CONFIG_FILE"
  EMAIL_BODY+=("Erreur: impossible de lire le fichier de configuration $CONFIG_FILE")
  exit 1
fi



# --- Fonctions utilitaires ---
fatal() {
  echo "$*"
  exit 1
}



# envoi de mail via msmtp
send_mail() {
  local subject="$1"
  local body="$2"
  echo -e "Subject:$subject" "\n\n" "$body" | msmtp -a default "$BACKUP_ALERT_EMAIL"
}



# vérifie si on est root pour certaines opérations (cron install / apt)
is_root() { [[ "$(id -u)" -eq 0 ]]; }



# formate l'heure en timestamp utilisable pour le nom
timestamp() { date '+%F-%H-%M'; }



# génère nom d'archive
ARCHIVE_NAME() {
  echo "backup_${HOSTNAME_SIMPLE}_$(timestamp).tar.gz"
}



# suppression d'un nombre d'archives locales en trop
rotate_local() {
  local path="$1" keep="$2" prefix="$3"
  mkdir -p "$path"
  # lister fichiers correspondants, trier, garder les + récents
  mapfile -t files < <(ls -1 "${path}/${prefix}"* 2>/dev/null || true)
  local total="${#files[@]}"
  if (( total <= keep )); then
    echo "Rotation locale: ${total} fichiers trouvés ≤ ${keep}, rien à supprimer."
    return 0
  fi
  # supprimer les plus anciens
  local toremove=$(( total - keep ))
  echo "Rotation locale: ${total} fichiers trouvés, suppression de ${toremove} plus anciens."
  for ((i=0; i<toremove; i++)); do
    rm -f -- "${files[i]}" && echo "Suppression locale: ${files[i]}" || echo "Échec suppression locale: ${files[i]}"
  done
}



# lister fichiers distants via sftp et retourner en stdout la liste triée (nom complet)
remote_list() {
  local remote_dir="$1"
  local batchfile
  batchfile="$(mktemp)"
  echo "ls $remote_dir" >"$batchfile"
  local out
  if command -v sshpass >/dev/null 2>&1; then
    out="$(sshpass -p "$BACKUP_SFTP_PASS" sftp -oBatchMode=no -P "$BACKUP_SFTP_PORT" "$BACKUP_SFTP_USER@$BACKUP_SFTP_HOST" -b "$batchfile" 2>/dev/null)"
    if [[ $? -ne 0 ]]; then
      echo "Échec de la liste des fichiers distants."
      rm -f "$batchfile"
      EMAIL_BODY+=("Échec de la liste des fichiers distants sur le serveur $HOSTNAME_SIMPLE.")
      return 1
    fi
  else
    if command -v expect >/dev/null 2>&1; then
      out="$(/usr/bin/expect -c "set timeout -1; spawn sftp -oBatchMode=no -P $BACKUP_SFTP_PORT $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST; expect \"password:\"; send \"$BACKUP_SFTP_PASS\r\"; expect \"sftp>\"; send \"ls $remote_dir\r\"; expect \"sftp>\"; send \"bye\r\"; expect eof" 2>/dev/null || true)"
    else
      rm -f "$batchfile"
      echo "sshpass et expect absents: impossible de lister les fichiers distants."
      EMAIL_BODY+=("sshpass et expect absents: impossible de lister les fichiers distants sur le serveur $HOSTNAME_SIMPLE.")
      return 1
    fi
  fi
  rm -f "$batchfile"

  # Parser la sortie: prendre le dernier champ de chaque ligne (nom de fichier)
  # On récupère uniquement les lignes contenant notre préfixe backup_${HOSTNAME_SIMPLE}_
  echo "$out" | \
    awk -v prefix="backup_${HOSTNAME_SIMPLE}_" '{
      # si la ligne contient prefix ou si la ligne ressemble à un nom simple, sortir dernier champ
      for(i=1;i<=NF;i++) if ($i ~ prefix) { print $i; next }
      # sinon imprimer dernier champ
      if (NF>0) print $NF
    }' | sed '/^$/d' | sort
  return 0
}



# supprimer fichier distant via sftp
remote_delete() {
  local fname="$1"
  local batchfile
  batchfile="$(mktemp)"
  cat >"$batchfile" <<EOF
rm $fname
bye
EOF
  if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$BACKUP_SFTP_PASS" sftp -oBatchMode=no -P "$BACKUP_SFTP_PORT" "$BACKUP_SFTP_USER@$BACKUP_SFTP_HOST" -b "$batchfile" >>"$BACKUP_LOG_FILE" 2>&1
    if [[ $? -ne 0 ]]; then
      echo "Échec de la suppression distante $fname"
      EMAIL_BODY+=("Échec de la suppression distante du fichier $fname sur le serveur $HOSTNAME_SIMPLE.")
      rm -f "$batchfile"
      return 1
    fi
    local rc=$?
    rm -f "$batchfile"
    return $rc
  else
    if command -v expect >/dev/null 2>&1; then
      /usr/bin/expect <<EOF >>"$LOG_FILE" 2>&1
set timeout -1
spawn sftp -oBatchMode=no -P $BACKUP_SFTP_PORT $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST
expect "password:"
send "$BACKUP_SFTP_PASS\r"
expect "sftp>"
send "rm $fname\r"
expect "sftp>"
send "bye\r"
expect eof
EOF
      rm -f "$batchfile"
      if [[ $? -ne 0 ]]; then
        echo "Échec de la suppression distante $fname"
        EMAIL_BODY+=("Échec de la suppression distante du fichier $fname sur le serveur $HOSTNAME_SIMPLE.")
        return 1
      fi
      return $?
    else
      rm -f "$batchfile"
      echo "sshpass et expect absents: impossible de supprimer distant $fname"
      EMAIL_BODY+=("sshpass et expect absents: impossible de supprimer distant $fname sur le serveur $HOSTNAME_SIMPLE.")
      return 2
    fi
  fi
}



### --- Début du travail --- ###
echo "=== Début sauvegarde ==="



# s'assurer que le dossier local existe
mkdir -p "$BACKUP_LOCAL_PATH" || fatal "Impossible de créer $BACKUP_LOCAL_PATH"



# Préparer répertoire temporaire
TS="$(date '+%F_%H-%M')"
TMPDIR="$(mktemp -d "/var/temp_backup_${TS}.XXXX")"
if [[ ! -d "$TMPDIR" ]]; then
  fatal "Impossible de créer répertoire temporaire."
fi
echo "Répertoire temporaire créé: $TMPDIR"



# 1) Dump SQL par base
SQL_DIR="${TMPDIR}/db"
mkdir -p "$SQL_DIR"
echo "Début dump SQL par base..."
# lister les bases, exclure celles système
readarray -t DBS < <(
  mysql -u "${DB_ADMIN_USERNAME}" --password="${DB_ADMIN_PASSWORD}" -e "SHOW DATABASES;" -s --skip-column-names | grep -Ev "^(information_schema|performance_schema|mysql|sys)$"
)
if [[ $? -ne 0 ]]; then
  echo "Échec de la commande SHOW DATABASES."
  DBS=()
  EMAIL_BODY+=("Échec de la commande SHOW DATABASES sur le serveur $HOSTNAME_SIMPLE.")
fi
if (( ${#DBS[@]} == 0 )); then
  echo "Aucune base trouvée ou échec de la commande SHOW DATABASES. On continue sans dump SQL."
else
  for db in "${DBS[@]}"; do
    outfile="${SQL_DIR}/${db}_$(date '+%F').sql"
    echo "Dump de la base: $db -> $(basename "$outfile")"
    mysqldump -u "${DB_ADMIN_USERNAME}" --password="${DB_ADMIN_PASSWORD}" --databases "$db" > "$outfile" || {
      echo "Échec mysqldump pour $db"
      EMAIL_BODY+=("Échec mysqldump pour la base $db sur le serveur $HOSTNAME_SIMPLE.")
    }
  done
fi



# 2) On va créer une archive unique contenant :
#    - le dossier db/ (dumps)
#    - /var/www
#    - /etc si demandé
ARCHIVE_FILENAME="$(ARCHIVE_NAME)"
ARCHIVE_PATH="${BACKUP_LOCAL_PATH}/${ARCHIVE_FILENAME}"

echo "Création de l'archive ${ARCHIVE_PATH} ..."

pushd "$TMPDIR" >/dev/null 2>&1 || fatal "Impossible de se placer dans $TMPDIR"

# dossier db déjà dans TMPDIR
mkdir -p "${TMPDIR}/db"  # au cas où
# Inclure db, /var/www et optionnellement /etc
if [[ "$BACKUP_INCLUDE_ETC" =~ ^(true|True|1|yes|YES|Yes)$ ]]; then
    tar -czf "$ARCHIVE_PATH" -C "$TMPDIR" db -C / var/www -C / etc >>"$BACKUP_LOG_FILE" 2>&1 || {
        echo "Echec création archive (avec /etc)."
        rm -rf "$TMPDIR"
        EMAIL_BODY+=("Échec de la création de l'archive de sauvegarde (avec /etc) sur le serveur $HOSTNAME_SIMPLE.")
        exit 1
    }
else
    tar -czf "$ARCHIVE_PATH" -C "$TMPDIR" db -C / var/www >>"$BACKUP_LOG_FILE" 2>&1 || {
        echo "Echec création archive."
        rm -rf "$TMPDIR"
        EMAIL_BODY+=("Échec de la création de l'archive de sauvegarde sur le serveur $HOSTNAME_SIMPLE.")
        exit 1
    }
fi

popd >/dev/null 2>&1 || true
echo "Archive créée : $ARCHIVE_PATH (taille: $(du -h "$ARCHIVE_PATH" | cut -f1))"



# 3) Rotation locale
rotate_local "$BACKUP_LOCAL_PATH" "$BACKUP_KEEP_LOCAL" "backup_${HOSTNAME_SIMPLE}_"
if [[ $? -ne 0 ]]; then
  EMAIL_BODY+=("Échec de la rotation locale sur le serveur $HOSTNAME_SIMPLE.")
fi



# 4) Upload SFTP
sshpass -p $BACKUP_SFTP_PASS scp -P $BACKUP_SFTP_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $ARCHIVE_PATH $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST:.
if [[ $? -ne 0 ]]; then
  echo "Échec de l'upload SFTP vers $BACKUP_SFTP_HOST"
  EMAIL_BODY+=("Échec de l'upload SFTP vers $BACKUP_SFTP_HOST depuis le serveur $HOSTNAME_SIMPLE.")
else
  echo "Upload SFTP réussi vers $BACKUP_SFTP_HOST"
fi



# 5) Rotation distante : lister fichiers puis supprimer les plus anciens
FILES=$(sshpass -p "$BACKUP_SFTP_PASS" sftp -P $BACKUP_SFTP_PORT -o StrictHostKeyChecking=no $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST << EOF
ls -l *.tar.gz
EOF
)
if [[ $? -ne 0 ]]; then
  echo "Échec de la liste des fichiers distants."
  EMAIL_BODY+=("Échec de la liste des fichiers distants sur le serveur $HOSTNAME_SIMPLE.")
  exit 1
fi
FILE_NAMES=$(echo "$FILES" | tail -n +2 | awk '{print $NF}' | grep -w "$HOSTNAME_SIMPLE")
COUNT=$(echo "$FILE_NAMES" | wc -l)
if [ "$COUNT" -gt "$BACKUP_KEEP_REMOTE" ]; then
  DEL=$((COUNT - BACKUP_KEEP_REMOTE))
  echo "Suppression de $DEL fichiers distants..."
  TO_DELETE=$(echo "$FILE_NAMES" | head -n $DEL)
  SCRIPT=""
  for f in $TO_DELETE; do
    SCRIPT+="rm \"$f\"\n"
  done
  echo -e "$SCRIPT" | sshpass -p "$BACKUP_SFTP_PASS" sftp -P $BACKUP_SFTP_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $BACKUP_SFTP_USER@$BACKUP_SFTP_HOST
  if [[ $? -ne 0 ]]; then
    echo "Échec de la rotation distante."
    EMAIL_BODY+=("Échec de la rotation distante sur le serveur $HOSTNAME_SIMPLE.")
  else
    echo "Rotation distante effectuée."
  fi
fi



# 6) Nettoyage temporaire
rm -rf "$TMPDIR"
echo "Nettoyage du temporaire effectué."



# 7) Envoi email si nécessaire
if (( ${#EMAIL_BODY[@]} > 0 )); then
  EMAIL_BODY=("Bonjour,\n\nLe script de sauvegarde sur le serveur $HOSTNAME_SIMPLE a rencontré des problèmes:\n" "${EMAIL_BODY[@]}" "\nConsultez le journal \"$BACKUP_LOG_FILE\".")
  send_mail "Alertes sauvegarde serveur $HOSTNAME_SIMPLE" "$(printf '%s\n' "${EMAIL_BODY[@]}")"
fi
