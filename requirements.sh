#!/bin/bash
# shellcheck shell=bash

# ==============================================================================
# requirements.sh — Verifica e installazione dipendenze per Backup_Cyborg.sh
# ==============================================================================
# Utilizzo:
#   ./requirements.sh           # Controlla se c'è tutto
#   sudo ./requirements.sh      # Installa in automatico quello che manca
# ==============================================================================

set -uo pipefail

REQUIRED_CMDS=(
    "7z"
    "sha256sum"
    "curl"
    "sftp"
    "scp"
    "ssh-keygen"
    "sshpass"
    "smbclient"
    "zenity"
)

cmd_description() {
    case "$1" in
        7z)         echo "Cifratura archivi .zip in AES-256 e divisione in volumi" ;;
        sha256sum)  echo "Calcolo hash SHA-256 dei file di backup" ;;
        curl)       echo "Invio email report diretto via SMTP" ;;
        sftp)       echo "Creazione cartelle e test connessione SFTP" ;;
        scp)        echo "Trasferimento file verso il server SFTP" ;;
        ssh-keygen) echo "Verifica chiavi SSH ECC (Ed25519 / ECDSA)" ;;
        sshpass)    echo "Passaggio password automatico a SFTP/SCP (modalità Umana)" ;;
        smbclient)  echo "Upload su cartella condivisa SMB con firma digitale" ;;
        zenity)     echo "Finestre per l'interfaccia grafica (--gui)" ;;
        *)          echo "" ;;
    esac
}

check_missing_cmds() {
    MISSING_CMDS=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_CMDS+=("$cmd")
        fi
    done
}

print_status() {
    echo "=== Controllo dipendenze per Backup_Cyborg.sh ==="
    for cmd in "${REQUIRED_CMDS[@]}"; do
        local desc
        desc="$(cmd_description "$cmd")"
        if command -v "$cmd" >/dev/null 2>&1; then
            printf "  \e[32m[OK]\e[0m       %-11s — %s\n" "$cmd" "$desc"
        else
            printf "  \e[31m[MANCANTE]\e[0m %-11s — %s\n" "$cmd" "$desc"
        fi
    done
    echo ""
}

install_packages() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\e[31mPer installare i pacchetti mancanti lancia lo script con sudo:\e[0m" >&2
        echo "  sudo ./requirements.sh" >&2
        exit 1
    fi

    echo "Installazione dei pacchetti mancanti in corso..."

    if command -v pacman >/dev/null 2>&1; then
        pacman -Sy --needed --noconfirm \
            7zip coreutils findutils curl openssh sshpass smbclient zenity
    elif command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends \
            p7zip-full coreutils findutils curl openssh-client sshpass smbclient zenity
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y \
            p7zip p7zip-plugins coreutils findutils curl openssh-clients sshpass samba-client zenity
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install \
            p7zip-full coreutils findutils curl openssh sshpass samba-client zenity
    else
        echo "Gestore pacchetti non supportato. Installa manualmente: ${MISSING_CMDS[*]}" >&2
        exit 1
    fi
}

main() {
    check_missing_cmds

    if [ "${1:-}" = "--quiet-check" ]; then
        if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
            echo "${MISSING_CMDS[*]}"
            exit 1
        fi
        exit 0
    fi

    print_status

    if [ ${#MISSING_CMDS[@]} -eq 0 ]; then
        echo -e "\e[32mTutto installato, puoi lanciare Backup_Cyborg.sh.\e[0m"
        exit 0
    fi

    echo -e "\e[33mPacchetti mancanti: ${MISSING_CMDS[*]}\e[0m"

    if [ "$(id -u)" -eq 0 ]; then
        install_packages
        echo ""
        check_missing_cmds
        print_status
        if [ ${#MISSING_CMDS[@]} -eq 0 ]; then
            echo -e "\e[32mInstallazione completata!\e[0m"
            exit 0
        else
            echo -e "\e[31mNon sono riuscito a installare: ${MISSING_CMDS[*]}\e[0m" >&2
            exit 1
        fi
    else
        echo -e "\nPer installare tutto da solo lancia:"
        echo -e "  \e[36msudo ./requirements.sh\e[0m"
        exit 1
    fi
}

main "$@"
