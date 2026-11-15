# raspi-homelab

Il mio homelab su un Raspberry Pi 4B: cosa ci gira, perché l'ho fatto così, come lo gestisco e
cosa ho imparato dai guasti. Per chi è curioso, per chi vuole farne uno e per chi ne ha già uno
e vuole migliorarlo.

Il sito: https://raspi-homelab.albgri.com

## Cosa c'è

- `docs/`: le pagine, in Markdown. Si leggono anche qui su GitHub. Da cui partire:
  [Controlla il tuo homelab](docs/controlla.md), venti cose che si rompono in silenzio e come
  accorgersene
- `scripts/controlla-homelab.sh`: verifica in un colpo molte di quelle venti voci. Non modifica
  niente; si lancia sul Pi con `sudo bash controlla-homelab.sh`
- `compose/unbound/unbound.conf`: la configurazione di Unbound descritta in
  [docs/dns.md](docs/dns.md)
- `index.html`, `pagina.html`, `assets/`: il sito, senza passaggi di compilazione

Anteprima locale: `python -m http.server 8000` nella cartella del repository, poi
http://127.0.0.1:8000/.

## Licenza

- Il codice (`scripts/`, `compose/`, i file HTML, CSS e JavaScript del sito) è sotto
  [AGPL-3.0](LICENSE)
- I testi (`README.md` e `docs/`) sono sotto [CC BY-SA 4.0](LICENSE-docs): puoi riusarli e
  modificarli citando la fonte e mantenendo la stessa licenza
