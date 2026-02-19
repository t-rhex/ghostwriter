# Contributing to Ghostwriter

## Branch Strategy

```
main              ← protected, requires PR + 1 approval
  └── feature/*   ← your work goes here
  └── fix/*       ← bug fixes
  └── release/*   ← protected, release candidates
```

**Never push directly to `main`.** All changes go through pull requests.

## Workflow

1. Create a branch from `main`:
   ```bash
   git checkout main && git pull
   git checkout -b feature/your-feature-name
   ```

2. Make your changes, commit with descriptive messages.

3. Push and open a PR:
   ```bash
   git push -u origin feature/your-feature-name
   gh pr create --title "Add your feature" --body "Description"
   ```

4. Get 1 approval, resolve all review threads, then squash-merge.

## Branch Naming

| Prefix | Use |
|--------|-----|
| `feature/` | New functionality |
| `fix/` | Bug fixes |
| `refactor/` | Code cleanup (no behavior change) |
| `docs/` | Documentation only |
| `release/` | Release preparation |

## Before Submitting a PR

- [ ] `swift build` passes with no new warnings
- [ ] `python3 -m py_compile Server/ghostwriter_server.py` passes
- [ ] Server starts and `/health` returns OK
- [ ] Test your change end-to-end (type in an app, verify correction/elaboration)

## Local Development

```bash
# Build Swift
swift build

# Start Python server
.venv/bin/python3 Server/ghostwriter_server.py

# Test correction
curl -s -X POST http://127.0.0.1:9274/v1/correct \
  -H "Content-Type: application/json" \
  -d '{"text":"Is you sure this works","tone":"neutral"}'

# Test elaboration
curl -s -X POST http://127.0.0.1:9274/v1/elaborate \
  -H "Content-Type: application/json" \
  -d '{"text":"I wanted to let you know that","tone":"neutral"}'
```

## Code Style

- Swift: follow existing patterns, no SwiftLint required
- Python: standard library style, type hints appreciated
- Shell scripts: use `set -euo pipefail`, quote variables
