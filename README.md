# cname_chain
prints any direct CNAME(s) for a name,  recursively follows CNAME chains until it reaches an A/AAAA (or times out),  detects loops and NXDOMAIN,  optionally checks a small list of common subdomains and follows chains for each.
