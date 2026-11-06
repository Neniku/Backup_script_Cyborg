#!/bin/bash
# shellcheck shell=bash disable=SC2329

# ==============================================================================
# Backup_Cyborg.sh — Backup Cifrato AES-256 (Specifiche Umana + Cyborg)
# ==============================================================================
# 1. Archivia ricorsivamente param1 in volumi .zip (compatibili anche con Windows)
#    cifrati con algoritmo simmetrico AES-256 e password complessa (24 caratteri).
# 2. Registra l'elenco completo di file/cartelle e gli hash SHA-256 in "diario-backup.log".
# 3. Esegue l'upload su SFTP (chiavi crittografiche ECC Ed25519/ECDSA o password)
#    e/o su SMB (con firma digitale obbligatoria dei pacchetti --signing=required,
#    negoziando automaticamente SMB3/SMB2).
# 4. Elimina automaticamente gli archivi locali sul client dopo l'upload, invia
#    report HTML + allegato diario-backup.log via email e cifra i log locali.
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# 1. Configurazione e Variabili Globali
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

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

# Parametri operativi (da config.env, ambiente, CLI posizionale o GUI)
SOURCE_DIR="${SOURCE_DIR:-}"
DEST_SERVER="${DEST_SERVER:-}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_PASS="${CYBORG_PASS:-${REMOTE_PASS:-}}"
PROTOCOL_MODE="${PROTOCOL_MODE:-both}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
SMB_PATH="${SMB_PATH:-/backup}"
SMB_SIGNING="${SMB_SIGNING:-required}"
SYSADMIN_EMAIL="${SYSADMIN_EMAIL:-}"
LOG_PASSWORD="${LOG_PASSWORD:-}"

# Parametri SMTP opzionali (invio diretto con curl senza MTA locale)
SMTP_SERVER="${SMTP_SERVER:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"

# Costanti e percorsi di runtime
INTERFACE_MODE=""
MAX_ARCHIVE_SIZE="${MAX_ARCHIVE_SIZE:-1024}"
CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-30}"
MAX_RETRY_ATTEMPTS="${MAX_RETRY_ATTEMPTS:-3}"
VERBOSITY="${VERBOSITY:-1}"

FILE_TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
READABLE_TIMESTAMP="$(date +"%d-%m-%Y %H:%M:%S")"
BACKUP_NAME="backup_${FILE_TIMESTAMP}"
TEMP_DIR="/tmp/backup_temp_$$"
LOG_DIR="${HOME}/.backup_logs"
LOG_FILE="${TEMP_DIR}/diario-backup.log"
LOCK_FILE="${HOME}/.backup_locks/backup_cyborg.lock"

# Stato runtime
ENCRYPTION_PASSWORD=""
CIPHER_USED="AES-256"
BACKUP_HASHES=""
HASH_COUNT=0
ARCHIVED_ITEMS_COUNT=0
TOTAL_SOURCE_SIZE_MB=0
LOCAL_CLEANUP_DONE=false
FATAL_ERROR=false
INTERRUPTED=false
SSH_COMMON_OPTS=()

# ------------------------------------------------------------------------------
# 2. Logging ("diario-backup.log"), Lock e Gestione Segnali (Traps)
# ------------------------------------------------------------------------------
ensure_runtime_dirs() {
    mkdir -p "$TEMP_DIR" "$LOG_DIR" "$(dirname "$LOCK_FILE")" 2>/dev/null || true
    chmod 700 "$TEMP_DIR" "$LOG_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    [ -e "${TEMP_DIR}/diario_backup.log" ] || ln -sf "$LOG_FILE" "${TEMP_DIR}/diario_backup.log" 2>/dev/null || true
}

log_write() {
    ensure_runtime_dirs
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1: $2" >> "$LOG_FILE"
}

log_info() {
    { [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; } && echo -e "$1"
    log_write "INFO" "$1"
}

log_success() {
    { [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; } && echo -e "\e[32mOK: $1\e[0m"
    log_write "SUCCESS" "$1"
}

log_error() {
    { [ "$INTERFACE_MODE" = "cli" ] || [ -z "$INTERFACE_MODE" ]; } && echo -e "\e[31mERRORE: $1\e[0m" >&2
    log_write "ERROR" "$1"
}

log_verbose() {
    [ "$VERBOSITY" -ge 2 ] && [ "$INTERFACE_MODE" = "cli" ] && echo -e "  $1"
    log_write "DEBUG" "$1"
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

find_backup_archives() {
    find "${TEMP_DIR}" -maxdepth 1 -type f \( -name "${BACKUP_NAME}.zip" -o -name "${BACKUP_NAME}.z*" -o -name "${BACKUP_NAME}.zip.*" \) 2>/dev/null | sort
}

cleanup_local_archives() {
    local removed=0
    local archives
    archives="$(find_backup_archives)"
    if [ -n "$archives" ]; then
        while IFS= read -r f; do
            [ -z "$f" ] && continue
            rm -f "$f" 2>/dev/null && removed=$((removed + 1))
        done <<< "$archives"
    fi
    LOCAL_CLEANUP_DONE=true
    log_success "Pulizia client completata: $removed volume/i temporanei rimossi dal disco locale."
}

cleanup_on_exit() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
    rm -rf "$TEMP_DIR" 2>/dev/null || true
}

emergency_trap() {
    INTERRUPTED=true
    log_error "Ricevuto segnale di interruzione. Pulizia di emergenza in corso..."
    cleanup_on_exit
    exit 130
}

trap cleanup_on_exit EXIT
trap emergency_trap INT TERM HUP QUIT

finalize_local_logs() {
    local html_src="${TEMP_DIR}/backup_report.html"
    local dest_zip="${LOG_DIR}/backup_${FILE_TIMESTAMP}_report.zip"
    local dest_log="${LOG_DIR}/diario-backup_${FILE_TIMESTAMP}.log"
    local dest_html="${LOG_DIR}/backup_${FILE_TIMESTAMP}.html"

    mkdir -p "$LOG_DIR" 2>/dev/null || true

    if [ -n "$LOG_PASSWORD" ]; then
        log_info "Cifratura dei log locali in archivio protetto da password..."
        (
            cd "$TEMP_DIR" || exit 1
            local files_to_zip=()
            [ -f "diario-backup.log" ] && files_to_zip+=("diario-backup.log")
            [ -f "backup_report.html" ] && files_to_zip+=("backup_report.html")
            if [ ${#files_to_zip[@]} -gt 0 ]; then
                7z a -tzip -mem=AES256 -mx=5 -p"$LOG_PASSWORD" "$dest_zip" "${files_to_zip[@]}" >/dev/null 2>&1
                chmod 600 "$dest_zip" 2>/dev/null || true
            fi
        )
        log_success "Log e report archiviati in: $dest_zip (protetto da LOG_PASSWORD)"
    else
        [ -f "$LOG_FILE" ] && cp -f "$LOG_FILE" "$dest_log" && chmod 600 "$dest_log" 2>/dev/null || true
        [ -f "$html_src" ] && cp -f "$html_src" "$dest_html" && chmod 600 "$dest_html" 2>/dev/null || true
        log_info "Diario e report salvati in $LOG_DIR (imposta LOG_PASSWORD in secrets/config.env per cifrarli)"
    fi
}

# ------------------------------------------------------------------------------
# 3. Crittografia Simmetrica AES-256, Manifesto File e Integrità SHA-256
# ------------------------------------------------------------------------------
# Schema password complessa Cyborg (24 char): 4 Upper + 4 Lower + 4 Cifre + 4 Simboli + 8 Misti
random_chars_from_pool() {
    local pool="$1" count="$2"
    local pool_len=${#pool}
    local max_valid=$((pool_len * (256 / pool_len)))
    local result="" byte
    while [ ${#result} -lt "$count" ]; do
        byte=$(od -An -N1 -tu1 < /dev/urandom | tr -d ' ')
        if [ -n "$byte" ] && [ "$byte" -lt "$max_valid" ]; then
            result+="${pool:$((byte % pool_len)):1}"
        fi
    done
    printf '%s' "$result"
}

generate_random_password() {
    local upper="ABCDEFGHJKLMNPQRSTUVWXYZ"
    local lower="abcdefghijkmnopqrstuvwxyz"
    local digits="0123456789"
    local symbols="!@#%^&*_+-="
    local raw_pass=""
    raw_pass+="$(random_chars_from_pool "$upper" 4)"
    raw_pass+="$(random_chars_from_pool "$lower" 4)"
    raw_pass+="$(random_chars_from_pool "$digits" 4)"
    raw_pass+="$(random_chars_from_pool "$symbols" 4)"
    raw_pass+="$(random_chars_from_pool "${upper}${lower}${digits}${symbols}" 8)"

    if command -v shuf >/dev/null 2>&1; then
        ENCRYPTION_PASSWORD="$(printf '%s' "$raw_pass" | fold -w1 | shuf | tr -d '\n')"
    else
        ENCRYPTION_PASSWORD="$raw_pass"
    fi
}

log_archived_manifest() {
    ensure_runtime_dirs
    local count=0
    {
        echo "================================================================================"
        echo "=== ELENCO FILE E DIRECTORY INCLUSI NELL'ARCHIVIO (${SOURCE_DIR}) ==="
        echo "================================================================================"
    } >> "$LOG_FILE"

    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if [ -d "$entry" ]; then
            echo "[DIR]  $entry" >> "$LOG_FILE"
        else
            echo "[FILE] $entry ($(stat -c%s "$entry" 2>/dev/null || echo 0) byte)" >> "$LOG_FILE"
        fi
        count=$((count + 1))
    done < <(find "$SOURCE_DIR" 2>/dev/null | sort)

    echo "================================================================================" >> "$LOG_FILE"
    ARCHIVED_ITEMS_COUNT=$count
    log_info "Registrati $ARCHIVED_ITEMS_COUNT elementi (file e directory) in diario-backup.log."
}

core_create_encrypted_backup() {
    log_info "Creazione archivio cifrato AES-256..."
    generate_random_password

    local parent_dir source_name
    parent_dir="$(dirname "$SOURCE_DIR")"
    source_name="$(basename "$SOURCE_DIR")"

    TOTAL_SOURCE_SIZE_MB=$(du -sm "$SOURCE_DIR" 2>/dev/null | awk '{print $1}')
    TOTAL_SOURCE_SIZE_MB="${TOTAL_SOURCE_SIZE_MB:-0}"
    log_verbose "Dimensione sorgente: ${TOTAL_SOURCE_SIZE_MB} MB"

    log_archived_manifest

    local zip_out="${TEMP_DIR}/${BACKUP_NAME}.zip"
    local split_args=()
    [ "$TOTAL_SOURCE_SIZE_MB" -ge "$MAX_ARCHIVE_SIZE" ] && split_args=("-v${MAX_ARCHIVE_SIZE}m")

    if ! (cd "$parent_dir" && 7z a -tzip -mem=AES256 -mx=5 -p"$ENCRYPTION_PASSWORD" "${split_args[@]}" "$zip_out" "$source_name" >/dev/null 2>&1); then
        log_error "Creazione archivio ZIP AES-256 con 7z fallita."
        FATAL_ERROR=true
        return 1
    fi

    calculate_sha256_hashes
}

calculate_sha256_hashes() {
    log_info "Calcolo hash SHA-256 di integrità..."
    BACKUP_HASHES=""
    HASH_COUNT=0

    local archives
    archives="$(find_backup_archives)"
    if [ -z "$archives" ]; then
        log_error "Nessun volume di backup trovato in $TEMP_DIR"
        FATAL_ERROR=true
        return 1
    fi

    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local h s n
        h="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
        s="$(stat -c%s "$file" 2>/dev/null || echo "0")"
        n="$(basename "$file")"
        BACKUP_HASHES="${BACKUP_HASHES}File: ${n}\nSHA256: ${h}\nDimensione: ${s} byte\n---\n"
        HASH_COUNT=$((HASH_COUNT + 1))
        log_verbose "Hash $n: $h (${s} byte)"
    done <<< "$archives"

    log_success "Calcolati hash SHA-256 per $HASH_COUNT volume/i."
}

# ------------------------------------------------------------------------------
# 4. Protocolli di Rete: SFTP (Chiavi ECC Ed25519/ECDSA) e SMB (Firma Digitale)
# ------------------------------------------------------------------------------
resolve_ecc_ssh_key() {
    [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ] && return 0
    if [ -f "${HOME}/.ssh/id_ed25519" ]; then
        SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
    elif [ -f "${HOME}/.ssh/id_ecdsa" ]; then
        SSH_KEY_PATH="${HOME}/.ssh/id_ecdsa"
    fi
}

exec_ssh_tool() {
    local tool="$1"
    shift
    resolve_ecc_ssh_key
    SSH_COMMON_OPTS=(
        -o "StrictHostKeyChecking=accept-new"
        -o "ConnectTimeout=$CONNECTION_TIMEOUT"
        -o "PubkeyAcceptedAlgorithms=+ssh-ed25519,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521"
    )
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ]; then
        SSH_COMMON_OPTS+=(-i "$SSH_KEY_PATH" -o BatchMode=yes)
        timeout "$CONNECTION_TIMEOUT" "$tool" "${SSH_COMMON_OPTS[@]}" "$@"
    elif [ -n "${REMOTE_PASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
        SSH_COMMON_OPTS+=(-o BatchMode=no -o PubkeyAuthentication=no -o PasswordAuthentication=yes)
        SSHPASS="$REMOTE_PASS" timeout "$CONNECTION_TIMEOUT" sshpass -e "$tool" "${SSH_COMMON_OPTS[@]}" "$@"
    else
        SSH_COMMON_OPTS+=(-o BatchMode=yes)
        timeout "$CONNECTION_TIMEOUT" "$tool" "${SSH_COMMON_OPTS[@]}" "$@"
    fi
}

run_sftp() { exec_ssh_tool sftp "$@"; }
run_scp()  { exec_ssh_tool scp "$@"; }

core_upload_sftp() {
    resolve_ecc_ssh_key
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "${SSH_KEY_PATH}" ]; then
        local key_info=""
        command -v ssh-keygen >/dev/null 2>&1 && key_info="$(ssh-keygen -l -f "$SSH_KEY_PATH" 2>/dev/null | awk '{print $NF}')"
        log_info "Avvio caricamento su SFTP ($DEST_SERVER) con chiave ECC ${SSH_KEY_PATH} ${key_info}..."
    else
        log_info "Avvio caricamento su SFTP ($DEST_SERVER)..."
    fi

    if ! run_sftp "$REMOTE_USER@$DEST_SERVER" <<< "pwd" >/dev/null 2>&1; then
        log_error "Connessione SFTP a $REMOTE_USER@$DEST_SERVER fallita. Verifica chiave ECC o credenziali."
        return 1
    fi

    local remote_dir="backup/backup_${FILE_TIMESTAMP}"
    run_sftp "$REMOTE_USER@$DEST_SERVER" >/dev/null 2>&1 << EOF
mkdir backup
mkdir $remote_dir
quit
EOF

    local archives uploaded=0 failed=0
    archives="$(find_backup_archives)"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local fname attempt=1 ok=false
        fname="$(basename "$file")"
        log_verbose "SFTP: invio $fname..."
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
    fi
    log_error "SFTP: completato con $failed errori."
    return 1
}

run_smbclient() {
    local smb_cmd="$1"
    # Negoziazione automatica SMB3/SMB2 con firma digitale dei pacchetti (--signing=required)
    local smb_opts=(-U "$REMOTE_USER" "--signing=${SMB_SIGNING}")
    if [ -n "${REMOTE_PASS:-}" ]; then
        PASSWD="$REMOTE_PASS" timeout "$CONNECTION_TIMEOUT" smbclient "//$DEST_SERVER$SMB_PATH" "${smb_opts[@]}" -c "$smb_cmd"
    else
        timeout "$CONNECTION_TIMEOUT" smbclient "//$DEST_SERVER$SMB_PATH" -N "${smb_opts[@]}" -c "$smb_cmd"
    fi
}

core_upload_smb() {
    log_info "Avvio caricamento su SMB (//$DEST_SERVER$SMB_PATH) con firma digitale (--signing=${SMB_SIGNING})..."
    if ! command -v smbclient >/dev/null 2>&1; then
        log_error "Comando smbclient non trovato. Esegui: sudo ./requirements.sh"
        return 1
    fi
    if ! run_smbclient "ls" >/dev/null 2>&1; then
        log_error "Connessione SMB firmata digitalmente a //$DEST_SERVER$SMB_PATH fallita. Verifica share, firma SMB e credenziali."
        return 1
    fi

    local smb_folder="backup_${FILE_TIMESTAMP}"
    run_smbclient "mkdir $smb_folder" >/dev/null 2>&1 || true

    local archives uploaded=0 failed=0
    archives="$(find_backup_archives)"
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        local fname attempt=1 ok=false
        fname="$(basename "$file")"
        log_verbose "SMB: invio $fname..."
        while [ "$attempt" -le "$MAX_RETRY_ATTEMPTS" ]; do
            if run_smbclient "cd $smb_folder; put \"$file\" \"$fname\"" >/dev/null 2>&1; then
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
        log_success "SMB: $uploaded volume/i caricati con successo in $smb_folder (firmato digitalmente)."
        return 0
    fi
    log_error "SMB: completato con $failed errori."
    return 1
}

core_upload_both() {
    local mode="${PROTOCOL_MODE,,}"
    local sftp_ok=false smb_ok=false

    case "$mode" in
        ftp|sftp)
            core_upload_sftp && { log_success "Upload completato con successo tramite protocollo SFTP!"; return 0; }
            FATAL_ERROR=true
            return 1
            ;;
        smb)
            core_upload_smb && { log_success "Upload completato con successo tramite protocollo SMB firmato!"; return 0; }
            FATAL_ERROR=true
            return 1
            ;;
        *)
            core_upload_sftp && sftp_ok=true
            core_upload_smb && smb_ok=true
            if [ "$sftp_ok" = false ] && [ "$smb_ok" = false ]; then
                log_error "Entrambi i protocolli di destinazione (SFTP e SMB) sono falliti."
                FATAL_ERROR=true
                return 1
            elif [ "$sftp_ok" = false ] || [ "$smb_ok" = false ]; then
                log_info "Upload completato parzialmente (ridondanza parziale: SFTP=$sftp_ok, SMB=$smb_ok)."
                return 0
            else
                log_success "Upload completato con successo su entrambi i protocolli (SFTP ECC + SMB Firmato)!"
                return 0
            fi
            ;;
    esac
}

# ------------------------------------------------------------------------------
# 5. Report HTML ed Email con Allegato "diario-backup.log" (curl SMTP + fallback)
# ------------------------------------------------------------------------------
generate_enhanced_html_report() {
    local html_file="${TEMP_DIR}/backup_report.html"
    local status_color="#28a745" status_title="COMPLETATO CON SUCCESSO"

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
.table-data td:first-child { font-weight: 600; color: #555; width: 38%; }
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
    <div class="sec-title">Chiave di Decifratura Simmetrica (${CIPHER_USED})</div>
    <div class="pass-box">${ENCRYPTION_PASSWORD:-Non disponibile}</div>
    <p style="font-size: 12px; color: #c0392b; margin: 4px 0 16px 0; text-align: center;">Salva questa password in un posto sicuro per poter estrarre i volumi ZIP.</p>
    <div class="sec-title">Dettagli Operazione</div>
    <table class="table-data">
      <tr><td>Data e Ora:</td><td>${READABLE_TIMESTAMP}</td></tr>
      <tr><td>Cartella Sorgente:</td><td>${SOURCE_DIR}</td></tr>
      <tr><td>Elementi Inclusi:</td><td>${ARCHIVED_ITEMS_COUNT} (elenco completo in diario-backup.log)</td></tr>
      <tr><td>Server Destinazione:</td><td>${DEST_SERVER}</td></tr>
      <tr><td>Dimensione Dati:</td><td>${TOTAL_SOURCE_SIZE_MB} MB</td></tr>
      <tr><td>Protocolli &amp; Sicurezza:</td><td>${PROTOCOL_MODE^^} (SFTP ECC + SMB Signing: ${SMB_SIGNING})</td></tr>
      <tr><td>Volumi Generati:</td><td>${HASH_COUNT} (Eliminati sul client: ${LOCAL_CLEANUP_DONE})</td></tr>
    </table>
    <div class="sec-title">Verifica Integrità (SHA-256)</div>
    <div class="hash-box">${formatted_hashes:-Nessun hash registrato}</div>
  </div>
  <div class="footer">Generato automaticamente da Backup_Cyborg.sh • Allegato: diario-backup.log</div>
</div>
</body>
</html>
EOF
}

build_mime_email_with_log() {
    local out_eml="$1"
    local html_file="${TEMP_DIR}/backup_report.html"
    local boundary="====CyborgBackupBoundary_$$===="

    cat > "$out_eml" << EOF
From: Cyborg Backup <${SMTP_USER:-backup@${DEST_SERVER:-localhost}}>
To: <${SYSADMIN_EMAIL}>
Subject: [Cyborg Backup] Report e diario-backup.log - $READABLE_TIMESTAMP
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="${boundary}"

--${boundary}
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 8bit

$(cat "$html_file")

--${boundary}
Content-Type: text/plain; charset=UTF-8; name="diario-backup.log"
Content-Disposition: attachment; filename="diario-backup.log"
Content-Transfer-Encoding: 8bit

$(cat "$LOG_FILE")

--${boundary}--
EOF
}

send_report_email() {
    generate_enhanced_html_report
    if [ -z "$SYSADMIN_EMAIL" ]; then
        log_info "Nessun indirizzo email configurato per il report (SYSADMIN_EMAIL vuoto)."
        return 0
    fi

    log_info "Invio report HTML e allegato diario-backup.log via email a $SYSADMIN_EMAIL..."
    local html_file="${TEMP_DIR}/backup_report.html"
    local mime_msg="${TEMP_DIR}/curl_mail.eml"
    build_mime_email_with_log "$mime_msg"

    if [ -n "$SMTP_SERVER" ] && command -v curl >/dev/null 2>&1; then
        log_verbose "Tentativo di invio tramite curl SMTP ($SMTP_SERVER:$SMTP_PORT)..."
        local curl_auth=()
        [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ] && curl_auth=(--user "$SMTP_USER:$SMTP_PASS")
        if curl --silent --ssl-reqd --url "smtp://${SMTP_SERVER}:${SMTP_PORT}" "${curl_auth[@]}" \
            --mail-from "${SMTP_USER:-backup@localhost}" --mail-rcpt "$SYSADMIN_EMAIL" --upload-file "$mime_msg" >/dev/null 2>&1; then
            log_success "Email con diario-backup.log inviata con successo tramite curl SMTP!"
            return 0
        fi
        log_error "Invio tramite curl SMTP fallito. Tento fallback locale..."
    fi

    if command -v sendmail >/dev/null 2>&1 && sendmail -t < "$mime_msg" 2>/dev/null; then
        log_success "Email con allegato diario-backup.log inviata tramite sendmail!"
        return 0
    fi

    if command -v mail >/dev/null 2>&1; then
        if mail -A "$LOG_FILE" -a "Content-Type: text/html; charset=UTF-8" -s "[Cyborg Backup] Report $READABLE_TIMESTAMP" "$SYSADMIN_EMAIL" < "$html_file" 2>/dev/null || \
           mail -s "[Cyborg Backup] diario-backup.log $READABLE_TIMESTAMP" "$SYSADMIN_EMAIL" < "$LOG_FILE" 2>/dev/null; then
            log_success "Email inviata con successo tramite comando mail locale!"
            return 0
        fi
    fi

    log_info "Nessun client email configurato. Il report HTML e diario-backup.log sono stati salvati nei log locali."
    return 0
}

# ------------------------------------------------------------------------------
# 6. Validatori di Input e Frontend Interattivi (CLI e GUI Zenity)
# ------------------------------------------------------------------------------
validate_directory() { [ -n "$1" ] && [ -d "$1" ] && [ -r "$1" ]; }

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        local o
        for o in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
            [ "$o" -le 255 ] || return 1
        done
        return 0
    fi
    [[ "$ip" =~ ^[a-zA-Z0-9.-]+$ ]]
}

validate_email() { [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; }
zenity_clean()   { zenity "$@" 2>/dev/null; }

cli_collect_params() {
    echo -e "\n=== CYBORG BACKUP SYSTEM — CONFIGURAZIONE CLI ===\n"
    while [ -z "$SOURCE_DIR" ]; do
        read -r -p "Cartella sorgente da salvare (param1): " SOURCE_DIR
        validate_directory "$SOURCE_DIR" || { echo "Cartella non valida o non leggibile."; SOURCE_DIR=""; }
    done
    while [ -z "$DEST_SERVER" ]; do
        read -r -p "IP o hostname server remoto (param2): " DEST_SERVER
        validate_ip "$DEST_SERVER" || { echo "Indirizzo server non valido."; DEST_SERVER=""; }
    done
    while [ -z "$REMOTE_USER" ]; do
        read -r -p "Utente remoto (param3): " REMOTE_USER
    done
    resolve_ecc_ssh_key
    if [ -z "$REMOTE_PASS" ]; then
        read -r -sp "Password remota (param4 - per SMB o SFTP senza chiave ECC): " REMOTE_PASS
        echo ""
    fi
    while [ -z "$SYSADMIN_EMAIL" ]; do
        read -r -p "Email sysadmin per report e diario-backup.log: " SYSADMIN_EMAIL
        validate_email "$SYSADMIN_EMAIL" || { echo "Formato email non valido."; SYSADMIN_EMAIL=""; }
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
    while ! validate_directory "$SOURCE_DIR"; do
        SOURCE_DIR=$(zenity_clean --file-selection --directory --title="Seleziona Cartella da Salvare (param1)") || exit 0
    done
    while [ -z "$DEST_SERVER" ] || ! validate_ip "$DEST_SERVER"; do
        DEST_SERVER=$(zenity_clean --entry --title="Server Remoto (param2)" --text="Inserisci IP o hostname del server di destinazione:") || exit 0
    done
    while [ -z "$REMOTE_USER" ]; do
        REMOTE_USER=$(zenity_clean --entry --title="Utente Remoto (param3)" --text="Inserisci nome utente remoto:") || exit 0
    done
    resolve_ecc_ssh_key
    if [ -z "$REMOTE_PASS" ] && [ -z "$SSH_KEY_PATH" ]; then
        REMOTE_PASS=$(zenity_clean --password --title="Password Remota (param4)") || exit 0
    fi
    while [ -z "$SYSADMIN_EMAIL" ] || ! validate_email "$SYSADMIN_EMAIL"; do
        SYSADMIN_EMAIL=$(zenity_clean --entry --title="Email Sysadmin" --text="Inserisci email per password, report e diario-backup.log:") || exit 0
    done
    [ -z "$SMB_PATH" ] && SMB_PATH="/backup"
}

# ------------------------------------------------------------------------------
# 7. Verifica Requisiti, Esecuzione del Backup e Entrypoint
# ------------------------------------------------------------------------------
check_requirements() {
    local req_cmds=("7z" "sha256sum" "curl" "sftp" "scp" "ssh-keygen" "sshpass" "smbclient")
    [ "$INTERFACE_MODE" = "gui" ] && req_cmds+=("zenity")

    local missing=()
    local cmd
    for cmd in "${req_cmds[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\e[31mERRORE: Requisiti mancanti sul sistema: ${missing[*]}\e[0m" >&2
        echo -e "Lo script non può partire senza tutte le dipendenze necessarie." >&2
        echo -e "Esegui prima:\n  \e[36msudo ${SCRIPT_DIR}/requirements.sh\e[0m" >&2
        exit 1
    fi
}

run_full_backup() {
    acquire_lock

    log_info "========================================================"
    log_info "Avvio Cyborg Backup: $READABLE_TIMESTAMP"
    log_info "Sorgente: $SOURCE_DIR | Destinazione: $DEST_SERVER | Modalità: ${PROTOCOL_MODE^^}"
    log_info "========================================================"

    core_create_encrypted_backup || {
        log_error "Fase di cifratura e creazione archivio fallita."
        send_report_email
        finalize_local_logs
        return 1
    }

    core_upload_both || log_error "Fase di upload non completata con successo."

    # Eliminazione automatica dell'archivio rimasto sul client al termine dell'upload
    cleanup_local_archives

    send_report_email
    finalize_local_logs

    if [ "$FATAL_ERROR" = false ]; then
        log_success "Procedura di backup conclusa con successo!"
        if [ "$INTERFACE_MODE" = "gui" ] && command -v zenity >/dev/null 2>&1; then
            zenity_clean --info --title="Backup Concluso" \
                --text="Backup completato con successo!\n\nPassword (${CIPHER_USED}):\n$ENCRYPTION_PASSWORD\n\nI log (diario-backup.log) e il report sono salvati in ~/.backup_logs/" \
                --width=460
        fi
        return 0
    fi
    log_error "Il backup ha riscontrato anomalie. Consulta diario-backup.log."
    return 1
}

show_version() {
    echo "Backup_Cyborg.sh v0.5 — Sistema di Backup Cifrato Ridondante (Umana + Cyborg)"
    exit 0
}

show_help() {
    local b="" reset="" cyan="" yellow=""
    if [ -t 1 ]; then
        b=$'\033[1m'; reset=$'\033[0m'; cyan=$'\033[36m'; yellow=$'\033[33m'
    fi
    cat << EOF
${b}Backup_Cyborg.sh${reset} — Backup cifrato AES-256 con doppia ridondanza (SFTP ECC + SMB Firmato)

${b}SINTASSI:${reset}
  ${cyan}sudo ./requirements.sh${reset}         # Verifica e installa tutte le dipendenze necessarie
  ${cyan}./Backup_Cyborg.sh${reset} [OPZIONI]
  ${cyan}./Backup_Cyborg.sh${reset} [param1:SORGENTE] [param2:IP] [param3:UTENTE] [param4:PASS] [param5:ftp|sftp|smb|both|EMAIL] [param6:EMAIL]

${b}OPZIONI:${reset}
  ${yellow}-g, --gui${reset}              Avvia l'interfaccia grafica (Zenity)
  ${yellow}-c, --cli${reset}              Forza la modalità riga di comando interattiva
  ${yellow}-k, --cleanup-locks${reset}    Rimuove file di lock orfani in ~/.backup_locks/
  ${yellow}-v, --version${reset}          Mostra la versione dello script
  ${yellow}-h, --help${reset}             Mostra questa guida dettagliata

${b}CONFIGURAZIONE TRAMITE FILE SECRETS (secrets/config.env):${reset}
  SOURCE_DIR          Cartella sorgente locale da archiviare ricorsivamente (param1)
  DEST_SERVER         Indirizzo IP o hostname del server di destinazione (param2)
  REMOTE_USER         Nome utente sul server remoto (param3)
  CYBORG_PASS         Password remota (param4 - usata per SMB o SFTP con sshpass)
  PROTOCOL_MODE       Protocollo di upload: both (default Cyborg), sftp, ftp, smb (param5)
  SSH_KEY_PATH        Percorso chiave SSH privata ECC (es. ~/.ssh/id_ed25519)
  SMB_PATH / SIGNING  Share SMB (default: /backup) e firma digitale (default: required)
  SYSADMIN_EMAIL      Email destinatario per report, password e diario-backup.log
  LOG_PASSWORD        Password personale per cifrare i log locali in ~/.backup_logs/
  SMTP_SERVER / PORT  Server e porta SMTP (es. smtp.gmail.com:587) per invio con curl
  SMTP_USER / PASS    Credenziali di autenticazione SMTP
EOF
    exit 0
}

process_params() {
    local pos_idx=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --gui|-g) INTERFACE_MODE="gui"; shift ;;
            --cli|-c) INTERFACE_MODE="cli"; shift ;;
            --cleanup-locks|-k) cleanup_locks_cmd ;;
            --version|-v) show_version ;;
            --help|-h) show_help ;;
            --*|-*)
                echo "Opzione non riconosciuta: $1 (usa --help per la guida)" >&2
                exit 1
                ;;
            *)
                pos_idx=$((pos_idx + 1))
                case "$pos_idx" in
                    1) SOURCE_DIR="$1" ;;
                    2) DEST_SERVER="$1" ;;
                    3) REMOTE_USER="$1" ;;
                    4) [ "$1" != "-" ] && REMOTE_PASS="$1" ;;
                    5)
                        if [[ "${1,,}" =~ ^(ftp|sftp|smb|both)$ ]]; then
                            PROTOCOL_MODE="${1,,}"
                        else
                            SYSADMIN_EMAIL="$1"
                        fi
                        ;;
                    6) SYSADMIN_EMAIL="$1" ;;
                esac
                shift
                ;;
        esac
    done
}

main() {
    process_params "$@"

    # Controllo rigoroso dei requisiti prima di partire
    check_requirements

    if [ -z "$INTERFACE_MODE" ]; then
        if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
            command -v zenity >/dev/null 2>&1 && INTERFACE_MODE="gui" || INTERFACE_MODE="cli"
        else
            INTERFACE_MODE="cli"
        fi
    fi

    if [ "$INTERFACE_MODE" = "gui" ]; then
        gui_collect_params
    else
        cli_collect_params
    fi

    if ! validate_directory "$SOURCE_DIR"; then
        log_error "Cartella sorgente '$SOURCE_DIR' non valida o inesistente."
        exit 1
    fi

    if [ -z "$DEST_SERVER" ] || ! validate_ip "$DEST_SERVER" || [ -z "$REMOTE_USER" ]; then
        log_error "Server di destinazione ('$DEST_SERVER') o utente remoto ('$REMOTE_USER') non validi."
        exit 1
    fi

    run_full_backup
}

main "$@"
