# Backup Script — Cyborg

[Italiano](#italiano) &nbsp;&middot;&nbsp; [English](#english)

Evoluzione di [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano).

---

<a name="italiano"></a>
## Italiano

Cyborg nasce da Umano: stessa logica di base a 5 parametri, ma con tutti i requisiti di sicurezza avanzata della traccia Cyborg. Cifratura simmetrica reale **AES-256** dei volumi `.zip` (estraibili anche da Windows), verifica dell'integrità tramite hash **SHA-256**, manifesto completo dei file salvato in **`diario-backup.log`**, upload ridondante su due destinazioni distinte (**SFTP con chiavi crittografiche ECC** + **SMB con firma digitale obbligatoria** e negoziazione automatica SMB3/SMB2), report HTML + allegato `diario-backup.log` inviati via email (`curl SMTP` o MTA locale) e protezione cifrata dei log locali.

---

### Cosa fa

1. Verifica all'avvio che tutte le dipendenze siano installate sul client (tramite `check_requirements` / `requirements.sh`)
2. Registra l'elenco ricorsivo completo di tutti i file e le directory in **`diario-backup.log`** e archivia la directory sorgente (`param1`) in uno o più volumi `.zip` cifrati in **AES-256** con password complessa a 24 caratteri generata a runtime (4 maiuscole, 4 minuscole, 4 cifre, 4 simboli + 8 misti mescolati con CSPRNG)
3. Calcola gli hash **SHA-256** per ogni volume generato
4. Carica gli archivi in modo ridondante su **SFTP** (autenticazione tramite chiavi ECC `Ed25519`/`ECDSA` o password) e su **SMB** (connessione firmata digitalmente `--signing=required`, retrocompatibile SMB3/SMB2)
5. Elimina automaticamente gli archivi temporanei rimasti sul client subito dopo l'upload
6. Genera un report HTML autonomo e lo invia via email al sysadmin allegando **`diario-backup.log`** (tramite `curl SMTP` diretto o client locale)
7. Protegge e archivia il report e `diario-backup.log` in un archivio `.zip` cifrato (`LOG_PASSWORD`) in `~/.backup_logs/`

---

### Funzionalità

| Funzionalità | Dettagli |
|---|---|
| Verifica Requisiti | Script `requirements.sh` per verifica e installazione automatica (`sudo ./requirements.sh`) |
| Cifratura archivi | ZIP AES-256 (`7z -tzip -mem=AES256` / fallback `zip`) con password complessa a 24 caratteri generata a runtime |
| Diario del backup | Manifesto completo di file e directory salvato in `diario-backup.log` e allegato all'email per il sysadmin |
| Integrità | Hash SHA-256 calcolato per ogni volume e incluso nel report |
| Ridondanza & Protocolli | Upload simultaneo SFTP (chiavi ECC `Ed25519`/`ECDSA`) + SMB (firma digitale `--signing=required`, SMB3/SMB2), oppure singolo (`ftp`/`sftp`/`smb`) |
| Pulizia Client | Rimozione immediata e tracciata dei volumi locali al termine dell'upload |
| Protezione log locali | Log e report archiviati in uno `.zip` protetto da password in `~/.backup_logs/` |
| Concorrenza & UI | Lock file contro esecuzioni simultanee; interfaccia CLI e GUI (Zenity) |

---

### Installazione Requisiti e Utilizzo

```bash
# 1. Verifica (o installa automaticamente con sudo) tutte le dipendenze sul client:
./requirements.sh
sudo ./requirements.sh

# 2. Configurazione raccomandata (senza credenziali in chiaro a riga di comando):
cp secrets/config.env.example secrets/config.env
# Modifica secrets/config.env con i tuoi parametri (il file è ignorato da git)

# 3. Esecuzione (carica automaticamente secrets/config.env se presente)
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Oppure con i 5 parametri posizionali (compatibile sia con traccia Umana che Cyborg):
./Backup_Cyborg.sh /path/to/source <ip_server> <utente> <password> <ftp|sftp|smb|both|email> [email]

# Altre opzioni
./Backup_Cyborg.sh --help
./Backup_Cyborg.sh --cleanup-locks
```

> Evitare di passare la password direttamente da riga di comando in produzione — può apparire nella history della shell. Preferire l'uso di `secrets/config.env`, l'autenticazione a chiave SSH ECC (`SSH_KEY_PATH`) o le variabili d'ambiente (`CYBORG_PASS`).

---

### Note di sicurezza

- La password di cifratura del backup è generata a runtime a 24 caratteri con CSPRNG (`/dev/urandom`) e mai salvata in chiaro nei log.
- L'autenticazione SFTP rileva e privilegia chiavi crittografiche ECC (`id_ed25519`, `id_ecdsa`) in batch mode.
- Le connessioni SMB impongono la firma digitale obbligatoria dei pacchetti (`--signing=required`), negoziano automaticamente SMB3/SMB2 e passano la password tramite variabile d'ambiente `PASSWD` (invisibile in `ps aux`).
- I log (`diario-backup.log`) e il report locali vengono cifrati in AES-256 tramite `LOG_PASSWORD` in `~/.backup_logs/`.

---

## License / Licenza

MIT — see [LICENSE](./LICENSE)

---

<a name="english"></a>
## English

Cyborg is the hardened evolution of Umano: same 5-parameter foundation, extended with all advanced Cyborg security requirements. True **AES-256** symmetric encryption of `.zip` volumes (extractable on Windows), **SHA-256** integrity verification, complete file and directory manifest logged in **`diario-backup.log`**, redundant dual upload (**SFTP with ECC cryptographic keys** + **digitally signed SMB** with automatic SMB3/SMB2 negotiation), standalone HTML report + `diario-backup.log` attachment sent via email (direct `curl SMTP` or local MTA), and encrypted local log archiving.

---

### Usage

```bash
# 1. Check or automatically install all required packages on the client:
./requirements.sh
sudo ./requirements.sh

# 2. Recommended setup (no credentials in CLI args):
cp secrets/config.env.example secrets/config.env
# Edit secrets/config.env with your parameters (the file is ignored by git)

# 3. Run (automatically sources secrets/config.env if present)
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Or pass positional arguments:
./Backup_Cyborg.sh /path/to/source <server_ip> <user> <password> <ftp|sftp|smb|both|email> [email]

# Other flags
./Backup_Cyborg.sh --help
./Backup_Cyborg.sh --cleanup-locks
```
