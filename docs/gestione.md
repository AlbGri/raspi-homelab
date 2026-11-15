# Gestione: la sessione mensile di aggiornamento

## In breve

Aggiorno i servizi a mano, una volta al mese. Diun mi avvisa ogni giorno quando esce una
versione nuova, e quegli avvisi diventano la lista di cosa aggiornare nella sessione. Perché a
mano e perché una volta al mese è spiegato in [Decisioni](decisioni.md).

La sessione ha due regole: un servizio alla volta, in un ordine fisso, e per ognuno un modo
pronto per tornare indietro se la versione nuova non funziona.

I comandi qui sotto si lanciano dalla cartella del compose, che chiamo `~/docker`.

## Prima di cominciare

Si cancellano le copie di riserva della sessione precedente: è passato un mese, e se qualcosa
non andava ce ne saremmo accorti.

```bash
docker images --format '{{.Repository}}:{{.Tag}}' | grep ':rollback$' | xargs -r docker rmi
```

La pulizia mensile automatica delle immagini ([voce 13](controlla.md) di Controlla) non le
tocca: cancella solo le immagini senza nome, e queste un nome ce l'hanno. Senza questo passo
resterebbero sul disco per sempre.

## Lo schema per ogni servizio

L'esempio è Pi-hole, ma vale per tutti. Si comincia sempre dalla cartella giusta:

```bash
cd ~/docker
```

Il `cd` va ripetuto anche a metà sessione: se la connessione SSH cade, si riparte dalla cartella
di casa, e un `docker compose` lanciato da lì non trova il file `.env` con le variabili. Il
segnale è una raffica di avvisi come questo:

```
WARN[0000] The "PIHOLE_PASSWORD" variable is not set. Defaulting to a blank string.
```

Se compare, **fermarsi**: il servizio verrebbe ricreato con le variabili vuote.

1. **Mettere da parte l'immagine in uso**, dandole un nome con `:rollback`:

   ```bash
   docker tag $(docker inspect -f '{{.Image}}' pihole) pihole/pihole:rollback
   ```

2. **Aggiornare:**

   ```bash
   docker compose pull pihole && docker compose up -d pihole
   ```

3. **Verificare** che il container sia acceso e sano, **e** che il servizio faccia ancora il
   suo lavoro: la tabella più sotto dice come, servizio per servizio. Un container `healthy`
   che non fa più quello che deve è il guasto più difficile da vedere.

4. **Se non va, tornare indietro:** si rimette il vecchio nome sull'immagine di riserva, e il
   compose la usa.

   ```bash
   docker tag pihole/pihole:rollback pihole/pihole:latest && docker compose up -d pihole
   ```

5. **La copia `:rollback` resta fino alla sessione successiva**, che la cancella come primo
   passo. Certi problemi si vedono solo dopo qualche giorno.

## Ordine e verifiche

Dal servizio meno delicato al più delicato: se qualcosa si rompe, si rompe un pezzo alla volta,
e i primi errori costano poco. Unbound viene prima di Pi-hole perché Pi-hole dipende da lui.

| # | Servizio | Come verificare |
|---|---|---|
| 1 | Samba | La cartella condivisa si apre dal PC |
| 2 | DuckDNS | L'ultima riga del suo registro riporta l'aggiornamento appena fatto |
| 3 | Redis di Immich | Immich si apre e la pagina dei lavori in coda si carica. Gli avvisi `missing 'error' handler on this Redis client` durante il riavvio sono normali |
| 4 | Unbound | `docker exec unbound drill -p 5335 example.com @127.0.0.1` risponde |
| 5 | Pi-hole | Le verifiche 1 e 2 della pagina sul [DNS](dns.md) |
| 6 | Home Assistant | La sezione qui sotto |

Due note:

- **DuckDNS**: se scrive il registro su file (opzione `LOG_FILE=true`), il registro del
  container resta vuoto, e `docker logs duckdns` non dice niente. Si legge il file:
  `tail -3 ~/docker/data/duckdns/duck.log`
- **Redis di Immich** sta nel compose di Immich, in una sottocartella: lì ogni `docker compose`
  vuole anche `--env-file ../.env`, per leggere le variabili del compose principale

Mentre Pi-hole si riavvia, la casa resta senza DNS per qualche secondo. Se non ripartisse,
l'unica via d'uscita è impostare a mano un DNS sul PC da cui si lavora: la
[voce 2](controlla.md) di Controlla spiega perché il router non fa da riserva.

## Home Assistant

È l'ultimo perché è il più delicato: cambia ogni mese, e ogni versione può modificare il
comportamento di un'integrazione.

**Prima**

- Leggere le note di rilascio di **tutte** le versioni saltate, dalla tua all'ultima, nella
  sezione "Backward-incompatible changes", cercando le integrazioni che usi
- Controllare che il backup della notte esista ([voce 20](controlla.md))
- Annotare gli errori che il registro mostra già adesso, per confrontarli dopo

Il backup non è un controllo di routine. Se la versione nuova ha già convertito il database,
rimettere la vecchia con `:rollback` può non bastare: la vecchia non sa leggere il formato
nuovo. In quel caso si torna indietro solo dal backup.

**Durante**

Al primo avvio dopo un salto di versione, Home Assistant può impiegare qualche minuto a
convertire il database. Non riavviarlo mentre lavora.

**Dopo**

- Il container è `healthy` e l'interfaccia si apre
- Gli errori del registro, raggruppati per frequenza, sono gli stessi di prima e non di più
- Una notifica di prova arriva davvero
- I sensori rispondono. In Tools > Template, per ogni integrazione importante, questo conta le
  entità non disponibili e deve dare `0`:

  ```
  {{ integration_entities('<integrazione>') | select('is_state', 'unavailable') | list | count }}
  ```

- I componenti installati da HACS funzionano ancora: non sono ufficiali, e sono i primi a
  rompersi quando Home Assistant cambia qualcosa

## Cosa resta fuori dalla sessione

- **Immich** ha la versione fissata nel `.env`. Diun sorveglia quindi un'etichetta che non
  cambia mai e non segnala mai una versione nuova. Si aggiorna a parte, leggendo le note di
  rilascio: è spiegato nella pagina su [Immich](immich.md)
- **WireGuard** (wg-easy) è fissato alla versione principale 14: Diun segnala solo le
  correzioni di quella linea, e il passaggio alla 15 si decide a parte
- **I servizi spenti** non li sorveglia Diun, che guarda solo i container accesi: si aggiornano
  quando li accendo
