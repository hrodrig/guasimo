# Design: Awesome README for guasimo

**Date:** 2026-08-01  
**Status:** approved (2026-08-01) — implemented in README  
**Scope:** rewrite `README.md` only (no install/script changes)  
**Language:** English (aligned with `docs/`)

## Decisions locked

| Topic | Choice |
|-------|--------|
| Audience | Mix: GitHub visitor first, then operator (landing corta) |
| Hero | Single real screenshot: `docs/assets/open-webui-lan-192-168-10-69.png` |
| Hardware photo | Real reference tower: `docs/assets/guasimo-workstation-tower.png` |
| Length | ~150–200 lines; deep detail stays in `docs/` / `SPECIFICATIONS.md` |
| Approach | Landing corta (not gghstats-clone, not runbook-first) |

## Goals

1. Visitor understands **what** guasimo is and **why** it exists within one viewport scroll.
2. Operator can install from README without reading the full docs tree first.
3. Authoritative contracts remain in SPEC/docs — README points, does not duplicate.
4. Honest metrics only (from current Status / validated runs). No invented stars, tok/s, or user counts.

## Non-goals

- New CI badges (no `.github/workflows` yet).
- New marketing site or Astro landing.
- Translating README to ES/DE/… (English only for now).
- Rewriting `docs/` content.

## Target section order

1. **Title + badges** (keep current badge row; Version pin stays `0.2.2` until next release)
2. **Repo / Releases** one-liner
3. **Hero image** — WebUI LAN screenshot with descriptive alt text
4. **One-liner + privacy pitch** (models stay on-box)
5. **Table of contents**
6. **Why guasimo** — 3–4 bullets (local, one-command path, OpenAI-compatible API, coding focus)
7. **Features** — short bullets (GPU detect + CUDA/CPU paths, systemd + nginx TLS, healthcheck, model pulls, benchmark)
8. **Prerequisites** — Ubuntu 26.04, NVIDIA preferred (CPU fallback), disk room for GGUF; link `docs/05-deployment.md` for CUDA apt pre-flight
9. **Quick start** — real clone URL `https://github.com/hrodrig/guasimo.git`; install → healthcheck → pull primary → bench → open `https://localhost/`
10. **Stack** — llama.cpp / Ollama / Open WebUI (one line each + swap-friendly note)
11. **Hardware target (compact)** — “Validated on …” summary + link `docs/02-hardware-decisions.md`; optional slim table (not full essay)
12. **Status** — one paragraph for **v0.2.2** (real validation dates/metrics already in README)
13. **Documentation** — links to SPEC, `docs/00-index.md`, roadmap, CHANGELOG
14. **Repository layout** — short tree (current content OK)
15. **Contributing** — short (issues/PRs welcome; English for docs)
16. **License** — MIT → `./LICENSE`

## Content rules

- Prefer fenced `bash` code blocks for commands (not indented-only blocks).
- Clone URL must be the real GitHub HTTPS URL (no `<this-repo>` placeholder).
- Hero path relative from repo root: `docs/assets/open-webui-lan-192-168-10-69.png`.
- Keep name expansion (Graphical Utility…) near top but after hero or under one-liner — do not bury the value prop under the acronym.
- Status must not grow into a changelog dump; point to `CHANGELOG.md` for history.
- Do not invent screenshots, tok/s, or hardware beyond what is already documented.

## Open items (none blocking)

- Optional later: root `assets/` hero copy (symlink or duplicate) for cleaner GitHub social preview — out of scope unless user asks.
- Optional later: CI badge when workflows exist.

## Acceptance

- [ ] README follows section order above
- [ ] Hero image renders on GitHub
- [ ] Quick start uses real clone URL and existing scripts
- [ ] No fabricated metrics
- [ ] Length roughly 150–200 lines
- [ ] Deep topics linked to `docs/` / SPEC

## Self-review

- Placeholders: none intentional (`<this-repo>` must be gone in implementation).
- Contradictions: badges say 0.2.2; Status must stay on v0.2.2 until release bump.
- Ambiguity: hardware table may be slim or “validated on” only — implementer picks slim table if it fits length budget.
- Scope: README.md only.
