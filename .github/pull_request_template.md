## Summary

<!-- Brief description of what this PR does -->

## Changes

-

## Type

- [ ] Bug fix
- [ ] New feature
- [ ] Enhancement
- [ ] Refactor
- [ ] Documentation
- [ ] Breaking change

## Testing

- [ ] Tested locally (macOS)
- [ ] Swift builds with no new warnings
- [ ] Python server starts and responds to /health
- [ ] Correction endpoint tested: `curl -s -X POST http://127.0.0.1:9274/v1/correct -H "Content-Type: application/json" -d '{"text":"test text","tone":"neutral"}'`
- [ ] Elaboration endpoint tested (if changed)

## Checklist

- [ ] Code follows existing patterns in the codebase
- [ ] No hardcoded paths or credentials
- [ ] No new `sudo` usage in scripts without justification
- [ ] Commit messages are descriptive
