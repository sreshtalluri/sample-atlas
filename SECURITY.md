# Security policy

Sample Atlas runs entirely on your Mac. It reads audio files you add, writes a private catalog under `~/Library/Application Support/Sample Atlas/`, and never uploads audio or metadata. The optional sound-search worker downloads a pinned model once and then runs offline.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private reporting: **Security → Report a vulnerability** on this repository. Include the macOS version, how to reproduce, and what an attacker could gain. You should hear back within a week.

## Supported versions

Only the latest release on the Releases page receives fixes.

## How the repository is protected

- `main` cannot be pushed to directly. Every change arrives as a pull request that must pass the test and app-build workflows and be approved by the code owner.
- Force pushes and branch deletion on `main` are blocked; history is linear.
- Secret scanning with push protection and Dependabot security updates are enabled; CodeQL scans Swift and Python on every pull request.
- Workflows run with read-only tokens; pull requests from forks never receive secrets, and workflow runs from outside contributors require maintainer approval.
- Release builds are produced by GitHub Actions from tagged commits, and the bundled `uv` binaries are fetched from a pinned release with verified SHA-256 checksums.
