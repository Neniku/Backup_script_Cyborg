# Backup Script — Cyborg

---
---

[English](#english) · [Italiano](#italiano)

Hardened evolution of [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano).

---
---

<a name="english"></a>
## English
---

Automates the full backup lifecycle for a local Linux directory: compression, encryption, integrity verification, redundant remote upload, HTML reporting and cleanup. Built with robustness in mind — it handles interrupted runs, concurrent execution attempts and failed uploads without losing data.

---

### What it does

1. Recursively archives the source directory (including hidden files) into split ZIP archives
2. Encrypts each archive with a randomly generated password
3. Computes SHA256 hashes for integrity verification
4. Uploads to both SFTP and SMB destinations
5. Generates an HTML report and sends it via email
6. Removes local archives after successful upload

---

### Features

| Feature | Details |
|---|---|
| Encryption | ZIP with auto-generated password at runtime |
| Integrity | SHA256 hash computed and logged post-upload |
| Redundancy | Dual upload: SFTP + SMB |
| Recovery | Checkpoint/resume for interrupted backups |
| Concurrency | Lock file prevents simultaneous executions |
| Interface | CLI and GUI mode via Zenity |
| Reporting | HTML report sent via email |

---

### Usage

```bash
# CLI
./Cyborg_V1.sh /path/to/source <server> <user> <password> <email>

# GUI
./Cyborg_V1.sh --gui

# Other flags
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
```

> Avoid passing passwords directly on the command line in production — they can appear in process listings and shell history. Prefer interactive mode or environment variables.

---

### Requirements

```bash
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

---

### vs. Umano (v1)

| Aspect | Umano | Cyborg |
|---|---|---|
| Encryption | No | Yes, auto-generated password |
| Integrity check | Log only | SHA256 hash |
| Remote destinations | FTP or SMB | SFTP + SMB |
| Recovery | No | Checkpoint and retry |
| Report | Plain text | HTML + email |

---

### Security notes

- Password is generated at runtime, never hardcoded
- SFTP used instead of FTP for encrypted transport
- Lock file prevents race conditions on concurrent runs
- Known limitation: password currently included in the report — separating secrets from reports is a planned improvement

---

---
<a name="italiano"></a>
## Italiano
---

Automatizza l'intero ciclo di vita del backup per una directory Linux locale: compressione, cifratura, verifica dell'integrità, upload remoto ridondante, report HTML e pulizia. Costruito con la robustezza come priorità — gestisce esecuzioni interrotte, tentativi di esecuzione concorrente e upload falliti senza perdere dati.

---

### Cosa fa

1. Archivia ricorsivamente la directory sorgente (inclusi i file nascosti) in archivi ZIP suddivisi
2. Cifra ogni archivio con una password generata casualmente a runtime
3. Calcola gli hash SHA256 per la verifica dell'integrità
4. Carica su SFTP e SMB in modo ridondante
5. Genera un report HTML e lo invia via email
6. Rimuove gli archivi locali dopo l'upload completato

---

### Funzionalità

| Funzionalità | Dettagli |
|---|---|
| Cifratura | ZIP con password generata automaticamente a runtime |
| Integrità | Hash SHA256 calcolato e registrato nel log post-upload |
| Ridondanza | Upload doppio: SFTP + SMB |
| Recovery | Checkpoint/ripresa per backup interrotti |
| Concorrenza | Lock file impedisce esecuzioni simultanee |
| Interfaccia | Modalità CLI e GUI tramite Zenity |
| Report | Report HTML inviato via email |

---

### Utilizzo

```bash
# CLI
./Cyborg_V1.sh /path/to/source <server> <utente> <password> <email>

# GUI
./Cyborg_V1.sh --gui

# Altre opzioni
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
```

> Evitare di passare la password direttamente da riga di comando in produzione — può apparire nel listato dei processi e nella history della shell. Preferire la modalità interattiva o le variabili d'ambiente.

---

### Requisiti

```bash
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

---

### vs. Umano (v1)

| Aspetto | Umano | Cyborg |
|---|---|---|
| Cifratura | No | Sì, password generata automaticamente |
| Verifica integrità | Solo log | Hash SHA256 |
| Destinazioni remote | FTP o SMB | SFTP + SMB |
| Recovery | No | Checkpoint e retry |
| Report | Testo semplice | HTML + email |

---

### Note di sicurezza

- La password è generata a runtime, mai hardcoded
- SFTP usato al posto di FTP per il trasporto cifrato
- Il lock file previene race condition in esecuzioni simultanee
- Limite noto: la password è attualmente inclusa nel report — separare i segreti dal report è un miglioramento previsto

---

## License / Licenza

MIT — see [LICENSE](./LICENSE)
