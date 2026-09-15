---
name: check-ibb
description: Audit an existing Infrastructure Building Block (IBB) directory against the automation-factory-architecture governance rules (manifest, contract schemas, security blueprint, pipeline stages, versioning, evidence, lifecycle). Use when a developer asks whether an IBB is compliant, ready for review, or wants a gap check — including mid-development, after scaffold-ibb, or before requesting a G2/G3 gate review.
---

# Check IBB Compliance

Audits one IBB directory (or a whole `<capability>-ibb/` repo) against the binding rule set in
`automation-factory-architecture/iac-governance-model/04-policy-set.md`, cross-referenced with
`05-standards-contracts.md` for the concrete shapes those rules check against. Use this both for a
one-off compliance question and as a self-check step at the end of `scaffold-ibb` or before a review.

## 1. Locate the inputs

- The architecture docs: look for a directory matching `automation-factory-architecture/` (or ask
  the developer where it lives if not found). Read at minimum:
  `iac-governance-model/04-policy-set.md`, `05-standards-contracts.md`, and
  `reference/rule-checklist.md` in this skill's own directory (a condensed version of the same rules
  for quick lookup — use the source docs, not just the condensed copy, when a rule's exact wording
  matters).
- The target IBB directory: the developer names it, or if there's exactly one directory containing
  an `ibb-manifest.yaml` in the workspace, use that.

## 2. Walk the rule groups, not the file tree

Don't just list files and guess relevance — for each rule group in `04-policy-set.md`
(`ART` composition, `OWN` ownership, `CON` contract, `SEC` security, `TST` testing, `VER` versioning,
`EVD` evidence, `LCM` lifecycle, `EXC` exceptions), check every `MUST` rule and note `SHOULD` rules as
non-blocking observations. For each rule, determine:

- **Met** — cite the specific file/field/line that satisfies it.
- **Partial** — satisfies the letter but misses part of the intent; say what's missing.
- **Missing** — no evidence found.
- **N/A** — rule doesn't apply to this IBB's scope (justify briefly, don't just skip silently).

Concrete things to actually check, not just skim for:

- `ART-002`/`VER-002`: does `ibb-manifest.yaml` pin exact versions for every implementation's
  `referenceDesign`, `securityBlueprint`, `iac`, `pipeline` — no unpinned or `latest` references?
- `ART-004`/`CON-002`: open the input schema — does it expose vendor-specific fields
  (`skuName`, `accountKind`, `allowBlobPublicAccess`, ...) directly, or only agnostic requirement
  classes? `additionalProperties: false` at each object level is a strong positive signal.
- `CON-005`/`EVD-004`: does the output schema's `status` enum include `partially completed` and
  `cancelled`, not just `completed`/`failed`?
- `CON-009`: does the input schema's `context` object require `requesterIdentity` and
  `correlationId`? (Note this rule is `[proposed]` in `12-open-decisions-adr-backlog.md` — flag it as
  a gap against the target design, not an automatic hard fail, and say so explicitly.)
- `SEC-002`: does every row in each `security-blueprints/*/security-blueprint.md` control table have
  all six required attributes — ID, Requirement, Priority, Rationale, Verification Method, Status?
  Missing "Rationale" or "Status" columns entirely is a common partial-compliance pattern.
- `SEC-004`/`SEC-005`: is there a policy-as-code check that runs pre-apply (plan-time) AND a separate
  verification step that re-checks live resource state post-apply? A pipeline that only runs
  `terraform apply` with no post-apply verification fails `SEC-005` even if `terraform plan` is
  policy-gated.
- `SEC-008`: does every `iac/<platform>/versions.tf` (or equivalent) declare a non-local Terraform
  `backend` block? No backend block = local state = violation.
- `TST-003`: is there a CI workflow that runs on pull request / every commit (lint, schema, secrets,
  SAST, IaC scan, policy conformance, tests) — distinct from the deploy-time consumption pipeline?
  A pipeline that only runs when a real request is submitted does not satisfy this.
- `VER-005`: does `VERSIONS.md` exist and reflect the current manifest?
- `OWN-002`: does `CODEOWNERS` exist at the repo root?
- `LCM-001`/`LCM-002`: does `ibb-manifest.yaml` `contract.operations` declare at least `create` plus
  either `upgrade` or `delete`? An IBB with only `create` is pilot-only by this rule.
- `EVD-003`: does a `correlationId` (or equivalent) actually propagate from the input into the
  evidence/output record, or does traceability stop at an internally generated `executionId`?

## 3. Weigh `[carried]` vs `[proposed]` rules honestly

`04-policy-set.md`'s Origin column marks each rule `[carried]` (already-decided, binding) or
`[proposed]` (not yet ratified per `12-open-decisions-adr-backlog.md`). Report violations of
`[proposed]` rules as real gaps against the intended target state, but explicitly flag that they
are not yet organizationally binding — don't conflate the two when giving the overall verdict.

## 4. Report

Give a verdict — **Compliant**, **Partially compliant**, or **Non-compliant** — with a one-line
reason, then a findings table (requirement → status → evidence, file paths included) grouped by rule
category. If the codebase has a `ReportFindings` tool available and the developer asked for a formal
review, use it; otherwise a markdown table in the response is fine. Call out explicitly:

- Anything that's a deliberate, reasonable scaffold/example simplification vs. an actual defect
  (e.g. a repo explicitly labeled "minimal example" isn't failing the same bar as a production
  release candidate — say which bar you're measuring against).
- The `[proposed]`-rule caveat from step 3.
- If this is being run right after `scaffold-ibb`, expect and don't over-flag the known "still on you"
  items that skill already tells the developer about (empty TRD/SBP content, no CI gate wired yet,
  no branch protection) — but do confirm the structural pieces it's responsible for are actually
  present (VERSIONS.md, CODEOWNERS, examples/, non-local backend stub, full status enum, etc.).

Keep the report scoped to what was asked — a quick "is X compliant" question doesn't need the full
56-rule table, just the categories with findings plus a summary line for categories that are clean.
