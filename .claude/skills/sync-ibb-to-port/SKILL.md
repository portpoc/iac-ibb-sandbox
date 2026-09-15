---
name: sync-ibb-to-port
description: Upload/sync an Infrastructure Building Block (IBB) into the Port.io software catalog over the REST API, authenticating from a .env file. Derives capability, building block, version, platform implementations, reference designs, security blueprints and their controls, pipeline, policy-as-code and requirement-dictionary entities from the IBB directory. Use when a developer wants to publish, upload, sync, push or register an IBB (or its docs, controls or policies) in Port, or refresh the catalog after changing a manifest, security blueprint or rego policy.
---

# Sync an IBB into the Port catalog

Publishes one `<capability>-ibb/` directory into Port as a connected set of catalog entities, so
the governance questions in `iac-governance-model/08-conformance-evidence-traceability.md` §4 become
catalog queries instead of a repo crawl. It also upserts any Port self-service action definitions
under `actions/*.json` (written by `scaffold-ibb` §4e) — this is what actually makes those actions
clickable in Port for everyone, not just in a session that happened to have direct Port API access.

The **repo is the source of truth**; Port is a projection of it. The script never invents a value —
a field absent from the IBB is left unset so the gap stays visible, and structural problems
(a control with no verification method, an unknown platform) fail the run rather than syncing
silently-wrong data.

## 1. Prerequisites

**Credentials.** Port → Organization → Credentials gives a Client ID and Client Secret. Put them in
a `.env` at the workspace root (the script walks up from the IBB directory to find it):

```
PORT_CLIENT_ID=
PORT_CLIENT_SECRET=
# EU (app.port.io / app.getport.io) — the default. US: https://api.us.port.io
# PORT_API_BASE_URL=https://api.port.io
```

`.env.example` in this skill directory is a copyable template. **Confirm `.env` is gitignored before
writing secrets into it** — if it is not, add it and say so; never commit credentials. Real
environment variables take precedence over the file, so CI can pass them as secrets instead.

**Blueprints must already exist.** This skill writes entities, not blueprints. The target data model
is the `ibb_*` blueprint family (see `reference/entity-mapping.md`). If a blueprint is missing the
API returns 404 — create the data model first.

**Python 3 with PyYAML** (`python3 -m pip install pyyaml`). Nothing else; HTTP uses the stdlib.

## 2. Always dry-run first

```bash
python3 .claude/skills/sync-ibb-to-port/scripts/sync_ibb_to_port.py \
  --ibb-dir object-storage-ibb --dry-run
```

This parses everything, runs the validations, and prints an entity count per blueprint without
sending or authenticating. Add `-v` to dump the payloads.

Show the developer the counts and confirm they look right before the real run. A count that is
lower than expected usually means a file is missing or misnamed — the fixed directory layout in
`05-standards-contracts.md` §2 is what the parser relies on.

## 3. Sync

```bash
python3 .claude/skills/sync-ibb-to-port/scripts/sync_ibb_to_port.py \
  --ibb-dir object-storage-ibb
```

Options:

| Flag | Purpose |
| :--- | :--- |
| `--ibb-dir` | The directory containing `ibb-manifest.yaml` (required) |
| `--requirement-dictionary` | Path to `requirement-properties.yaml`; defaults to `<ibb-dir>/../requirement-dictionary/` |
| `--lifecycle-stage` | `pilot` (default), `general-availability`, `deprecated`, `retired` — not derivable from the manifest |
| `--dry-run` | Parse, validate, print the plan; send nothing |
| `-v` | Print each entity payload |

Writes use `upsert=true&merge=true`, so the sync is **idempotent** — re-running after a repo change
updates the changed fields and leaves everything else alone. Entities are emitted parent-first so
relation targets always exist before the entity that points at them.

## 4. Interpreting a failed run

Validation failures print before anything is sent and exit 1. They are IBB defects, not script bugs
— fix the repo (or extend a blueprint enum) rather than working around them:

| Message | Meaning |
| :--- | :--- |
| `control X: no verification method` | `SEC-002` — a control with no verification method is unenforceable prose and makes the blueprint unpublishable |
| `control X: domain '...' is not in the blueprint enum` | Either the SBP uses a domain outside `security-blueprint.md` §3, or the enum needs extending |
| `security blueprint has no parseable controls` | The control table is missing or its header is not the seven mandatory columns |
| `implementation platform '...' is not one of [...]` | Manifest declares a platform the model doesn't know |
| `metadata.status '...' is not one of [...]` | Manifest status outside `draft → in-review → approved` |

An API failure exits 2 with Port's own response body. A 404 means the blueprint doesn't exist; a 401
means the credentials are wrong or from a different region than `PORT_API_BASE_URL`.

## 5. After syncing

Confirm in Port rather than trusting the exit code — open the building block's entity page, or query
`ibb_version` and check the version resolves with its implementations attached. Mention the page URL
to the developer.

If the developer is publishing a *new* capability, the dependency capabilities named in the manifest
are created as `status: proposed` stubs so relations resolve. Those are placeholders — if a real IBB
for that capability exists, sync it too.

## 6. Running in CI

`.github/workflows/sync-ibb-to-port.yml` already wires this up:

- **On pull request** — dry-runs every IBB in the repo. Validation failures fail the check, so a
  control missing its verification method blocks the merge instead of surfacing after it. This job
  needs **no credentials**, so it also works on fork PRs.
- **On push to `main`/`master`** (i.e. a merged PR) — runs the real sync.
- **`workflow_dispatch`** — manual run, optionally scoped to one `ibb_dir`.

Both jobs discover IBBs with `find . -name ibb-manifest.yaml`, so a new IBB is picked up with no
workflow change. Every IBB is synced, not just the changed ones — the upsert is idempotent, and
this avoids diff logic that breaks on shallow clones.

Repository setup: add `PORT_CLIENT_ID` and `PORT_CLIENT_SECRET` as secrets (the workflow uses a
`port` environment, so they can be scoped there and gated with required reviewers). US accounts also
need the `PORT_API_BASE_URL` repository **variable** set to `https://api.us.port.io`.

If the developer's SCM is Bitbucket rather than GitHub — which is what
`05-standards-contracts.md` §11 records as the current DSV toolchain — the same script runs
unchanged under Jenkins; only the trigger wrapper differs.

## 7. What this skill does not do

- **Does not create or modify blueprints**, dashboards, or entity pages. Self-service actions are
  the one exception to "entities only" — see `reference/entity-mapping.md` §10 — but the *action's
  target* (e.g. what blueprint it's scoped to) still isn't something this script invents.
- **Does not delete** entities removed from the repo. A control deleted from a security blueprint
  stays in Port until removed by hand. Flag this if a developer is renaming or removing controls.
- **Does not sync provisioned instances** (`ibb_instance`) — those come from pipeline runs, not the repo.
- **Is not a compliance gate.** It validates only what it must to build valid entities; use
  `check-ibb-compliance` for a real audit against the 56-rule policy set.
