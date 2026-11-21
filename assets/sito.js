// Guscio comune alle due pagine: tema, mappa del sito, briciole. Si carica nella <head> senza
// defer, cosi' il tema scelto vale prima che la pagina si disegni.

// Le pagine di docs/, per gruppo: mappa, briciole e i soli nomi che pagina.html accetta
const GRUPPI = [
    { nome: 'Cosa uso', pagine: { servizi: 'Servizi', hardware: 'Hardware', decisioni: 'Decisioni' } },
    { nome: 'Come funziona', pagine: { dns: 'DNS', 'home-assistant': 'Home Assistant', immich: 'Immich' } },
    { nome: 'Tenerlo in salute', pagine: { controlla: 'Controlla il tuo homelab',
        diagnostica: 'Lo script di controllo', gestione: 'Gestione' } },
];
const CHIAVE_TEMA = 'raspi-homelab/tema';

// La pagina di docs/ richiesta con ?doc=nome, se e' nell'elenco: un nome libero farebbe caricare
// a pagina.html un file qualsiasi. hasOwn, perche' "in" accetterebbe anche "toString"
const DOC = new URLSearchParams(location.search).get('doc');
const GRUPPO = GRUPPI.find(g => Object.hasOwn(g.pagine, DOC));

// Tema: segue il sistema finche' non si sceglie, poi la scelta resta salvata
let temaScelto = null;
try { temaScelto = localStorage.getItem(CHIAVE_TEMA); } catch (e) { /* archivio non disponibile */ }
if (temaScelto) document.documentElement.dataset.tema = temaScelto;
const scuro = () => (temaScelto || (matchMedia('(prefers-color-scheme: dark)').matches ? 'scuro' : 'chiaro')) === 'scuro';

function aggiornaTema() {
    const pulsante = document.getElementById('tema');
    pulsante.querySelector('.et').textContent = scuro() ? 'Chiaro' : 'Scuro';
    pulsante.setAttribute('aria-label', 'Passa al tema ' + (scuro() ? 'chiaro' : 'scuro'));
}

function costruisciMappa() {
    const mappa = document.getElementById('mappa');
    mappa.innerHTML = '<h2>Mappa del sito</h2><ul><li><a href="./" data-doc="">Home</a></li>'
        + GRUPPI.map(g => `<li><details${g === GRUPPO ? ' open' : ''}><summary>${g.nome}</summary><ul>`
            + Object.entries(g.pagine).map(([nome, titolo]) =>
                `<li><a href="pagina.html?doc=${nome}" data-doc="${nome}">${titolo}</a></li>`).join('')
            + '</ul></details></li>').join('') + '</ul>';
    // nessun "sei qui" su pagina.html con un nome sconosciuto
    const corrente = GRUPPO ? DOC : document.getElementById('documento') ? null : '';
    mappa.querySelector(`[data-doc="${corrente}"]`)?.setAttribute('aria-current', 'page');
    // sul telefono la mappa e' un foglio: un clic su una voce la chiude
    mappa.addEventListener('click', e => { if (e.target.closest('a')) chiudiMappa(); });
}

// Le sezioni della pagina corrente, sotto la sua voce: sul telefono la mappa fa da indice
function aggiungiSezioni(titoli) {
    const qui = document.querySelector('#mappa [aria-current]');
    if (!qui || !titoli.length) return;
    const ul = document.createElement('ul');
    for (const h of titoli) {
        const a = document.createElement('a');
        a.href = '#' + h.id;
        a.textContent = h.textContent;
        ul.append(document.createElement('li'));
        ul.lastChild.append(a);
    }
    qui.after(ul);
}

function chiudiMappa() {
    document.body.classList.remove('mappa-aperta');
    document.getElementById('apri-mappa').textContent = 'Mappa';
}

document.addEventListener('DOMContentLoaded', () => {
    costruisciMappa();
    if (GRUPPO) document.querySelector('.briciole').innerHTML =
        `<a href="./">Home</a> › ${GRUPPO.nome} › ${GRUPPO.pagine[DOC]}`;

    document.getElementById('apri-mappa').addEventListener('click', e => {
        e.target.textContent = document.body.classList.toggle('mappa-aperta') ? 'Chiudi' : 'Mappa';
    });
    document.getElementById('tema').addEventListener('click', () => {
        temaScelto = scuro() ? 'chiaro' : 'scuro';
        document.documentElement.dataset.tema = temaScelto;
        try { localStorage.setItem(CHIAVE_TEMA, temaScelto); } catch (e) { /* come sopra */ }
        aggiornaTema();
    });
    aggiornaTema();
});
