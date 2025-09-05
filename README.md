# cname_chain
prints any direct CNAME(s) for a name,
recursively follows CNAME chains until it reaches an A/AAAA (or times out),
detects loops and NXDOMAIN,
optionally checks a small list of common subdomains and follows chains for each.

# How to use
chmod +x cname_chain.sh

# Basic: show direct CNAME(s) and follow chain
./cname_chain.sh example.com

# Also scan a built-in list of common subdomains
./cname_chain.sh -s example.com

# Scan custom subdomains from a wordlist (one per line)
./cname_chain.sh -w subs.txt example.com
