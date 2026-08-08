# Supy Scanner — Marketing Website

A static, single-page marketing site for the `supy_scanner` SDK. Scanbot.io-style
layout, rebranded with a **purple** design system. No build step, no dependencies.

## Run

Just open `index.html` in a browser:

```bash
open supy-scanner-website/index.html
```

Or serve it (nicer for smooth-scroll / relative paths):

```bash
cd supy-scanner-website
python3 -m http.server 8080
# → http://localhost:8080
```

## Files

| File | Purpose |
|---|---|
| `index.html` | Page markup — hero, products, features, symbologies, use cases, code, platforms, CTA, footer |
| `styles.css` | Purple brand system + responsive layout, animated phone mockup |
| `script.js` | Sticky-nav shadow, mobile menu, scroll-reveal animations |

## Content source

Feature copy is drawn from the real library surface (`lib/supy_scanner.dart`,
`README.md`, `docs/SYMBOLOGIES.md`) — 13 barcode symbologies, document scanner +
on-device OCR, and the Single / Multiple / Find & Pick / Batch data-capture use cases.

Purely static presentation — nothing here calls the SDK or ships secrets.
