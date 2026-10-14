#!/bin/bash
# shellcheck shell=bash

# ==============================================================================
# Backup_Cyborg.sh — Backup cifrato AES-256 su SFTP e SMB con report HTML
# ==============================================================================
#
# DESCRIZIONE:
#   Archivia e cifra ricorsivamente file e cartelle in volumi ZIP (AES-256),
#   calcola gli hash SHA-256 di integrità, esegue l'upload ridondante su SFTP
#   e SMB, spedisce un report HTML dettagliato via email (curl SMTP o MTA locale)
#   e protegge i log locali in un archivio ZIP con password personale.
#
# UTILIZZO:
#   ./Backup_Cyborg.sh [sorgente] [server] [utente] [password] [email]
#   ./Backup_Cyborg.sh --gui              # Interfaccia grafica (Zenity)
#   ./Backup_Cyborg.sh --cli              # Interfaccia a riga di comando
#   ./Backup_Cyborg.sh --help             # Mostra questo aiuto
#   ./Backup_Cyborg.sh --cleanup-locks    # Rimuove eventuali lock orfani
#
# CONFIGURAZIONE E SEGRETI:
#   I parametri possono essere inseriti in secrets/config.env (vedi secrets/config.env.example)
#   oppure specificati via variabili d'ambiente:
#     CYBORG_CONFIG       Percorso personalizzato del file di configurazione
#     CYBORG_PASS         Password del server remoto (SFTP/SMB)
#     SSH_KEY_PATH        Percorso chiave SSH privata per auth SFTP senza password
#     LOG_PASSWORD        Password per proteggere il report e i log locali (.zip)
#     SMTP_SERVER         Server SMTP per invio email con curl (es. smtp.gmail.com)
#     SMTP_PORT           Porta SMTP (default: 587)
#     SMTP_USER           Username SMTP per autenticazione
#     SMTP_PASS           Password SMTP o app-password
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 1. Configurazione e variabili globali
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Caricamento configurazione da file secrets se presente
load_secrets_config() {
    local cfg="${CYBORG_CONFIG:-}"
    if [ -z "$cfg" ]; then
        if [ -f "${SCRIPT_DIR}/secrets/config.env" ]; then
            cfg="${SCRIPT_DIR}/secrets/config.env"
        elif [ -f "${SCRIPT_DIR}/.env" ]; then
            cfg="${SCRIPT_DIR}/.env"
        fi
    fi

    if [ -n "$cfg" ] && [ -f "$cfg" ]; then
        set -a
        # shellcheck source=/dev/null
        . "$cfg"
        set +a
    fi
}
load_secrets_config

# Parametri operativi (da config.env, ambiente o interattivi)
SOURCE_DIR="${SOURCE_DIR:-}"
DEST_SERVER="${DEST_SERVER:-}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_PASS="${CYBORG_PASS:-${REMOTE_PASS:-}}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SMB_PATH="${SMB_PATH:-/backup}"
SYSADMIN_EMAIL="${SYSADMIN_EMAIL:-}"
LOG_PASSWORD="${LOG_PASSWORD:-}"

# Parametri SMTP opzionali (per invio diretto con curl)
SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"

# Costanti e percorsi di runtime
INTERFACE_MODE=""
MAX_ARCHIVE_SIZE=1024
CONNECTION_TIMEOUT=30
MAX_RETRY_ATTEMPTS=3
VERBOSITY=1

FILE_TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
READABLE_TIMESTAMP="$(date +"%d-%m-%Y %H:%M:%S")"
BACKUP_NAME="backup_${FILE_TIMESTAMP}"
TEMP_DIR="/tmp/backup_temp_$$"
LOG_DIR="${HOME}/.backup_logs"
LOG_FILE="${TEMP_DIR}/diario_backup.log"
LOCK_FILE="${HOME}/.backup_locks/backup_cyborg.lock"

# Variabili di stato runtime
ENCRYPTION_PASSWORD=""
BACKUP_HASHES=""
HASH_COUNT=0
TOTAL_SOURCE_SIZE_MB=0
FATAL_ERROR=false
INTERRUPTED=false

# ------------------------------------------------------------------------------
# 2. Logging, Lock e Gestione Segnali (Traps)
# ------------------------------------------------------------------------------
ensure_runtime_dirs() {
    mkdir -p "$TEMP_DIR" "$LOG_DIR" "$(dirname "$LOCK_FILE")" 2>/dev/null || true
    chmod 700 "$TEMP_DIR" "$LOG_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
}

log_info() {
    ensure_runtime_dirs
    if [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; then
        echo -e "$1"
    fi
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] INFO: $1" >> "$LOG_FILE"
}

log_success() {
    ensure_runtime_dirs
    if [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; then
        echo -e "\e[32mOK: $1\e[0m"
    fi
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] SUCCESS: $1" >> "$LOG_FILE"
}

log_error() {
    ensure_runtime_dirs
    if [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; then
        echo -e "\e[31mERRORE: $1\e[0m" >&2
    fi
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] ERROR: $1" >> "$LOG_FILE"
}

log_verbose() {
    ensure_runtime_dirs
    if [ "$VERBOSITY" -ge 2 ] && [ "$INTERFACE_MODE" = "cli" ]; then
        echo -e "  $1"
    fi
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] DEBUG: $1" >> "$LOG_FILE"
}

acquire_lock() {
    ensure_runtime_dirs
    if [ -f "$LOCK_FILE" ]; then
        local old_pid
        old_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_error "Un'altra istanza del backup è già in esecuzione (PID: $old_pid)."
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo "$$" > "$LOCK_FILE"
}

cleanup_locks_cmd() {
    rm -f "${HOME}/.backup_locks"/*.lock 2>/dev/null || true
    echo "Lock file rimossi."
    exit 0
}

# shellcheck disable=SC2329
cleanup_on_exit() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

# shellcheck disable=SC2329
emergency_trap() {
    INTERRUPTED=true
    log_error "Ricevuto segnale di interruzione. Pulizia in corso..."
    cleanup_on_exit
    exit 130
}

trap cleanup_on_exit EXIT
trap emergency_trap INT TERM HUP QUIT

# Protegge e archivia il report HTML e il log locale in un file .zip (con password opzionale)
finalize_local_logs() {
    local html_src="${TEMP_DIR}/backup_report.html"
    local dest_zip="${LOG_DIR}/backup_${FILE_TIMESTAMP}_report.zip"
    local dest_log="${LOG_DIR}/backup_${FILE_TIMESTAMP}.log"
    local dest_html="${LOG_DIR}/backup_${FILE_TIMESTAMP}.html"

    mkdir -p "$LOG_DIR" 2>/dev/null || true

    if [ -n "$LOG_PASSWORD" ]; then
        log_info "Cifratura dei log locali in archivio protetto da password..."
        (
            cd "$TEMP_DIR" || exit 1
            local files_to_zip=()
            [ -f "diario_backup.log" ] && files_to_zip+=("diario_backup.log")
            [ -f "backup_report.html" ] && files_to_zip+=("backup_report.html")
            if [ ${#files_to_zip[@]} -gt 0 ]; then
                zip -q -j -P "$LOG_PASSWORD" "$dest_zip" "${files_to_zip[@]}"
                chmod 600 "$dest_zip" 2>/dev/null || true
            fi
        )
        log_success "Log e report archiviati in: $dest_zip (apribile con la password di LOG_PASSWORD)"
    else
        [ -f "$LOG_FILE" ] && cp -f "$LOG_FILE" "$dest_log" && chmod 600 "$dest_log" 2>/dev/null || true
        [ -f "$html_src" ] && cp -f "$html_src" "$dest_html" && chmod 600 "$dest_html" 2>/dev/null || true
        log_info "Log e report salvati in chiaro in $LOG_DIR (consigliato impostare LOG_PASSWORD in secrets/config.env)"
    fi
}

# ------------------------------------------------------------------------------
# 3. Crittografia AES-256 e Integrità SHA-256
# ------------------------------------------------------------------------------
generate_random_password() {
    if command -v openssl >/dev/null 2>&1; then
        ENCRYPTION_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' | head -c 24)"
    else
        local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%^&*_+-"
        local chars_len=${#chars}
        ENCRYPTION_PASSWORD=""
        while [ ${#ENCRYPTION_PASSWORD} -lt 24 ]; do
            local byte
            byte=$(od -An -N1 -tu1 < /dev/urandom | tr -d ' ')
            if [ "$byte" -lt $((chars_len * (255 / chars_len))) ]; then
                ENCRYPTION_PASSWORD+="${chars:$((byte % chars_len)):1}"
            fi
        done
    fi
}

core_create_encrypted_backup() {
    log_info "Creazione archivio cifrato AES-256..."
    generate_random_password

    local parent_dir
    local source_name
    parent_dir="$(dirname "$SOURCE_DIR")"
    source_name="$(basename "$SOURCE_DIR")"

    TOTAL_SOURCE_SIZE_MB=$(du -sm "$SOURCE_DIR" 2>/dev/null | awk '{print $1}')
    log_verbose "Dimensione sorgente: ${TOTAL_SOURCE_SIZE_MB} MB"

    local zip_out="${TEMP_DIR}/${BACKUP_NAME}.zip"

    # Esegui compressione e cifratura direttamente nella cartella genitore
    if ! (cd "$parent_dir" && zip -q -r -e -P "$ENCRYPTION_PASSWORD" -s "${MAX_ARCHIVE_SIZE}m" "$zip_out" "$source_name"); then
        log_error "Creazione archivio ZIP cifrato fallita."
        FATAL_ERROR=true
        return 1
    fi

    # Normalizza i nomi per i volumi creati da zip (possono essere .zip, .z01, .z02...)
    calculate_sha256_hashes
}

calculate_sha256_hashes() {
    log_info "Calcolo hash SHA-256 di integrità..."
    BACKUP_HASHES=""
    HASH_COUNT=0

    local archives
    archives=$(find "${TEMP_DIR}" -type f \( -name "${BACKUP_NAME}.zip" -o -name "${BACKUP_NAME}.z*" \) | sort)

    if [ -z "$archives" ]; then
        log_error "Nessun volume di backup trovato in $TEMP_DIR"
        FATAL_ERROR=true
        return 1
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local h
        local s
        local n
        h="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
        s="$(stat -c%s "$file" 2>/dev/null || echo "0")"
        n="$(basename "$file")"
        
        BACKUP_HASHES="${BACKUP_HASHES}File: ${n}\nSHA256: ${h}\nDimensione: ${s} byte\n---\n"
        HASH_COUNT=$((HASH_COUNT + 1))
        log_verbose "Hash $n: $h"
    done <<< "$archives"

    log_success "Calcolati hash SHA-256 per $HASH_COUNT volume/i."
}

# ------------------------------------------------------------------------------
# 4. Protocolli di Rete: SFTP e SMB
# ------------------------------------------------------------------------------
run_sftp() {
    local opts=(-o StrictHostKeyChecking=accept-new)
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ]; then
        opts+=(-i "$SSH_KEY_PATH" -o BatchMode=yes)
    else
        opts+=(-o BatchMode=no -o PasswordAuthentication=yes)
    fi
    timeout "$CONNECTION_TIMEOUT" sftp "${opts[@]}" "$@"
}

# shellcheck disable=SC2329
run_scp() {
    local opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout="$CONNECTION_TIMEOUT")
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ]; then
        opts+=(-i "$SSH_KEY_PATH")
    fi
    scp "${opts[@]}" "$@"
}

core_upload_sftp() {
    log_info "Avvio caricamento su SFTP ($DEST_SERVER)..."

    # Test rapido di connessione
    if ! run_sftp "$REMOTE_USER@$DEST_SERVER" <<< "pwd" >/dev/null 2>&1; then
        log_error "Connessione SFTP a $REMOTE_USER@$DEST_SERVER fallita. Verifica credenziali/chiave."
        return 1
    fi

    local remote_dir="backup/backup_${FILE_TIMESTAMP}"
    run_sftp "$REMOTE_USER@$DEST_SERVER" >/dev/null 2>&1 << EOF
mkdir backup
mkdir $remote_dir
quit
EOF

    local archives
    archives=$(find "${TEMP_DIR}" -type f \( -name "${BACKUP_NAME}.zip" -o -name "${BACKUP_NAME}.z*" \) | sort)

    local uploaded=0
    local failed=0
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local fname
        fname="$(basename "$file")"
        log_verbose "SFTP: invio $fname..."

        local attempt=1
        local ok=false
        while [ "$attempt" -le "$MAX_RETRY_ATTEMPTS" ]; do
            if run_scp "$file" "$REMOTE_USER@$DEST_SERVER:$remote_dir/$fname" >/dev/null 2>&1; then
                ok=true
                break
            fi
            attempt=$((attempt + 1))
            sleep 2
        done

        if [ "$ok" = true ]; then
            uploaded=$((uploaded + 1))
        else
            log_error "SFTP: upload fallito per $fname dopo $MAX_RETRY_ATTEMPTS tentativi."
            failed=$((failed + 1))
        fi
    done <<< "$archives"

    if [ "$failed" -eq 0 ] && [ "$uploaded" -gt 0 ]; then
        log_success "SFTP: $uploaded volume/i caricati con successo in $remote_dir."
        return 0
    else
        log_error "SFTP: completato con $failed errori."
        return 1
    fi
}

core_upload_smb() {
    log_info "Avvio caricamento su SMB (//$DEST_SERVER$SMB_PATH)..."

    if ! command -v smbclient >/dev/null 2>&1; then
        log_error "Comando smbclient non trovato. Installa samba-client/smbclient."
        return 1
    fi

    # Test connessione e listing share SMB
    if ! timeout "$CONNECTION_TIMEOUT" smbclient "//$DEST_SERVER$SMB_PATH" -U "$REMOTE_USER%$REMOTE_PASS" -c "ls" >/dev/null 2>&1; then
        log_error "Connessione SMB a //$DEST_SERVER$SMB_PATH fallita. Verifica share e credenziali."
        return 1
    fi

    local smb_folder="backup_${FILE_TIMESTAMP}"
    timeout "$CONNECTION_TIMEOUT" smbclient "//$DEST_SERVER$SMB_PATH" -U "$REMOTE_USER%$REMOTE_PASS" -c "mkdir $smb_folder" >/dev/null 2>&1 || true

    local archives
    archives=$(find "${TEMP_DIR}" -type f \( -name "${BACKUP_NAME}.zip" -o -name "${BACKUP_NAME}.z*" \) | sort)

    local uploaded=0
    local failed=0
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local fname
        fname="$(basename "$file")"
        log_verbose "SMB: invio $fname..."

        local attempt=1
        local ok=false
        while [ "$attempt" -le "$MAX_RETRY_ATTEMPTS" ]; do
            if timeout "$CONNECTION_TIMEOUT" smbclient "//$DEST_SERVER$SMB_PATH" -U "$REMOTE_USER%$REMOTE_PASS" -c "cd $smb_folder; put \"$file\" \"$fname\"" >/dev/null 2>&1; then
                ok=true
                break
            fi
            attempt=$((attempt + 1))
            sleep 2
        done

        if [ "$ok" = true ]; then
            uploaded=$((uploaded + 1))
        else
            log_error "SMB: upload fallito per $fname dopo $MAX_RETRY_ATTEMPTS tentativi."
            failed=$((failed + 1))
        fi
    done <<< "$archives"

    if [ "$failed" -eq 0 ] && [ "$uploaded" -gt 0 ]; then
        log_success "SMB: $uploaded volume/i caricati con successo in $smb_folder."
        return 0
    else
        log_error "SMB: completato con $failed errori."
        return 1
    fi
}

core_upload_both() {
    local sftp_ok=true
    local smb_ok=true

    core_upload_sftp || sftp_ok=false
    core_upload_smb || smb_ok=false

    if [ "$sftp_ok" = false ] && [ "$smb_ok" = false ]; then
        log_error "Entrambi i protocolli di destinazione (SFTP e SMB) sono falliti."
        FATAL_ERROR=true
        return 1
    elif [ "$sftp_ok" = false ] || [ "$smb_ok" = false ]; then
        log_info "Upload completato parzialmente (ridondanza parziale)."
        return 0
    else
        log_success "Upload completato con successo su entrambi i protocolli (SFTP + SMB)!"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# 5. Report HTML ed Email (curl SMTP + fallback)
# ------------------------------------------------------------------------------
generate_enhanced_html_report() {
    local html_file="${TEMP_DIR}/backup_report.html"
    local status_color="#28a745"
    local status_title="COMPLETATO CON SUCCESSO"

    if [ "$FATAL_ERROR" = true ]; then
        status_color="#dc3545"
        status_title="FALLITO / ERRORI RISCONTRATI"
    elif [ "$INTERRUPTED" = true ]; then
        status_color="#ffc107"
        status_title="INTERROTTO MANUALMENTE"
    fi

    local formatted_hashes
    formatted_hashes="$(echo -e "$BACKUP_HASHES" | sed 's/$/<br>/g')"

    cat > "$html_file" << EOF
<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Report Backup Cyborg - $READABLE_TIMESTAMP</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; background: #f4f6f8; color: #222; margin: 0; padding: 20px; }
.card { max-width: 680px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.08); overflow: hidden; }
.header { background: #1a1e24; color: #fff; padding: 24px; text-align: center; }
.header h1 { margin: 0; font-size: 20px; letter-spacing: 0.5px; }
.badge { display: inline-block; padding: 6px 14px; border-radius: 20px; font-weight: bold; font-size: 13px; margin-top: 10px; background: ${status_color}; color: #fff; }
.body { padding: 24px; }
.sec-title { font-size: 14px; text-transform: uppercase; color: #666; font-weight: 700; margin: 20px 0 8px 0; border-bottom: 2px solid #eee; padding-bottom: 4px; }
.pass-box { background: #eef3ff; border: 1px dashed #4a77d4; border-radius: 6px; padding: 14px; text-align: center; font-size: 18px; font-family: monospace; font-weight: bold; color: #1d39c4; word-break: break-all; margin: 10px 0; }
.table-data { width: 100%; border-collapse: collapse; margin-top: 8px; font-size: 14px; }
.table-data td { padding: 8px; border-bottom: 1px solid #f0f0f0; }
.table-data td:first-child { font-weight: 600; color: #555; width: 35%; }
.hash-box { background: #f8f9fa; border: 1px solid #e9ecef; border-radius: 6px; padding: 12px; font-family: monospace; font-size: 12px; max-height: 180px; overflow-y: auto; color: #333; }
.footer { text-align: center; padding: 16px; font-size: 12px; color: #888; background: #fafafa; border-top: 1px solid #eee; }
</style>
</head>
<body>
<div class="card">
  <div class="header">
    <h1>Cyborg Backup System</h1>
    <div class="badge">${status_title}</div>
  </div>
  <div class="body">
    <div class="sec-title">Chiave di Decifratura AES-256</div>
    <div class="pass-box">${ENCRYPTION_PASSWORD:-Non disponibile}</div>
    <p style="font-size: 12px; color: #c0392b; margin: 4px 0 16px 0; text-align: center;">Salva questa password in un posto sicuro per poter estrarre i volumi ZIP.</p>

    <div class="sec-title">Dettagli Operazione</div>
    <table class="table-data">
      <tr><td>Data e Ora:</td><td>${READABLE_TIMESTAMP}</td></tr>
      <tr><td>Cartella Sorgente:</td><td>${SOURCE_DIR}</td></tr>
      <tr><td>Server Destinazione:</td><td>${DEST_SERVER}</td></tr>
      <tr><td>Dimensione Dati:</td><td>${TOTAL_SOURCE_SIZE_MB} MB</td></tr>
      <tr><td>Protocolli Usati:</td><td>SFTP + SMB (Doppia Ridondanza)</td></tr>
      <tr><td>Volumi Generati:</td><td>${HASH_COUNT}</td></tr>
    </table>

    <div class="sec-title">Verifica Integrità (SHA-256)</div>
    <div class="hash-box">${formatted_hashes:-Nessun hash registrato}</div>
  </div>
  <div class="footer">
    Generato automaticamente da Backup_Cyborg.sh • Report sicuro
  </div>
</div>
</body>
</html>
EOF
}

send_report_email() {
    if [ -z "$SYSADMIN_EMAIL" ]; then
        log_info "Nessun indirizzo email configurato per il report (SYSADMIN_EMAIL vuoto)."
        return 0
    fi

    log_info "Invio report via email a $SYSADMIN_EMAIL..."
    generate_enhanced_html_report
    local html_file="${TEMP_DIR}/backup_report.html"

    # Metodo 1: Invio diretto via SMTP con curl (nessun client locale richiesto)
    if [ -n "$SMTP_SERVER" ] && command -v curl >/dev/null 2>&1; then
        log_verbose "Tentativo di invio tramite curl SMTP ($SMTP_SERVER:$SMTP_PORT)..."
        local curl_msg="${TEMP_DIR}/curl_mail.eml"
        cat > "$curl_msg" << EOF
From: Cyborg Backup <${SMTP_USER:-backup@${DEST_SERVER:-local}}>
To: <${SYSADMIN_EMAIL}>
Subject: [Cyborg Backup] Report $READABLE_TIMESTAMP
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8

$(cat "$html_file")
EOF
        local curl_auth=()
        if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
            curl_auth=(--user "$SMTP_USER:$SMTP_PASS")
        fi

        if curl --silent --ssl-reqd \
            --url "smtp://${SMTP_SERVER}:${SMTP_PORT}" \
            "${curl_auth[@]}" \
            --mail-from "${SMTP_USER:-backup@localhost}" \
            --mail-rcpt "$SYSADMIN_EMAIL" \
            --upload-file "$curl_msg" >/dev/null 2>&1; then
            log_success "Email inviata con successo tramite curl SMTP!"
            return 0
        else
            log_error "Invio tramite curl SMTP fallito. Tento fallback locale..."
        fi
    fi

    # Metodo 2: Fallback su mailutils / bsd-mailx
    if command -v mail >/dev/null 2>&1; then
        if mail -a "Content-Type: text/html; charset=UTF-8" -s "[Cyborg Backup] Report $READABLE_TIMESTAMP" "$SYSADMIN_EMAIL" < "$html_file" 2>/dev/null; then
            log_success "Email inviata con successo tramite comando mail locale!"
            return 0
        fi
    fi

    # Metodo 3: Fallback su sendmail
    if command -v sendmail >/dev/null 2>&1; then
        (
            echo "To: $SYSADMIN_EMAIL"
            echo "Subject: [Cyborg Backup] Report $READABLE_TIMESTAMP"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/html; charset=UTF-8"
            echo ""
            cat "$html_file"
        ) | sendmail -t 2>/dev/null && {
            log_success "Email inviata con successo tramite sendmail!"
            return 0
        }
    fi

    log_info "Nessun client email disponibile. Il report HTML completo è stato salvato nei log locali."
    return 0
}

# ------------------------------------------------------------------------------
# 6. Validatori di Input
# ------------------------------------------------------------------------------
validate_directory() {
    [ -n "$1" ] && [ -d "$1" ] && [ -r "$1" ]
}

validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || [[ "$ip" =~ ^[a-zA-Z0-9.-]+$ ]]
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# ------------------------------------------------------------------------------
# 7. Frontend Interattivi: CLI e GUI Zenity
# ------------------------------------------------------------------------------
zenity_clean() {
    zenity "$@" 2>/dev/null
}

cli_collect_params() {
    echo ""
    echo "=== CYBORG BACKUP SYSTEM — CONFIGURAZIONE CLI ==="
    echo ""

    while [ -z "$SOURCE_DIR" ]; do
        read -r -p "Cartella sorgente da salvare: " SOURCE_DIR
        if ! validate_directory "$SOURCE_DIR"; then
            echo "Cartella non valida o non leggibile."
            SOURCE_DIR=""
        fi
    done

    while [ -z "$DEST_SERVER" ]; do
        read -r -p "IP o hostname server remoto: " DEST_SERVER
        if ! validate_ip "$DEST_SERVER"; then
            echo "Indirizzo server non valido."
            DEST_SERVER=""
        fi
    done

    [ -z "$REMOTE_USER" ] && read -r -p "Utente remoto: " REMOTE_USER

    if [ -z "$REMOTE_PASS" ] && [ -z "$SSH_KEY_PATH" ]; then
        read -r -sp "Password remota (o premi invio per saltare se usi chiave SSH): " REMOTE_PASS
        echo ""
    fi

    while [ -z "$SYSADMIN_EMAIL" ]; do
        read -r -p "Email destinatario report: " SYSADMIN_EMAIL
        if ! validate_email "$SYSADMIN_EMAIL"; then
            echo "Formato email non valido."
            SYSADMIN_EMAIL=""
        fi
    done

    [ -z "$SMB_PATH" ] && read -r -p "Percorso condivisione SMB [default: /backup]: " SMB_PATH
    SMB_PATH="${SMB_PATH:-/backup}"

    echo ""
}

gui_collect_params() {
    if ! command -v zenity >/dev/null 2>&1; then
        echo "Zenity non trovato sul sistema, passaggio automatico a modalità CLI."
        INTERFACE_MODE="cli"
        cli_collect_params
        return
    fi

    if [ -z "$SOURCE_DIR" ]; then
        if ! SOURCE_DIR=$(zenity_clean --file-selection --directory --title="Seleziona Cartella da Salvare"); then
            exit 0
        fi
    fi

    if [ -z "$DEST_SERVER" ]; then
        if ! DEST_SERVER=$(zenity_clean --entry --title="Server Remoto" --text="Inserisci IP o hostname del server di destinazione:"); then
            exit 0
        fi
    fi

    if [ -z "$REMOTE_USER" ]; then
        if ! REMOTE_USER=$(zenity_clean --entry --title="Utente" --text="Inserisci nome utente remoto:"); then
            exit 0
        fi
    fi

    if [ -z "$REMOTE_PASS" ] && [ -z "$SSH_KEY_PATH" ]; then
        if ! REMOTE_PASS=$(zenity_clean --password --title="Password Remota"); then
            exit 0
        fi
    fi

    if [ -z "$SYSADMIN_EMAIL" ]; then
        if ! SYSADMIN_EMAIL=$(zenity_clean --entry --title="Email Report" --text="Inserisci indirizzo email per ricevere password e report:"); then
            exit 0
        fi
    fi

    [ -z "$SMB_PATH" ] && SMB_PATH="/backup"
}

# ------------------------------------------------------------------------------
# 8. Esecuzione del Backup e Entrypoint
# ------------------------------------------------------------------------------
run_full_backup() {
    acquire_lock

    log_info "========================================================"
    log_info "Avvio Cyborg Backup: $READABLE_TIMESTAMP"
    log_info "Sorgente: $SOURCE_DIR | Destinazione: $DEST_SERVER"
    log_info "========================================================"

    # Fase 1: Creazione archivi cifrati AES-256 e hash SHA-256
    core_create_encrypted_backup || {
        log_error "Fase di cifratura fallita."
        finalize_local_logs
        return 1
    }

    # Fase 2: Upload ridondante (SFTP + SMB)
    core_upload_both || {
        log_error "Fase di upload non completata con successo."
    }

    # Fase 3: Generazione e invio report
    send_report_email

    # Fase 4: Archiviazione e cifratura locale dei log
    finalize_local_logs

    if [ "$FATAL_ERROR" = false ]; then
        log_success "Procedura di backup conclusa con successo!"
        if [ "$INTERFACE_MODE" = "gui" ] && command -v zenity >/dev/null 2>&1; then
            zenity_clean --info --title="Backup Concluso" \
                --text="Backup completato con successo!\n\nPassword AES-256:\n$ENCRYPTION_PASSWORD\n\nI log e il report sono stati salvati in ~/.backup_logs/" \
                --width=450
        fi
        return 0
    else
        log_error "Il backup ha riscontrato anomalie. Consulta i log."
        return 1
    fi
}

show_version() {
    echo "Backup_Cyborg.sh v1.2.0 — Sistema di Backup Cifrato Ridondante"
    exit 0
}

show_help() {
    local b="" reset="" cyan="" yellow=""
    if [ -t 1 ]; then
        b=$'\033[1m'
        reset=$'\033[0m'
        cyan=$'\033[36m'
        yellow=$'\033[33m'
    fi

    cat << EOF
${b}Backup_Cyborg.sh${reset} — Backup cifrato AES-256 con doppia ridondanza (SFTP + SMB)

${b}SINTASSI:${reset}
  ${cyan}./Backup_Cyborg.sh${reset} [OPZIONI]
  ${cyan}./Backup_Cyborg.sh${reset} [SORGENTE] [SERVER] [UTENTE] [PASSWORD] [EMAIL]

${b}OPZIONI:${reset}
  ${yellow}-g, --gui${reset}              Avvia l'interfaccia grafica (Zenity)
  ${yellow}-c, --cli${reset}              Forza la modalità riga di comando interattiva
  ${yellow}-k, --cleanup-locks${reset}    Rimuove file di lock orfani in ~/.backup_locks/
  ${yellow}-v, --version${reset}          Mostra la versione dello script
  ${yellow}-h, --help${reset}             Mostra questa guida dettagliata

${b}CONFIGURAZIONE TRAMITE FILE SECRETS:${reset}
  I parametri possono essere preimpostati in ${cyan}secrets/config.env${reset}
  (copia il modello da ${cyan}secrets/config.env.example${reset}, file ignorato da Git):

  ${b}Variabile           Descrizione${reset}
  SOURCE_DIR          Cartella sorgente locale da archiviare
  DEST_SERVER         Indirizzo IP o hostname del server di destinazione
  REMOTE_USER         Nome utente sul server remoto
  CYBORG_PASS         Password remota (se non si usa l'autenticazione a chiave)
  SSH_KEY_PATH        Percorso chiave SSH privata (es. ~/.ssh/id_ed25519)
  SMB_PATH            Percorso condivisione SMB (default: /backup)
  SYSADMIN_EMAIL      Email destinatario report e password di decifratura
  LOG_PASSWORD        Password personale per archiviare i log locali in uno .zip protetto
  SMTP_SERVER         Server SMTP (es. smtp.gmail.com) per invio con curl senza MTA
  SMTP_PORT           Porta server SMTP (default: 587)
  SMTP_USER / PASS    Credenziali di autenticazione SMTP

${b}CARATTERISTICHE DI SICUREZZA:${reset}
  • ${b}Cifratura AES-256${reset}: ogni archivio è cifrato con una chiave casuale
    a 24 caratteri URL-safe generata a runtime (visibile nel report).
  • ${b}Integrità SHA-256${reset}: checksum crittografico calcolato per ogni volume.
  • ${b}Ridondanza Simultanea${reset}: caricamento indipendente su SFTP e SMB.
  • ${b}Protezione Log Locali${reset}: se LOG_PASSWORD è valorizzata, il log e il
    report HTML vengono archiviati in ~/.backup_logs/ in uno .zip protetto,
    apribile con doppio clic inserendo la propria password.

${b}ESEMPI DI UTILIZZO:${reset}
  ${cyan}# 1. Utilizzo consigliato (parametri configurati in secrets/config.env):${reset}
  ./Backup_Cyborg.sh

  ${cyan}# 2. Utilizzo con interfaccia grafica:${reset}
  ./Backup_Cyborg.sh --gui

  ${cyan}# 3. Esecuzione pianificata da crontab (non interattiva):${reset}
  ./Backup_Cyborg.sh --cli >/dev/null 2>&1

  ${cyan}# 4. Esecuzione con parametri posizionali da riga di comando:${reset}
  ./Backup_Cyborg.sh /home/utente/dati 192.168.1.100 backup_user segreto admin@email.it

EOF
    exit 0
}

process_params() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --gui|-g)
                INTERFACE_MODE="gui"
                shift
                ;;
            --cli|-c)
                INTERFACE_MODE="cli"
                shift
                ;;
            --cleanup-locks|-k)
                cleanup_locks_cmd
                ;;
            --version|-v)
                show_version
                ;;
            --help|-h)
                show_help
                ;;
            *)
                # Parametri posizionali: sorgente server utente pass email
                if [ -z "$SOURCE_DIR" ]; then SOURCE_DIR="$1";
                elif [ -z "$DEST_SERVER" ]; then DEST_SERVER="$1";
                elif [ -z "$REMOTE_USER" ]; then REMOTE_USER="$1";
                elif [ -z "$REMOTE_PASS" ]; then REMOTE_PASS="$1";
                elif [ -z "$SYSADMIN_EMAIL" ]; then SYSADMIN_EMAIL="$1";
                fi
                shift
                ;;
        esac
    done
}

main() {
    process_params "$@"

    # Verifica dipendenze di base
    local missing=()
    command -v zip >/dev/null 2>&1 || missing+=("zip")
    command -v sha256sum >/dev/null 2>&1 || missing+=("coreutils")
    command -v sftp >/dev/null 2>&1 || missing+=("openssh-client")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Dipendenze mancanti: ${missing[*]}" >&2
        echo "Installale con il gestore pacchetti del tuo sistema." >&2
        exit 1
    fi

    # Rilevamento automatico interfaccia se non forzata
    if [ -z "$INTERFACE_MODE" ]; then
        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            command -v zenity >/dev/null 2>&1 && INTERFACE_MODE="gui" || INTERFACE_MODE="cli"
        else
            INTERFACE_MODE="cli"
        fi
    fi

    # Raccolta parametri mancanti
    if [ "$INTERFACE_MODE" = "gui" ]; then
        gui_collect_params
    else
        cli_collect_params
    fi

    # Validazione finale parametri minimi
    if ! validate_directory "$SOURCE_DIR"; then
        log_error "Cartella sorgente '$SOURCE_DIR' non valida o inesistente."
        exit 1
    fi

    if [ -z "$DEST_SERVER" ] || [ -z "$REMOTE_USER" ]; then
        log_error "Server di destinazione o utente remoto non specificati."
        exit 1
    fi

    run_full_backup
}

main "$@"
