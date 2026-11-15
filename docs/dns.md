# DNS: Pi-hole e Unbound

Come è fatto il DNS di casa. I guasti possibili, e come accorgersene, sono nelle voci 1-4 di
[Controlla il tuo homelab](controlla.md).

## In breve

Ogni volta che un dispositivo apre un sito o un'app si collega a un servizio, prima chiede
"a che indirizzo si trova questo nome?". Il DNS è chi risponde. Nel mio homelab rispondono due
programmi sul Pi:

- **Pi-hole** fa da centralino: se il nome appartiene a un servizio di pubblicità o di
  tracciamento, risponde "non esiste" e la chiamata non parte. Funziona per tutti i dispositivi
  di casa, compresi TV e app, senza installare niente su di loro
- **Unbound** va a cercare le risposte alla fonte: invece di chiederle a un servizio esterno
  (quello del provider, o Google, o Cloudflare), interroga direttamente i server che gestiscono
  ogni dominio, e controlla che le risposte firmate non siano state alterate (DNSSEC)

Il prezzo: se il Pi si ferma, tutta la casa resta senza internet.

## Il percorso di una richiesta

```
 telefono, PC, TV
        │  il router, via DHCP, annuncia il Pi come DNS
        ▼
 Pi-hole  (porta 53)      filtro: pubblicità e tracciamento → 0.0.0.0
        │
        ▼
 Unbound  (127.0.0.1:5335)   cache e verifica DNSSEC
        │
        ▼
 server radice → server del dominio (.it, .com, ...) → server del sito
```

Il router non è nel percorso: annuncia il Pi ai dispositivi, ma per sé usa altri DNS, e non fa
da riserva se il Pi si ferma ([voce 2](controlla.md)).

## Pi-hole: le impostazioni che contano

Pi-hole gira in Docker in rete host, e si configura con variabili d'ambiente nel compose. Quelle
che contano:

```yaml
environment:
  FTLCONF_dns_upstreams: '127.0.0.1#5335'
  FTLCONF_dns_dnssec: 'false'
  FTLCONF_dns_reply_host_IPv4: '<IP del Pi>'
  FTLCONF_dns_revServers: 'true,<rete di casa>/24,<IP del router>,<dominio del router>'
  FTLCONF_misc_etc_dnsmasq_d: 'true'
  FTLCONF_webserver_port: '8080o,[::]:8080o'
```

- **`dns_upstreams`**: un solo DNS a monte, Unbound sul Pi stesso. Nessun DNS pubblico di
  riserva: se ci fosse, Pi-hole lo userebbe anche quando Unbound funziona
- **`dns_dnssec: 'false'`**: la verifica DNSSEC la fa già Unbound. Farla due volte non aggiunge
  niente
- **`dns_reply_host_IPv4`**: l'indirizzo con cui Pi-hole risponde per sé stesso e per i nomi
  locali. Senza, in certe configurazioni risponde `0.0.0.0`
- **`dns_revServers`**: per sapere il nome di un indirizzo della rete di casa, Pi-hole lo chiede
  al router, che lo conosce dal DHCP. Così nei registri di Pi-hole si legge il nome del
  dispositivo invece di un indirizzo
- **`misc_etc_dnsmasq_d`**: carica i file in `/etc/dnsmasq.d`, dove stanno i nomi locali (più
  sotto)
- **`webserver_port`**: l'interfaccia web sulla 8080. La `o` finale rende la porta facoltativa:
  se è occupata, Pi-hole parte lo stesso. In rete host la 8080 è presa per tutto il Pi, ed è per
  questo che un altro servizio che la voleva sta sulla 8085

## Unbound: il file di configurazione

Il file completo è in [`compose/unbound/unbound.conf`](../compose/unbound/unbound.conf). Le scelte
che contano:

- **ascolta solo su `127.0.0.1:5335`**: lo interroga Pi-hole dal Pi stesso, nessun altro
- **`use-caps-for-id: no`**: l'opzione mescola maiuscole e minuscole nelle domande come difesa
  in più, ma alcuni server non le rispettano e il risultato sono `SERVFAIL` sporadici e
  difficili da spiegare. È spenta anche nella configurazione ufficiale dell'immagine
- **cache per un Pi**: due thread, 16 e 32 MB, conservazione minima di 5 minuti, e `prefetch`,
  che rinnova le risposte più richieste prima che scadano
- **`private-address`**: un dominio pubblico non può rispondere con un indirizzo della rete di
  casa. È la difesa contro il DNS rebinding, in cui una pagina web prova a raggiungere i tuoi
  dispositivi passando dal browser. I nomi locali non ne risentono: li risolve prima Pi-hole
- **`root.key`**, il file delle chiavi DNSSEC, Unbound lo aggiorna da sé: per questo si monta
  la sua cartella, non il file da solo ([voce 8](controlla.md))

### Ispezionare un'immagine senza shell

L'immagine che uso (`klutchell/unbound`) è costruita da zero: non ha una shell, quindi
`docker exec -it unbound sh` non funziona. Si lavora con i programmi che contiene:

```bash
# una risposta di prova
docker exec unbound drill -p 5335 example.com @127.0.0.1

# il valore effettivo di un'opzione, per confermare che il container veda il file modificato
docker exec unbound unbound-checkconf -o msg-cache-size /etc/unbound/unbound.conf

# copiare fuori un file per leggerlo
docker cp unbound:/etc/unbound/unbound.conf /tmp/
```

## Nomi locali

Per raggiungere i servizi con un nome invece che con l'indirizzo, un file in
`/etc/dnsmasq.d/` di Pi-hole:

```
address=/<servizio>.lan/<IP del Pi>
address=/<nome del Pi>.<dominio del router>/<IP del Pi>
```

La seconda riga ha una storia. Il Pi ha un indirizzo statico, impostato sul Pi stesso: non lo
chiede al router, e così il router non impara il suo nome. Il risultato è che `ssh <nome del Pi>`
smette di funzionare finché non si aggiunge il record a mano.

Una nota per chi parte da zero: `.lan` funziona, ma non è un suffisso ufficiale. Quello riservato
alle reti di casa è `home.arpa`.

## Verifiche rapide

Dal PC, con l'indirizzo del Pi:

```bash
# 1. Il filtro funziona: un dominio pubblicitario deve rispondere 0.0.0.0 (e :: per IPv6)
nslookup doubleclick.net <IP del Pi>

# 2. DNSSEC funziona: un dominio con le firme sbagliate apposta deve dare errore
#    (su Windows "Server failed"), mentre un dominio normale risponde
nslookup dnssec-failed.org <IP del Pi>
nslookup example.com <IP del Pi>
```

Sul Pi:

```bash
# 3. Unbound risponde: rcode NOERROR e almeno una riga nella ANSWER SECTION
docker exec unbound drill -p 5335 example.com @127.0.0.1

# 4. Pi-hole sta usando Unbound, e non un DNS di riserva dimenticato:
#    deve rispondere [ 127.0.0.1#5335 ] e nient'altro
docker exec pihole pihole-FTL --config dns.upstreams
```

Se la verifica 2 risponde con un indirizzo invece che con un errore, la catena non passa da
Unbound, oppure Unbound non sta verificando le firme.
