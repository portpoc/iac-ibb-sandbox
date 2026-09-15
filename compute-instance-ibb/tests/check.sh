#!/usr/bin/env bash
# Local sanity checks for the Compute Instance IBB — schema validation of manifest and
# example/test fixtures. This is a developer convenience, NOT a substitute for the automated
# G1/G2 CI validation gate required by TST-003 (lint, secret scanning, SAST, IaC scan, policy
# conformance, unit/integration/contract tests) which must run on every pull request.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Validating ibb-manifest.yaml is present and parseable =="
python3 -c "import yaml,sys; yaml.safe_load(open('ibb-manifest.yaml'))"

echo "== Validating example/test request fixtures against the input schema =="
for f in tests/requests/*.json examples/*.json; do
  [ -e "$f" ] || continue
  echo "  - $f"
  python3 - "$f" <<'PY'
import json, sys
import jsonschema
schema = json.load(open("schemas/compute-instance-input-v1.schema.json"))
instance = json.load(open(sys.argv[1]))
jsonschema.validate(instance, schema)
PY
done

echo "OK"
