// Supy Scanner site — nav state, mobile menu, scroll reveals

const nav = document.getElementById('nav');
const burger = document.getElementById('burger');
const links = document.querySelector('.nav__links');

const toTop = document.getElementById('toTop');

// shadow on scroll + back-to-top visibility
const onScroll = () => {
  nav.classList.toggle('is-stuck', window.scrollY > 8);
  toTop?.classList.toggle('is-show', window.scrollY > 600);
};
onScroll();
window.addEventListener('scroll', onScroll, { passive: true });

toTop?.addEventListener('click', () =>
  window.scrollTo({ top: 0, behavior: 'smooth' })
);

// mobile menu
burger?.addEventListener('click', () => {
  const open = links.classList.toggle('is-open');
  burger.classList.toggle('is-open', open);
  burger.setAttribute('aria-expanded', String(open));
});
links?.querySelectorAll('a').forEach((a) =>
  a.addEventListener('click', () => {
    links.classList.remove('is-open');
    burger.classList.remove('is-open');
    burger.setAttribute('aria-expanded', 'false');
  })
);

// scroll reveal
const revealTargets = document.querySelectorAll(
  '.product-card, .feature, .usecase, .platform, .stat, .chip, .code-split__copy, .code-window, .section__head, .step, .faq__item, .compare'
);
revealTargets.forEach((el) => el.classList.add('reveal'));

const io = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry, i) => {
      if (entry.isIntersecting) {
        setTimeout(() => entry.target.classList.add('is-in'), (i % 6) * 55);
        io.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.12, rootMargin: '0px 0px -40px 0px' }
);
revealTargets.forEach((el) => io.observe(el));

// count-up stats — animate numbers when they scroll into view
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const counters = document.querySelectorAll('.stat .num[data-count]');

if (!reduceMotion && counters.length && 'IntersectionObserver' in window) {
  const runCount = (el) => {
    const target = Number(el.getAttribute('data-count')) || 0;
    const dur = 1300;
    const start = performance.now();
    const tick = (now) => {
      const p = Math.min((now - start) / dur, 1);
      const eased = 1 - Math.pow(1 - p, 3); // easeOutCubic
      el.textContent = String(Math.round(target * eased));
      if (p < 1) requestAnimationFrame(tick);
      else el.textContent = String(target);
    };
    requestAnimationFrame(tick);
  };
  const countIo = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          runCount(entry.target);
          countIo.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.5 }
  );
  counters.forEach((el) => {
    el.textContent = '0';
    countIo.observe(el);
  });
}

// rotating hero word — cycle Barcode → Document → Data Capture
const rotWords = Array.from(document.querySelectorAll('.rotator__word'));
if (!reduceMotion && rotWords.length > 1) {
  let cur = 0;
  setInterval(() => {
    const now = rotWords[cur];
    const next = rotWords[(cur + 1) % rotWords.length];
    now.classList.remove('is-active');
    now.classList.add('is-out');
    next.classList.remove('is-out');
    next.classList.add('is-active');
    // clear the outgoing state once it has slid away
    setTimeout(() => now.classList.remove('is-out'), 600);
    cur = (cur + 1) % rotWords.length;
  }, 2400);
}

// document scanner demo — cycle detect → capture → crop → OCR, syncing the steps
const docScanner = document.getElementById('docScanner');
const scanSteps = Array.from(document.querySelectorAll('#scanSteps .scan-step'));
if (docScanner && scanSteps.length) {
  const STAGES = scanSteps.length; // 4
  const applyStage = (s) => {
    docScanner.setAttribute('data-stage', String(s));
    scanSteps.forEach((el, i) => el.classList.toggle('is-active', i === s));
  };
  if (reduceMotion) {
    applyStage(STAGES - 1); // show the finished, captured state statically
  } else {
    let stage = 0;
    applyStage(0);
    setInterval(() => {
      stage = (stage + 1) % STAGES;
      applyStage(stage);
    }, 1700);
  }
}

// ---------- advanced motion (all pointer/scroll driven; skipped under reduced-motion) ----------

// reading-progress bar — how far down the page you are
const progress = document.getElementById('scrollProgress');
if (progress && !reduceMotion) {
  let progQueued = false;
  const updateProgress = () => {
    progQueued = false;
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const p = max > 0 ? Math.min(window.scrollY / max, 1) : 0;
    progress.style.setProperty('--p', String(p));
  };
  updateProgress();
  window.addEventListener(
    'scroll',
    () => {
      if (!progQueued) {
        progQueued = true;
        requestAnimationFrame(updateProgress);
      }
    },
    { passive: true }
  );
}

// hero pointer parallax — nudge the aurora blobs, phone and float-cards toward the cursor
const parallaxEls = Array.from(document.querySelectorAll('[data-parallax]'));
if (parallaxEls.length && !reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  const hero = document.getElementById('hero') || document.body;
  let px = 0.5, py = 0.5, pQueued = false;
  const applyParallax = () => {
    pQueued = false;
    const dx = (px - 0.5) * 2; // -1 .. 1
    const dy = (py - 0.5) * 2;
    parallaxEls.forEach((el) => {
      const f = parseFloat(el.getAttribute('data-parallax')) || 0;
      el.style.setProperty('--px', (dx * f * 34).toFixed(2) + 'px');
      el.style.setProperty('--py', (dy * f * 34).toFixed(2) + 'px');
    });
  };
  hero.addEventListener(
    'mousemove',
    (e) => {
      px = e.clientX / window.innerWidth;
      py = e.clientY / window.innerHeight;
      if (!pQueued) {
        pQueued = true;
        requestAnimationFrame(applyParallax);
      }
    },
    { passive: true }
  );
  hero.addEventListener('mouseleave', () => {
    parallaxEls.forEach((el) => {
      el.style.setProperty('--px', '0px');
      el.style.setProperty('--py', '0px');
    });
  });
}

// 3D tilt — the hero phone (writes CSS vars its float keyframe composes) and the content cards
if (!reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  const tiltFromEvent = (el, e, max) => {
    const r = el.getBoundingClientRect();
    const cx = (e.clientX - r.left) / r.width - 0.5; // -0.5 .. 0.5
    const cy = (e.clientY - r.top) / r.height - 0.5;
    return { ry: (cx * max).toFixed(2), rx: (-cy * max).toFixed(2) };
  };

  const phone = document.querySelector('.phone[data-parallax-tilt]');
  if (phone) {
    phone.addEventListener('mousemove', (e) => {
      const { rx, ry } = tiltFromEvent(phone, e, 12);
      phone.style.setProperty('--rx', rx + 'deg');
      phone.style.setProperty('--ry', ry + 'deg');
    });
    phone.addEventListener('mouseleave', () => {
      phone.style.setProperty('--rx', '0deg');
      phone.style.setProperty('--ry', '0deg');
    });
  }

  const tiltCards = document.querySelectorAll('.product-card, .price-card, .platform, .usecase');
  tiltCards.forEach((card) => {
    let raf = 0, last = null;
    card.addEventListener('mouseenter', () => card.classList.add('is-tilting'));
    card.addEventListener('mousemove', (e) => {
      last = e;
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const { rx, ry } = tiltFromEvent(card, last, 7);
        card.style.transform = `perspective(720px) rotateX(${rx}deg) rotateY(${ry}deg) translateY(-4px)`;
      });
    });
    card.addEventListener('mouseleave', () => {
      if (raf) { cancelAnimationFrame(raf); raf = 0; }
      card.classList.remove('is-tilting');
      card.style.transform = '';
    });
  });
}

// magnetic buttons — the primary CTAs lean toward the cursor as it approaches
if (!reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  document.querySelectorAll('.btn--primary, .btn--light').forEach((btn) => {
    btn.addEventListener('mousemove', (e) => {
      const r = btn.getBoundingClientRect();
      const x = (e.clientX - r.left - r.width / 2) * 0.3;
      const y = (e.clientY - r.top - r.height / 2) * 0.3;
      btn.style.transform = `translate(${x.toFixed(1)}px, ${(y - 2).toFixed(1)}px)`;
    });
    btn.addEventListener('mouseleave', () => {
      btn.style.transform = '';
    });
  });
}

// scrollspy — highlight the nav link of the section in view
const navLinks = Array.from(document.querySelectorAll('.nav__links a'));
const sections = navLinks
  .map((a) => document.querySelector(a.getAttribute('href')))
  .filter(Boolean);

const spy = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        const id = '#' + entry.target.id;
        navLinks.forEach((a) =>
          a.classList.toggle('is-active', a.getAttribute('href') === id)
        );
      }
    });
  },
  { rootMargin: '-45% 0px -50% 0px' }
);
sections.forEach((s) => spy.observe(s));

// ---------- checkout ----------
// Backend base URL. Point this at your deployed supy-licensing-backend.
// Override at runtime with `window.SUPY_CHECKOUT_API` before this script loads.
const CHECKOUT_API = window.SUPY_CHECKOUT_API || 'http://localhost:8080';

const checkoutStatus = document.getElementById('checkout-status');
function setCheckoutStatus(msg, isError) {
  if (!checkoutStatus) return;
  checkoutStatus.textContent = msg;
  checkoutStatus.classList.toggle('is-error', Boolean(isError));
}

document.querySelectorAll('[data-checkout-tier]').forEach((btn) => {
  btn.addEventListener('click', async () => {
    const tier = btn.getAttribute('data-checkout-tier');
    btn.disabled = true;
    setCheckoutStatus('Starting secure checkout…', false);
    try {
      const res = await fetch(CHECKOUT_API + '/checkout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tier }),
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.url) {
        window.location.href = data.url; // hand off to Stripe Checkout
        return;
      }
      if (res.status === 501) {
        setCheckoutStatus('Checkout isn’t live yet — email sales@supy.io to get set up.', true);
      } else {
        setCheckoutStatus(data.error ? 'Checkout error: ' + data.error : 'Checkout is temporarily unavailable.', true);
      }
    } catch (_) {
      setCheckoutStatus('Could not reach the checkout service. Try again shortly.', true);
    } finally {
      btn.disabled = false;
    }
  });
});
