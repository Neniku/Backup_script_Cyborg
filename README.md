# 🤖 Backup Script — Cyborg

> Evolution of [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano) — a hardened, automated Linux backup solution with encryption, integrity verification, and redundant remote storage.

![Language](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=flat&logo=linux&logoColor=black)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat)

🇬🇧 [English](#english) · 🇮🇹 [Italiano](#italiano)

---

<a name="english"></a>
## 🇬🇧 English

### What it does

Automates the full backup lifecycle for a local directory:

1. Recursively archives the source (including hidden files) into split ZIP archives
2. Encrypts each archive with a randomly generated password
3. Computes **SHA256 hashes** for integrity verification
4. Uploads redundantly to both **SFTP** and **SMB** destinations
5. Generates an **HTML report** and sends it via email
6. Cleans up local artifacts after successful upload

### Key Features

| Feature | Details |
|---|---|
| 🔒 Encryption | AES-256 ZIP with auto-generated password |
| ✅ Integrity | SHA256 hash verification post-upload |
| 📡 Redundancy | Dual upload: SFTP + SMB |
| 🔁 Recovery | Checkpoint/resume system for interrupted backups |
| 🔐 Lock system | Prevents concurrent executions |
| 🖥️ UI | CLI and GUI mode (Zenity) |
| 📊 Reporting | HTML report + email delivery |

### Usage

```bash
# CLI mode
./Cyborg_V1.sh /path/to/source 192.168.1.50 user password user@example.com

# GUI mode (requires Zenity)
./Cyborg_V1.sh --gui

# Other options
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
```

### Requirements

```bash
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

### vs. Umano (v1)

| Aspect | Umano | Cyborg |
|---|---|---|
| Encryption | ❌ | ✅ Auto-generated password |
| Integrity check | Log only | SHA256 hash |
| Remote destination | FTP or SMB | SFTP **+** SMB |
| Recovery | ❌ | ✅ Checkpoint & retry |
| Report | Plain text | HTML + email |

### Security Notes

- Password is generated at runtime and never hardcoded
- SFTP preferred over FTP for encrypted transport
- Lock file prevents race conditions on concurrent runs
- Future improvement: externalize secrets via env file or secret manager

---

<a name="italiano"></a>
## 🇮🇹 Italiano

### Cosa fa

Automatizza l'intero ciclo di backup di una directory locale:

1. Archivia ricorsivamente la sorgente (inclusi i file nascosti) in archivi ZIP suddivisi
2. Cifra ogni archivio con una password generata casualmente
3. Calcola gli **hash SHA256** per la verifica dell'integrità
4. Carica in modo ridondante su **SFTP** e **SMB**
5. Genera un **report HTML** e lo invia via email
6. Rimuove gli artefatti locali dopo l'upload completato

### Funzionalità principali

| Funzionalità | Dettagli |
|---|---|
| 🔒 Cifratura | ZIP AES-256 con password generata automaticamente |
| ✅ Integrità | Verifica hash SHA256 post-upload |
| 📡 Ridondanza | Upload doppio: SFTP + SMB |
| 🔁 Recovery | Checkpoint/ripresa per backup interrotti |
| 🔐 Lock | Impedisce esecuzioni concorrenti |
| 🖥️ Interfaccia | Modalità CLI e GUI (Zenity) |
| 📊 Report | Report HTML + invio via email |

### Utilizzo

```bash
# Modalità CLI
./Cyborg_V1.sh /path/to/source 192.168.1.50 utente password utente@esempio.com

# Modalità GUI (richiede Zenity)
./Cyborg_V1.sh --gui

# Altre opzioni
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
```

### Requisiti

```bash
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

### vs. Umano (v1)

| Aspetto | Umano | Cyborg |
|---|---|---|
| Cifratura | ❌ | ✅ Password generata automaticamente |
| Verifica integrità | Solo log | Hash SHA256 |
| Destinazione remota | FTP o SMB | SFTP **+** SMB |
| Recovery | ❌ | ✅ Checkpoint & retry |
| Report | Testo semplice | HTML + email |

### Note di sicurezza

- La password è generata a runtime e non è mai hardcoded
- SFTP preferito a FTP per il trasporto cifrato
- Il lock file previene race condition in caso di esecuzioni simultanee
- Miglioramento futuro: esternalizzare i segreti tramite env file o secret manager

---

## Related / Correlati

- [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano) — la versione base da cui questo script è evoluto

## License / Licenza

MIT — see [LICENSE](./LICENSE)
