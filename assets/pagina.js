// Mostra il file di docs/ scelto con ?doc=nome. DOC e GRUPPO vengono da sito.js
const articolo = document.getElementById('documento');

function mostraErrore(testo) {
    articolo.innerHTML = '<p class="avviso errore"><b>Errore:</b> </p>';
    articolo.firstChild.append(testo);
}

function idDaTitolo(testo) {
    // Le voci di Controlla ("17. Titolo") diventano #voce-17, così i rimandi restano corti
    const voce = testo.match(/^(\d+)\.\s/);
    if (voce) return 'voce-' + voce[1];
    return testo.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

// Nei file i collegamenti puntano ad altri .md e a ../cartella/file, così funzionano anche
// leggendo il repository su GitHub; sul sito diventano pagine e percorsi dalla radice
function sistemaCollegamenti() {
    for (const a of articolo.querySelectorAll('a[href]')) {
        a.classList.add('rimando');
        const href = a.getAttribute('href');
        if (/^[a-z]+:/i.test(href) || href.startsWith('#')) continue;
        const md = href.match(/^([\w-]+)\.md(#.*)?$/);
        if (md) {
            let ancora = md[2] || '';
            // "voce 17" nel testo, oppure solo "17", come nella tabella dello script
            const voce = a.textContent.match(/voce\s+(\d+)/i) || a.textContent.match(/^(\d+)$/);
            if (!ancora && md[1] === 'controlla' && voce) ancora = '#voce-' + voce[1];
            a.setAttribute('href', 'pagina.html?doc=' + md[1] + ancora);
        } else if (href.startsWith('../')) {
            a.setAttribute('href', href.slice(3));
        }
    }
}

async function carica() {
    if (!GRUPPO) {
        mostraErrore('pagina non trovata. Scegline una dalla mappa del sito.');
        return;
    }
    let testo;
    try {
        const risposta = await fetch('docs/' + DOC + '.md');
        if (!risposta.ok) throw new Error(risposta.status);
        testo = await risposta.text();
    } catch (errore) {
        mostraErrore('non riesco a caricare la pagina (' + errore.message + '). Riprova fra poco.');
        return;
    }
    if (typeof marked === 'undefined') {
        mostraErrore('non riesco a caricare il programma che impagina il testo. Riprova fra poco.');
        return;
    }

    articolo.innerHTML = marked.parse(testo);
    for (const h of articolo.querySelectorAll('h1, h2, h3')) h.id = idDaTitolo(h.textContent);
    sistemaCollegamenti();
    aggiungiSezioni(articolo.querySelectorAll('h2'));

    const titolo = articolo.querySelector('h1');
    if (titolo) document.title = titolo.textContent + ' - Il mio homelab';
    // i titoli hanno l'id solo ora: ripetere il salto all'ancora la fa trovare e accende :target
    if (location.hash) location.replace(location.hash);
}

// dopo sito.js, che sullo stesso evento costruisce la mappa
document.addEventListener('DOMContentLoaded', carica);
