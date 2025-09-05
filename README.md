## cname_chain
prints any direct CNAME(s) for a name, recursively follows CNAME chains until it reaches an A/AAAA (or times out), detects loops and NXDOMAIN, optionally checks a small list of common subdomains and follows chains for each.

## ./cname_scan_stream.sh

Usage: ./cname_scan_stream.sh [-w wordlist] [-P jobs] [-t timeout] [-r tries] [-a] <domain>

  -w wordlist   File with labels or FQDNs (one per line; # = comment)
  
  -P jobs       Parallel workers for xargs (default: 1)

  -t timeout    dig per-query timeout seconds (default: 2)
  
  -r tries      dig tries (default: 1)
  
  -a            Print all queries, not just positives
  
Examples:

  ./cname_scan_stream.sh -w subs.txt example.com
  
  ./cname_scan_stream.sh -w subs.txt -P 16 example.com
  
  ./cname_scan_stream.sh -w subs.txt -P 16 -a -t 1 -r 1 example.com
