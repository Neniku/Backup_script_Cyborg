# Backup Script — Cyborg

[Italiano](#italiano) &nbsp;&middot;&nbsp; [English](#english)

Evoluzione di [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano).

---

<a name="italiano"></a>
## Italiano

Cyborg nasce da Umano: stessa logica di base a 5 parametri, ma con tutto quello che serviva per la versione avanzata. Cifratura reale **AES-256** dei volumi `.zip` (tramite `7z`), verifica dell'integrità tramite hash **SHA-256**, elenco completo dei file salvati dentro **`diario-backup.log`**, upload ridondante su due destinazioni (**SFTP con chiavi ECC** + **SMB con firma digitale**), report HTML + allegato `diario-backup.log` inviati via email (`curl SMTP` o mail locale) e protezione dei log locali in uno `.zip` con password personale.

---

### Cosa fa

1. Controlla all'avvio che tutti i pacchetti necessari siano presenti sul client (tramite `requirements.sh`)
2. Salva l'elenco ricorsivo di tutti i file e le cartelle in **`diario-backup.log`** e comprime la directory sorgente in uno o più volumi `.zip` cifrati in **AES-256** con password casuale a 24 caratteri generata al momento
3. Calcola gli hash **SHA-256** per ogni volume creato
4. Carica il backup su **SFTP** (con chiave SSH ECC `Ed25519`/`ECDSA` o password) e su **SMB** (con firma digitale dei pacchetti attiva e compatibilità SMB3/SMB2)
5. Cancella subito gli archivi `.zip` temporanei rimasti sul client appena finito l'upload
6. Genera il report HTML e lo invia via email al sysadmin allegando **`diario-backup.log`**
7. Salva una copia locale di log e report in `~/.backup_logs/` dentro uno `.zip` protetto da `LOG_PASSWORD`

---

### Requisiti e perché servono

Prima di usare lo script puoi verificare o installare tutto in automatico con:

```bash
./requirements.sh          # Controlla cosa c'è e cosa manca
sudo ./requirements.sh     # Installa da solo i pacchetti mancanti
```

Ecco perché lo script richiede ciascun componente sul client:

| Comando | A cosa serve nello script |
|---|---|
| `7z` | Crea archivi `.zip` cifrati con vero algoritmo **AES-256** (`-tzip -mem=AES256`), li divide in più volumi se superano la dimensione massima e cifra i log locali (al posto del vecchio `zip` che usava ZipCrypto) |
| `sha256sum` | Calcola il checksum SHA-256 di ogni volume `.zip` per verificare che i file non siano corrotti |
| `sftp` / `scp` | Creano la cartella sul server remoto e trasferiscono i volumi tramite SSH |
| `ssh-keygen` | Controlla la chiave SSH locale per verificare nei log che sia una chiave ECC (`Ed25519` o `ECDSA`), fa già parte di OpenSSH |
| `sshpass` | Serve quando si usa SFTP con password invece della chiave SSH (modalità Umana), perché `sftp` e `scp` di base non accettano password passate da script |
| `smbclient` | Carica i volumi sulla cartella condivisa SMB/Windows attivando la firma digitale dei pacchetti (`--signing=required`) |
| `curl` | Permette di inviare l'email col report e il log collegandosi direttamente a un server SMTP esterno (es. Gmail), senza dover configurare un server di posta locale |
| `zenity` | Mostra le finestre grafiche quando si lancia lo script con `--gui` |

---

### Come configurare `secrets/config.env`

Per non dover reinserire ogni volta IP, utente, password o email a mano (e senza mai rischiare di caricare dati personali su GitHub), lo script legge automaticamente il file `secrets/config.env`.

1. Copia il file di esempio già pronto nella cartella `secrets/`:
   ```bash
   cp secrets/config.env.example secrets/config.env
   ```
2. Apri `secrets/config.env` con un editor di testo (`nano secrets/config.env` o VS Code) e compila le variabili che ti servono:
   ```env
   SOURCE_DIR="/home/tuo_utente/Documenti"
   DEST_SERVER="192.168.1.100"
   REMOTE_USER="backup_user"
   CYBORG_PASS="tua_password_server"
   PROTOCOL_MODE="both"
   SSH_KEY_PATH="/home/tuo_utente/.ssh/id_ed25519"
   SMB_PATH="/backup"
   SMB_SIGNING="required"
   SYSADMIN_EMAIL="tua_email@esempio.it"
   LOG_PASSWORD="password_per_aprire_i_log_locali"

   # Opzionali per inviare l'email con curl (es. App Password di Gmail):
   SMTP_SERVER="smtp.gmail.com"
   SMTP_PORT="587"
   SMTP_USER="tua_email@gmail.com"
   SMTP_PASS="xxxx xxxx xxxx xxxx"
   ```
3. Chiudi e salva (consigliato dare `chmod 600 secrets/config.env`).
   La cartella `secrets/config.env` è già dentro `.gitignore`, quindi Git la ignorerà sempre. Quando lanci `./Backup_Cyborg.sh`, lo script trova da solo `secrets/config.env`, carica tutte le impostazioni compilate e ti chiede solo quelle che hai eventualmente lasciato vuote.

---

### Utilizzo

```bash
# Esecuzione normale (legge da solo secrets/config.env se esiste)
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Oppure passando i 5 parametri da riga di comando:
./Backup_Cyborg.sh /path/sorgente <ip_server> <utente> <password> <ftp|sftp|smb|both|email> [email]

# Altre opzioni
./Backup_Cyborg.sh --help
./Backup_Cyborg.sh --version
./Backup_Cyborg.sh --cleanup-locks
```

---

## License / Licenza

MIT — see [LICENSE](./LICENSE)

---

<a name="english"></a>
## English

Cyborg is the evolution of Umano: same 5-parameter logic, extended with true **AES-256** `.zip` encryption (via `7z`), **SHA-256** integrity hashes, full file manifest inside **`diario-backup.log`**, redundant dual upload (**SFTP with ECC keys** + **SMB with digital signing**), HTML report + `diario-backup.log` attachment sent via email (`curl SMTP` or local MTA), and password-protected local log archiving.

### Setup & Usage

```bash
# 1. Check or install dependencies automatically:
./requirements.sh
sudo ./requirements.sh

# 2. Configure local secrets (ignored by Git):
cp secrets/config.env.example secrets/config.env
nano secrets/config.env

# 3. Run:
./Backup_Cyborg.sh --cli
./Backup_Cyborg.sh --gui

# Or via positional arguments:
./Backup_Cyborg.sh /path/to/source <server_ip> <user> <password> <ftp|sftp|smb|both|email> [email]
```
