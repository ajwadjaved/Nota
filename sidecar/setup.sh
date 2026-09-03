#!/usr/bin/env bash
# Prepare the Python sidecar: virtualenv, MLX, and a CA bundle that trusts
# whatever the host Mac trusts. Safe to re-run.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${HERE}/.venv"
CA_BUNDLE="${VENV}/kuroko-ca.pem"
MODEL="${KUROKO_MODEL:-mlx-community/Qwen3.8-27B-4bit}"

say() { printf '\033[38;5;108m%s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m%s\033[0m\n' "$*"; }
die() {
  printf '\033[38;5;167m%s\033[0m\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "The sidecar is macOS only."
[[ "$(uname -m)" == "arm64" ]] || die "MLX needs Apple Silicon."

command -v uv >/dev/null || die "uv not found. Run: brew install uv"

# ── Environment ───────────────────────────────────────────────────────────
say "Creating virtualenv..."
uv venv --allow-existing --python 3.12 "$VENV" >/dev/null

say "Installing MLX..."
uv pip install --quiet --python "${VENV}/bin/python" -r "${HERE}/requirements.txt"

# ── Certificates ──────────────────────────────────────────────────────────
# Python ships its own CA list (certifi) and ignores the system keychain, so on
# any network doing TLS inspection every HTTPS call from Python fails with
# CERTIFICATE_VERIFY_FAILED while curl and the browser work fine. Appending the
# machine's own trusted roots to certifi's bundle fixes that without disabling
# verification, which would be the wrong trade entirely.
say "Building CA bundle..."
{
  "${VENV}/bin/python" -c "import certifi; print(open(certifi.where()).read())"
  security find-certificate -a -p /Library/Keychains/System.keychain
  security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain
} >"$CA_BUNDLE"
say "  $(grep -c 'BEGIN CERT' "$CA_BUNDLE") certificates"

# ── Reachability ──────────────────────────────────────────────────────────
# Weights come from a different host than the API, and corporate proxies
# routinely allow the second and block the first. Diagnosing that through a
# Python traceback is miserable, so check it here and say so plainly.
export SSL_CERT_FILE="$CA_BUNDLE"

api_ok=false
cdn_ok=false

curl -fsI --max-time 15 https://huggingface.co >/dev/null 2>&1 && api_ok=true

probe_url="https://huggingface.co/${MODEL}/resolve/main/config.json"
curl -fsL --max-time 20 -o /dev/null "$probe_url" 2>/dev/null && cdn_ok=true

weights_status=$(
  curl -sL --max-time 25 -o /dev/null -w '%{http_code}' -r 0-1023 \
    "https://huggingface.co/${MODEL}/resolve/main/model-00001-of-00003.safetensors" 2>/dev/null || echo 000
)

echo
if ! $api_ok; then
  warn "huggingface.co is unreachable. Check the network before going further."
elif [[ "$weights_status" == "200" || "$weights_status" == "206" ]]; then
  say "Hub and CDN both reachable."
  echo
  say "Fetch the model (about 16 GB):"
  echo "  SSL_CERT_FILE=$CA_BUNDLE \\"
  echo "    ${VENV}/bin/hf download $MODEL"
else
  warn "The Hub API is reachable but the weights CDN is not (HTTP ${weights_status})."
  warn "Model files are served from a separate host, commonly:"
  warn "  us.aws.cdn.hf.co, cas-server.xethub.hf.co"
  warn ""
  warn "A filtering proxy that allows huggingface.co and blocks those hosts"
  warn "produces exactly this. Fetch the weights on an unfiltered network, or"
  warn "have the hosts allowed; once cached under ~/.cache/huggingface the"
  warn "sidecar never needs the network again."
  $cdn_ok || warn ""
  $cdn_ok || warn "Note: even small file downloads failed, so this may be broader."
fi
