// Mostra un file di docs/ scelto con ?doc=nome. Solo i nomi dell'elenco: un parametro libero
// permetterebbe di far caricare alla pagina un file qualsiasi.
const DOCUMENTI = ['controlla', 'servizi', 'hardware', 'decisioni', 'dns', 'home-assistant',
    'immich', 'gestione', 'diagnostica'];

const articolo = document.getElementById('documento');

function mostraErrore(testo) {
    articolo.innerHTML = '';
    const p = document.createElement('p');
    p.className = 'errore';
    p.textContent = testo;
    articolo.append(p);
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
    const nome = new URLSearchParams(location.search).get('doc');
    if (!DOCUMENTI.includes(nome)) {
        mostraErrore('Pagina non trovata. Torna all\'elenco e scegline una.');
        return;
    }
    let testo;
    try {
        const risposta = await fetch('docs/' + nome + '.md');
        if (!risposta.ok) throw new Error(risposta.status);
        testo = await risposta.text();
    } catch (errore) {
        mostraErrore('Non riesco a caricare la pagina (' + errore.message + '). Riprova fra poco.');
        return;
    }
    if (typeof marked === 'undefined') {
        mostraErrore('Non riesco a caricare il programma che impagina il testo. Riprova fra poco.');
        return;
    }

    articolo.innerHTML = marked.parse(testo);
    for (const h of articolo.querySelectorAll('h1, h2, h3')) h.id = idDaTitolo(h.textContent);
    sistemaCollegamenti();

    const titolo = articolo.querySelector('h1');
    if (titolo) document.title = titolo.textContent + ' - Il mio homelab';
    if (location.hash) document.getElementById(location.hash.slice(1))?.scrollIntoView();
}

carica();
