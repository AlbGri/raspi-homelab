# DNS: Pi-hole e Unbound

Come è fatto il DNS di casa. I guasti possibili, e come accorgersene, sono nelle voci 1-4 di
[Controlla il tuo homelab](controlla.md).

## In breve

Ogni volta che un dispositivo apre un sito o un'app si collega a un servizio, prima chiede
"a che indirizzo si trova questo nome?". Il DNS è chi risponde. Nel mio homelab rispondono due
programmi sul Pi:

- **Pi-hole** fa da centralino. Se il nome appartiene a un servizio di pubblicità, di
  tracciamento o di telemetria (i dati che TV, domotica e visori mandano di continuo ai
  produttori), risponde "non esiste" e la chiamata non parte. Funziona per tutti i dispositivi
  di casa, compresi TV e app, senza installare niente su di loro
- **Unbound** va a cercare le risposte alla fonte: invece di chiederle a un servizio esterno
  (quello del provider, o Google, o Cloudflare), interroga direttamente i server che gestiscono
  ogni dominio, e controlla che le risposte firmate non siano state alterate (DNSSEC)

Se il Pi si ferma, tutta la casa resta senza internet.

## Cosa non blocca, e cosa costa

Pi-hole toglie gran parte della pubblicità e della telemetria, e chiede un po' di manutenzione.

- **La pubblicità che arriva dallo stesso indirizzo del contenuto passa.** Pi-hole vede solo il
  nome a cui il dispositivo si collega. Se video e spot arrivano dallo stesso nome, come su
  YouTube, bloccare gli spot vorrebbe dire bloccare i video
- **Chi usa un DNS suo lo scavalca.** Alcuni dispositivi e app hanno un DNS scritto dentro, e un
  browser con il "DNS sicuro" impostato su un servizio esterno (Cloudflare, Google) non passa da
  Pi-hole
- **Le liste decidono tutto.** Pi-hole blocca solo i nomi che trova nelle liste che gli si danno.
  Più liste, e più aggressive, vuol dire più blocchi, ma anche più siti che smettono di
  funzionare, come un link in una newsletter, il tracciamento di un pacco o il pagamento in un
  negozio online
- **Ogni falso positivo è un'eccezione a mano.** Si cerca nel registro delle richieste (Query Log)
  il nome bloccato e lo si aggiunge fra quelli ammessi, in Group Management > Domains. Se
  il Pi serve tutta la famiglia, le eccezioni toccherà aggiungerle a te

### Le liste che uso

| Lista | Cosa blocca |
|---|---|
| [StevenBlack](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts) | La lista di base, prudente, per pubblicità e malware |
| [OISD big](https://big.oisd.nl/) | Pubblicità, tracciamento e malware, curata per rompere poco |
| [AdGuard DNS](https://v.firebog.net/hosts/AdguardDNS.txt) | Pubblicità e tracciamento |
| [Ads and tracking](https://www.github.developerdan.com/hosts/lists/ads-and-tracking-extended.txt) | Pubblicità e tracciamento |
| [Tracking aggressive](https://www.github.developerdan.com/hosts/lists/tracking-aggressive-extended.txt) | Tracciamento, in modo più deciso, e può rompere qualche sito |
| [AMP](https://www.github.developerdan.com/hosts/lists/amp-hosts-extended.txt) | Le pagine AMP di Google, per cui i risultati di ricerca aperti in quella versione non si caricano |
| [Facebook](https://www.github.developerdan.com/hosts/lists/facebook-extended.txt) | Facebook e i suoi servizi |
| [TikTok](https://raw.githubusercontent.com/superover/TikTok-Blocklist/master/tiktok.txt) | TikTok |
| [Hate and junk](https://www.github.developerdan.com/hosts/lists/hate-and-junk-extended.txt) | Siti d'odio e spazzatura |
| [Dating](https://www.github.developerdan.com/hosts/lists/dating-services-extended.txt) | Siti e app di incontri |

Le ultime quattro non riguardano la pubblicità e tolgono servizi interi. Sono una scelta di
casa, e Pi-hole permette di applicarle solo ad alcuni dispositivi, con i gruppi (Group
Management > Groups).

## Il percorso di una richiesta

1. Telefono, PC e TV chiedono al Pi, che il router annuncia come DNS (via DHCP)
2. Pi-hole (porta 53) filtra: ai nomi di pubblicità e tracciamento risponde `0.0.0.0`
3. Unbound (`127.0.0.1:5335`) tiene la cache e verifica DNSSEC
4. Unbound chiede ai server radice, poi a quelli del dominio (.it, .com...), infine a quello del
   sito

Il router non è nel percorso. Annuncia il Pi ai dispositivi, ma per sé usa altri DNS e non fa
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
  riserva, perché Pi-hole lo userebbe anche quando Unbound funziona
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
  se è occupata, Pi-hole parte lo stesso. In rete host la 8080 è presa per tutto il Pi, e un
  servizio che la vuole deve usarne un'altra

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
- **`root.key`**, il file delle chiavi DNSSEC, Unbound lo aggiorna da sé, quindi si monta
  la sua cartella e non il file da solo ([voce 8](controlla.md))

### Ispezionare un'immagine senza shell

L'immagine che uso (`klutchell/unbound`) è costruita da zero e non ha una shell, quindi
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

La seconda riga serve perché il Pi ha un indirizzo statico, impostato sul Pi stesso. Non lo
chiede al router, che così non impara il suo nome, e `ssh <nome del Pi>` non funziona finché il
record non si aggiunge a mano.

Chi parte da zero farebbe meglio a usare `home.arpa`, il suffisso riservato alle reti di casa.
Anche `.lan` funziona, ma non è ufficiale.

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
