# Controlla il tuo homelab

Venti controlli da fare su un Raspberry Pi con Docker e Home Assistant. Ognuno nasce da un problema che ho avuto io, e nessuno richiede di comprare qualcosa.

I guasti che mi sono costati di più non hanno dato nessun errore: notifiche mute per due giorni, il Bluetooth fermo per tre, un blocco del Pi che nessuno ha notato. Per questo ogni voce dice anche come accorgersene. Per me un guasto è risolto solo quando c'è un controllo automatico che lo noterebbe la volta successiva.

Ogni voce ha tre parti:

- **Controlla**: cosa guardare, di solito un comando da lanciare sul Pi
- **Perché**: cosa succede se è sbagliato
- **Correggi**: cosa ho fatto io

Se le prime righe di una voce non ti riguardano, passa alla successiva. Fra `< >` ci sono i valori da sostituire con i tuoi.

## Ora e DNS

### 1. NTP punta a indirizzi IP

**Controlla.** Quali server usa il Pi per l'ora:

```bash
grep -rhE '^(NTP|FallbackNTP)=' /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.d/ 2>/dev/null
```

Se non esce niente valgono i server predefiniti, che sono nomi (`*.pool.ntp.org`). La voce ti riguarda se sul Pi gira un resolver che verifica DNSSEC, come Unbound.

**Perché.** Il Pi non ha un orologio con la batteria, e al boot riparte dall'ultima ora salvata. Se è rimasto spento qualche giorno, quell'ora è vecchia. Unbound controlla la data delle firme DNSSEC della zona radice e, con un orologio fuori dal loro periodo di validità, le rifiuta, e ogni risposta diventa `SERVFAIL`. NTP dovrebbe correggere l'ora, ma per raggiungere un server indicato per nome deve risolverlo, e il DNS è fermo proprio per l'ora sbagliata.

A me è successo a settembre 2026, dopo alcuni giorni di Pi spento. Nessun dispositivo di casa risolveva più i nomi, e con un DNS esterno impostato a mano sul PC la rete tornava.

**Correggi.** Un file `/etc/systemd/timesyncd.conf.d/10-ntp-ip.conf`:

```ini
[Time]
NTP=<IP del router, se fa da server NTP>
FallbackNTP=162.159.200.1 216.239.35.0
```

I due di riserva sono `time.cloudflare.com` e `time.google.com`. Poi `sudo systemctl restart systemd-timesyncd`.

Due note:

- `fake-hwclock` salva l'ora a intervalli regolari. Aiuta dopo un distacco improvviso della corrente, ma dopo uno spegnimento lungo l'ora salvata è comunque vecchia.
- Subito dopo il boot `timedatectl` può dire `System clock synchronized: no` per qualche minuto anche quando tutto è a posto. Sul mio Pi la prima sincronizzazione arriva dopo circa quattro minuti e mezzo, perché Docker cambia più volte la configurazione di rete mentre crea le sue reti.

### 2. Sai cosa succede alla casa se il DNS del Pi si ferma?

**Controlla.** Sul router, due impostazioni che sembrano la stessa cosa e non lo sono:

- il DNS che il router **annuncia** ai dispositivi (via DHCP)
- il DNS che il router **usa per sé**

Sul FRITZ!Box stanno in due pagine diverse: il primo nelle impostazioni IPv4 della rete domestica, il secondo nei dati di accesso a internet.

**Perché.** Se i dispositivi ricevono il Pi come DNS, un guasto del Pi lascia senza internet tutta la casa, anche con il router che funziona. L'opzione "usa DNS pubblici se il DNS non risponde" che alcuni router offrono riguarda di solito solo le richieste del router stesso: ai dispositivi non arriva.

**Correggi.** Qui c'è una scelta da fare, sapendo cosa comporta. Annunciare un secondo DNS pubblico tiene in piedi la rete, ma i dispositivi lo useranno anche quando il Pi funziona, e una parte della pubblicità passerà. Io ho tenuto solo il Pi, e mi sono segnato la via d'uscita, cioè un DNS impostato a mano sul dispositivo da cui lavoro.

Per verificare che il filtro sia davvero attivo non basta guardare il router. Chiedi al Pi un dominio pubblicitario e controlla che risponda `0.0.0.0`:

```bash
nslookup doubleclick.net <IP del Pi>
```

### 3. Il controllo di salute del DNS fallisce davvero, e Pi-hole non aspetta Unbound

**Controlla.** Che healthcheck ha Pi-hole nel compose:

```bash
docker inspect --format '{{json .Config.Healthcheck}}' pihole
```

**Perché.** Due modi in cui un healthcheck dice "sano" con il DNS rotto:

- usa un nome locale (`pi.hole`), che Pi-hole risolve da sé anche con Unbound fermo
- si fida del codice d'uscita di `dig`, che è 0 anche quando la risposta è `SERVFAIL`

**Correggi.** Un nome esterno, e un `grep` che fallisce se la risposta è vuota:

```yaml
healthcheck:
  test: ["CMD-SHELL", "dig +short +time=2 +tries=1 @127.0.0.1 cloudflare.com | grep -q ."]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

Viene la tentazione di aggiungere a Pi-hole un `depends_on` con `condition: service_healthy` verso Unbound. Io non l'ho fatto, perché legherebbe l'avvio di Pi-hole alla salute di Unbound, e un DNS che risponde male diventerebbe un DNS che non parte per niente. Preferisco che i due guasti restino separati.

### 4. I container in rete host condividono il limite di Pi-hole

**Controlla.** Quali container usano la rete dell'host:

```bash
docker ps --format '{{.Names}}\t{{.Networks}}' | grep -w host
```

**Perché.** Verso Pi-hole tutti questi container si presentano con lo stesso indirizzo, quello del Pi. Pi-hole limita le richieste per indirizzo (di base 1000 al minuto), e se un solo container entra in un ciclo di richieste, il limite scatta per tutti, e ogni altro servizio resta senza DNS.

**Correggi.** Qui basta saperlo. Se un servizio perde il DNS senza motivo apparente, cerca nei messaggi di Pi-hole un avviso di rate limiting sull'indirizzo del Pi, e fra i client più attivi il Pi stesso.

## Docker

### 5. Prima di un `--force-recreate`: l'immagine sul disco è quella che sta girando?

**Controlla.** Confronta l'immagine del container con quella che il disco ha sotto lo stesso tag:

```bash
docker inspect --format '{{.Image}}' <container>
docker image inspect --format '{{.Id}}' <immagine:tag>
```

Se i due valori sono diversi, sul disco c'è una versione più recente in attesa.

**Perché.** `docker compose up -d --force-recreate <servizio>` ricrea il container dall'immagine che trova sul disco. Con un tag mobile (`:latest`, `:stable`) quell'immagine può essere più nuova di quella in esecuzione. Basta un `docker compose pull` fatto settimane prima, o uno strumento che scarica gli aggiornamenti senza applicarli.

A me è successo a settembre 2026. Ho ricreato Home Assistant solo per aggiungere una cartella, ed è passato dalla 2026.4 alla 2026.9, cinque mesi di versioni in un colpo. Nel salto si è rotto il legame fra il dispositivo Telegram e le sue entità di notifica (vedi la voce 14), e per due giorni non è arrivata nessuna notifica, senza un errore.

**Correggi.**

- Prima di un `--force-recreate` su un tag mobile fai il confronto qui sopra, e se serve decidi l'aggiornamento apposta invece di subirlo
- Non tenere immagini nuove sul disco in attesa. Io sono passato da Watchtower a [Diun](https://crazymax.dev/diun/), che interroga i registry e avvisa senza scaricare niente
- Dopo ogni ricreazione controlla che il servizio faccia ancora il suo lavoro, perché `healthy` da solo non lo garantisce

### 6. Nessun container su un'immagine senza tag

**Controlla.**

```bash
docker ps --format '{{.Names}}\t{{.Image}}'
```

Nella seconda colonna ci deve essere `nome:tag`. Un codice esadecimale vuol dire che il container gira su un'immagine che ha perso il suo tag.

**Perché.** Succede quando il tag passa a una versione più nuova mentre il container continua a girare su quella vecchia. Chi controlla gli aggiornamenti, come Diun, non vede quel container, perché non c'è più un riferimento al registry da interrogare.

**Correggi.** Ricreare il container sulla versione che vuoi. Rimettere il tag a mano all'immagine vecchia non risolve.

### 7. Una sola policy dei log, e tutti i container la applicano

**Controlla.** Se esiste una policy globale, e quali container la usano davvero:

```bash
cat /etc/docker/daemon.json
docker ps -aq | xargs docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Config}}'
```

Un container con `map[]` non ha limiti sui log.

**Perché.** Di base Docker conserva i log dei container senza limite di dimensione, e su un Pi lo spazio finisce. La policy in `daemon.json` ha due tranelli:

- vale solo per i container **creati dopo**. Quelli esistenti tengono la configurazione con cui sono nati, anche dopo il riavvio di Docker. Passano sotto la policy solo quando vengono ricreati
- un `daemon.json` scritto male impedisce a Docker di partire. Se sul Pi gira Pi-hole, la casa resta senza DNS

**Correggi.** La policy sta in un posto solo, `/etc/docker/daemon.json`, e non si ripete nei compose, così i servizi futuri la ereditano senza doverlo ricordare.

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

Prima di riavviare Docker si valida il file:

```bash
sudo dockerd --validate --config-file /etc/docker/daemon.json
```

Poi si ricreano i container un po' alla volta, tenendo a mente la voce 5.

### 8. Nessun bind mount di un file singolo che il programma riscrive

**Controlla.** Nei `volumes:` dei compose, le righe che montano un file e non una cartella. Per ognuna: il programma nel container scrive su quel file?

**Perché.** Molti programmi aggiornano un file scrivendo una copia temporanea e rinominandola al posto dell'originale. Su un file montato da solo la rinomina fallisce. Nel mio caso era Unbound, che non riusciva ad aggiornare il file delle chiavi DNSSEC (`root.key`); quel file viveva solo dentro il container e si perdeva a ogni ricreazione.

Il tranello vale anche al contrario. Se sull'host sostituisci un file montato singolarmente con qualcosa che ne crea uno nuovo (`mv`, alcuni editor), il container continua a vedere la versione vecchia. `cp` e `scp` riscrivono il file al suo posto e vanno bene.

**Correggi.** Se il programma deve scrivere, monta la cartella che contiene il file. I file di sola configurazione, montati `:ro`, possono restare singoli.

### 9. Nessuna porta pubblicata sull'IP di un'interfaccia creata da un altro container

**Controlla.** Nei `ports:` dei compose, le righe che indicano un indirizzo (`<IP>:<porta>:<porta>`). Quell'indirizzo esiste già al boot, o lo crea un altro container? Il caso tipico è l'interfaccia della VPN creata da `wg-easy`.

```bash
ip -br addr
```

**Perché.** Al boot Docker può provare a pubblicare la porta prima che l'altro container abbia creato l'interfaccia, e in quel caso il container non parte. Non c'è un modo affidabile di ordinarli, né con `depends_on` né con systemd.

**Correggi.** Pubblica la porta sull'IP del Pi nella rete di casa. Se i client della VPN devono raggiungerla e la VPN porta tutto il traffico (full tunnel), ci arrivano già da lì.

### 10. Home Assistant ha il tempo di chiudere il database

**Controlla.** Dopo un riavvio di Home Assistant, nel suo log:

```
could not validate that the sqlite3 database was shutdown cleanly
```

e quanto tempo Docker gli concede per fermarsi (vuoto o `<nil>` vuol dire 10 secondi):

```bash
docker inspect --format '{{.Config.StopTimeout}}' homeassistant
```

**Perché.** Alla chiusura Docker manda un segnale di arresto e, dopo 10 secondi, uccide il processo. Se un'integrazione rallenta l'arresto (da me era `monitor_docker`), Home Assistant viene ucciso con il database ancora aperto. Una volta non fa danni, ma ripetuto prima o poi corrompe il database, che contiene tutta la cronologia.

**Correggi.** Nel compose, sul servizio di Home Assistant:

```yaml
stop_grace_period: 60s
```

Poi un riavvio di prova, dopo il quale il messaggio non deve ricomparire. Se l'integrazione si bloccasse del tutto nessun tempo basterebbe, quindi questo riduce il rischio senza toglierlo.

### 11. I servizi senza password non stanno in rete host

**Controlla.** Per ogni container in rete host (il comando della voce 4), quali porte apre, e se chi ci arriva deve autenticarsi:

```bash
sudo ss -tlnp
```

**Perché.** In rete host ogni porta aperta dal container è aperta su tutte le interfacce del Pi, compresi la rete di casa e i client della VPN. Diun, per esempio, apre un servizio senza autenticazione per i propri comandi.

**Correggi.** Per i servizi che non devono essere raggiunti da fuori, una rete bridge e nessuna porta pubblicata. Per chi deve leggere lo stato di Docker (Home Assistant, Diun), un [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) in sola lettura invece del socket di Docker montato direttamente.

### 12. Le regole del firewall per i container coprono tutta la `172.16.0.0/12`

**Controlla.** Se un container in rete bridge chiama un servizio dell'host (per esempio Diun che manda un webhook a Home Assistant in rete host), con quale sorgente è aperta la porta:

```bash
sudo ufw status numbered
```

**Perché.** Il container si presenta con un indirizzo `172.x`, non con quello della rete di casa. Se UFW ha la politica di base che rifiuta le connessioni in entrata, il pacchetto viene scartato senza risposta. Il container va in timeout e nel log del servizio chiamato non compare niente, ed è proprio questo l'indizio, perché una richiesta arrivata e rifiutata lascerebbe una traccia.

**Correggi.** La regola va scritta su tutto l'intervallo che Docker usa per le sue reti. La sottorete di un container Docker la sceglie da sé e cambia se la rete viene ricreata, e una regola scritta solo per quella smetterebbe di valere senza avvisare.

```bash
sudo ufw allow from 172.16.0.0/12 to any port <porta> proto tcp
```

### 13. Pulizie di Docker: cosa non lanciare

**Controlla.** Se qualche script o cron lancia `docker system prune`:

```bash
grep -rn 'prune' /etc/cron* /usr/local/bin 2>/dev/null
```

**Perché.**

- `docker system prune -a` toglie anche le immagini con un tag non usate in quel momento, come gli aggiornamenti scaricati e le immagini tenute per tornare indietro
- `--volumes` può cancellare volumi con dei dati dentro
- le stime di spazio recuperabile (`docker system df`, la colonna `SIZE` di `docker images`) contano più volte i layer condivisi e promettono molto più di quello che si libera

**Correggi.** `docker image prune -f` toglie solo le immagini senza tag e non usate, ed è sicuro. Io lo faccio girare una volta al mese con un file in `/etc/cron.monthly/`, eseguibile e senza punti nel nome (altrimenti `run-parts` lo salta):

```bash
#!/bin/sh
docker image prune -f
```

## Home Assistant

### 14. Le notifiche puntano a `entity_id`, non a `device_id`

**Controlla.** Nella cartella di configurazione di Home Assistant:

```bash
grep -n "device_id" automations.yaml scripts.yaml
```

Interessano le righe sotto `target:`. Quelle nei trigger sono un'altra cosa.

**Perché.** Un'azione con destinatario `device_id` cerca le entità di quel dispositivo. Se non ne trova più, per esempio dopo un aggiornamento o un'integrazione rimossa e riaggiunta, non dà errore e non scrive niente nel log. È quello che è successo a me dopo l'aggiornamento della voce 5. Per due giorni nessuna notifica, e me ne sono accorto solo perché ne aspettavo una che non è arrivata.

**Correggi.** Usa `entity_id` (per esempio `notify.<nome>`), che non cambia. Poi esegui l'automazione a mano e controlla che il messaggio arrivi davvero. Vale per qualsiasi azione con `target:`, non solo per le notifiche.

### 15. Le notifiche con dati esterni partono in testo semplice

**Controlla.** Le notifiche Telegram che contengono qualcosa che non hai scritto tu: il nome di un'immagine Docker, un percorso, l'output di un comando, un JSON ricevuto da un webhook.

**Perché.** `notify.send_message` verso Telegram interpreta il testo come Markdown. Basta un trattino basso o una parentesi spaiata nel dato per far rifiutare l'intero messaggio. Nel log di Home Assistant compare

```
Can't parse entities: can't find end of the entity starting at byte offset N
```

ma sul telefono non arriva niente. Le notifiche che contengono solo numeri e indirizzi IP sono al sicuro, finché il dato non cambia forma.

Il testo semplice però non toglie l'anteprima dei link. Telegram riconosce comunque gli indirizzi, e un nome come `ghcr.io/...` diventa una scheda di GitHub più alta del messaggio.

**Correggi.** Per i messaggi con dati esterni si usa l'azione dell'integrazione Telegram, che accetta entrambe le opzioni:

```yaml
- action: telegram_bot.send_message
  data:
    parse_mode: plain_text
    disable_web_page_preview: true
    title: "Aggiornamento disponibile"
    message: "{{ trigger.json.image }}"
```

### 16. Il database conserva solo quello che serve, e le esclusioni filtrano davvero

**Controlla.** Quali entità scrivono più righe nel database (su una copia del file, o in sola lettura come qui):

```bash
sqlite3 -readonly <cartella di HA>/home-assistant_v2.db \
  "SELECT m.entity_id, COUNT(*) FROM states s
   JOIN states_meta m ON s.metadata_id = m.metadata_id
   GROUP BY m.entity_id ORDER BY 2 DESC LIMIT 20;"
```

Se nell'elenco compaiono entità che pensavi di aver escluso con `entity_globs`, l'esclusione non sta funzionando.

**Perché.**

- Un `entity_globs` che non corrisponde a nessuna entità non dà nessun errore, quindi sembra funzionare e può restare sbagliato per mesi. Attenzione ai nomi simili, come le entità di `monitor_docker` che finiscono in `_memory_percent`, non in `_memory_percentage`
- `purge_keep_days` vale per tutto il database e non distingue la temperatura di una stanza, che vale la pena tenere una settimana, da un sensore che scrive ogni pochi secondi per un grafico di un quarto d'ora
- cancellare righe non rimpicciolisce il file, perché SQLite riusa lo spazio liberato senza restituirlo al disco
- `hours_to_show` di un grafico e la durata di conservazione del database sono due impostazioni indipendenti

**Correggi.** Un'automazione notturna che pota solo i sensori rumorosi:

```yaml
- alias: Pulizia sensori ad alta frequenza
  triggers:
    - trigger: time
      at: "03:30:00"
  actions:
    - action: recorder.purge_entities
      data:
        keep_days: 1
        entity_globs:
          - sensor.docker_*_cpu
          - sensor.docker_*_memory
  mode: single
```

I glob, invece dei singoli `entity_id`, fanno rientrare da soli i container che aggiungerai. Le statistiche a lungo termine (media, minimo e massimo orari) non vengono toccate. Gira prima del backup notturno, che così non si porta dietro righe destinate a sparire. Per recuperare spazio sul disco serve, una tantum, `recorder.purge` con `repack: true`, che è lento e rallenta Home Assistant mentre lavora.

### 17. Gli avvisi arrivano in coppia, e li hai provati provocando il guasto

**Controlla.** Per ogni automazione di avviso, l'hai mai vista scattare? E l'avviso di ripristino può arrivare senza che sia arrivato prima quello di guasto?

**Perché.**

- A ottobre 2026 il Bluetooth di Home Assistant si è bloccato e tutti i sensori SwitchBot sono diventati non disponibili. È durato tre giorni prima che qualcuno se ne accorgesse. Nel log c'era `Failed to restart Bluetooth scanner` ogni minuto, ma nessuno leggeva il log
- Dopo un riavvio del Pi è arrivato "Immich di nuovo raggiungibile" senza nessun "non raggiungibile" prima. L'automazione notificava il ritorno da qualsiasi stato, anche quello di un servizio che stava semplicemente partendo

**Correggi.** Un avviso di guasto con un ritardo, e il ripristino come attesa dentro la stessa automazione, così le due notifiche arrivano sempre in coppia e un guasto più breve della soglia non ne produce nessuna:

```yaml
- alias: Avviso servizio non raggiungibile
  triggers:
    - trigger: state
      entity_id: binary_sensor.<servizio>_ok
      to: "off"
      for:
        minutes: 10
  actions:
    - action: notify.send_message
      target:
        entity_id: notify.<nome>
      data:
        message: "<servizio> non raggiungibile da 10 minuti"
    - wait_for_trigger:
        - trigger: state
          entity_id: binary_sensor.<servizio>_ok
          to: "on"
    - action: notify.send_message
      target:
        entity_id: notify.<nome>
      data:
        message: "<servizio> di nuovo raggiungibile"
  mode: single
```

Poi provoca il guasto e aspetta la notifica, perché finché non l'hai vista scattare non sai se funziona. Per il Bluetooth la prova giusta è `sudo rfkill block bluetooth` (e poi `unblock`, perché il blocco sopravvive al riavvio). `systemctl stop bluetooth` non va bene, perché Home Assistant lo risveglia da solo in un paio di minuti.

Se il Bluetooth si blocca davvero, `bluetoothctl power off` e `on` non bastano, anche se è quello che suggerisce il log. Serve `sudo systemctl restart bluetooth`, e Home Assistant riprende da solo entro un minuto. Ho scelto di farmi avvisare invece di riavviarlo in automatico, perché un ripristino automatico nasconderebbe il guasto e richiederebbe di dare a Home Assistant i permessi di amministratore sul Pi.

## Sistema e backup

### 18. Se il sistema sta su un SSD collegato via USB

**Controlla.** Se il disco usa il driver `uas`, e se il kernel ha dovuto resettarlo:

```bash
lsusb -t | grep -i 'Driver=uas'
sudo journalctl -k | grep -i 'uas_eh'
```

Senza `sudo`, `journalctl` risponde `-- No entries --` anche quando le voci ci sono, perché l'utente normale vede solo il proprio journal.

**Perché.** Molti adattatori USB per SSD usano il protocollo UAS. Quando un comando al disco va in timeout, il kernel annulla tutto e resetta il dispositivo, e per circa 30 secondi l'intero Pi resta fermo ad aspettare il disco. I servizi non cadono, ma quelli con un timeout interno possono uscirne in uno stato incoerente. Il blocco del Bluetooth della voce 17 è cominciato proprio con uno di questi reset. Il mio adattatore ha un chip ASMedia (`174c:55aa` in `lsusb`), molto diffuso.

**Correggi.** Se i reset si ripetono, si può disattivare UAS per quell'adattatore aggiungendo a `/boot/firmware/cmdline.txt` (una riga sola, tutto sulla stessa) il parametro:

```
usb-storage.quirks=<vendor>:<product>:u
```

con i due codici letti da `lsusb`. Il disco diventa un po' più lento. Un errore in quel file impedisce al Pi di avviarsi, e se il Pi fa da DNS la casa resta senza internet. Prima fai una copia del file e tieni a portata di mano un modo per correggerlo da un altro computer. Per ora non l'ho applicato, perché ho avuto un solo episodio, e tengo il conto dei reset con lo [script diagnostico](diagnostica.md).

### 19. Se il Pi si blocca, riparte da solo, e tu lo sai

**Controlla.** Se il watchdog hardware è attivo (`0` vuol dire spento):

```bash
systemctl show -p RuntimeWatchdogUSec
```

E poi: se stanotte il Pi si fosse riavviato da solo, lo sapresti?

**Perché.** A ottobre 2026 il Pi si è bloccato di notte. Il journal si interrompe su una riga normale, senza errori e senza la sequenza di spegnimento; il watchdog hardware l'ha fatto ripartire dopo un minuto. L'ho scoperto solo per una notifica strana arrivata al riavvio. La causa del blocco non si può ricostruire, perché con il sistema fermo non è stato scritto niente. Senza watchdog un Pi bloccato resta bloccato finché qualcuno non stacca la spina, e con lui il DNS di casa.

**Correggi.** Il watchdog si attiva con un file `/etc/systemd/system.conf.d/watchdog.conf`:

```ini
[Manager]
RuntimeWatchdogSec=1min
```

Vale dal riavvio successivo. Io ho messo un minuto. Dopo il riavvio controlla nel journal (`sudo journalctl -b | grep -i watchdog`) che il valore sia stato accettato dall'hardware.

Per l'avviso, Home Assistant legge da quanto tempo è acceso il Pi. Nel container `/proc/uptime` è quello dell'host:

```yaml
command_line:
  - sensor:
      name: Uptime Raspberry
      command: "cut -d. -f1 /proc/uptime"
      unit_of_measurement: s
      scan_interval: 300
```

e all'avvio di Home Assistant un'automazione aspetta cinque minuti e avvisa se il Pi è acceso da meno di mezz'ora. Così un riavvio del solo Home Assistant non produce nessuna notifica:

```yaml
- alias: Avviso riavvio del Pi
  triggers:
    - trigger: homeassistant
      event: start
  actions:
    - delay: "00:05:00"
    - action: homeassistant.update_entity
      target:
        entity_id: sensor.uptime_raspberry
    - condition: numeric_state
      entity_id: sensor.uptime_raspberry
      below: 1800
    - action: notify.send_message
      target:
        entity_id: notify.<nome>
      data:
        message: "Il Pi si è riavviato da {{ states('sensor.uptime_raspberry') | int // 60 }} minuti"
```

Non usare per questo l'ora dell'ultimo avvio di System Monitor, che su un Pi senza orologio con la batteria viene calcolata al boot, con l'ora ancora sbagliata, e non viene più corretta.

### 20. I backup esistono, sono recenti, stanno su un altro disco, e ne hai ripristinato uno

**Controlla.** Quattro domande:

- dove sono i backup, e quanti giorni ha il più recente?
- stanno sullo stesso disco dei dati che proteggono?
- un controllo automatico ti avvisa se smettono di essere fatti?
- ne hai mai ripristinato uno?

Per trovarli conviene cercare i file per nome, non le pianificazioni:

```bash
sudo find / -xdev -iname '*backup*' -mtime -3 2>/dev/null
```

**Perché.**

- Avevo concluso di non avere nessun backup, cercando nei cron e nei timer di systemd. Invece Immich fa da solo il dump del proprio database ogni notte, con una funzione interna che né cron né systemd vedono
- Home Assistant aveva un solo backup, vecchio di cinque mesi, quello creato dalla procedura iniziale. I backup automatici non erano mai stati pianificati. Il pannello lo diceva, ma nessuno lo guardava
- Foto, dump del database di Immich e backup di Home Assistant stanno tutti sullo stesso SSD. Proteggono da un errore o da un database corrotto, ma se muore il disco si perde tutto. La copia su un altro disco non ce l'ho ancora, ed è il punto aperto più importante del mio homelab

**Correggi.**

- **Home Assistant**: Settings > System > Backups, in fondo alla pagina "Configure backup settings", con backup giornaliero e le ultime tre copie. La chiave di cifratura senza cui i backup non si ripristinano va tenuta fuori dal Pi (io ne ho anche una copia su carta)
- **Immich**: il backup del database si attiva nelle impostazioni di amministrazione, e i dump finiscono nella cartella `backups/` dentro quella delle foto. Io ne ho ripristinato uno su un database usa e getta e confrontato i conteggi con quello vero. La procedura è nella pagina su [Immich](immich.md)
- **Copia su un disco esterno**: in `/etc/fstab` montato per UUID e con l'opzione `nofail`, così un disco scollegato non blocca l'avvio del Pi. Lo script di copia deve controllare che il disco sia montato davvero (`mountpoint -q <cartella>`) e fermarsi con un errore se non lo è. Altrimenti scrive nella cartella vuota sul disco di sistema e lo riempie senza dire niente
- **Controllo automatico dell'età**: lo fa lo [script diagnostico](diagnostica.md), che avvisa se l'ultimo backup è troppo vecchio

## Se ne fai solo tre

- la **20**, perché senza un backup provato un guasto del disco porta via tutto
- la **17**, perché un avviso mai visto scattare può non funzionare proprio quando serve
- la **1**, se sul Pi gira Unbound: è l'unica che può lasciare tutta la casa senza internet a ogni riavvio dopo qualche giorno di Pi spento
