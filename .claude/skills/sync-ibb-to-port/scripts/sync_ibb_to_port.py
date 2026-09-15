#!/usr/bin/env python3
"""
Sync one Infrastructure Building Block directory into the Port.io catalog.

Reads an IBB laid out per automation-factory-architecture/05-standards-contracts.md §2,
derives catalog entities from the files on disk, and upserts them through the Port REST API.

The manifest and the repo files are the source of truth. Nothing is invented: a field that
does not exist on disk is left unset rather than defaulted, so a gap in the IBB shows up as
a gap in the catalog instead of being papered over.

Auth comes from a .env file (or the real environment):
    PORT_CLIENT_ID, PORT_CLIENT_SECRET, optionally PORT_API_BASE_URL.

Usage:
    python3 sync_ibb_to_port.py --ibb-dir ../../object-storage-ibb [--dry-run] [-v]

Exit codes: 0 ok, 1 usage/validation error, 2 API error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: python3 -m pip install pyyaml")

DEFAULT_API = "https://api.port.io/v1"

# Enum values the blueprints accept. Kept here so a mismatch fails locally with a useful
# message instead of a 400 from the API halfway through a sync.
CONTROL_DOMAINS = {
    "Identity & Access", "Network Security", "Data Protection", "Logging & Monitoring",
    "Vulnerability Management", "Secrets Management", "Compliance", "Incident Response",
    "Platform Hardening", "Supply Chain Security", "Object Ownership",
}
CONTROL_PRIORITIES = {"Critical", "High", "Medium", "Low"}
CONTROL_STATUSES = {"Planned", "Implemented", "Verified"}
MANIFEST_STATUSES = {"draft", "in-review", "approved"}
PLATFORMS = {"aws", "azure", "gcp", "on-prem"}
REQUIREMENT_CATEGORIES = {"sizing", "access", "resilience", "security", "operations"}


# --------------------------------------------------------------------------- env & http

def load_dotenv(start: Path) -> None:
    """Load the nearest .env walking up from `start`. Real env vars always win."""
    for directory in [start, *start.parents]:
        env_file = directory / ".env"
        if not env_file.is_file():
            continue
        for raw in env_file.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):]
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            os.environ.setdefault(key, value)
        return


class PortClient:
    def __init__(self, base_url: str, client_id: str, client_secret: str, dry_run: bool):
        self.base_url = base_url.rstrip("/")
        self.dry_run = dry_run
        self._token: str | None = None
        self._creds = {"clientId": client_id, "clientSecret": client_secret}

    def _request(self, method: str, path: str, payload: dict | None, auth: bool = True,
                 ignore_404: bool = False) -> dict | None:
        url = f"{self.base_url}{path}"
        data = json.dumps(payload).encode() if payload is not None else None
        headers = {"Content-Type": "application/json"}
        if auth:
            headers["Authorization"] = f"Bearer {self.token}"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read().decode() or "{}")
        except urllib.error.HTTPError as exc:
            if ignore_404 and exc.code == 404:
                return None
            body = exc.read().decode(errors="replace")
            raise SystemExit(f"Port API {exc.code} on {method} {path}\n{body}") from exc
        except urllib.error.URLError as exc:
            raise SystemExit(f"Cannot reach {url}: {exc.reason}") from exc

    @property
    def token(self) -> str:
        if self._token is None:
            resp = self._request("POST", "/auth/access_token", self._creds, auth=False)
            self._token = resp["accessToken"]
        return self._token

    def upsert(self, blueprint: str, entity: dict) -> None:
        if self.dry_run:
            return
        self._request(
            "POST",
            f"/blueprints/{blueprint}/entities?upsert=true&merge=true",
            entity,
        )

    def upsert_action(self, action: dict) -> None:
        if self.dry_run:
            return
        identifier = action["identifier"]
        # Actions have no upsert=true query param like entities — check existence first,
        # then PUT (update; PATCH returns 404 — not a supported route) or POST (create).
        existing = self._request("GET", f"/actions/{identifier}", None, ignore_404=True)
        if existing is None:
            self._request("POST", "/actions", action)
        else:
            self._request("PUT", f"/actions/{identifier}", action)


# --------------------------------------------------------------------------- parsing

def read(path: Path) -> str | None:
    return path.read_text(encoding="utf-8") if path.is_file() else None


def git_repo_url(directory: Path) -> str | None:
    """Best-effort https URL for the repo's origin remote. None if not a git repo / no remote."""
    try:
        raw = subprocess.run(
            ["git", "-C", str(directory), "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    if not raw:
        return None
    if raw.startswith("git@"):
        # git@github.com:org/repo.git -> https://github.com/org/repo
        host, _, path = raw.partition(":")
        host = host.split("@", 1)[1]
        return f"https://{host}/{path.removesuffix('.git')}"
    return raw.removesuffix(".git")


def split_row(line: str) -> list[str]:
    """Split a markdown table row, honouring escaped pipes."""
    cells = line.replace(r"\|", "\0").strip().strip("|").split("|")
    return [c.replace("\0", "|").strip() for c in cells]


def parse_control_table(markdown: str, source: Path) -> list[dict]:
    """Extract control rows from a Security Blueprint's markdown table.

    Expects the seven mandatory columns from security-blueprint.md §4:
    ID | Domain | Requirement | Priority | Rationale | Verification Method | Status
    """
    controls, header_seen = [], False
    for line in markdown.splitlines():
        if not line.lstrip().startswith("|"):
            header_seen = False
            continue
        cells = split_row(line)
        if not header_seen:
            if cells and cells[0].strip().upper() == "ID":
                header_seen = True
            continue
        if set("".join(cells)) <= set(": -"):  # separator row
            continue
        if len(cells) < 7:
            print(f"  ! {source.name}: skipping malformed control row: {cells[:1]}")
            continue
        cid, domain, requirement, priority, rationale, verification, status = cells[:7]
        if not cid:
            continue
        controls.append({
            "id": cid, "domain": domain, "requirement": requirement,
            "priority": priority, "rationale": rationale,
            "verification_method": verification, "status": status,
        })
    return controls


def header_field(markdown: str, label: str) -> str | None:
    """Pull `- **Label:** value` out of a document header block."""
    m = re.search(rf"^\s*[-*]\s*\*\*{re.escape(label)}:?\*\*\s*(.+?)\s*$", markdown, re.M)
    if not m:
        return None
    return m.group(1).strip().strip("`")


def summarise(text: str, limit: int) -> str:
    """Shorten a requirement to a title, cutting on a word boundary."""
    clean = re.sub(r"\s+", " ", text.replace("`", "")).strip()
    if len(clean) <= limit:
        return clean
    return clean[:limit].rsplit(" ", 1)[0].rstrip(",;:") + "…"


def verification_stages(text: str) -> list[str]:
    lowered = text.lower()
    stages = []
    if "pre-apply" in lowered or "policy-as-code" in lowered:
        stages.append("pre-apply-policy")
    if "post-apply" in lowered or "live-resource" in lowered:
        stages.append("post-apply-live-check")
    if "design review" in lowered:
        stages.append("design-review")
    return stages


def parse_rego(text: str) -> tuple[int, list[str]]:
    """Return (deny rule count, referenced control IDs) for a rego policy file."""
    rules = len(re.findall(r"^\s*deny\b.*\{", text, re.M))
    ids = re.findall(r"SBP\s+([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d{3})", text)
    return rules, sorted(set(ids))


# --------------------------------------------------------------------------- mapping

class IbbSync:
    def __init__(self, ibb_dir: Path, lifecycle_stage: str, verbose: bool):
        self.dir = ibb_dir
        self.lifecycle_stage = lifecycle_stage
        self.verbose = verbose
        self.errors: list[str] = []
        manifest_path = ibb_dir / "ibb-manifest.yaml"
        if not manifest_path.is_file():
            raise SystemExit(f"No ibb-manifest.yaml in {ibb_dir} — not an IBB directory.")
        self.manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8")) or {}
        self.meta = self.manifest.get("metadata", {}) or {}
        self.contract = self.manifest.get("contract", {}) or {}
        self.implementations = self.manifest.get("implementations", {}) or {}
        self.name = self.meta.get("name")
        self.version = str(self.meta.get("version", ""))
        if not self.name or not self.version:
            raise SystemExit("manifest metadata.name and metadata.version are required.")
        self.vkey = f"{self.name}@{self.version}"
        # blueprint -> [entity, ...], emitted in insertion order so relation targets exist first
        self.plan: list[tuple[str, dict]] = []
        # Port self-service action definitions from actions/*.json — a separate API surface
        # from blueprint entities, so kept in their own list.
        self.actions: list[dict] = []

    def add(self, blueprint: str, entity: dict) -> None:
        self.plan.append((blueprint, entity))

    # -- individual blueprints ---------------------------------------------

    def capabilities(self) -> None:
        self.add("ibb_capability", {
            "identifier": self.name,
            "title": self.name.replace("-", " ").title(),
            "properties": {"status": "approved"},
        })
        for dep in self.manifest.get("dependencies", []) or []:
            self.add("ibb_capability", {
                "identifier": dep,
                "title": str(dep).replace("-", " ").title(),
                "properties": {
                    "status": "proposed",
                    "description": f"Declared as a dependency by `{self.name}`.",
                },
            })

    def building_block(self) -> None:
        iface = self.contract.get("interface", {}) or {}
        engine = iface.get("implementation")
        props: dict[str, Any] = {
            "lifecycle_stage": self.lifecycle_stage,
            "manifest_path": f"{self.dir.name}/ibb-manifest.yaml",
            "declared_operations": self.contract.get("operations", []) or [],
            "supported_platforms": sorted(self.implementations.keys()),
        }
        if self.meta.get("owner"):
            props["owner_team"] = self.meta["owner"]
        if self.meta.get("support"):
            props["support"] = str(self.meta["support"])
        repo_url = git_repo_url(self.dir)
        if repo_url:
            props["repo_url"] = repo_url
        if iface.get("type"):
            props["interface_type"] = iface["type"]
        if engine:
            props["pipeline_engine"] = [engine]

        for prop, filename in (("readme", "README.md"), ("runbook", "docs/runbook.md")):
            content = read(self.dir / filename)
            if content:
                props[prop] = content

        # Concatenated per-platform docs, so the entity page renders them as one tab each.
        for prop, subdir, fname, heading in (
            ("reference_designs", "reference-designs", "reference-design.md", "Reference Design"),
            ("security_blueprints", "security-blueprints", "security-blueprint.md", "Security Blueprint"),
        ):
            chunks = []
            for platform in sorted(self.implementations.keys()):
                doc = read(self.dir / subdir / platform / fname)
                if doc:
                    chunks.append(f"# {platform} — {heading}\n\n{doc}")
            if chunks:
                props[prop] = "\n\n---\n\n".join(chunks)

        self.add("ibb", {
            "identifier": self.name,
            "title": f"{self.name.replace('-', ' ').title()} IBB",
            "properties": props,
            "relations": {
                "capability": self.name,
                "depends_on": list(self.manifest.get("dependencies", []) or []),
            },
        })

    def version_entity(self) -> None:
        status = self.meta.get("status", "draft")
        if status not in MANIFEST_STATUSES:
            self.errors.append(
                f"metadata.status '{status}' is not one of {sorted(MANIFEST_STATUSES)}")
        schemas = self.contract.get("schemas", {}) or {}
        execution = self.contract.get("execution", {}) or {}
        props: dict[str, Any] = {
            "version": self.version,
            "status": status,
            "operations": self.contract.get("operations", []) or [],
        }
        if schemas.get("input"):
            props["input_schema"] = schemas["input"]
            m = re.search(r"-(v\d+)\.schema\.json$", str(schemas["input"]))
            if m:
                props["contract_version"] = m.group(1)
        if schemas.get("output"):
            props["output_schema"] = schemas["output"]
        if schemas.get("error"):
            props["error_schema"] = schemas["error"]
        if "asynchronous" in execution:
            props["asynchronous"] = bool(execution["asynchronous"])
        if execution.get("idempotencyKey"):
            props["idempotency_key"] = execution["idempotencyKey"]
        for prop, filename in (("changelog", "CHANGELOG.md"),
                               ("compatibility_matrix", "VERSIONS.md")):
            content = read(self.dir / filename)
            if content:
                props[prop] = content
        self.add("ibb_version", {
            "identifier": self.vkey,
            "title": self.vkey,
            "properties": props,
            "relations": {"ibb": self.name},
        })

    def docs_and_controls(self) -> None:
        for platform, impl in sorted(self.implementations.items()):
            if platform not in PLATFORMS:
                self.errors.append(
                    f"implementation platform '{platform}' is not one of {sorted(PLATFORMS)}")

            trd = read(self.dir / "reference-designs" / platform / "reference-design.md")
            if trd:
                self.add("ibb_reference_design", {
                    "identifier": f"{self.name}-{platform}-trd@{self.version}",
                    "title": f"{self.name} — {platform} TRD",
                    "properties": {
                        "version": self.version,
                        "status": header_field(trd, "Status") or "draft",
                        "platform": platform,
                        "technology": impl.get("technology"),
                        "owner": header_field(trd, "Owner") or self.meta.get("owner"),
                        "document_path": impl.get("referenceDesign"),
                        "content": trd,
                    },
                })

            sbp = read(self.dir / "security-blueprints" / platform / "security-blueprint.md")
            if not sbp:
                continue
            sbp_id = f"{self.name}-{platform}-sbp@{self.version}"
            self.add("ibb_security_blueprint", {
                "identifier": sbp_id,
                "title": f"{self.name} — {platform} SBP",
                "properties": {
                    "version": self.version,
                    "status": header_field(sbp, "Status") or "draft",
                    "platform": platform,
                    "scope": header_field(sbp, "Scope") or f"{self.name} on {platform}",
                    "paired_trd": header_field(sbp, "Paired Technical Reference Design"),
                    "owner": header_field(sbp, "Owner") or self.meta.get("owner"),
                    "document_path": impl.get("securityBlueprint"),
                    "content": sbp,
                },
            })

            controls = parse_control_table(
                sbp, self.dir / "security-blueprints" / platform / "security-blueprint.md")
            if not controls:
                self.errors.append(f"{platform}: security blueprint has no parseable controls")
            for c in controls:
                for field, allowed in (("domain", CONTROL_DOMAINS),
                                       ("priority", CONTROL_PRIORITIES),
                                       ("status", CONTROL_STATUSES)):
                    if c[field] not in allowed:
                        self.errors.append(
                            f"control {c['id']}: {field} '{c[field]}' is not in the blueprint "
                            f"enum {sorted(allowed)} — add it to ibb_security_control or fix the table")
                if not c["verification_method"]:
                    self.errors.append(
                        f"control {c['id']}: no verification method (SEC-002 — unpublishable)")
                self.add("ibb_security_control", {
                    "identifier": c["id"],
                    "title": f"{c['id']} — {summarise(c['requirement'], 52)}",
                    "properties": {
                        "domain": c["domain"],
                        "priority": c["priority"],
                        "status": c["status"],
                        "requirement": c["requirement"],
                        "rationale": c["rationale"],
                        "verification_method": c["verification_method"],
                        "verification_stage": verification_stages(c["verification_method"]),
                        "mandatory": c["priority"] in ("Critical", "High"),
                    },
                    "relations": {"security_blueprint": sbp_id},
                })

    def implementation_entities(self) -> None:
        mapping = self.manifest.get("requirementMapping", {}) or {}
        for platform, impl in sorted(self.implementations.items()):
            iac_path = impl.get("iac")
            props: dict[str, Any] = {
                "platform": platform,
                "technology": impl.get("technology"),
                "iac_path": iac_path,
            }
            if "approved" in impl:
                props["approved"] = bool(impl["approved"])
            if iac_path and (self.dir / iac_path).is_dir():
                props["iac_framework"] = "terraform" if list(
                    (self.dir / iac_path).glob("*.tf")) else None
                versions_tf = read(self.dir / iac_path / "versions.tf") or ""
                # An uncommented backend block means state is not on local disk (SEC-008).
                props["backend_configured"] = bool(
                    re.search(r"^\s*backend\s+\"", versions_tf, re.M))
            policy_dir = self.dir / "policies" / platform
            if policy_dir.is_dir():
                rego = sorted(policy_dir.glob("*.rego"))
                if rego:
                    props["policy_path"] = str(rego[0].relative_to(self.dir).as_posix())
            if mapping.get(platform):
                props["requirement_mapping"] = mapping[platform]
            props = {k: v for k, v in props.items() if v is not None}

            relations = {"ibb_version": self.vkey, "ibb": self.name}
            if (self.dir / "reference-designs" / platform / "reference-design.md").is_file():
                relations["reference_design"] = f"{self.name}-{platform}-trd@{self.version}"
            if (self.dir / "security-blueprints" / platform / "security-blueprint.md").is_file():
                relations["security_blueprint"] = f"{self.name}-{platform}-sbp@{self.version}"

            self.add("ibb_implementation", {
                "identifier": f"{self.vkey}/{platform}",
                "title": f"{self.vkey} — {platform}",
                "properties": props,
                "relations": relations,
            })

    def pipeline_entity(self) -> None:
        for engine in ("github-actions", "jenkins"):
            pipeline_dir = self.dir / "pipelines" / engine
            if not pipeline_dir.is_dir():
                continue
            files = sorted(list(pipeline_dir.glob("*.yml")) + list(pipeline_dir.glob("*.yaml")))
            if not files:
                continue
            body = read(files[0]) or ""
            lowered = body.lower()
            self.add("ibb_pipeline", {
                "identifier": f"{self.name}-{engine}@{self.version}",
                "title": f"{self.name} pipeline ({engine})",
                "properties": {
                    "version": self.version,
                    "engine": engine,
                    "status": self.meta.get("status", "draft"),
                    "definition_path": str(files[0].relative_to(self.dir).as_posix()),
                    "has_preapply_policy_gate": "conftest" in lowered or "opa " in lowered,
                    "has_postapply_verification": "verify" in lowered,
                    "emits_evidence": "evidence" in lowered,
                    "propagates_correlation_id": "correlationid" in lowered.replace("_", ""),
                    "stages": [
                        m.group(1).strip()
                        for m in re.finditer(r"^\s*-\s*name:\s*(.+?)\s*$", body, re.M)
                    ],
                },
                "relations": {"ibb_version": self.vkey},
            })

    def policy_entities(self) -> None:
        policies_root = self.dir / "policies"
        if not policies_root.is_dir():
            return
        for platform_dir in sorted(p for p in policies_root.iterdir() if p.is_dir()):
            platform = platform_dir.name
            for rego in sorted(platform_dir.glob("*.rego")):
                text = rego.read_text(encoding="utf-8")
                rule_count, control_ids = parse_rego(text)
                package = None
                pm = re.search(r"^\s*package\s+(\S+)", text, re.M)
                if pm:
                    package = pm.group(1)
                self.add("ibb_policy", {
                    "identifier": f"{self.name}-{platform}-policy",
                    "title": f"{self.name} — {platform} policy",
                    "properties": {
                        "platform": platform,
                        "engine": "conftest",
                        "stage": "pre-apply",
                        "package_name": package,
                        "file_path": str(rego.relative_to(self.dir).as_posix()),
                        "rule_count": rule_count,
                        "content": f"```rego\n{text}\n```",
                    },
                    "relations": {
                        "ibb": self.name,
                        "implementation": f"{self.vkey}/{platform}",
                        "enforces_controls": control_ids,
                    },
                })

    def requirement_properties(self, dictionary: Path | None) -> None:
        if dictionary is None or not dictionary.is_file():
            return
        doc = yaml.safe_load(dictionary.read_text(encoding="utf-8")) or {}
        for category, cat_body in (doc.get("categories", {}) or {}).items():
            if category not in REQUIREMENT_CATEGORIES:
                self.errors.append(f"requirement category '{category}' is outside the fixed five")
            for prop_name, spec in ((cat_body or {}).get("properties", {}) or {}).items():
                used_by = list(spec.get("usedBy", []) or [])
                if self.name not in used_by:
                    continue  # only sync properties this IBB actually consumes
                props: dict[str, Any] = {
                    "category": category,
                    "property_name": prop_name,
                    "type": spec.get("type"),
                    "description": spec.get("description"),
                }
                if spec.get("enum"):
                    props["allowed_values"] = spec["enum"]
                if spec.get("minimum") is not None:
                    props["minimum"] = spec["minimum"]
                self.add("ibb_requirement_property", {
                    "identifier": f"{category}.{prop_name}",
                    "title": f"{category}.{prop_name}",
                    "properties": {k: v for k, v in props.items() if v is not None},
                    "relations": {"used_by": used_by},
                })

    def self_service_actions(self) -> None:
        actions_dir = self.dir / "actions"
        if not actions_dir.is_dir():
            return
        for path in sorted(actions_dir.glob("*.json")):
            try:
                action = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                self.errors.append(f"actions/{path.name}: not valid JSON ({exc})")
                continue
            if not action.get("identifier"):
                self.errors.append(f"actions/{path.name}: missing 'identifier'")
                continue
            if not action.get("trigger"):
                self.errors.append(f"actions/{path.name}: missing 'trigger'")
                continue
            if not action.get("invocationMethod"):
                self.errors.append(f"actions/{path.name}: missing 'invocationMethod'")
                continue
            self.actions.append(action)

    def build(self, dictionary: Path | None) -> None:
        self.capabilities()
        self.building_block()
        self.version_entity()
        self.docs_and_controls()
        self.implementation_entities()
        self.pipeline_entity()
        self.policy_entities()
        self.requirement_properties(dictionary)
        self.self_service_actions()


# --------------------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description="Sync an IBB directory into the Port catalog.")
    ap.add_argument("--ibb-dir", required=True, type=Path,
                    help="Path to the <capability>-ibb directory containing ibb-manifest.yaml")
    ap.add_argument("--requirement-dictionary", type=Path, default=None,
                    help="Path to requirement-properties.yaml "
                         "(default: <ibb-dir>/../requirement-dictionary/requirement-properties.yaml)")
    ap.add_argument("--lifecycle-stage", default="pilot",
                    choices=["pilot", "general-availability", "deprecated", "retired"],
                    help="Not derivable from the manifest; defaults to pilot")
    ap.add_argument("--dry-run", action="store_true",
                    help="Parse and validate, print the plan, send nothing")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="Print each entity payload")
    args = ap.parse_args()

    ibb_dir = args.ibb_dir.resolve()
    if not ibb_dir.is_dir():
        sys.exit(f"No such directory: {ibb_dir}")

    dictionary = args.requirement_dictionary
    if dictionary is None:
        guess = ibb_dir.parent / "requirement-dictionary" / "requirement-properties.yaml"
        dictionary = guess if guess.is_file() else None

    sync = IbbSync(ibb_dir, args.lifecycle_stage, args.verbose)
    sync.build(dictionary)

    if sync.errors:
        print("Validation problems found in the IBB:\n")
        for err in sync.errors:
            print(f"  - {err}")
        print("\nFix these in the IBB (or extend the blueprint enums) and re-run.")
        return 1

    counts: dict[str, int] = {}
    for blueprint, _ in sync.plan:
        counts[blueprint] = counts.get(blueprint, 0) + 1
    print(f"{ibb_dir.name}: {len(sync.plan)} entities across {len(counts)} blueprints")
    for blueprint, n in counts.items():
        print(f"  {blueprint:<28} {n}")
    if sync.actions:
        print(f"  {'self-service actions':<28} {len(sync.actions)}")

    if args.dry_run:
        if args.verbose:
            print()
            for blueprint, entity in sync.plan:
                print(f"--- {blueprint} / {entity['identifier']}")
                print(json.dumps(entity, indent=2)[:2000])
            for action in sync.actions:
                print(f"--- action / {action['identifier']}")
                print(json.dumps(action, indent=2)[:2000])
        print("\nDry run — nothing sent.")
        return 0

    load_dotenv(ibb_dir)
    client_id = os.environ.get("PORT_CLIENT_ID")
    client_secret = os.environ.get("PORT_CLIENT_SECRET")
    if not client_id or not client_secret:
        sys.exit(
            "PORT_CLIENT_ID and PORT_CLIENT_SECRET must be set (in .env or the environment).\n"
            "Get them from Port → Organization → Credentials."
        )
    base_url = (os.environ.get("PORT_API_BASE_URL") or DEFAULT_API).rstrip("/")
    if not base_url.endswith("/v1"):
        base_url += "/v1"

    client = PortClient(base_url, client_id, client_secret, dry_run=False)
    print(f"\nUpserting to {base_url} ...")
    for blueprint, entity in sync.plan:
        client.upsert(blueprint, entity)
        print(f"  ok  {blueprint:<28} {entity['identifier']}")
        if args.verbose:
            print(json.dumps(entity, indent=2)[:2000])

    for action in sync.actions:
        client.upsert_action(action)
        print(f"  ok  {'action':<28} {action['identifier']}")
        if args.verbose:
            print(json.dumps(action, indent=2)[:2000])

    print(f"\nDone. {len(sync.plan)} entities upserted, {len(sync.actions)} actions upserted.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
