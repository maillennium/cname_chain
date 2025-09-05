#!/usr/bin/env bash
# Stream-optimized CNAME scanner with optional parallelism.
# Usage:
#   ./cname_scan_stream.sh -w wordlist.txt example.com
#   ./cname_scan_stream.sh -w wordlist.txt -P 16 example.com      # 16-way parallel
#   ./cname_scan_stream.sh -w wordlist.txt -P 16 -a example.com   # print all attempts
#
# Notes:
# - Requires: dig, xargs
# - Recommends a local caching resolver (e.g., unbound) for speed/stability.

set -euo pipefail

JOBS=1           # parallel workers for xargs
TIMEOUT=2        # dig per-query timeout seconds
TRIES=1          # dig tries
PRINT_ALL=0      # -a to print every query (even when no CNAME)
WORDLIST=""
DOMAIN=""

usage() {
  cat <<EOF
Usage: $0 [-w wordlist] [-P jobs] [-t timeout] [-r tries] [-a] <domain>
  -w wordlist   File with labels or FQDNs (one per line; # = comment)
  -P jobs       Parallel workers for xargs (default: 1)
  -t timeout    dig per-query timeout seconds (default: 2)
  -r tries      dig tries (default: 1)
  -a            Print all queries, not just positives
Examples:
  $0 -w subs.txt example.com
  $0 -w subs.txt -P 16 example.com
  $0 -w subs.txt -P 16 -a -t 1 -r 1 example.com
EOF
}

trim() { awk '{$1=$1}1' <<<"${1//$'\r'/}"; }  # strip CRLF and trim

while getopts ":w:P:t:r:a" opt; do
  case "$opt" in
    w) WORDLIST="$OPTARG" ;;
    P) JOBS="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    r) TRIES="$OPTARG" ;;
    a) PRINT_ALL=1 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then usage; exit 1; fi
command -v dig >/dev/null 2>&1 || { echo "ERROR: 'dig' not found."; exit 1; }
command -v xargs >/dev/null 2>&1 || { echo "ERROR: 'xargs' not found."; exit 1; }

# Build a stream of FQDNs to test:
gen_fqdns() {
  if [[ -z "$WORDLIST" ]]; then
    # No wordlist: just test the apex and some common subs
    for s in "" www mail ftp api dev test staging cdn m mx blog shop portal vpn owa autodiscover; do
      [[ -z "$s" ]] && echo "$DOMAIN" || echo "$s.$DOMAIN"
    done
    return
  fi

  if [[ ! -f "$WORDLIST" ]]; then
    echo "ERROR: wordlist '$WORDLIST' not found" >&2
    exit 1
  fi

  # Stream lines, skipping blanks/comments; convert labels → FQDNs
  # NOTE: We don't dedupe 4M entries to avoid high memory; feed as-is.
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue

    # If looks like an absolute FQDN, use as-is; else append DOMAIN.
    if [[ "$line" == *.* ]]; then
      echo "$line"
    else
      echo "$line.$DOMAIN"
    fi
  done < "$WORDLIST"
}

# One-query runner: prints only positives unless -a was given.
query_one() {
  local fqdn="$1"
  # Use +short and CNAME only; fast and quiet
  local ans
  ans="$(dig +time=$TIMEOUT +tries=$TRIES +retry=0 +short CNAME "$fqdn" 2>/dev/null || true)"
  if [[ -n "$ans" ]]; then
    # There may be multiple CNAMEs; print each
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      echo "$fqdn -> $target"
    done <<< "$ans"
  else
    if [[ $PRINT_ALL -eq 1 ]]; then
      echo "$fqdn -> (no CNAME)"
    fi
  fi
}

export -f query_one
export TIMEOUT TRIES PRINT_ALL

# Drive the scan: serial or parallel via xargs -P
if [[ "$JOBS" -gt 1 ]]; then
  # -n1: one fqdn per process; adjust -P to your resolver capacity
  gen_fqdns | xargs -n1 -P "$JOBS" -I{} bash -c 'query_one "$@"' _ {}
else
  # Serial scan
  while IFS= read -r fqdn; do
    query_one "$fqdn"
  done < <(gen_fqdns)
fi
