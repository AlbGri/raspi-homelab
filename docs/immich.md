# Immich: le foto in casa

## In breve

Immich è un'alternativa a Google Foto che gira sul tuo computer. L'app del telefono carica le
foto appena le scatti, e le sfogli per data, luogo, album e persone, con la ricerca per
contenuto ("spiaggia", "cane"). Sul mio Pi tiene circa 41.000 foto e video, in quattro
container: server, riconoscimento di volti e oggetti, database e cache.

Si parte dal compose ufficiale **della versione che installi**, preso dalla pagina della release
su GitHub: quello della pagina principale del progetto può essere già avanti. Qui sotto solo le
modifiche che ho fatto, e la parte che conta di più: backup e ripristino.

## Cosa ho cambiato rispetto al compose ufficiale

**Database e cache senza internet.** Due reti invece di una: database e cache stanno solo su
quella interna, che non esce; server e riconoscimento stanno su entrambe, per scaricare mappe e
modelli.

```yaml
networks:
  immich-internal:
    internal: true
  immich-external:
```

**La porta solo sull'indirizzo di casa**, `"${RASPBERRY_IP}:2283:2283"` invece di `2283:2283`,
e mai sull'interfaccia della VPN, che al riavvio può non esistere ancora
([voce 9](controlla.md)). Da fuori casa, con la VPN accesa, il telefono arriva all'indirizzo di
casa come tutto il resto.

**`restart: unless-stopped`** invece di `always`: un container spento a mano resta spento anche
dopo un riavvio del Pi.

**La versione fissata** nel `.env` (`IMMICH_VERSION=v2.7.4`) invece di `release`, che segue
sempre l'ultima. Immich cambia spesso in modi che rompono la compatibilità: si aggiorna quando
lo decido, dopo aver letto le note di rilascio.

**Le variabili nel `.env` del compose principale**, così le password stanno in un file solo. Il
prezzo è `--env-file ../.env` in ogni comando: senza, Docker crea i container con le variabili
vuote (l'avviso è descritto in [Gestione](gestione.md)).

**Il server aspetta che database e cache siano pronti**, non solo partiti:

```yaml
depends_on:
  immich-postgres:
    condition: service_healthy
```

Per il DNS la [voce 3](controlla.md) sconsiglia proprio questa attesa, perché un controllo di
salute sbagliato lascerebbe senza internet tutta la casa. Qui no: senza database Immich è
inutile comunque.

## Aggiornare

Immich resta fuori dalla sessione mensile: con la versione fissata Diun non vede mai le uscite
nuove, che si controllano a mano sulla pagina delle release. Si leggono le note di tutte le
versioni saltate, si cambia `IMMICH_VERSION`, e si aggiornano i quattro container insieme:

```bash
cd ~/docker/immich-compose
docker compose --env-file ../.env pull
docker compose --env-file ../.env up -d
```

## Il backup del database

Le foto sono file, ma album, volti, persone, date e posizioni stanno nel database: senza, 41.000
foto diventano un mucchio di file senza ordine.

Immich copia il database ogni notte da sé (si attiva nelle impostazioni di amministrazione), nella
cartella `backups` dentro quella delle foto. Due cose da sapere:

- **l'ora nel nome del file è UTC**: le 02:00 del nome sono le 03:00 d'inverno e le 04:00
  d'estate
- **non passa da cron**: lo pianifica Immich al suo interno, e chi cerca i backup nel crontab
  conclude che non esistono. Mi è successo: la [voce 20](controlla.md) spiega come cercarli per
  nome, e perché serve anche una copia su un altro disco

## Ripristinare il database: la procedura provata

Un backup mai ripristinato è una speranza, non un backup. Provando il mio ho scoperto che il
file da solo non basta: contiene **solo i dati**, non crea l'utente né il database, e non dice
in quale database caricarsi. Da qui due errori con sintomi opposti:

- **se l'utente `immich` non esiste**, escono decine di `ERROR: role "immich" does not exist` e
  non entra niente. Te ne accorgi
- **se carichi nel database sbagliato**, finisce **senza un solo errore** e i dati vanno
  altrove. È il caso peggiore, perché tutto sembra a posto

La prova, su un database usa e getta che non tocca quello vero:

```bash
# 1. Postgres di prova con la STESSA immagine del database di Immich (quelle normali non hanno
#    l'estensione per la ricerca). Utente e database li creano le variabili
docker run -d --name pgtest \
  -e POSTGRES_USER=immich -e POSTGRES_PASSWORD=<una qualunque> -e POSTGRES_DB=immich \
  -v ~/pgtest:/var/lib/postgresql/data \
  <immagine del database di Immich>

# 2. Il caricamento, NEL DATABASE immich: il -d immich è il passo da non sbagliare
gunzip -c <cartella delle foto>/backups/immich-db-backup-<data e ora>.sql.gz \
  | docker exec -i pgtest psql -U immich -d immich

# 3. Il controllo: numeri vicini a quelli veri, ed estensione presente
#    (tabelle al singolare nella 2.7.4: le query con "assets" e "albums" sono per versioni vecchie)
docker exec pgtest psql -U immich -d immich -c \
  "SELECT (SELECT count(*) FROM asset) AS asset, (SELECT count(*) FROM album) AS album;"
docker exec pgtest psql -U immich -d immich -c "SELECT extname FROM pg_extension;"

# 4. Pulizia
docker rm -f pgtest
sudo rm -rf ~/pgtest
```

Sul Pi ci vogliono circa due minuti per una copia di 234 MB compressi. In un ripristino vero,
utente e database li crea il container del database al primo avvio: il passo critico resta il
`-d immich`.

## Da Google Foto a Immich

Google Takeout scarica tutte le foto in più file zip, con accanto a ciascuna un JSON con data,
posizione e persone. [immich-go](https://github.com/simulot/immich-go) li carica in Immich
abbinando ogni foto al suo JSON. Serve una chiave API, da creare nelle impostazioni del tuo
account Immich. Dal PC, in PowerShell:

```powershell
$zip = Get-ChildItem "<cartella del Takeout>\takeout-*.zip" | ForEach-Object { $_.FullName }
& "<cartella di immich-go>\immich-go.exe" upload from-google-photos `
  --server=http://<IP del Pi>:2283 --api-key=<chiave> `
  --include-unmatched --session-tag --concurrent-tasks=4 --log-file=import.log $zip
```

- **tutti gli zip in un comando solo**: una foto e il suo JSON possono stare in zip diversi
- **`--include-unmatched`**: senza, le foto senza JSON vengono saltate in silenzio, e se poi
  svuoti Google "saltata" vuol dire "persa"
- **`--session-tag`**: etichetta tutto l'import, che si ritrova e si annulla in blocco
- **`--concurrent-tasks=4`** invece di 12: il Pi intanto deve continuare a fare il DNS di casa
- **prima una prova con `--dry-run`**

Il risultato mi ha sorpreso: il 60% delle foto c'era già, da un import fatto in passato, e le foto
nuove sono state appena 251. Il valore vero è stato altro: date, luoghi e persone recuperati per
circa 25.000 foto che c'erano già, spoglie. Rilanciare un import non crea doppioni, perché
Immich salta i file che ha già.

Prima di svuotare Google Foto, in quest'ordine: una copia delle foto su un altro disco (finché
non c'è, la seconda copia è proprio Google), un ripristino del database provato, solo allora lo
svuotamento. Alla fine si cancellano le chiavi API dell'import, che danno pieno accesso alla
libreria.
