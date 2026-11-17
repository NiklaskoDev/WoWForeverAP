# 006 — hotfix: gitleaks job lacks pull-requests read permission

Status: implemented
Version: 0.0.0 → 0.0.1 (proposal only; nothing released yet, fix ships with the next release under `[Unreleased]`)
Gate (fix only · no API/format change · no migration or new dependency · ≤ 3 source files · no critical decision): holds — 1 source file (`.github/workflows/security.yml`), CI config only, restores the intended secret scan; least-privilege read scope, no write scope added

Symptom: on PR #5 the `secrets` job of `.github/workflows/security.yml` fails; `check` in `ci.yml` passes. Present since the workflow came in with the template in the first commit; affects every `pull_request` run.
Repro: any `pull_request` event → `gitleaks/gitleaks-action@v2` calls `GET /repos/{owner}/{repo}/pulls/{n}/commits` → `403 Resource not accessible by integration`, header `x-accepted-github-permissions: pull_requests=read` (job 134338453806, run 44167808715).
Cause: `.github/workflows/security.yml:12-13` — the workflow-level `permissions:` grants only `contents: read`, so `GITHUB_TOKEN` (passed at `:26`) has no `pull-requests` scope; gitleaks-action needs `pull-requests: read` to list PR commits on `pull_request` events (confirmed by: trace — the 403 response names the missing `pull_requests=read` permission).
Fix: `.github/workflows/security.yml:16-18` — add a job-level `permissions:` block to the `secrets` job (between `runs-on`/`timeout-minutes` and `steps`) containing exactly `contents: read` and `pull-requests: read`. Job-level `permissions` replaces the workflow-level block for that job, so `contents: read` must be repeated there (checkout with `fetch-depth: 0` needs it). Leave the workflow-level `permissions: contents: read` and the `dependencies` job unchanged. Same pattern as `.github/workflows/release.yml:24-25` (job-level override).
Regression test: `tests/test_workflows.py` (new) — `test_secrets_job_permissions_are_least_privilege`: load `REPO_ROOT / ".github/workflows/security.yml"` with `yaml.safe_load` (PyYAML from Archipelago's requirements; import `REPO_ROOT` from `tests/conftest.py` or derive it the same way), take `jobs["secrets"]["permissions"]` and assert it equals `{"contents": "read", "pull-requests": "read"}` exactly (so nothing broader or extra). Second assertion in the same test or a separate one: top-level `permissions` still equals `{"contents": "read"}`. Fails on the current file (`secrets` has no `permissions` key → KeyError/assert), passes after the fix. Use `.get("permissions")` and assert so the failure is an assertion, not an error.

Affected — changed symbols, their direct callers/readers, shared data they write:
| Part | Covered by |
|---|---|
| `security.yml` job `secrets` permissions | `tests/test_workflows.py` (new) |
| `security.yml` workflow-level permissions (unchanged, must stay `contents: read`) | `tests/test_workflows.py` (new, second assertion) |
| `security.yml` job `secrets` run on `pull_request` / `push` / `schedule` | manual: PR #5 CI run — `secrets` job green (the PR's CI run counts) |
| `security.yml` job `dependencies` (untouched, inherits workflow-level) | manual: PR #5 CI run — job result unchanged |
| `ci.yml`, `release.yml` | not affected — each has its own `permissions` block; no shared/reusable permission config |

Decisions for the programmer: none
Follow-ups: `security.yml:23` comment notes organisations need a `GITLEAKS_LICENSE` secret — only relevant if the repo moves to an org account; not done here.
