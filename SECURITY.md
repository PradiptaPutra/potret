# Security Policy

## Supported versions

Only the latest release of Potret receives security fixes.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub's [private vulnerability reporting](https://github.com/PradiptaPutra/potret/security/advisories/new)
(Security → Report a vulnerability). Include:

- what you found and where (file / command / window),
- steps to reproduce or a proof of concept,
- the impact you think it has.

You'll get a response as soon as possible. Once a fix is ready, it ships in the
next release and the advisory is published with credit (unless you prefer to stay
anonymous).

## Scope notes

Potret is a local macOS app — it has no backend and loads no remote content. The
most relevant areas are the Tauri command boundary (`src-tauri/src/lib.rs`), file
writes (save / history / drag-out), and clipboard/`screencapture` handling.
