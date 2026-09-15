# IBB → Port entity mapping

What the sync script reads, and where each value lands. Governed-object IDs (G1–G11) refer to
`iac-governance-model/02-governed-objects-artifact-model.md` §3.

Entities are emitted in this order so relation targets always exist first.

## 1. `ibb_capability` — Capability (G1)

| Entity | Source | Notes |
| :--- | :--- | :--- |
| `<name>` | `metadata.name` | `status: approved` |
| one per dependency | `dependencies[]` | `status: proposed` stubs so the relation resolves |

## 2. `ibb` — Infrastructure Building Block (G3 product identity)

| Property | Source |
| :--- | :--- |
| `owner_team` / `support` | `metadata.owner` / `metadata.support` |
| `declared_operations` | `contract.operations` (`LCM-001`) |
| `interface_type` / `pipeline_engine` | `contract.interface.type` / `.implementation` |
| `supported_platforms` | keys of `implementations` |
| `manifest_path` | `<ibb-dir>/ibb-manifest.yaml`, repo-relative |
| `readme` / `runbook` | `README.md` / `docs/runbook.md` |
| `reference_designs` / `security_blueprints` | every platform's doc concatenated under a `# <platform>` heading |
| `lifecycle_stage` | **not in the manifest** — from `--lifecycle-stage`, default `pilot` |
| relations | `capability`, `depends_on[]` |

The concatenated doc properties are markdown-formatted, so Port renders each as its own entity-page
tab. They duplicate the per-platform `content` on the TRD/SBP entities — regenerated on every sync,
so the two cannot drift as long as the sync is the only writer.

## 3. `ibb_version` — IBB Version (G3, the governed unit)

Identifier `<name>@<version>`.

| Property | Source |
| :--- | :--- |
| `version` / `status` | `metadata.version` / `metadata.status` |
| `contract_version` | the `vN` in the input schema filename |
| `input_schema` / `output_schema` / `error_schema` | `contract.schemas.*` |
| `operations` | `contract.operations` |
| `asynchronous` / `idempotency_key` | `contract.execution.*` |
| `changelog` / `compatibility_matrix` | `CHANGELOG.md` / `VERSIONS.md` (`VER-005`) |

Release-record fields (`artifact_digest`, `signed`, `approved_by`, `approved_at`, `released_at`) are
**deliberately left unset** — they are outputs of the G3 release gate, not repo contents. A release
pipeline should write them.

## 4. `ibb_reference_design` (G4) and `ibb_security_blueprint` (G5)

One per platform. Identifiers `<name>-<platform>-trd@<version>` / `-sbp@<version>`.

`status`, `owner`, `scope` and `paired_trd` are read from the document's `- **Label:** value` header
block; `content` is the whole file. `technology` comes from `implementations.<platform>.technology`.

## 5. `ibb_security_control`

One entity per row of the SBP control table, keyed by the control ID. Requires the seven mandatory
columns from `infrastructure-building-block/security-blueprint.md` §4:

```
| ID | Domain | Requirement | Priority | Rationale | Verification Method | Status |
```

Derived, not read:

- `verification_stage` — inferred from the verification text: `pre-apply-policy` (mentions pre-apply
  or policy-as-code), `post-apply-live-check` (post-apply or live-resource), `design-review`.
- `mandatory` — true for `Critical` and `High`. This encodes the block-vs-report rule in
  `06-guardrails-control-points.md` §3; change it here if that policy changes.

An empty verification method fails the run (`SEC-002`).

## 6. `ibb_implementation`

Identifier `<name>@<version>/<platform>`.

| Property | Source |
| :--- | :--- |
| `technology` / `approved` / `iac_path` | `implementations.<platform>.*` |
| `iac_framework` | `terraform` if `iac/<platform>/*.tf` exists |
| `backend_configured` | an uncommented `backend "..."` block in `versions.tf` (`SEC-008`) |
| `policy_path` | first `.rego` under `policies/<platform>/` |
| `requirement_mapping` | `requirementMapping.<platform>` (`CON-002`) |
| relations | `ibb_version`, `ibb`, `reference_design`, `security_blueprint` |

The direct `ibb` relation exists so entity-page tables can scope to the building block; the
`ibb_version` relation is the governance-correct one.

## 7. `ibb_pipeline` (G7)

One per engine directory under `pipelines/`. `stages` is every `- name:` in the workflow. The four
booleans are keyword heuristics over the file — `has_preapply_policy_gate` (conftest/opa),
`has_postapply_verification` (verify), `emits_evidence` (evidence), `propagates_correlation_id`.
They indicate presence, **not correctness**; only `check-ibb-compliance` judges whether the gate is
real.

## 8. `ibb_policy`

One per `.rego` under `policies/<platform>/`. `rule_count` counts `deny` blocks; `enforces_controls`
relates to every control ID matched by `SBP <ID>` in the file, which is how a control traces to the
rule that gates it. `content` is the source fenced as rego.

## 9. `ibb_requirement_property`

From the shared `requirement-dictionary/requirement-properties.yaml`, filtered to properties whose
`usedBy` includes this IBB. Identifier `<category>.<property>`. `used_by` becomes the many-relation,
so the cross-IBB vocabulary stays a single set of entities rather than per-IBB copies.

## 10. Self-service actions

One per file under `actions/*.json` — these are not blueprint entities, so they don't go through
`upsert()`/the `?upsert=true` entity endpoint; each is checked for existence (`GET /actions/{id}`)
and then `POST /actions` (create) or `PUT /actions/{id}` (update — `PATCH` on this route returns
404, it is not supported). Validation is minimal —
`identifier`, `trigger`, and `invocationMethod` must be present — since the file's actual shape is
Port's own action schema (see `scaffold-ibb` SKILL.md §4e for how these are authored), not something
this script re-derives from other files the way entities are.

## Not synced

`ibb_instance` (G11), `ibb_golden_path` (G9) and `ibb_solution_design` (G8) have no repo
representation — instances come from pipeline runs, the other two from outside the IBB.
