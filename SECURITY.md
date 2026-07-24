# Security Policy

## Supported versions

Uncork is early-access software. Only the latest `main` and the most recent release
receive fixes.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Instead, use GitHub's
private vulnerability reporting on this repository (the **Security** tab, "Report a
vulnerability"), or contact a maintainer directly.

Include what you found, how to reproduce it, and the impact. We will acknowledge the
report, investigate, and keep you updated on a fix.

## Scope notes

Uncork downloads and runs third-party components (Wine engines, graphics backends,
and the Epic/GOG command-line clients). Vulnerabilities in those upstream projects
should be reported to them; we will update the versions Uncork ships once fixes are
available. Issues in how Uncork fetches, verifies, or runs those components are in
scope here.
