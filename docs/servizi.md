# Servizi

## In breve

Sul Pi girano una ventina di servizi, ognuno nel suo container: un pacchetto che contiene il
programma e tutto ciò che gli serve, separato dagli altri e dal sistema. Si dividono in due
gruppi: quelli sempre accesi e quelli che accendo solo quando servono.

Il limite vero è la memoria. Il Pi ha 3,7 GB di RAM, e i servizi sempre accesi ne usano circa
1,3. Con i soli servizi sempre accesi il sistema usa già un po' di swap (1,1 GB a ottobre 2026),
la memoria d'appoggio sul disco: più lenta, ma evita che qualcosa si fermi per mancanza di spazio. Per questo il resto
si accende su richiesta (vedi [Decisioni](decisioni.md)).

I valori di memoria qui sotto sono di ottobre 2026: cambiano di giorno in giorno, servono a dare l'ordine di grandezza.

## Sempre accesi

| Servizio | A cosa serve | RAM |
|---|---|---|
| **Rete** | | |
| Pi-hole | Blocca pubblicità e tracciamento per tutti i dispositivi di casa | 123 MB |
| Unbound | Trova gli indirizzi dei siti andando direttamente alla fonte | 19 MB |
| **Casa** | | |
| Home Assistant | Il centro della casa: sensori, automazioni, notifiche, la dashboard da cui gestisco tutto | 504 MB |
| go2rtc | Porta il video della camera a Home Assistant | 13 MB |
| **Foto** | | |
| Immich (server) | L'alternativa a Google Foto: backup dal telefono, album, ricerca | 331 MB |
| Immich (database) | Dove Immich tiene l'elenco delle foto e tutto ciò che sa di loro | 125 MB |
| Immich (cache) | Memoria veloce per i lavori in coda | 13 MB |
| Immich (riconoscimento) | Riconosce volti e oggetti, e permette di cercare "spiaggia" o "cane" | 134 MB |
| **File e accesso** | | |
| Samba | Le cartelle del Pi condivise in rete, visibili dal PC come un disco | 5 MB |
| WireGuard (wg-easy) | Una VPN: da fuori casa il telefono si collega come se fosse in casa | 2 MB |
| DuckDNS | Tiene un nome fisso per raggiungere casa, anche quando il provider cambia indirizzo | 7 MB |
| **Manutenzione** | | |
| Diun | Controlla ogni giorno se ci sono versioni nuove dei servizi e mi avvisa | 10 MB |
| Proxy di Docker | Dà a Home Assistant e a Diun il permesso di leggere lo stato dei container, e niente di più | 2 MB |

Come funzionano Pi-hole e Unbound è nella pagina sul [DNS](dns.md); Immich ha una [pagina
sua](immich.md).

## Accesi su richiesta

| Servizio | A cosa serve |
|---|---|
| Jellyfin | Un Netflix di casa: guarda film e serie salvati sul Pi, dalla TV, dal telefono o dal PC |
| Gruppo film e serie | I programmi che tengono in ordine la libreria che Jellyfin mostra. Partono e si fermano insieme, con un solo tasto |
| Dozzle | Mostra in una pagina web i registri di tutti i container, utile quando qualcosa non va |

Li accendo dalla dashboard di Home Assistant quando servono, e poi li spengo.
