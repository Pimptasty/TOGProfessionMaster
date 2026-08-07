<!-- markdownlint-disable MD049 MD050 -->
<!-- Audit files quote both sides verbatim and are append-only, so emphasis style is not the
     reviewer's to normalise. Every other rule still applies. -->
# Peer review — TOGProfessionMaster

Peer-review findings for **TOGProfessionMaster**.

**This is the INVERSE of a harness contract.** A contract is raised by this addon and answered by
the harness, in the harness repo (`WoWAPITesting/docs/contracts/TOGProfessionMaster.md`, staged here
as [`Tests/HARNESS_CONTRACT.md`](../Tests/HARNESS_CONTRACT.md)). An audit is raised by a **review
session** and answered by **this addon**, here in this repo. Same append-only conversation, roles
swapped. The protocol is in the harness's `HARNESS_CONTRACT.md`, and the method for producing
findings is in its `docs/REVIEW.md`.

**A review session writes its findings directly into this file, and this file ONLY.** It is the one
thing a harness session touches in this repo — it will not edit `CLAUDE.md`, the docs index or
`.pkgmeta`, and it will not commit here. Wiring the pointers, re-arming the watcher and committing
are ours. Our job in this file is to **answer** the findings.

**This file is APPEND-ONLY, both directions.** Neither side edits, re-titles, re-orders or moves
what the other wrote. A finding that has been fixed is **answered in place**, never deleted.

**Do not add a `Fixed` / `Resolved` section and move findings into it.** That is the most natural
thing to reach for and it defeats the whole design: a finding's value is its failure scenario
sitting next to the code it describes, and moving it is a slower form of deleting it. A fixed
finding stays exactly where it is, with a response block under it, and its row in the Status table
flips to FIXED. The Status table is the only place state is tracked.

**A finding whose fix belongs in the harness does not go here** — that is a contract, and it goes to
[`Tests/HARNESS_CONTRACT.md`](../Tests/HARNESS_CONTRACT.md) instead. Keep the two files honest about
which side owns the fix.

## Status

A view, not a record — this is the one part of the file that may be rewritten.

| # | Finding | Severity | State |
| --- | --- | --- | --- |
| — | _No findings yet._ | — | — |

## Findings

_None yet._ A review session appends them here; each carries a `file:line` and a concrete failure
scenario, and this addon answers underneath with an `> **Addon response — …**` block.

## Checked and correct

Findings that dissolved on tracing, and why. **This section is not optional.** Roughly half of a
review's promising leads turn out to be fine, and without this the next reviewer spends the same
hours reaching the same relief.

_Nothing recorded yet._

## Not covered

What a review did **not** look at. A review that silently skipped three files reads as a clean bill
of health for them.

_No review has been conducted against this file yet._ The file exists so that one has somewhere to
land — an audit written with no home is the failure this protocol was created to stop.
