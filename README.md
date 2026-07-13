# Backup Script Cyborg

Evoluzione della versione **Umano** del progetto di backup per Linux, con un focus più marcato su cifratura, integrità dei dati, ridondanza del deposito remoto e recupero automatico in caso di errore.

Lo script automatizza il backup ricorsivo di una directory locale, comprime il contenuto in uno o più archivi ZIP, li crittografa, ne calcola gli hash SHA256 e li carica su due destinazioni remote: un server **SFTP** e una condivisione **SMB**.

## Panoramica

La versione Cyborg nasce come estensione della consegna “umana” già completata, ma introduce una serie di migliorie sostanziali orientate alla robustezza del flusso di backup.

### Funzionalità principali

- Backup ricorsivo della directory sorgente, inclusi file nascosti
- Compressione in uno o più archivi ZIP
- Crittografia automatica degli archivi con password casuale generata dallo script
- Verifica di integrità tramite hash SHA256
- Upload ridondante su **SFTP** e **SMB**
- Validazione preventiva di connessioni, credenziali e permessi
- Interfaccia a riga di comando e interfaccia grafica con Zenity
- Sistema di lock per evitare esecuzioni concorrenti 
- Sistema di checkpoint e recovery per riprendere un backup interrotto
- Report finale HTML con riepilogo tecnico del backup
- Invio del report via email
- Rimozione automatica degli archivi locali dopo upload completato

## Differenze rispetto alla versione Umano

Questa versione non si limita a salvare e trasferire i dati, ma aggiunge protezioni e verifiche che la rendono più adatta a uno scenario “cyborg” [file:95].

| Aspetto | Umano | Cyborg |
|---|---|---|
| Compressione | ZIP | ZIP |
| Crittografia | No | Sì, con password generata automaticamente |
| Integrità | Log dei file salvati | Hash SHA256 dei file di backup |
| Destinazione remota | FTP o SMB | SFTP + SMB |
| Recupero | Base | Checkpoint e recovery |
| Report finale | Testuale | HTML + email |

## Requisiti

Lo script è pensato per Linux e utilizza Bash insieme a vari strumenti esterni.

### Dipendenze principali

- `bash`
- `zip`
- `sha256sum`
- `sftp`
- `scp`
- `smbclient`
- `zenity`
- utility standard come `find`, `du`, `df`, `stat`, `split`, `timeout`
- un sistema di invio email configurato localmente

### Installazione dipendenze

Su Debian/Ubuntu:

```bash
sudo apt update
sudo apt install zip openssh-client smbclient zenity mailutils coreutils findutils
```

## Utilizzo

### Sintassi

```bash
./Cyborg_V1.sh [cartella_origine] [server] [utente] [password] [email]
```

Esempio:

```bash
./Cyborg_V1.sh /home/user/documenti 192.168.1.50 backupuser password123 admin@example.com
```

## Opzioni disponibili

```bash
./Cyborg_V1.sh --gui
./Cyborg_V1.sh --cli
./Cyborg_V1.sh --help
./Cyborg_V1.sh --cleanup-locks
./Cyborg_V1.sh
```

### Significato delle opzioni

- `--gui`: forza la modalità grafica con Zenity
- `--cli`: forza la modalità testuale
- `--help`: mostra la guida
- `--cleanup-locks`: elimina lock file orfani
- senza parametri: permette di scegliere la modalità operativa

## Configurazione

Nel file sono presenti alcune variabili predefinite che possono essere adattate all’ambiente:

```bash
DEFAULT_SOURCE=""
DEFAULT_SERVER=""
DEFAULT_USERNAME=""
DEFAULT_PASSWORD=""
DEFAULT_EMAIL=""
DEFAULT_SMB_PATH="/Samba"
```

Sono inoltre presenti costanti operative per controllo spazio, timeout e retry:

```bash
MIN_FREE_SPACE_MB=1024
SPACE_SAFETY_FACTOR=1.5
CONNECTION_TIMEOUT=30
MAX_CONNECTION_RETRIES=3
MAX_ARCHIVE_SIZE=1024
TEMP_DIR="/tmp/backup_temp"
LOCK_FILE="$HOME/.backup_locks/backup_script.lock"
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=3
VERBOSITY=1
```

## Flusso operativo

Il processo segue una sequenza precisa:

1. Raccolta dei parametri da CLI o GUI
2. Verifica della raggiungibilità e delle credenziali
3. Controllo dello spazio disponibile
4. Generazione della password di cifratura
5. Creazione degli archivi ZIP
6. Calcolo degli hash SHA256
7. Upload via SFTP e SMB
8. Generazione del report HTML
9. Invio del report via email
10. Pulizia degli archivi locali

## Cifratura e integrità

Uno degli elementi distintivi della versione Cyborg è l’uso della cifratura automatica degli archivi con password generata in modo casuale dallo script.

Dopo la creazione dei file di backup, lo script calcola anche gli hash SHA256 dei file prodotti, così da fornire un controllo di integrità separato dalla cifratura stessa.

## Upload ridondante

A differenza della versione precedente, questa versione esegue il deposito remoto su due canali distinti:

- **SFTP**, con test di autenticazione e scrittura
- **SMB**, con validazione della condivisione e verifica dei permessi

Questo approccio migliora l’affidabilità complessiva del backup, perché consente di conservare più copie remote dello stesso materiale.

## Logging e report

Il progetto genera un file `diario_backup.log` nella directory temporanea e produce anche un report HTML più ricco, che riassume lo stato del backup e include informazioni tecniche sui file elaborati.

Il report finale viene poi inviato via email al sysadmin indicato nei parametri.

## Recovery e robustezza

Lo script include diversi meccanismi di protezione operativa:

- lock file per impedire esecuzioni simultanee;
- checkpoint per riprendere compressione o upload;
- retry automatici sui trasferimenti falliti;
- pulizia degli artefatti temporanei dopo completamento corretto;
- gestione delle interruzioni e dei casi di errore.

## Note di sicurezza

Nel contesto didattico del progetto, il backup gestisce anche la password di cifratura e alcuni dettagli tecnici nel log e nel report email.

Dal punto di vista pratico, la gestione dei segreti può essere ulteriormente migliorata in futuro, ad esempio separando i materiali sensibili dal report e usando un sistema più strutturato per la distribuzione delle credenziali.

## Limiti attuali

Dal codice si notano alcuni aspetti che dipendono più dall’infrastruttura che dallo script stesso:

- l’uso di chiavi ECC lato SFTP richiede configurazione server specifica;
- la firma digitale SMB dipende dal supporto del server e del client;
- il vincolo IP e la finestra oraria di accesso vanno implementati lato rete/firewall;
- la password di cifratura è trattata in modo funzionale ma non come segreto da hardening reale.

## Relazione con la versione Umano

La versione Cyborg si appoggia alla versione Umano già completata e ne rappresenta l’evoluzione naturale. Il repository della base precedente è disponibile qui:

- [Backup_script_Umano](https://github.com/Neniku/Backup_script_Umano)

## Contesto didattico

Il progetto è stato sviluppato come esercizio di fine anno su Linux e automatizzazione dei backup, con l’obiettivo di passare da una soluzione “umana” a una soluzione più avanzata, orientata a cifratura, integrità, ridondanza e recupero.

## Note sul processo di sviluppo

Parte dello sviluppo è stata assistita da strumenti di AI. Ogni suggerimento è stato verificato, corretto e integrato manualmente prima della pubblicazione.

## Licenza

Questo progetto è distribuito sotto licenza MIT. Vedi il file `LICENSE` per i dettagli.
