// Directional photo navigation: swipe, keyboard, and link click handling.
// Uses View Transitions API when available, plain navigation otherwise.
//
// Cross-document View Transitions only work reliably in Blink (Chrome/Edge).
// We gate on the Navigation API as a proxy for full cross-document VT support.

(function () {
  const hasVT = 'startViewTransition' in document && 'navigation' in window;
  const hero  = document.querySelector('.photo-hero--current');
  const inDir = sessionStorage.getItem('vtDir');

  const hasPrev = !!document.querySelector('.photo-pager-link.prev');
  const hasNext = !!document.querySelector('.photo-pager-link.next');

  // ── Entry animation (non-VT path) ──────────────────────────────────────────
  if (!hasVT && !inDir && hero) {
    hero.classList.add('pn-in');
    hero.addEventListener('animationend', function cleanup() {
      hero.classList.remove('pn-in');
      hero.removeEventListener('animationend', cleanup);
    });
  } else if (hasVT && inDir) {
    document.documentElement.dataset.vtDir = inDir;
  }

  if (inDir) sessionStorage.removeItem('vtDir');

  // ── Navigation helpers ─────────────────────────────────────────────────────
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
    location.href = url;
  }

  if (prevEl) prevEl.addEventListener('click', function (e) { e.preventDefault(); navigate('prev'); });
  if (nextEl) nextEl.addEventListener('click', function (e) { e.preventDefault(); navigate('next'); });

  if (!hero) return;

  // ── Shared snap-back ───────────────────────────────────────────────────────
  function snapBack() {
    hero.classList.add('pn-snap-back');
    hero.style.transform = '';
    hero.addEventListener('transitionend', function cleanup() {
      hero.classList.remove('pn-snap-back');
      hero.style.transform = '';
      hero.removeEventListener('transitionend', cleanup);
    });
  }

  // ── Trackpad / wheel horizontal swipe ─────────────────────────────────────
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
      if (url && Math.abs(wheelDx) >= window.innerWidth * 0.3) {
        navigate(dir);
      }
      wheelDx     = 0;
      wheelLocked = null;
    }, 80);
  }, { passive: false });

  // ── Touch swipe — drag the hero for visual feedback ───────────────────────
  let touchStartX = 0;
  let touchStartY = 0;
  let touchLastX  = 0;
  let touchLastT  = 0;
  let swipeLocked = null;
  let dragging    = false;

  hero.addEventListener('touchstart', function (e) {
    touchStartX = e.touches[0].clientX;
    touchStartY = e.touches[0].clientY;
    touchLastX  = touchStartX;
    touchLastT  = e.timeStamp;
    swipeLocked = null;
    dragging    = false;
    hero.classList.remove('pn-snap-back');
    hero.style.transition = 'none';
    hero.style.transform  = '';
  }, { passive: true });

  hero.addEventListener('touchmove', function (e) {
    if (swipeLocked === 'v') return;
    const dx = e.touches[0].clientX - touchStartX;
    const dy = e.touches[0].clientY - touchStartY;
    if (swipeLocked === null) {
      if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
      swipeLocked = Math.abs(dx) > Math.abs(dy) ? 'h' : 'v';
    }
    if (swipeLocked === 'h') {
      e.preventDefault();
      dragging   = true;
      touchLastX = e.touches[0].clientX;
      touchLastT = e.timeStamp;

      // Dampen drag toward a missing neighbour; 40% follow for normal direction
      const constrained =
        (dx > 0 && !hasPrev) ? dx * 0.1 :
        (dx < 0 && !hasNext) ? dx * 0.1 :
        dx * 0.4;

      hero.style.transform = 'translateX(' + constrained + 'px)';
    }
  }, { passive: false });

  hero.addEventListener('touchend', function (e) {
    if (!dragging) return;
    dragging = false;

    const dx       = e.changedTouches[0].clientX - touchStartX;
    const dt       = e.timeStamp - touchLastT;
    const velocity = dt > 0 ? Math.abs(e.changedTouches[0].clientX - touchLastX) / dt : 0;
    const dir      = dx < 0 ? 'next' : 'prev';
    const url      = dir === 'next' ? nextUrl : prevUrl;

    const committed = url && (
      Math.abs(dx) >= window.innerWidth * 0.3 ||
      velocity >= 0.3
    );

    if (committed) {
      navigate(dir);
    } else {
      snapBack();
    }
  }, { passive: true });

  hero.addEventListener('touchcancel', function () {
    if (!dragging) return;
    dragging = false;
    snapBack();
  }, { passive: true });

  // ── Keyboard arrows ────────────────────────────────────────────────────────
  addEventListener('keydown', function (e) {
    if (e.key === 'ArrowRight') navigate('next');
    if (e.key === 'ArrowLeft')  navigate('prev');
  });
})();
