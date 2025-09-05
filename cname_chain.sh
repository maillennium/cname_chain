#!/usr/bin/env bash
# cname_chain.sh — Show CNAMEs for a domain and recursively follow the chain.
# Usage:
#   ./cname_chain.sh example.com
#   ./cname_chain.sh -s example.com        # also checks common subdomains
#   ./cname_chain.sh -w wordlist.txt example.com  # checks subdomains from file
#
# Requires: dig (bind-utils)

set -euo pipefail

COMMON_SUBS=(www mail ftp api dev test staging m mx cdn blog shop portal vpn owa autodiscover _sip._tls _sipfederationtls._tcp)

usage() {
  cat <<EOF
Usage: $0 [-s] [-w wordlist] <domain>
  -s              Also check a built-in list of common subdomains
  -w wordlist     File with subdomains to check (one per line)
Examples:
  $0 example.com
  $0 -s example.com
  $0 -w subs.txt example.com
EOF
}

have_dig() { command -v dig >/dev/null 2>&1; }

if ! have_dig; then
  echo "ERROR: 'dig' not found. Install bind-utils or dnsutils." >&2
  exit 1
fi

CHECK_SUBS=0
WORDLIST=""
while getopts ":sw:" opt; do
  case "$opt" in
    s) CHECK_SUBS=1 ;;
    w) WORDLIST="$OPTARG" ;;
    *) usage; exit 1 ;;
  endac
done
shift $((OPTIND-1))

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then usage; exit 1; fi

# Query helper: return ANSWER section for a given name/type or empty
dig_answer() {
  local name="$1" rtype="${2:-ANY}"
  # +nocomments +noauthority +noadditional keeps output clean
  dig +noall +answer "$name" "$rtype"
}

# Get RCODE; 0=NOERROR, 3=NXDOMAIN, etc.
dig_rcode() {
  local name="$1"
  dig +noall +comments "$name" ANY | awk '/status:/{print $6}' | tr -d ','
}

# Resolve CNAME chain for a single FQDN
resolve_chain() {
  local name="$1"
  local -A seen=()                  # loop detection
  local depth=0 max_depth=25

  echo "=== $name ==="

  # First: show any direct CNAME(s)
  local direct_cnames
  direct_cnames="$(dig_answer "$name" CNAME || true)"
  if [[ -n "$direct_cnames" ]]; then
    echo "Direct CNAME(s):"
    echo "$direct_cnames"
  else
    echo "Direct CNAME(s): none"
  fi

  # Follow: loop until A/AAAA or no CNAME
  local current="$name"
  while (( depth < max_depth )); do
    ((depth++))
    if [[ -n "${seen[$current]:-}" ]]; then
      echo "Loop detected at: $current  (chain already visited)"
      return 0
    fi
    seen[$current]=1

    # If we already have final records, print and break
    local aaaa a
    aaaa="$(dig_answer "$current" AAAA || true)"
    a="$(dig_answer "$current" A || true)"
    if [[ -n "$a$aaaa" && -z "$(dig_answer "$current" CNAME || true)" ]]; then
      echo "Terminal records for $current:"
      [[ -n "$aaaa" ]] && echo "$aaaa"
      [[ -n "$a"    ]] && echo "$a"
      break
    fi

    # If there is a CNAME, step to target (pick first if multiple)
    local cname_line
    cname_line="$(dig_answer "$current" CNAME | head -n1 || true)"
    if [[ -n "$cname_line" ]]; then
      # Format: "<name>. <TTL> IN CNAME <target>."
      local target
      target="$(awk '{print $5}' <<<"$cname_line")"
      # strip trailing dot
      target="${target%.}"
      echo "[$depth] $current  ->CNAME->  $target"
      current="$target"
      continue
    fi

    # No CNAME; check status
    local rcode
    rcode="$(dig_rcode "$current")"
    case "$rcode" in
      NOERROR)
        if [[ -z "$a$aaaa" ]]; then
          echo "No A/AAAA found for $current (but DNS said NOERROR)."
        fi
        ;;
      NXDOMAIN)
        echo "NXDOMAIN for $current"
        ;;
      *)
        echo "Non-success DNS status for $current: $rcode"
        ;;
    esac
    break
  done

  if (( depth >= max_depth )); then
    echo "Max depth ($max_depth) reached; stopping to avoid infinite loop."
  fi
  echo
}

# Main run for the apex
resolve_chain "$DOMAIN"

# Optional: subdomain checks
declare -a subs_to_check=()
if (( CHECK_SUBS == 1 )); then
  subs_to_check+=("${COMMON_SUBS[@]}")
fi
if [[ -n "$WORDLIST" ]]; then
  if [[ ! -f "$WORDLIST" ]]; then
    echo "ERROR: wordlist '$WORDLIST' not found" >&2
    exit 1
  fi
  mapfile -t wl < <(grep -v '^[[:space:]]*$' "$WORDLIST" | sed 's/\r$//')
  subs_to_check+=("${wl[@]}")
fi

if (( ${#subs_to_check[@]} > 0 )); then
  echo "Scanning subdomains (${#subs_to_check[@]}) for CNAME chains…"
  for sub in "${subs_to_check[@]}"; do
    fqdn="${sub}.${DOMAIN}"
    resolve_chain "$fqdn"
  done
fi
