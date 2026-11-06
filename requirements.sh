#!/bin/bash
# shellcheck shell=bash

# ==============================================================================
# requirements.sh — Verifica e installazione dipendenze per Backup_Cyborg.sh
# ==============================================================================
# Utilizzo:
#   ./requirements.sh           # Verifica se tutti i requisiti sono presenti
#   sudo ./requirements.sh      # Installa automaticamente i pacchetti mancanti
# ==============================================================================

set -uo pipefail

# Mappa comandi richiesti da Backup_Cyborg.sh
REQUIRED_CMDS=(
    "7z"
    "zip"
    "sha256sum"
    "openssl"
    "curl"
    "sftp"
    "scp"
    "ssh-keygen"
    "sshpass"
    "smbclient"
    "zenity"
)

check_missing_cmds() {
    MISSING_CMDS=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_CMDS+=("$cmd")
        fi
    done
}

print_status() {
    echo "=== Verifica Requisiti Backup_Cyborg.sh ==="
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf "  \e[32m[OK]\e[0m       %-12s (%s)\n" "$cmd" "$(command -v "$cmd")"
        else
            printf "  \e[31m[MANCANTE]\e[0m %-12s\n" "$cmd"
        fi
    done
    echo ""
}

install_packages() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\e[31mERRORE: Per installare i pacchetti mancanti esegui questo script con sudo:\e[0m" >&2
        echo "  sudo ./requirements.sh" >&2
        exit 1
    fi

    echo "Installazione automatica delle dipendenze in corso..."

    if command -v pacman >/dev/null 2>&1; then
        # Arch Linux / Garuda Linux / Manjaro / CachyOS
        pacman -Sy --needed --noconfirm \
            7zip zip coreutils findutils openssl curl openssh sshpass smbclient zenity
    elif command -v apt-get >/dev/null 2>&1; then
        # Debian / Ubuntu / Linux Mint / Kali
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends \
            p7zip-full zip coreutils findutils openssl curl openssh-client sshpass smbclient zenity
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora / RHEL / Rocky / AlmaLinux
        dnf install -y \
            p7zip p7zip-plugins zip coreutils findutils openssl curl openssh-clients sshpass samba-client zenity
    elif command -v zypper >/dev/null 2>&1; then
        # openSUSE
        zypper --non-interactive install \
            p7zip-full zip coreutils findutils openssl curl openssh sshpass samba-client zenity
    else
        echo "ERRORE: Gestore pacchetti non riconosciuto. Installa manualmente: ${MISSING_CMDS[*]}" >&2
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
        echo -e "\e[32mTutti i requisiti sono soddisfatti! Backup_Cyborg.sh è pronto all'uso.\e[0m"
        exit 0
    fi

    echo -e "\e[33mComandi mancanti: ${MISSING_CMDS[*]}\e[0m"

    if [ "$(id -u)" -eq 0 ]; then
        install_packages
        echo ""
        check_missing_cmds
        print_status
        if [ ${#MISSING_CMDS[@]} -eq 0 ]; then
            echo -e "\e[32mInstallazione completata con successo!\e[0m"
            exit 0
        else
            echo -e "\e[31mAlcuni comandi risultano ancora mancanti: ${MISSING_CMDS[*]}\e[0m" >&2
            exit 1
        fi
    else
        echo -e "\nPer installare tutto automaticamente, lancia:"
        echo -e "  \e[36msudo ./requirements.sh\e[0m"
        exit 1
    fi
}

main "$@"
