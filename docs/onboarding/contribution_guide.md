# Contribution Guide

> For full setup instructions, see [setup_env.md](setup_env.md). For code style, see [coding_standards.md](coding_standards.md).

## Workflow

1. Create a feature branch from `main`
2. Make your changes in the relevant component(s)
3. Run the component's test suite and fix any failures
4. Format your code with the appropriate tool (see [coding_standards.md](coding_standards.md))
5. Submit a pull request with a clear description

## PR Checklist

- [ ] Tests pass for all changed components
- [ ] Code is formatted
- [ ] Documentation updated if APIs, protocols, or configuration changed
- [ ] Commit messages prefixed with component name (e.g., `gateway: ...`)
- [ ] Signed commits used for protocol or cryptographic changes

## What Needs Review

| Change type                  | Reviewer                            |
| ---------------------------- | ----------------------------------- |
| Protocol or envelope changes | Maintainer (signed commit required) |
| Security / crypto changes    | Maintainer (signed commit required) |
| New API endpoints            | Component owner                     |
| Bug fixes                    | Any contributor                     |
| Documentation                | Any contributor                     |

## Testing Your Changes

```bash
# Gateway
cd quoodle-gateway && python -m pytest tests/ -v

# Control plane
cd quoodle-control-plane && php artisan test

# Full E2E validation
./scripts/run_e2e_full.sh
```

## Protocol Changes

If your change modifies command envelopes, WebSocket messages, IOCTL structures, or authentication flows:

1. Update the relevant spec in `docs/protocols/`
2. Update any affected component READMEs
3. Use signed commits
4. Tag the PR with `protocol-change`
