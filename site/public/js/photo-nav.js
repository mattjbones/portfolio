// Directional photo navigation: swipe, keyboard, and link click handling.
// Uses View Transitions API when available, CSS class fallback otherwise.
//
// Cross-document View Transitions (via <meta name="view-transition">) only
// work reliably in Blink (Chrome/Edge). Safari has startViewTransition but
// not cross-document support, so we gate on the Navigation API as a proxy.

(function () {
  const hasVT   = 'startViewTransition' in document && 'navigation' in window;
  const carousel = document.querySelector('.photo-carousel');
  const hero    = document.querySelector('.photo-hero--current');
  const inDir   = sessionStorage.getItem('vtDir');

  const hasPrev = !!document.querySelector('.photo-hero--prev img');
  const hasNext = !!document.querySelector('.photo-hero--next img');
  const baseX   = -window.innerWidth;

  // ── Entry animation (non-VT path) ──────────────────────────────────────────
  if (!hasVT) {
    if (!inDir && hero) {
      // No direction (e.g. arrived from gallery) — plain fade in
      hero.classList.add('pn-in');
      hero.addEventListener('animationend', function cleanup() {
        hero.classList.remove('pn-in');
        hero.removeEventListener('animationend', cleanup);
      });
    }
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

  function navigate(dir, fromSwipe) {
    const url = dir === 'next' ? nextUrl : prevUrl;
    if (!url) return;

    sessionStorage.setItem('vtDir', dir);

    if (hasVT && !fromSwipe) {
      // Keyboard / click: use cross-document View Transition slide
      document.documentElement.dataset.vtDir = dir;
      location.href = url;
      return;
    }

    // Swipe / wheel / non-VT: slide the carousel strip then navigate.
    // VT is skipped here because its snapshot captures the page before JS
    // runs, so the carousel would be in the wrong position in the transition.
    if (carousel) {
      const targetX = dir === 'next'
        ? baseX - window.innerWidth
        : baseX + window.innerWidth;
      carousel.classList.add('pn-swipe-commit');
      carousel.style.transform = 'translateX(' + targetX + 'px)';
    }
    setTimeout(function () { location.href = url; }, 280);
  }

  // Wire prev/next link clicks to set direction
  if (prevEl) prevEl.addEventListener('click', function (e) { e.preventDefault(); navigate('prev'); });
  if (nextEl) nextEl.addEventListener('click', function (e) { e.preventDefault(); navigate('next'); });

  // ── Trackpad / wheel horizontal swipe ────────────────────────────────────
  if (carousel) {
    let wheelDx      = 0;
    let wheelTimer   = null;
    let wheelLocked  = null; // 'h' | 'v' | null
    let wheelActive  = false;

    function wheelCommitOrSnap() {
      wheelTimer  = null;
      wheelActive = false;
      wheelLocked = null;

      const dir = wheelDx < 0 ? 'next' : 'prev';
      const url = dir === 'next' ? nextUrl : prevUrl;
      const committed = url && Math.abs(wheelDx) >= window.innerWidth * 0.3;

      if (committed) {
        navigate(dir, true);
      } else {
        snapBack();
      }
      wheelDx = 0;
    }

    carousel.addEventListener('wheel', function (e) {
      // Determine axis on first event of a gesture
      if (wheelLocked === null) {
        if (Math.abs(e.deltaX) <= Math.abs(e.deltaY)) {
          wheelLocked = 'v';
        } else {
          wheelLocked = 'h';
        }
      }
      if (wheelLocked === 'v') return;

      e.preventDefault();

      if (!wheelActive) {
        wheelActive = true;
        carousel.classList.remove('pn-snap-back', 'pn-swipe-commit');
        carousel.style.transition = 'none';
      }

      wheelDx -= e.deltaX;

      // Block scrolling toward a missing neighbour
      const constrained =
        (wheelDx > 0 && !hasPrev) ? 0 :
        (wheelDx < 0 && !hasNext) ? 0 :
        wheelDx;

      carousel.style.transform = 'translateX(' + (baseX + constrained) + 'px)';

      // Debounce: commit/snap when wheel events stop
      clearTimeout(wheelTimer);
      wheelTimer = setTimeout(wheelCommitOrSnap, 80);
    }, { passive: false });
  }

  // ── Touch swipe — drag the carousel strip ─────────────────────────────────
  if (!carousel) return;

  let touchStartX = 0;
  let touchStartY = 0;
  let touchLastX  = 0;
  let touchLastT  = 0;
  let swipeLocked = null; // 'h' | 'v' | null
  let dragging    = false;

  function snapBack() {
    carousel.classList.add('pn-snap-back');
    carousel.style.transform = 'translateX(' + baseX + 'px)';
    carousel.addEventListener('transitionend', function cleanup() {
      carousel.classList.remove('pn-snap-back');
      carousel.removeEventListener('transitionend', cleanup);
    });
  }

  carousel.addEventListener('touchstart', function (e) {
    touchStartX = e.touches[0].clientX;
    touchStartY = e.touches[0].clientY;
    touchLastX  = touchStartX;
    touchLastT  = e.timeStamp;
    swipeLocked = null;
    dragging    = false;
    carousel.classList.remove('pn-snap-back');
    carousel.style.transition = 'none';
    carousel.style.transform  = 'translateX(' + baseX + 'px)';
  }, { passive: true });

  carousel.addEventListener('touchmove', function (e) {
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

      // Block dragging toward a missing neighbour
      const constrained =
        (dx > 0 && !hasPrev) ? 0 :
        (dx < 0 && !hasNext) ? 0 :
        dx;

      carousel.style.transform = 'translateX(' + (baseX + constrained) + 'px)';
    }
  }, { passive: false });

  carousel.addEventListener('touchend', function (e) {
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
      navigate(dir, true);
    } else {
      snapBack();
    }
  }, { passive: true });

  carousel.addEventListener('touchcancel', function () {
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
