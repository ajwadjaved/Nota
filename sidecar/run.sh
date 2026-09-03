#!/usr/bin/env bash
# Start the Tier 3 sidecar.
#
#   ./run.sh              # the configured model
#   ./run.sh --stub       # no weights, for testing the wiring
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${HERE}/.venv"
CA_BUNDLE="${VENV}/nota-ca.pem"

[[ -x "${VENV}/bin/python" ]] || {
  echo "No virtualenv. Run sidecar/setup.sh first." >&2
  exit 1
}

if [[ "${1:-}" == "--stub" ]]; then
  export NOTA_MODEL=stub
fi

# Only needed if the weights are not cached yet and Python has to fetch them;
# see the certificate note in README.md.
[[ -f "$CA_BUNDLE" ]] && export SSL_CERT_FILE="$CA_BUNDLE"

exec "${VENV}/bin/python" "${HERE}/server.py"
