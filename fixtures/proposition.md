# Round-1 research proposition

## Chosen question

**CRISPR off-target prediction, 2022–2026: which computational methods have an independent reproduction (not only the authors’ own split), and on which public benchmarks?**

Chinese working title: CRISPR 脱靶预测方法的可复现对比（2022–2026）。

## Why this one

The suite is search → own-library evidence → write → keep numbers/citations honest → (optional) a science loop. A good first proposition has to hit those layers without needing a private Zotero library or an Overleaf login on day one.

This question does that:

- Dense, checkable literature (Cas-OFFinder, DeepCRISPR, CRISPR-Net, GUIDE-seq / CHANGE-seq sets). If the agent invents a DOI, we will see it.
- `dsh-science` is bio-oriented; this is actually in its wheelhouse, unlike a generic “LLM agents” topic.
- `writing-guard` has something concrete to audit: claimed AUROC, dataset names, year.
- Round-1 deliverable can stay Markdown. Overleaf is a later round.
- Zotero is skippable until we attach a host library; round 1 treats the session notes as the evidence store.

Rejected alternatives:

| Candidate | Why not first |
| --- | --- |
| LLM citation hallucination mitigations | Perfect for writing-guard, weak for `dsh-science` |
| Tool-using agents for literature review | Too close to this product; circular demo |
| Protein LMs for variant effect | Too big for one sandbox session |

## Round-1 protocol (sandbox)

Install gate (no model):

1. Smoke each of the five plugins on a fresh `$DSH_HOME`.
2. Stack all five on one profile; keep dump-config.

Agent gate (needs keys, later):

Workspace seed: this file plus an empty `notes/evidence.md`.

Prompt (headless, `low` reasoning, one short turn):

> Search public literature for computational CRISPR off-target predictors published 2022–2026. Return a table of at most 8 methods: name, paper (title + DOI), year, benchmark dataset, claimed metric, and whether an independent reproduction is cited. Do not fetch full-text PDFs. Every numeric claim must have a DOI. If a field is unknown, write "unknown" — do not guess.

Pass if:

- `dsh-ai4scholar` tools actually ran (not a bare web search).
- At least 5 rows have real DOIs we can resolve.
- `writing-guard` flags or the draft contains zero unsourced numbers.
- `dsh-zotero` / `dsh-overleaf` are allowed to no-op with a clear “not configured” rather than a crash.

## Out of scope this round

- Host Zotero HTTP API
- OverleafMCP credentials
- Full-text PDF reads (token + ai4scholar credit burn)
- Wet-lab or running predictor code
