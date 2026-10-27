# Security Policy

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.

Email <inquiry@skaiworldwide.com> with "AgensGraph security" in the subject
line. Please include:

- A description of the vulnerability and what an attacker could do with it
- The AgensGraph version (`SELECT version();`) and how it was installed
- Steps to reproduce, ideally a minimal SQL/Cypher script
- Any proof-of-concept code, logs, or configuration needed to reproduce it

We will acknowledge your report and keep you informed as we investigate. Please
give us a reasonable time to release a fix before disclosing the issue
publicly.

## Scope

This policy covers AgensGraph itself. AgensGraph is based on PostgreSQL; if the
vulnerability is in unmodified PostgreSQL code and affects PostgreSQL as well,
please report it to the
[PostgreSQL security team](https://www.postgresql.org/support/security/) so
that all downstream projects are covered.

Fixes are released in a new AgensGraph version. See
[Releases](https://github.com/skaiworldwide-oss/agensgraph/releases) for the
current version.
