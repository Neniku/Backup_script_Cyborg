# Backup Script — Cyborg

[Italiano](#italiano) &nbsp;&middot;&nbsp; [English](#english)

Evoluzione di [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano).

---

<a name="italiano"></a>
## Italiano

Cyborg nasce da Umano: stessa logica di base, ma con tutto quello che mancava nella prima versione. La cifratura degli archivi (AES-256), la verifica dell'integrità tramite hash SHA-256, l'upload ridondante su due destinazioni distinte (SFTP + SMB), il report HTML inviato via email (con supporto nativo `curl SMTP` o mail locale) e la protezione dei log locali in un archivio ZIP con password personale. Lo script gestisce anche i tentativi di esecuzione concorrente tramite lock file.

---

### Cosa fa

1. Archivia ricorsivamente la directory sorgente in volumi ZIP cifrati con password AES-256 (24 caratteri URL-safe generati a runtime)
2. Calcola gli hash SHA-256 per la verifica dell'integrità
3. Carica su SFTP (con supporto chiave SSH) e SMB in modo ridondante
4. Genera un report HTML elegante e lo invia via email (con `curl SMTP` diretto o client locale)
5. Protegge e archivia il report e il log locali in un archivio ZIP con password (`LOG_PASSWORD`) in `~/.backup_logs/`
6. Rimuove i file temporanei locali in chiaro dopo il completamento

---

### Funzionalità

| Funzionalità | Dettagli |
|---|---|
| Cifratura archivi | ZIP AES-256 con password a 24 caratteri generata automaticamente a runtime |
| Integrità | Hash SHA-256 calcolato per ogni volume e incluso nel report |
| Ridondanza | Upload simultaneo: SFTP (con chiave SSH o password) + SMB |
| Protezione log locali | Log e report archiviati in uno `.zip` protetto da password in `~/.backup_logs/` |
| Concorrenza | Lock file per impedire esecuzioni simultanee |
| Interfaccia | Modalità CLI e GUI (Zenity) |
| Report | HTML autonomo inviato via email tramite `curl SMTP` o MTA locale |

---

### Utilizzo

```bash
# Configurazione raccomandata (senza credenziali a riga di comando):
cp secrets/config.env.example secrets/config.env
# Modifica secrets/config.env con i tuoi parametri (il file è ignorato da git)

# Esecuzione (carica automaticamente secrets/config.env se presente)
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Oppure con parametri posizionali:
./Backup_Cyborg.sh /path/to/source <server> <utente> <password> <email>

# Altre opzioni
./Backup_Cyborg.sh --help
./Backup_Cyborg.sh --cleanup-locks
```

> Evitare di passare la password direttamente da riga di comando in produzione — può apparire nel listato dei processi e nella history della shell. Preferire l'uso di `secrets/config.env`, l'autenticazione a chiave SSH (`SSH_KEY_PATH`) o le variabili d'ambiente (`CYBORG_PASS`).

---

### Requisiti

```bash
sudo apt install zip openssh-client smbclient zenity curl coreutils findutils
```

---

### Note di sicurezza

- La password di cifratura del backup è generata a runtime a 24 caratteri e mai hardcoded.
- L'autenticazione SFTP supporta chiavi SSH private con batch mode (`SSH_KEY_PATH`).
- I log e il report locali possono essere protetti tramite `LOG_PASSWORD` in `secrets/config.env`: si aprono con doppio clic inserendo la propria password personale.
- Il lock file previene race condition in esecuzioni simultanee.

---

## License / Licenza

MIT — see [LICENSE](./LICENSE)

---

<a name="english"></a>
## English

Cyborg is the hardened evolution of Umano: same core logic, but with everything the first version was missing. Archive encryption (AES-256), SHA-256 integrity verification, redundant upload to two separate destinations (SFTP + SMB), standalone HTML reporting sent via email (direct `curl SMTP` or local MTA), and local log protection inside a password-protected ZIP archive.

---

### What it does

1. Recursively archives the source directory into AES-256 encrypted split ZIP archives with a 24-character runtime password
2. Computes SHA-256 hashes for integrity verification
3. Uploads to both SFTP (with SSH private key support) and SMB destinations
4. Generates an HTML report and sends it via email (direct `curl SMTP` or local MTA)
5. Encrypts local logs and HTML report into a password-protected ZIP archive in `~/.backup_logs/`
6. Cleans up temporary unencrypted files after upload

---

### Usage

```bash
# Recommended setup (no credentials in CLI args):
cp secrets/config.env.example secrets/config.env
# Edit secrets/config.env with your parameters (the file is ignored by git)

# Run (automatically sources secrets/config.env if present)
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Or pass positional arguments:
./Backup_Cyborg.sh /path/to/source <server> <user> <password> <email>

# Other flags
./Backup_Cyborg.sh --help
./Backup_Cyborg.sh --cleanup-locks
```

---

### Requirements

```bash
sudo apt install zip openssh-client smbclient zenity curl coreutils findutils
```
