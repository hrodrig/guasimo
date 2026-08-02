# Awesome README Implementation Plan

> **For agentic workers:** Implement task-by-task. Steps use checkbox syntax.

**Goal:** Rewrite `README.md` as a landing-corta awesome README per the approved design spec.

**Architecture:** Single-file Markdown rewrite; reuse existing docs assets; add reference workstation photo; deep content stays linked in `docs/`.

**Tech Stack:** Markdown, GitHub-flavored README, existing `docs/assets/` PNGs.

## Global Constraints

- English only; no fabricated metrics
- Hero: `docs/assets/open-webui-lan-192-168-10-69.png`
- Hardware photo (real box): `docs/assets/guasimo-workstation-tower.png`
- Clone URL: `https://github.com/hrodrig/guasimo.git`
- Version badges stay `0.2.2`
- Length ~150–200 lines
- REQUIRED reading: `docs/superpowers/specs/2026-08-01-readme-awesome-design.md`

---

## Task 1: Assets + README rewrite

**Files:**
- Create: `docs/assets/guasimo-workstation-tower.png` (reference tower photo)
- Modify: `README.md`
- Modify: design spec status → approved

- [ ] Confirm tower PNG in `docs/assets/`
- [ ] Rewrite README to section order in design spec
- [ ] Hardware section: slim table + tower photo + “validated on this box”
- [ ] Quick start uses real clone URL and fenced `bash` blocks
- [ ] `wc -l README.md` in ~150–200 range
- [ ] Commit (message approval if required by repo rules)
