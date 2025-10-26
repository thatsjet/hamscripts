# Contributing to hamscripts

Thanks for wanting to help! This repository is a collection of small, practical scripts and how-tos for amateur radio operators. Contributions big or small are welcome — add a script, fix a typo, or improve documentation.

## Quick guide

- Fork the repo, create a feature branch, and open a PR against `main`.
- Keep changes focused and small; one logical change per PR makes review fast.
- Reference any related issue in the PR description (e.g., `Fixes #12`).

## Pull request checklist

- [ ] The change is described clearly in the PR body.
- [ ] Files you add live in a sensible folder (for example, `mac_winlink_runner/` for Winlink-related helpers).
- [ ] Scripts include a short header with: purpose, usage, dependencies, and tested platform(s).
- [ ] If you add or change a script, include minimal usage/testing instructions in the README or the script header.
- [ ] Scripts are idempotent where practical — running them twice shouldn't leave your system in a broken state.
- [ ] Follow the repository license: this repo is governed by The Unlicense (see `./LICENSE`).

## Script style & tips

- Shell scripts
  - Use `set -euo pipefail` where appropriate and handle failures gracefully.
  - Prefer `mktemp` for temporary files and track/cleanup PIDs if you spawn background processes.
  - Add comments for non-obvious logic and expected environment variables or hardware (e.g., radio model, serial port).
  - Run `shellcheck` before submitting bash/sh scripts. It catches many common issues.

- Cross-platform notes
  - If a script is macOS-specific, mark it in the header. If it should work on Linux too, test both and note any differences.

## Testing

- Add minimal steps in the README or script header for how you tested the change (e.g., manual steps, commands run, observed behavior).
- Automated tests aren't required, but if you add them, keep them fast and document how to run them.

## Commit messages

- Keep commits small and focused. Use present-tense, short summary lines (e.g., `Add winlink_runner start/stop helper`).

## Reporting issues

- Open an issue with a clear title and reproduction steps. If you're reporting a bug in a script, include the OS, shell, and relevant hardware or connection details.

## Review process

- Maintainers will try to review PRs quickly. Please respond to review comments and update your branch as needed.

## Thanks and 73

Thanks for contributing — your help keeps these scripts useful and friendly. 73 and enjoy the airwaves!
