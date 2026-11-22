// Écran de lancement commun à tous les jeux :
// « Jouer dans le navigateur » ou « Installer sur le téléphone ».
// Il n'apparaît pas quand le jeu est déjà ouvert comme appli installée.
(function () {
  var standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  var deferredPrompt = null;
  var ua = navigator.userAgent;
  var isIOS = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  var isAndroid = /Android/i.test(ua);
  var isMobile = isIOS || isAndroid;

  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    deferredPrompt = e;
  });

  if (standalone) return;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text) n.textContent = text;
    return n;
  }

  function build() {
    var overlay = el('div', 'gl-overlay');
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    var card = el('div', 'gl-card');
    overlay.appendChild(card);

    var iconLink = document.querySelector('link[rel="apple-touch-icon"]') || document.querySelector('link[rel="icon"]');
    if (iconLink) {
      var img = el('img', 'gl-icon');
      img.src = iconLink.href;
      img.alt = '';
      card.appendChild(img);
    }
    card.appendChild(el('h1', 'gl-title', document.title));
    card.appendChild(el('p', 'gl-text', 'Comment veux-tu jouer ?'));

    var play = el('button', 'gl-btn gl-main', '▶  Jouer dans le navigateur');
    var install = el('button', 'gl-btn', isMobile ? '📲  Installer sur le téléphone' : '📲  Installer comme une appli');
    var steps = el('div', 'gl-steps');
    steps.hidden = true;
    card.appendChild(play);
    card.appendChild(install);
    card.appendChild(steps);
    document.body.appendChild(overlay);

    play.addEventListener('click', function () {
      overlay.remove();
      var canvas = document.getElementById('canvas');
      if (canvas) canvas.focus();
    });

    install.addEventListener('click', function () {
      if (deferredPrompt) {
        deferredPrompt.prompt();
        deferredPrompt.userChoice.then(function (choice) {
          deferredPrompt = null;
          if (choice.outcome === 'accepted') {
            steps.hidden = false;
            steps.textContent = "C'est installé ! Tu trouveras le jeu sur ton écran d'accueil.";
          }
        });
        return;
      }
      steps.hidden = false;
      steps.innerHTML = '';
      var list = el('ol');
      var items;
      if (isIOS) {
        items = ['Ouvre cette page dans Safari.', 'Appuie sur le bouton Partager (carré avec une flèche).', "Choisis « Sur l'écran d'accueil »."];
      } else if (isAndroid) {
        items = ['Ouvre cette page dans Chrome.', 'Appuie sur le menu ⋮ en haut à droite.', "Choisis « Installer l'application » ou « Ajouter à l'écran d'accueil »."];
      } else {
        items = ["Dans Chrome ou Edge, clique sur l'icône d'installation à droite de la barre d'adresse.", 'Ou ouvre cette page sur ton téléphone pour l’installer dessus.'];
      }
      items.forEach(function (t) { list.appendChild(el('li', null, t)); });
      steps.appendChild(list);
    });

    window.addEventListener('appinstalled', function () {
      steps.hidden = false;
      steps.textContent = "C'est installé ! Tu trouveras le jeu sur ton écran d'accueil.";
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', build);
  } else {
    build();
  }
})();
