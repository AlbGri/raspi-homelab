# Decisioni

Tengo un registro delle scelte con il loro motivo, perché dopo qualche mese il motivo non lo
ricorda nessuno e torna la tentazione di riaprire discussioni già chiuse. Lo consiglio anche a
te: basta un file di testo.

Per ogni scelta c'è cosa ho scartato e perché. Le scelte nate da un guasto (ora del Pi, controlli
di salute del DNS, log di Docker, notifiche, firewall, database di Home Assistant) sono spiegate
in [Controlla il tuo homelab](controlla.md), insieme al guasto che le ha fatte nascere.

## Cosa installare

### Unbound come resolver, invece di un DNS pubblico a monte

**Scartato:** Pi-hole che inoltra le richieste a un DNS pubblico (Cloudflare, Quad9 e simili).

**Perché:** per non dipendere da un servizio esterno. Unbound interroga direttamente i server
radice e quelli di ogni dominio. Unbound però è un componente in più, con le sue trappole, da cui
vengono la [voce 1](controlla.md) e la [voce 8](controlla.md) di Controlla.

### Niente intelligenza artificiale locale sul Pi

**Scartato:** Ollama o un modello linguistico per descrivere e catalogare le foto.

**Perché:** un Pi 4B non ha una scheda grafica, e servirebbero minuti per ogni immagine. Il
riconoscimento di volti e oggetti di Immich basta, e sul Pi funziona.

### Qualità dell'aria dalle centraline ufficiali

**Scartato:** WAQI, e Open-Meteo.

**Perché:** le centraline WAQI della mia zona erano ferme da mesi senza che il servizio lo
dicesse. Open-Meteo risponde sempre, ma i suoi valori vengono da un modello calcolato su
una griglia di circa 11 km. Volevo misure vere, e OpenAQ pubblica quelle delle centraline
dell'agenzia regionale per l'ambiente. Di qualunque fonte conviene controllare la data
dell'ultima misura, perché un dato che arriva può essere vecchio di mesi.

## Come organizzarlo

### Container accesi solo quando servono

**Scartato:** tenere tutto acceso sempre.

**Perché:** la RAM del Pi è poca, e alcuni servizi la usano solo quando li guardi. Dalla
dashboard di Home Assistant accendo e spengo un gruppo intero con un solo tasto, e tutto
quello che serve per film e serie parte e si ferma insieme.

Il proxy che dà a Home Assistant la lettura dello stato di Docker, invece, non si spegne mai.
Senza, Home Assistant non sa più quali container sono accesi, e gli interruttori smettono
di funzionare.

### Immich in un compose separato

**Scartato:** metterlo nel compose principale con tutto il resto.

**Perché:** Immich esce spesso con modifiche che rompono la compatibilità, e i suoi quattro
container devono avere sempre la stessa versione. Separato si aggiorna da solo, dopo aver letto
le note di rilascio, con le sue variabili e senza toccare il resto. Le differenze rispetto al
compose ufficiale sono nella pagina su [Immich](immich.md).

### Immich: le foto si caricano, non si leggono da una cartella

**Scartato:** la External Library, in cui Immich legge le foto da una cartella che gestisci tu.

**Perché:** un solo percorso per tutto. Le foto del telefono arrivano dall'app di Immich,
l'archivio importato da Google Foto con `immich-go`, e finiscono tutte nello stesso posto,
gestito da Immich.

### Il riconoscimento delle foto di Immich resta sempre acceso

**Scartato:** accenderlo solo quando serve, oppure farlo girare su un computer più potente.

**Perché:** lavora solo quando ci sono foto nuove da analizzare (volti, oggetti); il resto del
tempo occupa circa 130 MB e quasi niente processore. Acceso, le foto nuove vengono analizzate
appena arrivano, e la ricerca per contenuto, che senza non funziona, è sempre disponibile. Il
computer più potente mi è servito una volta sola, per l'import iniziale di tutto l'archivio.

### Rete host come regola, rete bridge per le eccezioni

**Scartato:** una rete bridge per ogni servizio, con le porte pubblicate una per una.

**Perché:** in rete host ogni servizio si raggiunge sull'indirizzo del Pi senza configurare
niente, e Home Assistant vede i dispositivi di casa. I costi sono tre:

- le porte si scontrano, e un servizio deve spostarsi se la sua porta è già presa (la 8080 la
  occupa Pi-hole)
- tutti i container hanno lo stesso indirizzo verso Pi-hole ([voce 4](controlla.md))
- ogni porta è aperta su tutte le interfacce ([voce 11](controlla.md))

Per questo Diun e Immich stanno in reti bridge. Il database e la cache di Immich stanno in una
rete interna, senza accesso a internet: solo il server e il machine learning escono, per
scaricare mappe e modelli.

### I video della camera fuori dalla configurazione di Home Assistant

**Scartato:** salvarli sotto la cartella di configurazione di Home Assistant, o in
`/config/www`.

**Perché:** dati e configurazione restano separati, e i backup di Home Assistant non si
gonfiano di video. La cartella dei media è già condivisa in rete, quindi le clip si guardano dal
PC senza passare da Home Assistant. In `/config/www` mai, perché quella cartella è servita
**senza password** e chiunque conosca l'indirizzo vedrebbe i video di casa.

## Come aggiornarlo

### Aggiornamenti a mano, una volta al mese

**Scartato:** aggiornamenti automatici con Watchtower; aggiornare ogni volta che arriva un
avviso.

**Perché:**

- **Diun al posto di Watchtower.** Diun non scarica niente, chiede ai registry se c'è una
  versione nuova e manda un avviso. Gli basta il permesso di leggere, e le versioni nuove non
  restano sul disco pronte a entrare di nascosto ([voce 5](controlla.md))
- **Una sessione al mese, ma avvisi ogni giorno.** Gli avvisi arrivavano ogni due o tre giorni
  e nessuno aggiornava. Mancava un'abitudine, e ridurli a uno al mese avrebbe solo
  concentrato lo stesso rumore. Ora gli avvisi
  sono la lista della spesa della sessione mensile, che ha un ordine fisso e un modo di tornare
  indietro per ogni servizio (la procedura è in [Gestione](gestione.md))
- **Via il pulsante "scarica aggiornamenti" dalla dashboard.** Scaricava le immagini di tutti i
  servizi senza applicarle, e con un tocco ricreava la situazione della voce 5

## Come documentarlo

### I commenti dicono cos'è una cosa e perché

**Scartato:** commenti e descrizioni che raccontano la storia ("prima usavamo X, poi...").

**Perché:** chi legge un file di configurazione, me compreso fra un anno, non ha vissuto quella
storia, e gli serve sapere perché le cose sono così oggi. La storia sta in un registro a parte,
che è questa pagina.

### Le azioni pericolose della dashboard si spiegano nel messaggio di conferma

**Scartato:** un suggerimento che compare passando sopra il pulsante.

**Perché:** i pulsanti che uso non hanno suggerimenti, e dal telefono non si passa sopra a
niente. Il messaggio di conferma è l'unico modo, già previsto da Home Assistant, di dire cosa
sta per succedere nel momento in cui serve saperlo.
