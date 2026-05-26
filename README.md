# community-brain-distribution

A self-host Tier B distribution of the Community Brain retrieval system: search and ask questions over a curated coaching-call corpus on your own machine.

## What this is

- A Docker Compose stack: a retrieval-server (LanceDB-backed search API) + Open WebUI (chat UI).
- A pre-built corpus blob downloaded from this repo's GitHub Releases.
- A filter for Open WebUI that injects retrieval results into your chat.

Recipients run everything locally. No data leaves your machine.

## Quick start

1. Read [`INSTALL.md`](./INSTALL.md).
2. If you use an AI coding assistant (Claude Code, Codex, Cursor, etc.), point it at `INSTALL.md` and say "follow this on my machine."

## Operator

This repo is the cooked-product face of [RecapFlow-automation](https://github.com/hopchouinard/RecapFlow-automation). Source code, Python package, and release tooling live there.

## License

[TBD by operator — replace this section with chosen license terms.]
