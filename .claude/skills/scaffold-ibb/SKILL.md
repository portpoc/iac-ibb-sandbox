---
name: scaffold-ibb
description: Scaffold a new Infrastructure Building Block (IBB) — the fixed directory layout, manifest, schemas, pipeline, policy-as-code, reference designs, security blueprints, and governance files required by automation-factory-architecture. Use when a developer wants to create/bootstrap/start a new IBB, capability, or "infrastructure building block" repo/directory.
---

# Scaffold an Infrastructure Building Block

Generates a new IBB that is structurally compliant with
`automation-factory-architecture/iac-governance-model/04-policy-set.md` and
`05-standards-contracts.md` from the moment it's created, so the developer starts
from a conformant baseline instead of discovering gaps at review time (see
`check-ibb-compliance` for auditing an existing one).

Read those two files plus `infrastructure-building-block/infrastructure-building-block-definition.md`
and `infrastructure-building-block/ibb-api-pipeline-component.md` from the architecture repo if they
are present in the workspace and you need to resolve an ambiguity — this skill's templates already
encode their concrete requirements, but the source docs are the tie-breaker.

## 1. Gather inputs before writing anything

Ask the developer (use AskUserQuestion for anything not stated, don't guess silently):

- **Capability name** — technology-agnostic, kebab-case (e.g. `object-storage`, `relational-database`,
  `message-broker`). Reject anything that names a vendor/product (`s3-bucket`, `azure-sql`) — that
  belongs at the implementation level, not the capability level (`ART-003`, `ART-004`).
- **Owning team** — one named, accountable team (`OWN-001`). No shared or vacant ownership.
- **Support contact** — Slack channel / email / on-call route.
- **Target platforms/implementations** — a subset of the fixed platform vocabulary (§1a). Each
  becomes a paired reference-design + security-blueprint + iac directory (`SEC-001`).
- **Lifecycle operations to support** — at minimum `validate`, `create`, `read`, `delete`.
  If the developer only wants `create`, flag `LCM-002`: an IBB with create but neither `upgrade` nor
  `delete` is not releasable beyond pilot — ask whether to declare `upgrade` now (even as a stub) or
  accept pilot-only status explicitly.
- **Input and output variables** — don't ask this blind. Propose a capability-specific draft first,
  sourced from the shared requirement dictionary where possible; see §1b.
- **Selected technology per platform** — the actual service this capability will be built on for
  each target platform (e.g. Amazon S3 for `object-storage`/`aws`, Azure SQL Database for
  `relational-database`/`azure`). Propose one sensible, commonly-used default per platform and let
  the developer confirm or override — this drives everything written in step 4.
- **Pipeline engine** — `github-actions` or `jenkins` (or both). The contract must stay stable
  regardless of engine (`CON-004`).
- **Dependencies on other capabilities** — e.g. `identity`, `key-management`, `logging` (`ART-006`).

Do not proceed to generation until you have at least: capability name, owner, one platform, and one
requirement class.

## 1a. Fixed vocabularies — org-wide, never per-IBB choices

Two `context` fields are drawn from a fixed enumeration shared by every IBB. Do not let the developer
redefine, extend, or rename these — if a proposed value isn't on the list, that's a conversation to
have with the platform stewards, not a schema edit on this IBB:

- **`context.environment`** — exactly `dev`, `qua`, `tst`, `ppr`, `prd`. Every IBB's input schema
  uses this literal enum.
- **`context.platform`** — drawn from `aws`, `azure`, `gcp`, `on-prem`. An individual IBB's schema
  enum is restricted to whichever subset it actually implements (mirrors `implementations:` in the
  manifest) — never the full four unless all four are genuinely built.

These two, plus `applicationId`, are the non-negotiable mandatory inputs regardless of capability —
call this out explicitly to the developer so they don't mistake them for something the capability
gets to customize. They sit in `context`, not `requirements`: `requirements` is where the
capability-specific, agnostic knobs from §1b go.

## 1b. Propose requirements from the shared requirement dictionary, organized by category

`requirements` in every IBB's input contract is **nested by category**:
`requirements.<category>.<property>` — e.g. `requirements.sizing.storageTier`. The category set is
fixed and high-level, exactly like the `context.platform`/`context.environment` vocabularies in
§1a — it is not a per-IBB choice:

- **`sizing`** — capacity, throughput, or access-frequency tier; how big/fast/hot the resource is.
- **`access`** — who or what can reach, read, or write the resource.
- **`resilience`** — durability, versioning, retention, backup, and availability behaviour.
- **`security`** — encryption and data-protection requirements beyond access control.
- **`operations`** — scheduling, maintenance windows, tagging, and other operational knobs that
  don't fit the categories above.

Do not add a sixth category for a new IBB. If a property genuinely doesn't fit any of the five,
that's a conversation about extending the fixed list, not a schema edit on this IBB.

The properties inside each category come from **`requirement-dictionary/requirement-properties.yaml`**
at the workspace root — a file this skill does not own and does not live inside; it is shared across
every `*-ibb` directory so the next capability reuses the same property instead of reinventing it.
If it doesn't exist yet, create it seeded with the five categories above, each with empty
`properties: {}`, and the header comment shown below.

1. Read the dictionary. For each of the five categories, check whether an existing property already
   fits this capability's needs — reuse it verbatim (same name, type, enum, description). The whole
   point of the dictionary is that `accessScope` means the same thing whether it's `object-storage`
   or `message-broker`.
2. For any category where nothing existing fits, draft a new property proposal under the same
   constraint as before, repeated from `ART-004`/`CON-002`: every property must be **agnostic to the
   underlying technology**. Name and describe what the consumer needs, not how a specific vendor
   exposes it — a consumer chooses a tier, a scope, a behaviour; they don't choose a SKU, an instance
   type, an IOPS number, or any other provider-specific setting. Reject `skuName`, `vCpuCount`,
   `iops`, and similar — those belong in the manifest's `requirementMapping`, translated internally
   per platform, never in the external contract. The same property and value set must make sense
   across every platform this IBB targets — if it only makes sense for one implementation, it isn't
   part of the agnostic contract. Prefer enums over free text where the capability has a natural
   small set of tiers or modes.
3. Present the combined proposal — reused properties and new ones, grouped by category — via
   AskUserQuestion (edit or replace freely; it's a starting draft, not a mandate) rather than an
   open-ended "what fields do you want" question.
4. After the developer agrees, **write any new properties back into the dictionary** under their
   category, each tagged `usedBy: [<capability-name>]` (or append to an existing property's
   `usedBy` list when reusing one). Leaving a new property only in this IBB's schema defeats the
   purpose — the dictionary is what makes step 1 of the *next* IBB faster.

A category with no properties for this capability is omitted entirely from the schema's
`requirements.properties` — don't emit an empty object for it. A category is listed in
`requirements.required` only if at least one of its own properties is required; otherwise it's an
optional object the consumer may omit.

Dictionary file shape (`requirement-dictionary/requirement-properties.yaml`):

```yaml
categories:
  sizing:
    description: Capacity, throughput, or access-frequency tier — never a vendor SKU.
    properties:
      storageTier:
        type: string
        enum: [standard, infrequent-access, archive]
        description: Access-frequency tier; maps to the provider's storage class / access tier.
        usedBy: [object-storage]
  access:
    description: Who or what can reach, read, or write the resource.
    properties: {}
  resilience:
    description: Durability, versioning, retention, backup, and availability behaviour.
    properties: {}
  security:
    description: Encryption and data-protection requirements beyond access control.
    properties: {}
  operations:
    description: Scheduling, maintenance windows, tagging, and other operational knobs.
    properties: {}
```

`result` (output) fields are **not** drawn from the dictionary and stay a flat object — propose them
the same way properties used to be proposed (agnostic, per-capability, via AskUserQuestion), since
`result` is small and rarely reused verbatim the way input knobs are. Categorization applies to
`requirements` only.

## 2. Fixed directory layout — do not deviate

Per `05-standards-contracts.md` §2, this layout is fixed: named directories may not be renamed or
omitted, though extra ones may be added.

```text
<capability-name>-ibb/
├── ibb-manifest.yaml
├── README.md
├── CHANGELOG.md
├── VERSIONS.md
├── CODEOWNERS
├── reference-designs/<platform>/reference-design.md         (one per platform)
├── security-blueprints/<platform>/security-blueprint.md     (one per platform, paired by dir name)
├── iac/<platform>/                                           (Terraform: main.tf, variables.tf, outputs.tf, versions.tf)
├── pipelines/{github-actions,jenkins}/                       (github-actions/<capability>.yml is a symlink into ../../.github/workflows/)
├── policies/<platform>/*.rego
├── schemas/{<capability>-input-v1,<capability>-output-v1,ibb-error-v1}.schema.json
├── actions/{provision,update,decommission}.json               (Port.io self-service action definitions, see §4e)
├── tests/{check.sh, requests/*.json, events/*.json}
├── examples/                                                 (mandatory — minimal runnable example per implementation)
└── docs/                                                      (operational runbook lives here)
```

Create this under the working directory unless the developer names a different parent. Use
`<capability-name>-ibb` as the repo/directory name to match the "one repo per capability team, many
IBBs inside it" convention loosely — for a single-IBB repo this top-level directory *is* the repo.

`requirement-dictionary/requirement-properties.yaml` is **not** part of this layout — it lives as a
sibling at the workspace root (alongside every `*-ibb` directory), shared across all of them. See
§1b.

## 3. Generate the structural and governance files from `templates/`

Templates in this skill's `templates/` directory are annotated with `{{PLACEHOLDER}}` tokens. Read
each template, substitute every placeholder, and Write the result to the corresponding path. Do not
hand-write these files from scratch — the templates already encode the fixes for gaps a prior audit
found in a hand-built IBB (missing `VERSIONS.md`, missing `CODEOWNERS`, no Terraform backend, schema
excluding `correlationId`/`requesterIdentity`, no `partially completed` status). Preserve those fixes.

| Template | Destination | Notes |
| :--- | :--- | :--- |
| `templates/ibb-manifest.yaml.tmpl` | `ibb-manifest.yaml` | One block per platform under `implementations:`. `requirementMapping.<platform>` nests by category to mirror the input schema's `requirements.<category>.<property>` — `requirementMapping.<platform>.<category>.<property>`. `dataClassification` is a `context` field, not a requirements category, so it stays a sibling key under `requirementMapping.<platform>`, not nested inside a category. |
| `templates/README.md.tmpl` | `README.md` | |
| `templates/CHANGELOG.md.tmpl` | `CHANGELOG.md` | Seed with `0.1.0 — initial scaffold` |
| `templates/VERSIONS.md.tmpl` | `VERSIONS.md` | Compatibility matrix, one row per release |
| `templates/CODEOWNERS.tmpl` | `CODEOWNERS` | Owning team gates every path |
| `templates/reference-design.md.tmpl` | `reference-designs/<platform>/reference-design.md` | One per platform, per TRD's 13 required sections |
| `templates/security-blueprint.md.tmpl` | `security-blueprints/<platform>/security-blueprint.md` | One per platform; control table needs ID/Requirement/Priority/Rationale/Verification/**Status** — all six columns are mandatory (`SEC-002`) |
| `templates/schemas/input-v1.schema.json.tmpl` | `schemas/<capability>-input-v1.schema.json` | `context` object MUST include `requesterIdentity` and `correlationId` as required properties, not just `applicationId`/`environment`/`platform` (`CON-009`). `environment` and `platform` enums come from the §1a fixed vocabularies — never freeform. `requirements` is nested by category (`requirements.<category>.<property>`), sourced from `requirement-dictionary/requirement-properties.yaml` per the §1b process, agreed with the developer. |
| `templates/schemas/output-v1.schema.json.tmpl` | `schemas/<capability>-output-v1.schema.json` | `status` enum MUST include `partially completed` and `cancelled`, not just `completed`/`failed`/`rejected` (`EVD-004`, `05-standards-contracts.md` §10). `result` properties come from the §1b proposal. |
| `templates/schemas/error-v1.schema.json.tmpl` | `schemas/ibb-error-v1.schema.json` | Copy near-verbatim; this schema is meant to be shared across all IBBs |
| `templates/pipelines/github-actions.yml.tmpl` | `.github/workflows/<capability>.yml`, symlinked from `pipelines/github-actions/<capability>.yml` | Stages 1-3 (assign execution id, schema validation, pinned version/implementation check) already contain real, working logic — substitute placeholders and leave them as-is. Stage 4 onward is shape/stage-order reference only — replace every remaining stage with real logic in §4d. Don't ship this file with `echo "TODO"` bodies past stage 3. GitHub only triggers workflow files that physically live under `.github/workflows/`, so that's the canonical copy; create `pipelines/github-actions/<capability>.yml` as a relative symlink to it (`ln -s ../../.github/workflows/<capability>.yml pipelines/github-actions/<capability>.yml`) so the governance layout still has a real, readable file at the required path with no risk of the two drifting apart. |
| `templates/policies/policy.rego.tmpl` | `policies/<platform>/<platform>-<capability>.rego` | Shape reference only — write real deny rules in §4d, keyed to the actual Security Blueprint control IDs and Terraform resource types |
| `templates/tests/check.sh.tmpl` | `tests/check.sh` | Schema validation + fixture sanity, not a substitute for real CI (see step 5) |
| `templates/examples/example-request.json.tmpl` | `examples/<platform>-create.json` | One per platform — this is the mandatory `examples/` directory, not optional |
| `templates/docs/runbook.md.tmpl` | `docs/runbook.md` | Support, escalation, known failure modes, recovery |
| `templates/actions/provision.json.tmpl`, `update.json.tmpl`, `decommission.json.tmpl` | `actions/provision.json`, `actions/update.json`, `actions/decommission.json` | Port.io self-service action definitions — real content, not shape reference; see §4e |

These are structural/governance files — manifest, docs, schemas, policy/pipeline *shape*. Write them
fully (they're never TODO stubs), but they don't require domain knowledge of the selected technology.
Step 4 is where the skill stops scaffolding and starts actually building the IBB.

## 4. Write real component content — this is not a stub generator

Continue past the skeleton and author the actual Technical Reference Design, Security Blueprint,
Terraform, and pipeline logic yourself, on the developer's behalf, using the selected technology from
step 1. Don't leave `<!-- fill in -->` placeholders or `echo "TODO"` steps in what you deliver — those
were fine for a bare scaffold, they are not fine for what this skill now produces. The concrete,
proven shape to build from is `object-storage-ibb/` in this workspace (its `reference-designs/aws-s3/`,
`security-blueprints/aws-s3/`, `iac/aws/main.tf`, and `pipelines/github-actions/object-storage.yml`) —
read it before writing anything in this step if it's present. It is a real, working IBB implementation,
not just documentation of one.

### 4a. Technical Reference Design — real decisions, not blanks

For each platform, fill in `templates/reference-design.md.tmpl`'s 13 sections with actual decisions,
in the compact style of `object-storage-ibb/reference-designs/aws-s3/reference-design.md`: a
"Selected technology" table (one row per concern — the storage/compute/db service, encryption
approach, access model, availability approach mapped from the agreed `availabilityClass` values, a
naming convention, etc.), a short component diagram, and real operational dependencies. Every
decision must be genuinely implementable by the Terraform you're about to write in §4c — don't
describe an architecture and then build something else.

### 4b. Security Blueprint — real, verifiable controls

Derive the actual control table for `templates/security-blueprint.md.tmpl`, one row per control that
matters for the selected technology, covering at minimum Identity & Access, Data Protection, Network,
and Logging & Monitoring. All six attributes from `SEC-002` are mandatory — **ID, Domain, Requirement,
Priority, Rationale, Verification Method, Status** — don't drop Rationale or Status the way a
verification-method-only table does (that's a partial-compliance pattern a prior audit flagged; see
`check-ibb-compliance`). For Verification Method, say concretely how it's checked — e.g. "policy-as-code
pre-apply (`policies/<platform>/...`) + live-resource check post-apply (`aws s3api get-...`)" — and set
Status to `Implemented` once the Terraform resource satisfying it is actually written in §4c (never
`Verified`; nobody has run this against real infrastructure yet — that's what a real pipeline run
proves, not this skill).

### 4c. Terraform — the executable implementation

Write real `iac/<platform>/main.tf`, `variables.tf`, `outputs.tf` implementing every control from §4b,
annotated `# SBP <id>` above the resource(s) that satisfy it — mirror
`object-storage-ibb/iac/aws/main.tf`'s pattern exactly (a `locals.common_tags` block carrying
`ibb:name`/`ibb:version`/`app:id`/`app:environment`/`data:classification`, resources driven by
variables that the pipeline resolves from `requirementMapping`, not hardcoded values). `outputs.tf`
must expose whatever `result` fields were agreed in §1b (typically at least a resource identifier and
an endpoint) — never secrets (`SEC-006`). `versions.tf` still needs the non-local backend block from
the standard template, with real bucket/table values commented if you don't have them (§6).

### 4d. Pipeline — real stages, one real runtime-verification block per control

Write the actual pipeline from `templates/pipelines/github-actions.yml.tmpl` to
`.github/workflows/<capability>.yml` — that's the only path GitHub's own workflow indexer reads,
so it's the file that must contain the real content. Then create
`pipelines/github-actions/<capability>.yml` as a relative symlink pointing at it
(`../../.github/workflows/<capability>.yml`), so the governance directory layout still resolves to
the same real file instead of a second copy that can drift out of sync. Stages 1-3 (assign an
execution id; validate the request against the input schema via `check-jsonschema`; check the two
things a shared schema can't express — pinned IBB version matches this pipeline, and the requested
platform has an approved implementation) already ship with real, working logic in the template —
only substitute its `{{PLACEHOLDER}}` tokens, don't rewrite that logic. Continue from stage 4
onward, following `object-storage-ibb/pipelines/github-actions/object-storage.yml` stage-for-stage:
authorize (reject non-prod callers against `environment: prd`), resolve the implementation and map
`requirements.<category>.<property>` (and `context.dataClassification`) through `ibb-manifest.yaml`'s
`requirementMapping` into Terraform variables — `requirementMapping.<platform>` mirrors the same
category nesting as the request (`requirementMapping.<platform>.<category>.<property>`), so the
lookup path is identical on both sides of the translation — short-circuit on `validate`,
obtain scoped credentials via OIDC for each platform actually implemented (`aws-actions/configure-aws-credentials`,
`azure/login`, `google-github-actions/auth` — for `on-prem`, there is no universal action; say
explicitly that credential retrieval must be adapted to the org's actual secret/credential broker and
leave a clearly labeled single step for it, don't invent a fake one), `terraform plan`, a `conftest`
gate against `policies/<platform>/` before any apply, `terraform apply`/`destroy`, then — the one part
that's genuinely fresh authoring — **a live-resource verification step that checks every SBP control
row from §4b by name**, one CLI call per control against the platform's own tooling (`aws s3api`,
`az storage account show`, `gcloud storage buckets describe`, …), each emitting a
`{control, result, detail}` record; compose the standardized evidence/output on success and the shared
error contract on failure, then upload both as artifacts. This verification block is the one piece of
this skill's own judgment that can't be templated away — write it fresh, grounded in the actual
control list you just wrote in §4b, not copied verbatim from the object-storage example if the
controls differ.

Also write real `policies/<platform>/*.rego` deny rules — one per plan-time-checkable control from
§4b, keyed to the actual Terraform resource type/attribute, not the commented-out example in the
template.

### 4e. Port.io self-service actions — a human's entry point to the pipeline

A pipeline nobody can click is not self-service. Write one Port self-service action per
consumer-facing lifecycle operation so the IBB shows up as a runnable action on its Port catalog
page, not just a schema and a workflow file only CI knows how to call.

**Which operations get a button.** By default, generate exactly three: `provision.json`
(`create`), `update.json` (`upgrade`), `decommission.json` (`delete`) — these are what a human
actually clicks. `validate` and `read` stay pipeline-only (used by CI/tests and programmatic
callers); don't clutter the catalog with buttons for them unless the developer specifically asks.
If the manifest doesn't declare `upgrade` (pilot-only per `LCM-002`), skip `update.json` and say so.

**Determine the invocation target.**
- If `github-actions` is one of the pipeline engines, wire a `GITHUB` invocation — Port has native
  support for it and it needs no extra broker. Get `org`/`repo` from `git remote get-url origin` in
  the working directory (ask the developer if the repo has no remote yet, or isn't pushed); the
  `workflow` field is the file name under `.github/workflows/` (`<capability>.yml`), not the
  `pipelines/github-actions/` symlink path.
- If the IBB is Jenkins-only (no `github-actions` engine), use a `WEBHOOK` invocation pointed at the
  org's Jenkins generic webhook trigger for this job. That URL is org/environment-specific and not
  knowable from the repo — template it as a placeholder and list it under §6 as still-on-developer,
  the same way a Terraform backend value is.
- If both engines exist, default to `GITHUB` for the self-service action (it needs no extra
  configuration) and mention in the PR/handoff that a Jenkins-triggered variant can be added the same
  way once the org's webhook URL is known.

**User inputs — ask for only what a human should decide.** Build `userInputs.properties` from:
  - The mandatory `context` fields the human must supply: `applicationId`, `environment` (enum,
    §1a), `costCenter`, `dataClassification`, plus `changeReference` as optional free text (enforced
    conditionally for `prd` by the pipeline's authorization stage, per `CON-009`/`SEC-007`). If a
    Security Blueprint control already forecloses a value (e.g. this capability's data is
    unavoidably public, so `confidential` is always rejected pre-apply), narrow the form's enum to
    match — don't offer a choice the policy gate guarantees will fail.
  - `platform` — only ask if the IBB implements more than one; with a single implementation, hardcode
    it into the request template instead of adding a redundant input.
  - Every `requirements.<category>.<property>` this capability actually declared in §1b, with the
    same type/enum/description as the schema (and the dictionary) — the self-service form and the
    input schema must agree, since the form is just a friendlier way of producing the same request.
  - **Never ask for** `request.requestId`, `context.correlationId`, or `context.requesterIdentity` —
    these are derived automatically from the Port run context in the invocation template (below),
    not typed by a human. Confirm the exact run-context expression syntax against Port's current
    self-service action templating docs before shipping to production; treat the ones used here as
    a starting convention, not a guaranteed-stable API.

**Compose the invocation.** GitHub's `workflow_dispatch` allows at most 10 declared inputs and only
string values, and the pipeline template already declares exactly one (`request`) — so the action's
`workflowInputs` must build the *entire* request JSON as a single templated string assigned to that
one input, not one workflow input per form field:

```json
{
  "invocationMethod": {
    "type": "GITHUB",
    "org": "<org>",
    "repo": "<repo>",
    "workflow": "<capability>.yml",
    "workflowInputs": {
      "request": "{\"request\":{\"operation\":\"create\",\"requestId\":\"req-{{ .run.id }}\"},\"buildingBlock\":{\"name\":\"<capability>\",\"version\":\"<version>\"},\"context\":{\"applicationId\":\"{{ .inputs.applicationId }}\",\"environment\":\"{{ .inputs.environment }}\",\"platform\":\"<platform-or-input>\",\"costCenter\":\"{{ .inputs.costCenter }}\",\"dataClassification\":\"{{ .inputs.dataClassification }}\",\"requesterIdentity\":\"{{ .trigger.by.user.email }}\",\"correlationId\":\"corr-{{ .run.id }}\",\"changeReference\":\"{{ .inputs.changeReference }}\"},\"requirements\":{\"<category>\":{\"<property>\":\"{{ .inputs.<property> }}\"}}}"
    },
    "reportWorkflowStatus": true
  }
}
```

Note the two template syntaxes share `{{ }}` but never collide: this skill's own placeholders are
bare tokens (`{{CAPABILITY_NAME}}`, `{{VERSION}}`), substituted by exact-string replacement, while
Port's runtime expressions always start with a space and a dot (`{{ .inputs.x }}`, `{{ .run.id }}`)
and are left untouched by that substitution — write them literally in the `.tmpl` file, no escaping
needed.

Leave a number- or array-typed input **unquoted** in the template (`{{ .inputs.ttlSeconds }}`,
`{{ .inputs.recordValues }}`) so Port substitutes a JSON number/array, not a quoted string — only
string-typed inputs get the surrounding quotes.

**Never let two or more literal `}` sit adjacent anywhere in the template.** Port's invocation-method
templating engine scans for `{{`/`}}` tokens character-by-character; it does not know JSON structure,
so a run of 2+ raw closing braces — which happens naturally whenever the *last* property of the
*last* nested object is an unquoted expression, since nothing then separates that expression's own
`}}` from the JSON closes stacking up right after it — gets misread as a second, unmatched `}}`
token and the whole action fails with `Failed to evaluate invocation method: Found closing double
braces at index N without opening double braces`. This is exactly the failure mode when
`requirements` wraps a single category whose last property is a number or array (e.g.
`"recordValues":{{ .inputs.recordValues }}}}}`  — 2 expression-closing braces immediately followed
by 3 literal closes for the property's object, the category object, and the root object). Fix it by
inserting a single space before each subsequent literal `}` so no two are adjacent — JSON is
whitespace-insensitive outside strings, so this costs nothing:
`"recordValues":{{ .inputs.recordValues }} } } }`. Check every `.tmpl` output for this pattern after
substitution, not just the last field — any nested-object tail can trigger it.

`trigger.operation` is `"CREATE"` for `provision.json`, `"DAY-2"` for `update.json`, `"DELETE"` for
`decommission.json`; the request's own `request.operation` field is the literal matching string
(`create`/`upgrade`/`delete`), hardcoded per action — the human picks the action, not a dropdown
inside it. Leave `requiredApproval: false` by default and mention to the developer that gating
`decommission.json` behind a Port approval flow is a reasonable, org-specific hardening they may
want to add.

**Apply it.** Writing the JSON file is necessary but not sufficient — the action doesn't exist in
Port until it's pushed. If the `mcp__port__upsert_action` tool is available in the current session,
call it directly (once per file) and confirm the result. Either way, `sync-ibb-to-port` is the
durable, CI-reachable path (it reads `actions/*.json` the same way it reads everything else from the
repo) — mention that running it (or waiting for the next scheduled sync) is what makes the action
appear for everyone, not just this session.

## 5. Verify what you wrote, don't just declare it done

- Run `terraform fmt -check` and, if the `terraform` binary is available, `terraform validate` in each
  `iac/<platform>/` — catch syntax errors before handing this back. Note plainly that `validate`
  without real provider credentials cannot catch everything (auth failures, quota, drift) — it only
  proves the HCL itself is well-formed and internally consistent.
- Validate every schema and the manifest parse cleanly, and that `examples/<platform>-*.json` actually
  validates against the input schema (same checks as `tests/check.sh`).
- Run the `check-ibb-compliance` skill against the result and report its findings — don't just assert
  compliance yourself.

## 6. What's still genuinely on the developer

After §4 and §5, what's left is only what truly requires access or authority this skill doesn't have —
say so plainly, and don't imply the rest is still a TODO when it isn't:

- Real Terraform backend values (bucket/table/subscription/etc.) — the skill leaves this templated
  because it doesn't know the org's actual state-store configuration.
- CI/CD secrets and environment-scoped variables the pipeline references (OIDC role ARNs, tenant/
  subscription IDs, `CALLER_ENV`) — these are set in the platform's repo/environment settings, not
  files.
- Wiring a CI validation gate (lint, secret scanning, SAST, IaC scan, policy conformance, contract
  tests) that runs on every PR — distinct from the deploy-time pipeline just written, required by
  `TST-003` at G1/G2. Ask whether the repo already has a shared org CI template to wire in.
- Configuring branch protection requiring `CODEOWNERS` approval (`OWN-002`) — a repo setting, not a
  file.
- An actual test deployment against real cloud credentials (`TST-004`) — this skill can write and
  locally validate the Terraform, but cannot prove it applies cleanly without running it somewhere
  real.
- The org's actual Jenkins generic webhook trigger URL (and its credential), if the IBB is
  Jenkins-only — `actions/*.json`'s `WEBHOOK` invocation is templated but cannot be pointed at a
  real endpoint without it.
- Running `sync-ibb-to-port` (or waiting for its scheduled/CI run) so the `actions/*.json` files
  just written actually become clickable in Port, if the skill's session had no direct Port access
  to push them immediately.

## 7. Substitution rules

- `{{CAPABILITY_NAME}}` — kebab-case capability name
- `{{CAPABILITY_TITLE}}` — Title Case for prose (`Object Storage`)
- `{{OWNER_TEAM}}`, `{{SUPPORT_CONTACT}}`
- `{{PLATFORM}}` — repeat file generation once per platform, drawn from the §1a subset chosen
  (`aws`, `azure`, `gcp`, `on-prem`)
- `{{OPERATIONS}}` — YAML list matching what was gathered in step 1
- `{{ENVIRONMENT_ENUM}}` — always the literal `["dev", "qua", "tst", "ppr", "prd"]`, never customized
- `{{PLATFORMS_ENUM}}` — the subset of the platform vocabulary this IBB actually implements
- `{{REQUIREMENT_CATEGORIES}}` — the subset of the fixed category list (`sizing`/`access`/
  `resilience`/`security`/`operations`) this IBB actually populates, each with properties sourced
  from `requirement-dictionary/requirement-properties.yaml` per §1b — never invent a new top-level
  category per IBB. In `README.md.tmpl`'s `{{REQUIREMENT_CATEGORY_SECTIONS}}`, render one `###`
  subsection per populated category with a parameter/values/meaning table, in the same order as the
  dictionary's fixed category list.
- `{{RESULT_FIELDS}}` — the `result` schema properties agreed in §1b (output stays a flat object;
  only `requirements` input is organized by category)
- `{{VERSION}}` — start every component and the manifest at `0.1.0`, `status: draft` (not `approved` —
  approval is a G3 release-gate outcome, not a scaffold default)
- `{{DEPENDENCIES}}` — YAML list of other capability names the IBB declares dependency on
- `{{ORG}}`, `{{REPO}}` — from `git remote get-url origin` (owner/repo), used by `actions/*.json`'s
  `GITHUB` invocation; ask the developer if there's no remote yet
- `{{WORKFLOW_FILE}}` — `<capability>.yml`, the file under `.github/workflows/` (not the
  `pipelines/github-actions/` symlink path)

## 8. Idempotence and re-runs

If the target directory already has some of these files, don't overwrite silently — list what exists,
ask the developer whether to fill in only the gaps or regenerate specific files.
