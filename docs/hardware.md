# Hardware

## In breve

Un Raspberry Pi 4B da 4 GB, dentro un case che contiene anche un SSD da 2 TB, alimentato da un
piccolo gruppo di continuità. Comprati in tre momenti diversi, per una spesa totale di circa
320 €.

Il consumo è fra 5 e 10 W, una stima che non ho ancora misurato con precisione. Acceso tutto
l'anno fa circa 45-90 kWh, cioè 10-25 € di corrente a 0,25-0,30 € al kWh.

## I pezzi

| Pezzo | Modello | Prezzo | Quando |
|---|---|---|---|
| Computer | Raspberry Pi 4 Model B, 4 GB, kit (usato) | circa 80 € | agosto 2024 |
| Case | [DeskPi Pro V2](https://www.amazon.it/dp/B08MDX6NXN) | circa 60 € | novembre 2025 |
| Disco | Samsung 870 EVO 2 TB, SATA (usato) | circa 150 € | novembre 2025 |
| Gruppo di continuità | Tecnoware ERA PLUS (mini UPS in corrente continua) | circa 33 € | agosto 2026 |

I prezzi sono quelli che ho pagato. Oggi i dischi costano circa il triplo, quindi lo stesso
SSD peserebbe molto di più sul totale. Se non devi tenere un archivio di foto, un disco più
piccolo basta.

A questi si aggiunge un dongle Bluetooth USB con chip CSR, un modello economico molto diffuso.

Il sistema è Raspberry Pi OS a 64 bit, basato su Debian 13, e parte direttamente dall'SSD:
nessuna scheda SD.

## Il case DeskPi Pro

Dentro il case stanno il Pi e l'SSD, collegato a una porta USB 3 del Pi da un piccolo ponte
esterno. C'è anche una ventola, governata da una schedina che il Pi vede come una porta seriale:
`/dev/ttyUSB0` (un convertitore CH340).

La velocità la scelgo a mano da un menu di Home Assistant con cinque livelli, da spenta al 100%.
Il menu fa partire uno script Python che scrive la velocità sulla porta seriale. Nell'ultimo
controllo il processore era a 39 °C, senza rallentamenti per il calore. Per verificarlo:

```bash
vcgencmd measure_temp
vcgencmd get_throttled   # 0x0 = nessun rallentamento, né adesso né dall'accensione
```

**Un'avvertenza.** La porta seriale è montata nel container di Home Assistant, perché è lì che
gira lo script. Se la schedina si stacca, il dispositivo sparisce e Home Assistant non si può più
ricreare finché la riga resta nel compose.

## Perché un SSD e non la scheda SD

Home Assistant, Pi-hole e Immich scrivono di continuo: database, registri, miniature delle foto.
Le schede SD non sono fatte per questo. Si consumano, e quando cedono lo fanno spesso senza
preavviso, portandosi via il sistema. Un SSD regge le scritture molto meglio, è più veloce, e da
2 TB tiene anche tutte le foto.

Il punto debole è il collegamento USB. Il ponte fra USB e SATA ogni tanto si resetta, e per una
trentina di secondi il Pi resta fermo sul disco. Come accorgersene e cosa si può fare è nella
[voce 18](controlla.md) di Controlla.

## Il gruppo di continuità

È un mini UPS che lavora in corrente continua: sta fra l'alimentatore e il Pi e, se manca la
corrente, continua ad alimentarlo dalla sua batteria. Tolta la spina, il Pi resta acceso senza
accorgersene. L'autonomia non l'ho ancora misurata.

Il vantaggio non è solo restare accesi. Uno spegnimento brusco può lasciare un database a metà
di una scrittura, e un disco che si spegne mentre scrive è uno dei modi più comuni di
rovinare un sistema.

C'è anche una conseguenza pratica. Da quando c'è l'UPS, un riavvio inatteso **non** va attribuito
per prima cosa a un calo di corrente. A ottobre 2026 il Pi si è bloccato, ed è stato il watchdog
a riavviarlo: un meccanismo che riavvia il Pi se il sistema smette di rispondere. Come attivarlo,
e come farsi avvisare quando succede, è nella [voce 19](controlla.md).

## Bluetooth

Il Bluetooth integrato del Pi è spento, con una riga in `/boot/firmware/config.txt`:

```
dtoverlay=disable-bt
```

I sensori Bluetooth arrivano a Home Assistant dal dongle USB. Ogni tanto la ricerca dei
dispositivi si blocca, e tutti i sensori smettono di aggiornarsi insieme. Come accorgersene e
come rimediare è nella [voce 17](controlla.md).

Ho pensato di cambiare il dongle e per ora non l'ho fatto: dei due blocchi avuti, l'ultimo è
partito da un reset del disco, non dal dongle. Lo cambierò se un blocco arriverà senza un reset
del disco poco prima.
