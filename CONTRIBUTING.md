# Contributing

Thanks for helping make Sample Atlas better. Small, focused pull requests are easiest to review and merge.

## Before you start

- Open an issue for anything larger than a bug fix so we can agree on the approach first. The [roadmap](PLAN.md) lists what is planned.
- You need macOS 14 or later and Xcode 15.3+ (Swift 5.10). Run `swift test` before opening a pull request.
- Never commit audio files, catalog databases, model weights, credentials, or absolute paths from your machine. `.gitignore` blocks the common cases; please keep it that way.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make the change with tests where behaviour changes (`Tests/AtlasCoreTests`). Filename-parsing changes need example filenames in the tests; use invented or freely redistributable names, not private pack contents.
3. Run `swift test`. If you touched `scripts/` or the workflows, also run `scripts/make-app.sh`.
4. Open the pull request against `main` and fill in the template.

Every pull request must pass the **Test** and **Build macOS app** checks and be approved by the code owner before it can merge; `main` does not accept direct pushes. Reviews look at the whole diff, so avoid unrelated changes, generated files, and new dependencies without a stated reason.

## Style

Match the surrounding code. Keep functions short, prefer the standard library, and add a comment only where the reason for the code is not obvious from reading it.
