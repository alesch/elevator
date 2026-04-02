# CI/CD Pipeline Guide

This document explains how we automate the testing and deployment of the elevator project.

## 1. Local Development

Before you push code to GitHub, you should run the following command to make sure everything is clean:

```bash
mix ci
```

This single command runs:

- **Formatter**: Makes sure your code style matches the project.
- **Credo**: Checks for common coding mistakes.
- **Audit**: Checks if any of our dependencies have known security bugs.
- **Sobelow**: Scans the code for Phoenix-specific security holes.
- **Dialyzer**: Checks for type errors.
- **Tests**: Runs all automated tests in the `test/` folder.

## 2. GitHub Actions (Automated Checks)

Every time you push code or open a Pull Request, GitHub runs these checks in parallel for speed:

1. **✨ Linting**: Runs `mix format` and `mix credo`.
2. **🛡️ Security**: Runs `mix deps.audit` and `mix sobelow`.
3. **🔍 Static Analysis**: Runs `mix dialyzer` (Type checking).
4. **🧪 Automated Tests**: Runs `mix test`.

**Deployment Block**: If any of these four jobs fail, the project will **not** be deployed to production.

## 3. Shipping to Production

If all the checks above pass, the following happens automatically:

1. **Build Docker Image**: A new production-ready container is built.
2. **Push to GHCR**: The image is stored in the GitHub Container Registry.
3. **Deploy to Fly.io**: Fly.io is notified to pull the new image and restart the app in Stockholm.

## 4. Required Secrets

To make the deployment work, the following secrets must be set in the GitHub repository or Fly.io dashboard:

- `SECRET_KEY_BASE`: Used for encryption.
- `PHX_HOST`: The actual domain (usually `elevator.fly.dev`).
- `FLY_API_TOKEN`: Your API key for Fly.io.

---
**Maintenance**: If you add a new library or tool, make sure to update the `mix ci` alias in `mix.exs`.
