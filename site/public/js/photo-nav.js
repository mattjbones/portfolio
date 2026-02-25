// Directional photo navigation: scroll-snap carousel, keyboard, and link click handling.
// Uses View Transitions API when available, plain navigation otherwise.
//
// Cross-document View Transitions only work reliably in Blink (Chrome/Edge).
// We gate on the Navigation API as a proxy for full cross-document VT support.
//
// On touch/mobile: a 3-panel scroll-snap strip (prev | current | next) provides
// native momentum scrolling. After the strip snaps to a neighbour panel we fire
// location.href to commit the navigation. The scroll IS the visual transition, so
// the entry animation is suppressed on arrival (vtScrolled flag).
//
// On desktop: strip overflow is hidden (CSS); wheel + keyboard use VT as before.

(function () {
  const hasVT       = 'startViewTransition' in document && 'navigation' in window;
  const hero        = document.querySelector('.photo-hero--current');
  const inDir       = sessionStorage.getItem('vtDir');
  const wasScrolled = sessionStorage.getItem('vtScrolled') === '1';

  sessionStorage.removeItem('vtScrolled');
  if (inDir) sessionStorage.removeItem('vtDir');

  // ── Entry animation (non-VT / non-scroll path) ─────────────────────────
  if (!wasScrolled) {
    if (!hasVT && !inDir && hero) {
      hero.classList.add('pn-in');
      hero.addEventListener('animationend', function cleanup() {
        hero.classList.remove('pn-in');
        hero.removeEventListener('animationend', cleanup);
      });
    } else if (hasVT && inDir) {
      document.documentElement.dataset.vtDir = inDir;
    }
  }

  // ── Navigation helpers ──────────────────────────────────────────────────
  const prevEl  = document.querySelector('.photo-pager-link.prev');
  const nextEl  = document.querySelector('.photo-pager-link.next');
  const prevUrl = prevEl?.href;
  const nextUrl = nextEl?.href;

  if (!prevUrl && !nextUrl) return;

  function navigate(dir) {
    const url = dir === 'next' ? nextUrl : prevUrl;
    if (!url) return;
    sessionStorage.setItem('vtDir', dir);
    if (hasVT) document.documentElement.dataset.vtDir = dir;
    location.replace(url);
  }

  function navigateFromScroll(url) {
    // Scroll was the visual transition — skip entry animation on arrival
    sessionStorage.setItem('vtScrolled', '1');
    location.replace(url);
  }

  if (prevEl) prevEl.addEventListener('click', function (e) { e.preventDefault(); navigate('prev'); });
  if (nextEl) nextEl.addEventListener('click', function (e) { e.preventDefault(); navigate('next'); });

  // ── Scroll-strip initialisation & navigation ────────────────────────────
  const strip = document.getElementById('photo-strip');
  if (strip) {
    const panels     = [...strip.children];
    const currentIdx = panels.findIndex(function (p) { return p.classList.contains('photo-hero--current'); });

    // Jump instantly to the current panel (the prev panel sits to its left)
    if (currentIdx > 0) {
      requestAnimationFrame(function () {
        strip.scrollTo({ left: currentIdx * strip.clientWidth, behavior: 'instant' });
      });
    }

    let scrollTimer = null;
    let navigating  = false;
    let initDone    = false;

    // Allow 2 frames for the initial programmatic scroll to settle before
    // treating scroll events as user intent.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { initDone = true; });
    });

    function onScrollEnd() {
      if (!initDone || navigating) return;
      const idx = Math.round(strip.scrollLeft / strip.clientWidth);
      if (idx === currentIdx) return;
      navigating = true;
      var url = panels[idx] && panels[idx].dataset && panels[idx].dataset.url;
      if (url) navigateFromScroll(url);
    }

    // scrollend fires natively on Chrome 114+.
    // Debounce fallback covers iOS Safari which lacks scrollend.
    strip.addEventListener('scroll', function () {
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(onScrollEnd, 120);
    }, { passive: true });

    if ('onscrollend' in window) {
      strip.addEventListener('scrollend', onScrollEnd, { passive: true });
    }
  }

  if (!hero) return;

  // ── Trackpad / wheel horizontal swipe (desktop) ────────────────────────
  let wheelDx     = 0;
  let wheelTimer  = null;
  let wheelLocked = null;

  window.addEventListener('wheel', function (e) {
    clearTimeout(wheelTimer);
    if (wheelLocked === null) {
      wheelLocked = Math.abs(e.deltaX) <= Math.abs(e.deltaY) ? 'v' : 'h';
    }
    if (wheelLocked === 'v') {
      wheelTimer = setTimeout(function () { wheelLocked = null; }, 80);
      return;
    }
    e.preventDefault();
    wheelDx -= e.deltaX;
    wheelTimer = setTimeout(function () {
      const dir = wheelDx < 0 ? 'next' : 'prev';
      const url = dir === 'next' ? nextUrl : prevUrl;
      if (url && Math.abs(wheelDx) >= window.innerWidth * 0.3) navigate(dir);
      wheelDx     = 0;
      wheelLocked = null;
    }, 80);
  }, { passive: false });

  // ── Keyboard arrows ─────────────────────────────────────────────────────
  addEventListener('keydown', function (e) {
    if (e.key === 'ArrowRight') navigate('next');
    if (e.key === 'ArrowLeft')  navigate('prev');
  });
})();
