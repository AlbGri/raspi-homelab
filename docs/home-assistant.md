# Home Assistant: il pannello di controllo del Pi

## In breve

Home Assistant tiene insieme la casa: sensori, automazioni, notifiche, e una dashboard da cui si
controlla tutto, anche dal telefono. Nel mio homelab fa anche un secondo lavoro, che è il tema
di questa pagina: sorveglia il Pi. Mi avvisa quando qualcosa si rompe, mostra lo stato dei
servizi, e da lì accendo e spengo quelli che servono di rado.

Gira in Docker come gli altri servizi, non come sistema operativo dedicato (Home Assistant OS).
Mancano quindi gli add-on, i programmi aggiuntivi da un clic: ogni servizio in più è un
container nel compose. In cambio il Pi resta un normale computer Linux, con tutto il resto
accanto.

## Le notifiche

Gli avvisi arrivano su Telegram e seguono due principi.

**Un avviso che arriva sempre smette di essere letto.** Il firewall del Pi blocca in media circa
78 tentativi l'ora da internet: scansioni automatiche che colpiscono qualsiasi indirizzo
pubblico, e non vogliono dire niente. L'avviso scatta solo quando si supera la soglia di 100, e
solo nel momento in cui la si supera.

**Ogni avviso dice cosa fare.** Chi lo riceve è spesso al telefono e non deve ricordarsi niente:
l'avviso di riavvio contiene i comandi per trovarne la causa, quello del firewall il comando per
bloccare l'indirizzo.

| Avviso | Quando | Dettagli |
|---|---|---|
| Pi riavviato | Home Assistant parte e il Pi è acceso da meno di mezz'ora | [voce 19](controlla.md) |
| Bluetooth bloccato | I sensori Bluetooth smettono di aggiornarsi, poi il ritorno | [voce 17](controlla.md) |
| Immich irraggiungibile | La porta non risponde da 10 minuti, poi il ritorno | più sotto |
| Aggiornamento di un container | Diun trova una versione nuova | più sotto |
| Aggiornamenti del sistema | `apt` ha pacchetti da aggiornare | |
| Firewall | Troppi tentativi da internet, un indirizzo bloccato da Fail2ban, un accesso SSH da un indirizzo sconosciuto | |

Per il firewall Home Assistant, che sta in un container, non vede i registri del Pi: uno script
sull'host li riassume in un file dentro una cartella montata anche in Home Assistant, e un
sensore lo legge.

## "Acceso" non vuol dire "raggiungibile"

Docker dice che un container è `healthy` quando il suo controllo interno risponde, ma il
controllo gira dentro il container e non sa se la porta arriva alla rete di casa. Immich può
essere `healthy` e irraggiungibile da qualsiasi telefono. Il sensore fa quindi quello che fa il
telefono:

```yaml
command_line:
  - sensor:
      name: "Immich Raggiungibile"
      command: "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://<IP del Pi>:2283/api/server/ping || echo 000"
      scan_interval: 300
```

Vale `200` quando Immich risponde. L'avviso di ritorno è legato a quello di guasto con
`wait_for_trigger`, come nella [voce 17](controlla.md): prima mi era arrivato un "di nuovo
raggiungibile" senza nessun guasto annunciato, per un solo controllo fallito mentre Immich
stava ancora partendo dopo un riavvio.

Vale per ogni servizio importante: controllalo da dove lo usi, non da dentro.

## Diun verso Home Assistant

Diun avvisa Home Assistant con un webhook, una chiamata a un indirizzo di Home Assistant:

```yaml
environment:
  - DIUN_WATCH_SCHEDULE=0 9 * * *
  - DIUN_WATCH_FIRSTCHECKNOTIF=false
  - DIUN_NOTIF_WEBHOOK_ENDPOINT=http://<IP del Pi>:8123/api/webhook/diun_updates
  - DIUN_NOTIF_WEBHOOK_METHOD=POST
  - DIUN_NOTIF_WEBHOOK_HEADERS_CONTENT-TYPE=application/json
```

- **`FIRSTCHECKNOTIF=false`**: senza, il primo controllo manda un avviso per ogni container
  esistente
- **`CONTENT-TYPE` con il trattino.** Diun ricava il nome dell'intestazione dal nome della
  variabile: con `CONTENT_TYPE` Home Assistant riceve il webhook ma con i dati vuoti, senza
  errori da nessuna parte
- **nell'automazione, `mode: queued`**: Diun manda una chiamata per ogni immagine, e con la
  modalità predefinita `single` gli aggiornamenti arrivati insieme dopo il primo andrebbero persi

## Lo stato di Docker

Home Assistant legge lo stato dei container con il componente `monitor_docker` di HACS, non dal
socket di Docker, che dà il controllo completo del Pi, ma da un proxy che lascia passare solo le
letture ([voce 11](controlla.md)). Gli interruttori della dashboard per accendere e spegnere i
servizi li sto rivedendo, e per questo non ne descrivo il meccanismo.
