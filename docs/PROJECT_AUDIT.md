# Project audit (start of Phase 0)

Environment note: the working directory was empty at the start of this session. The previously delivered
coming-soon project was restored from its delivered archive (`codehackademy.zip`) plus the registration update files,
so this audit describes that delivered code. There was no existing Git repository, backend integration or env file.

## What existed (the coming-soon site)
- Next.js 16 App Router, React 19, TypeScript 6, Tailwind v4, npm. Single page `/`.
- Construction-site concept: hero, interactive warning sign, developer terminal, caution tape, Easter egg, manifesto, footer.
- Registration banner + live countdown + registration link (deadline 29 Nov 2026 23:59 WAT) and WhatsApp/LinkedIn links.
- Brand assets: original logo (kept untouched in `public/brand/`), trimmed `logo.png`, favicon, Apple icon, Open Graph image.
- Tokens: orange `#FD5000` (sampled from the logo), ink `#0A1114`, paper `#F7F5F0`; Archivo + JetBrains Mono, self-hosted.
- `config/site.ts` with a placeholder "developer contact".

## Preserved
Logo and icons, colour tokens, fonts, hard-offset "sticker" button style, registration banner/countdown/link (and the confirmed
registration data), SEO metadata approach, accessibility conventions (skip link, focus ring, reduced motion).

## Removed (temporary concept)
Construction sign, developer terminal, caution tape, Easter egg, "Developer at work" copy, developer-contact button, coming-soon pages.

## Missing at the start (now addressed or scheduled)
Four of the five repositories, shared design system, Supabase project structure, auth, roles, RLS, audit log, admin and student apps,
the public interest form backend, CI. See `SPEC_CHECKLIST.md`.
