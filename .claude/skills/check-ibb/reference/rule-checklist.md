# Condensed rule checklist

Source of truth: `automation-factory-architecture/iac-governance-model/04-policy-set.md`. This is a
quick-reference copy for the audit walk — re-read the source file for exact wording, enforcement
point (G0-G6) and evidence artifact when it matters, and whenever the two disagree, the source file
wins.

Level: **M** = MUST (binding, blocks). **S** = SHOULD (recorded, doesn't block).
Origin: **C** = `[carried]` (already binding). **P** = `[proposed]` (not yet ratified — flag as gap
against intent, not a hard organizational violation).

## A. Composition & artifact integrity (`IACG-ART`)
- ART-001 M/C — TRD + SBP + IaC + API/Pipeline all present; missing any one is not releasable.
- ART-002 M/C — all four versioned together, bound by one `ibb-manifest.yaml` per release.
- ART-003 M/C — exactly one coherent capability; a multi-capability bundle is a golden path, not an IBB.
- ART-004 M/C — contract is technology-agnostic; platform specifics stay inside the IBB.
- ART-005 M/C — IaC implements the TRD and every mandatory SBP control, not a generic script.
- ART-006 M/C — dependencies on other capabilities declared explicitly in the manifest.
- ART-007 M/C — no catalog entry without executable automation behind it.

## B. Ownership (`IACG-OWN`)
- OWN-001 M/C — exactly one named accountable owner team; no shared/vacant ownership.
- OWN-002 M/C — write access gated by `CODEOWNERS`; merges require owning-team approval.
- OWN-003 S/C — governed objects readable by all authenticated users (inner-source default).
- OWN-004 M/C — an agent may propose changes, never approve/release them.
- OWN-005 M/C — every automated actor runs under a distinct non-human, least-privileged identity.
- OWN-006 M/P — an ownerless/dissolved-team IBB moves to `deprecated` within 30 days.

## C. Contract & consumption (`IACG-CON`)
- CON-001 M/C — machine-readable contract: identity, version, operations, schemas, status/error model, authz model, lifecycle, dependencies, support route.
- CON-002 M/C — contract exposes only consumer-permitted choices; no provider-specific params externally.
- CON-003 M/C — consumers invoke only through the published interface; no direct provider/IaC calls.
- CON-004 M/C — external contract doesn't depend on execution technology; pipeline engine replaceable.
- CON-005 M/C — shared status model + structured error model (code, category, failed stage, retryable, remediation) across every IBB.
- CON-006 S/C — long-running ops are async with retrievable status.
- CON-007 M/C — idempotent on `requestId`; retry doesn't duplicate infrastructure.
- CON-008 M/C — portal / API-CI-CD / IaC-native import all resolve the same versioned artifact and guardrails.
- CON-009 M/P — mandatory context params (requestId, applicationId, environment, platform, dataClassification, requesterIdentity, correlationId) required; missing ones rejected, not defaulted.

## D. Security (`IACG-SEC`)
- SEC-001 M/C — every TRD has a paired SBP; different implementations need their own SBP.
- SEC-002 M/C — every SBP control has ID, requirement, priority, rationale, verification method, status; no verification method = not publishable.
- SEC-003 S/C — control priority is risk-based (likelihood × impact), not uniform.
- SEC-004 M/C — mandatory controls implemented in IaC and verified by the pipeline; manual post-deploy check isn't a primary control.
- SEC-005 M/C — successful `apply` ≠ security conformance; an explicit verification result is required.
- SEC-006 M/C — secrets never in outputs/logs/responses; brokered to workload identity.
- SEC-007 M/C — caller authenticated + operation authorized per capability/environment before execution; orchestrator never gets privileged credentials.
- SEC-008 M/C — IaC state treated as confidential and protected (encrypted, access-controlled, versioned backend).
- SEC-009 M/P — security findings above a published severity threshold block release.

## E. Testing & validation (`IACG-TST`)
- TST-001 M/C — golden paths/SDKs are integration-tested.
- TST-002 S/C — building blocks tested in combination with commonly-composed blocks.
- TST-003 M/C — every change runs automated validation (format, lint, schema, secrets, SAST, IaC scan, policy conformance, unit/integration/contract tests) — a CI gate on every PR, not just at deploy time.
- TST-004 M/C — release candidate proven by a controlled test deployment: deploy → verify controls → validate outputs → collect evidence → destroy.
- TST-005 M/C — contract compatibility tested against the previous version; unclassified breaking change fails the build.
- TST-006 M/C — only green, policy-validated builds promoted to the registry.

## F. Versioning & release (`IACG-VER`)
- VER-001 M/C — published versions are immutable; never overwritten/re-tagged.
- VER-002 M/C — any accepted component change produces a new IBB version.
- VER-003 M/C — semantic versions, automated + explicit classification rules.
- VER-004 M/C — consumers pin an explicit version; no floating `latest`/branch/moving tag.
- VER-005 M/C — every release publishes release notes (behaviour/security/contract/migration) + updated compatibility matrix (`VERSIONS.md`).
- VER-006 M/C — breaking change = major version + documented migration guidance.
- VER-007 S/C — support window is current major + previous major (N, N-1).
- VER-008 M/C — release approved on the complete tested product, not documentation alone.

## G. Evidence & traceability (`IACG-EVD`)
- EVD-001 M/C — every resource traceable to IBB name/version, implementation, component versions, source commit, pipeline execution, effective inputs, applied controls, validation results, evidence location.
- EVD-002 M/C — evidence produced by the pipeline as a by-product, not assembled manually afterward.
- EVD-003 M/C — a correlation ID propagates from the originating request through orchestration, pipeline, IaC run, and provider resource.
- EVD-004 M/C — failures reported through the structured error contract, distinguishing failure from partial completion.
- EVD-005 M/P — evidence retained per applicable control/regulation, queryable by IBB/version/application/environment.

## H. Lifecycle (`IACG-LCM`)
- LCM-001 M/C — every IBB declares which lifecycle operations it supports; undeclared = unsupported.
- LCM-002 M/P — create-only (no upgrade, no decommission) is not releasable beyond pilot.
- LCM-003 M/C — drift between desired and actual state detected continuously, remediated via an approved workflow.
- LCM-004 M/C — upgrading to a newer IBB version is an explicit lifecycle operation, never invisible.
- LCM-005 M/P — vulnerabilities remediated within the published severity-based window, via a patch release.
- LCM-006 M/C — decommissioning removes resources and updates dependent records through automation.

## I. Exceptions (`IACG-EXC`)
- EXC-001 M/P — any MUST deviation requires a registered, approved exception before execution.
- EXC-002 M/P — every exception is time-boxed, names compensating controls, links to covered instances.
- EXC-003 M/P — an expired exception becomes a non-conformance automatically.
- EXC-004 M/P — a third exception against the same rule/IBB raises a backlog item against the owning team.
- EXC-005 M/P — break-glass execution only for a declared incident, under a named identity, reviewed within 24h.
