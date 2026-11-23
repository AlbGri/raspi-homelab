# Lo script di controllo

## In breve

Molte voci di [Controlla il tuo homelab](controlla.md) si possono verificare da sole. Lo script
[`controlla-homelab.sh`](../scripts/controlla-homelab.sh) lo fa in un colpo, e per ogni voce
risponde `OK`, `ATTENZIONE` o `SALTATO`.

Non modifica niente e non copia file. L'output non contiene percorsi né configurazioni, quindi
si può incollare dove serve, per esempio in una chat per chiedere aiuto.

Ogni controllo è nato da un guasto rimasto invisibile per giorni o settimane, perché nessuno
andava a guardare. Per non affidarmi alla memoria, lo lancio come primo passo della
[sessione mensile](gestione.md).

## Come si lancia

Sul Pi:

```bash
curl -O https://raspi-homelab.albgri.com/scripts/controlla-homelab.sh
less controlla-homelab.sh        # leggilo prima: si lancia con sudo
sudo bash controlla-homelab.sh
```

Senza `sudo` funziona lo stesso, ma salta i controlli che leggono il registro del kernel e i
file di Home Assistant. Home Assistant e Immich li trova da solo, dal nome dell'immagine.

## Cosa controlla

| Controllo | Voce |
|---|---|
| Disco, RAM, temperatura, rallentamenti per calore o alimentazione, servizi di sistema falliti | |
| NTP punta a indirizzi IP | [1](controlla.md) |
| Nessun container su un'immagine senza tag | [6](controlla.md) |
| Log di Docker limitati, e ogni container creato con il limite | [7](controlla.md) |
| Nessun file singolo montato in scrittura | [8](controlla.md) |
| Home Assistant ha il tempo di chiudere il database | [10](controlla.md) |
| Immagini senza nome che si accumulano | [13](controlla.md) |
| Nessuna automazione verso dispositivi che non esistono più | [14](controlla.md) |
| Reset del disco USB | [18](controlla.md) |
| Watchdog attivo | [19](controlla.md) |
| Età dei backup di Home Assistant e di Immich, e se stanno sullo stesso disco del sistema | [20](controlla.md) |

Le altre voci non si possono verificare con uno script, perché dipendono dal router, da come
sono scritte le notifiche o da una prova che va fatta a mano.

## Un esempio di risultato

```
OK          base     disco di sistema al 31%
ATTENZIONE  voce 1   NTP punta a nomi: pool.ntp.org
OK          voce 7   daemon.json limita la dimensione dei log
ATTENZIONE  voce 7   container creati senza limite ai log, da ricreare: pihole
SALTATO     voce 18  nessun disco USB con driver uas
OK          voce 20  Database di Immich: l'ultimo backup ha 0 giorni
                     sta sullo stesso disco del sistema: serve anche una copia altrove

Risultato: 3 OK, 2 da guardare, 1 saltati.
```

`SALTATO` vuol dire che quella cosa da te non c'è, o che serve `sudo`.
