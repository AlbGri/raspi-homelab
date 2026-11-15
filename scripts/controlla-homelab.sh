#!/bin/bash
# Controlla un homelab su Raspberry Pi con Docker e Home Assistant.
# Ogni controllo corrisponde a una voce di "Controlla il tuo homelab" e stampa
# OK, ATTENZIONE o SALTATO. Non modifica niente e non copia file: l'output si può
# incollare dove serve, perché non contiene percorsi dell'host né configurazioni.
#
# Uso: sudo bash controlla-homelab.sh
# Senza sudo funziona lo stesso, ma salta i controlli che leggono il journal del kernel
# e i file di Home Assistant.
#
# Home Assistant e Immich si trovano da soli dal nome dell'immagine. Se hai più istanze
# o nomi insoliti, indica i container: HA_CONTAINER=nome IMMICH_CONTAINER=nome sudo -E bash ...

VOCI="https://raspi-homelab.albgri.com, pagina \"Controlla il tuo homelab\""

ok=0; warn=0; skip=0
report() {   # report STATO VOCE MESSAGGIO
    local label
    case "$1" in
        OK) label="OK        "; ok=$((ok + 1)) ;;
        ATTENZIONE) label="ATTENZIONE"; warn=$((warn + 1)) ;;
        *) label="SALTATO   "; skip=$((skip + 1)) ;;
    esac
    printf '%s  %-8s %s\n' "$label" "$2" "$3"
}
detail() { printf '                     %s\n' "$1"; }

is_root() { [[ $EUID -eq 0 ]]; }
has() { command -v "$1" > /dev/null 2>&1; }
age_days() { echo $(( ( $(date +%s) - $(stat -c %Y "$1") ) / 86400 )); }

docker_ok=false
if has docker && docker info > /dev/null 2>&1; then docker_ok=true; fi

# Trova un container dal nome dell'immagine, se non è stato indicato a mano
find_container() {
    $docker_ok || return
    docker ps -a --format '{{.Names}} {{.Image}}' | awk -v pat="$1" '$2 ~ pat {print $1; exit}'
}
# Percorso sull'host montato in un container in una certa destinazione
mount_source() {
    docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Source}}{{end}}{{end}}" "$1" 2>/dev/null
}

HA_CONTAINER="${HA_CONTAINER:-$(find_container 'home-assistant')}"
IMMICH_CONTAINER="${IMMICH_CONTAINER:-$(find_container 'immich-server')}"
HA_CONFIG=""
[[ -n "$HA_CONTAINER" ]] && HA_CONFIG=$(mount_source "$HA_CONTAINER" /config)

echo "Controllo dell'homelab - $(date '+%Y-%m-%d %H:%M')"
echo "Le voci sono spiegate in: $VOCI"
is_root || echo "Senza sudo: alcuni controlli verranno saltati."
echo

# --- Basi -------------------------------------------------------------------------------

disk=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [[ "$disk" -gt 85 ]]; then report ATTENZIONE base "disco di sistema pieno al $disk%"
else report OK base "disco di sistema al $disk%"; fi

mem=$(free | awk '/^Mem:/ {printf "%.0f", ($2 - $7) / $2 * 100}')
if [[ "$mem" -gt 85 ]]; then report ATTENZIONE base "RAM in uso al $mem%"
else report OK base "RAM in uso al $mem%"; fi

if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))
    if [[ "$temp" -gt 70 ]]; then report ATTENZIONE base "processore a $temp °C"
    else report OK base "processore a $temp °C"; fi
fi

if has vcgencmd; then
    throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    if [[ "$throttled" == "0x0" ]]; then report OK base "nessun rallentamento per calore o alimentazione"
    else report ATTENZIONE base "rallentamenti rilevati ($throttled): alimentatore o temperatura"; fi
fi

failed=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
if [[ -z "$failed" ]]; then report OK base "nessun servizio di sistema fallito"
else
    report ATTENZIONE base "servizi di sistema falliti:"
    while read -r unit; do detail "$unit"; done <<< "$failed"
fi

# --- Voce 1: NTP per indirizzo -----------------------------------------------------------
# Senza orologio a batteria, al riavvio l'ora è sbagliata: DNSSEC rifiuta le firme, il DNS
# smette di rispondere e NTP non può più risolvere i nomi dei server per correggerla.

if systemctl is-active --quiet systemd-timesyncd; then
    servers=$(timedatectl show-timesync -p SystemNTPServers --value 2>/dev/null)
    [[ -z "$servers" ]] && servers=$(timedatectl show-timesync -p FallbackNTPServers --value 2>/dev/null)
    names=$(tr ' ' '\n' <<< "$servers" | grep -v '^$' | grep -Ev '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9a-fA-F:]+$')
    if [[ -z "$servers" ]]; then report ATTENZIONE "voce 1" "nessun server NTP configurato"
    elif [[ -z "$names" ]]; then report OK "voce 1" "NTP punta solo a indirizzi IP"
    else report ATTENZIONE "voce 1" "NTP punta a nomi: $(tr '\n' ' ' <<< "$names")"; fi
else
    report SALTATO "voce 1" "systemd-timesyncd non è attivo: controlla a mano il tuo client NTP"
fi

# --- Docker -----------------------------------------------------------------------------

if ! $docker_ok; then
    report SALTATO docker "Docker non raggiungibile: lancia con sudo, o con un utente nel gruppo docker"
else
    # Voce 6: un container su un'immagine senza tag è invisibile a chi sorveglia gli
    # aggiornamenti, perché non ha un nome da confrontare con il registry
    untagged=$(docker ps -a --format '{{.Names}} {{.Image}}' | awk '$2 ~ /^(sha256:)?[0-9a-f]{12,64}$/ {print $1}')
    if [[ -z "$untagged" ]]; then report OK "voce 6" "tutti i container usano un'immagine con nome"
    else report ATTENZIONE "voce 6" "container su immagine senza tag: $(tr '\n' ' ' <<< "$untagged")"; fi

    # Voce 7: la policy dei log vale solo per i container creati dopo averla impostata
    if [[ -f /etc/docker/daemon.json ]] && grep -q 'max-size' /etc/docker/daemon.json; then
        report OK "voce 7" "daemon.json limita la dimensione dei log"
    else
        report ATTENZIONE "voce 7" "daemon.json non limita i log dei container"
    fi
    unbounded=""
    for c in $(docker ps -a --format '{{.Names}}'); do
        cfg=$(docker inspect -f '{{.HostConfig.LogConfig.Type}} {{range $k, $v := .HostConfig.LogConfig.Config}}{{$k}} {{end}}' "$c")
        [[ "$cfg" == json-file* && "$cfg" != *max-size* ]] && unbounded+="$c "
    done
    if [[ -z "$unbounded" ]]; then report OK "voce 7" "ogni container ha i log limitati"
    else report ATTENZIONE "voce 7" "container creati senza limite ai log, da ricreare: $unbounded"; fi

    # Voce 8: un file montato da solo si rompe se il programma lo riscrive con un rename.
    # Si segnalano solo quelli scrivibili: le sole letture, come /etc/localtime, vanno bene
    single=""
    for c in $(docker ps -a --format '{{.Names}}'); do
        while IFS='|' read -r src dst rw; do
            [[ -n "$src" && "$rw" == "true" && -f "$src" ]] && single+="$c:$dst "
        done < <(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}|{{.Destination}}|{{.RW}}{{"\n"}}{{end}}{{end}}' "$c")
    done
    if [[ -z "$single" ]]; then report OK "voce 8" "nessun file singolo montato in scrittura"
    else
        report ATTENZIONE "voce 8" "file singoli montati in scrittura: verifica che il programma non li riscriva"
        for m in $single; do detail "$m"; done
    fi

    # Voce 10: con i 10 secondi predefiniti Home Assistant può non fare in tempo a chiudere
    # il database, che al riavvio successivo risulta chiuso male
    if [[ -n "$HA_CONTAINER" ]]; then
        stop=$(docker inspect -f '{{if .Config.StopTimeout}}{{.Config.StopTimeout}}{{else}}10{{end}}' "$HA_CONTAINER")
        unclean=$(docker logs "$HA_CONTAINER" 2>&1 | grep -c 'was shutdown cleanly')
        if [[ "$stop" -ge 30 ]]; then report OK "voce 10" "Home Assistant ha $stop secondi per fermarsi"
        else report ATTENZIONE "voce 10" "Home Assistant ha solo $stop secondi per fermarsi (stop_grace_period)"; fi
        [[ "$unclean" -gt 0 ]] && detail "chiusure non pulite del database nel log attuale: $unclean"
    else
        report SALTATO "voce 10" "container di Home Assistant non trovato"
    fi

    # Voce 13: le immagini senza nome si accumulano a ogni aggiornamento
    dangling=$(docker images -f dangling=true -q | wc -l)
    if [[ "$dangling" -gt 10 ]]; then report ATTENZIONE "voce 13" "$dangling immagini senza nome: manca una pulizia periodica"
    else report OK "voce 13" "$dangling immagini senza nome"; fi
fi

# --- Home Assistant ---------------------------------------------------------------------

# Voce 14: un'azione verso un device_id che non esiste più non fallisce e non lo dice
if [[ -z "$HA_CONFIG" ]]; then
    report SALTATO "voce 14" "cartella di configurazione di Home Assistant non trovata"
elif ! is_root; then
    report SALTATO "voce 14" "serve sudo per leggere il registro dei dispositivi"
elif ! has python3; then
    report SALTATO "voce 14" "serve python3"
else
    orphans=$(python3 - "$HA_CONFIG" << 'PYEOF'
import json, os, re, sys
base = sys.argv[1]
try:
    with open(os.path.join(base, ".storage", "core.device_registry")) as fh:
        known = {d["id"] for d in json.load(fh)["data"]["devices"]}
except (OSError, ValueError, KeyError):
    print("-1")
    raise SystemExit
used = set()
for name in ("automations.yaml", "scripts.yaml", "scenes.yaml"):
    try:
        with open(os.path.join(base, name)) as fh:
            used |= set(re.findall(r"device_id:\s*['\"]?([0-9a-f]{32})", fh.read()))
    except OSError:
        pass
print(len(used - known))
PYEOF
)
    if [[ "$orphans" == "-1" ]]; then report SALTATO "voce 14" "registro dei dispositivi non leggibile"
    elif [[ "$orphans" -eq 0 ]]; then report OK "voce 14" "nessuna automazione punta a dispositivi inesistenti"
    else report ATTENZIONE "voce 14" "device_id nelle automazioni che non esistono più: $orphans (usa entity_id)"; fi
fi

# --- Sistema e backup -------------------------------------------------------------------

# Voce 18: un disco dietro un bridge USB con driver uas può bloccarsi e resettarsi
if has lsusb && lsusb -t 2>/dev/null | grep -q 'Driver=uas'; then
    if is_root; then
        # Il journal copre solo un periodo: un "nessun reset" vale da quella data in poi
        kernel_log=$(journalctl --no-pager -o short-iso _TRANSPORT=kernel 2>/dev/null)
        since=$(head -1 <<< "$kernel_log" | cut -c1-10)
        resets=$(grep -c 'uas_eh_device_reset_handler start' <<< "$kernel_log")
        if [[ "$resets" -eq 0 ]]; then report OK "voce 18" "disco USB con uas: nessun reset dal $since"
        else report ATTENZIONE "voce 18" "disco USB con uas: $resets reset dal $since"; fi
    else
        report SALTATO "voce 18" "serve sudo per leggere il journal del kernel"
    fi
else
    report SALTATO "voce 18" "nessun disco USB con driver uas"
fi

# Voce 19: senza watchdog un Pi bloccato resta bloccato finché qualcuno non lo stacca
watchdog=$(systemctl show -p RuntimeWatchdogUSec --value 2>/dev/null)
if [[ -n "$watchdog" && "$watchdog" != "0" && "$watchdog" != "infinity" ]]; then
    report OK "voce 19" "watchdog attivo ($watchdog)"
else
    report ATTENZIONE "voce 19" "watchdog non attivo: un blocco non si risolve da solo"
fi

# Voce 20: conta l'età dell'ultimo backup, non la sua esistenza; e se sta sullo stesso
# disco del sistema, un guasto del disco porta via dati e backup insieme
root_dev=$(df --output=source / | tail -1)
check_backups() {   # check_backups ETICHETTA CARTELLA SCHEMA GIORNI_MASSIMI
    local newest days
    newest=$(ls -t "$2"/$3 2>/dev/null | head -1)
    if [[ -z "$newest" ]]; then
        report ATTENZIONE "voce 20" "$1: nessun backup trovato"
        return
    fi
    days=$(age_days "$newest")
    if [[ "$days" -gt "$4" ]]; then report ATTENZIONE "voce 20" "$1: l'ultimo backup ha $days giorni"
    else report OK "voce 20" "$1: l'ultimo backup ha $days giorni"; fi
    [[ "$(df --output=source "$2" | tail -1)" == "$root_dev" ]] \
        && detail "sta sullo stesso disco del sistema: serve anche una copia altrove"
}

if [[ -z "$HA_CONFIG" ]]; then report SALTATO "voce 20" "Home Assistant non trovato"
elif ! is_root; then report SALTATO "voce 20" "serve sudo per leggere i backup di Home Assistant"
else check_backups "Home Assistant" "$HA_CONFIG/backups" '*.tar' 7; fi

if [[ -z "$IMMICH_CONTAINER" ]]; then
    report SALTATO "voce 20" "Immich non trovato"
else
    # La cartella delle foto è /data nelle versioni recenti e /usr/src/app/upload nelle
    # installazioni più vecchie; un container può averle entrambe, e una può essere vuota
    upload=""; any_mount=""
    for dest in /data /usr/src/app/upload; do
        src=$(mount_source "$IMMICH_CONTAINER" "$dest")
        [[ -n "$src" ]] && any_mount="$src"
        if [[ -n "$src" && -d "$src/backups" ]]; then upload="$src"; break; fi
    done
    if ! is_root; then report SALTATO "voce 20" "serve sudo per leggere i backup di Immich"
    elif [[ -z "$any_mount" ]]; then report SALTATO "voce 20" "cartella delle foto di Immich non trovata"
    elif [[ -z "$upload" ]]; then report ATTENZIONE "voce 20" "Immich non salva copie del database: attivale nelle impostazioni"
    else check_backups "Database di Immich" "$upload/backups" 'immich-db-backup-*.sql.gz' 3; fi
fi

echo
echo "Risultato: $ok OK, $warn da guardare, $skip saltati."
