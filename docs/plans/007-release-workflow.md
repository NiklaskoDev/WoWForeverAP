# 007 — Release workflow that builds, verifies and attaches the deliverables

Status: approved
Type: feature
Version impact: none — CI/tooling only (`docs/ai/versioning.md`: "Docs/CI/test-only changes need no release"); takes effect with the first release the programmer orders. No tag is pushed by this plan.

## Goal
A pushed `vX.Y.Z[-prN]` tag produces a GitHub release that carries `wow_forever.apworld` and `WoWForeverAP-<version>.zip` (plus `SHA256SUMS`, see D2), built with the same command CI uses, and the release fails before publishing when the tag, `VERSION` and the stamped versions disagree. A dry run (local script, and optionally `workflow_dispatch`, see D1) runs every step except publishing.

Out of scope: performing a release, bumping `VERSION`, editing the `[0.1.0]` stub in `CHANGELOG.md`, Docker images, signing/attestations, uploading anywhere other than the GitHub release, changing `ci.yml` or `docs/ai/*`.

## Reuse
- `tools/build.py` — the build itself (`python tools/build.py`, same line as `scripts/ci.sh:23`); `VERSION_FILE`, `read_version`, `check_version`, `world_version`, `PRERELEASE_SUFFIX`, `BuildError`, `APWORLD_FOLDER`, `ADDON_FOLDERS`, `MANIFEST_NAME`, `VERSION_PLACEHOLDER` are imported, not re-implemented.
- `.github/workflows/ci.yml` via `workflow_call` — the existing reusable test job, unchanged.
- `.github/workflows/release.yml` — kept as the base: tag triggers, prerelease detection, CHANGELOG notes semantics, `gh release create --verify-tag`, `env:`-only expression passing.
- `tests/test_workflows.py` — same `yaml.safe_load` assertion pattern as for `security.yml`; `tests/test_build.py` fixture style (`build.build(tmp_path, version)`).
- New `tools/release_check.py`: nothing existing verifies built zips against a tag; moving the template's inline tag regex and awk notes extraction into Python makes them testable and reuses `build.check_version` instead of a second regex (refactor confined to the code being changed).
- New `scripts/release_dry_run.sh`: the local dry run the request asks for; runs exactly the workflow's commands.

## Code layout
- `tools/release_check.py` — new: tag/VERSION check, artifact verification, checksums, release notes; CLI with subcommands.
- `scripts/release_dry_run.sh` — new: local dry run (no network, no git, no publish).
- `.github/workflows/release.yml` — rewritten as three jobs `test` → `build` → `publish`.
- `tests/test_release_check.py` — new: unit tests of `tools/release_check.py`.
- `tests/test_workflows.py` — extended: pins `release.yml` structure and permissions (module docstring widened accordingly).
- `apworld/wow_forever/docs/setup_en.md` — one sentence on verifying `SHA256SUMS` (only if D2 = a).
- `CHANGELOG.md` — line under `[Unreleased]` → `Added`.

## Data
None.

## Interfaces
`tools/release_check.py` (stdlib only, `import build` like `build.py` imports `gen_addon_data`; Python 3.11-compatible). All failures raise `ReleaseError(RuntimeError)`; `main(argv=None) -> int` prints `error: <msg>` to stderr and returns 1 (same pattern as `build.main`).

- `version_from_tag(tag: str) -> str` — requires leading `v`, returns `check_version(tag[1:])`; `BuildError` is re-raised as `ReleaseError` naming the tag.
- `ensure_tag_matches_version_file(tag: str, version_file: Path = build.VERSION_FILE) -> str` — returns the version; error `tag v1.2.3 does not match VERSION 1.2.2` when they differ (exact compare, so a `-prN` tag needs `-prN` in `VERSION`, as `versioning.md` §Release step 3 implies).
- `is_prerelease(version: str) -> bool` — `build.PRERELEASE_SUFFIX.search(version) is not None`.
- `expected_artifacts(dist: Path, version: str) -> list[Path]` — `[dist / f"{APWORLD_FOLDER}.apworld", dist / f"WoWForeverAP-{version}.zip"]`, same order as `build.build` returns.
- `verify_artifacts(dist: Path, version: str) -> list[Path]` — error when: an expected file is missing; `dist` holds any other file except `SHA256SUMS` and `notes.md`; `wow_forever/archipelago.json` in the apworld has `world_version != build.world_version(version)`; for each folder in `ADDON_FOLDERS`, `<folder>/<folder>.toc` is missing from the addon zip or lacks the line `## Version: <version>`; any `.toc` in the zip still contains `@version@`. Returns `expected_artifacts(...)`.
- `write_checksums(paths: list[Path], out: Path) -> Path` — writes `out` in `sha256sum` format: `<64 hex>  <basename>\n` per path in the given order, `hashlib.sha256` read in chunks (D2 = a only).
- `release_notes(changelog_text: str, version: str) -> str` — lines strictly between the first line starting with `## [<version>]` and the next line starting with `## [` (or EOF); `""` when absent. Same semantics as the template's awk.
- `ensure_notes(notes: str, version: str) -> None` — D4 = a only: final version with empty/whitespace notes → `ReleaseError("CHANGELOG.md has no '## [X.Y.Z]' section with content")`; pre-releases pass.

CLI `python tools/release_check.py <cmd>`:
- `tag <tag>` → `ensure_tag_matches_version_file`; prints `version=<v>` and `prerelease=true|false` (two lines, appended to `$GITHUB_OUTPUT` by the workflow).
- `verify <version> [--dist DIR]` (default `ROOT/dist`) → `verify_artifacts`, then `write_checksums(..., DIR/"SHA256SUMS")` (D2); prints `verified <path>` per file and `wrote <path>`.
- `notes <version> [--changelog FILE] [--out FILE]` (defaults `ROOT/CHANGELOG.md`, `ROOT/dist/notes.md`) → writes the notes file (possibly empty), then `ensure_notes` (D4).

`scripts/release_dry_run.sh [tag]` — `set -euo pipefail`, `cd` to repo root like `ci.sh`; tag defaults to `v` + `VERSION` stripped; runs in order: `release_check.py tag "$tag"`, `rm -rf dist`, `python tools/build.py`, `release_check.py verify "$version"`, `release_check.py notes "$version"`, then prints (echo only) the `gh release create` command the workflow would run with the file list. Never calls `git` or `gh`.

## Security and user data
- No secrets beyond the built-in `GITHUB_TOKEN`.
- Least privilege: workflow default `contents: read`; `build` job `contents: read`; only `publish` gets `contents: write`, and it runs no repository code (no checkout, no Python), only downloads the artifact and calls `gh` (D3). `packages: write` is removed (D5).
- `${{ }}` values reach `run:` only through `env:`, never interpolated into scripts.
- No personal data.

## UI
None.

## Steps
1. `tools/release_check.py` per Interfaces, module docstring in the style of `build.py` (usage lines + what it checks).
2. `scripts/release_dry_run.sh` per Interfaces; executable bit set.
3. Rewrite `.github/workflows/release.yml`:
   - Header comment: keep "pushing the tag IS the release decision"; add one line that a `workflow_dispatch` run is a dry run and never publishes (D1).
   - `on.push.tags`: the two existing patterns unchanged; `on.workflow_dispatch:` (D1).
   - `permissions: {contents: read}`; `concurrency: {group: release-${{ github.ref }}, cancel-in-progress: false}`.
   - `test`: `uses: ./.github/workflows/ci.yml` (unchanged).
   - `build`: `needs: test`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`, `permissions: {contents: read}`, `outputs: {version: ${{ steps.tag.outputs.version }}, prerelease: ${{ steps.tag.outputs.prerelease }}}`. Steps, each with a `name`:
     1. `actions/checkout@v4` (as in `ci.yml`).
     2. `actions/setup-python@v5`, `python-version: '3.12'`.
     3. `id: tag`, name `Check tag against VERSION`: env `EVENT: ${{ github.event_name }}`, `REF_NAME: ${{ github.ref_name }}`; `if [ "$EVENT" = workflow_dispatch ]; then TAG="v$(tr -d '[:space:]' < VERSION)"; else TAG="$REF_NAME"; fi`; `python tools/release_check.py tag "$TAG" >> "$GITHUB_OUTPUT"`.
     4. name `Build`: `run: python tools/build.py` — exactly this line, identical to `scripts/ci.sh`.
     5. name `Verify artifacts`: env `VERSION: ${{ steps.tag.outputs.version }}`; `python tools/release_check.py verify "$VERSION"`.
     6. name `Release notes`: env `VERSION`; `python tools/release_check.py notes "$VERSION"`.
     7. `actions/upload-artifact@v4`: `name: release-files`, `path: dist/`, `if-no-files-found: error`, `retention-days: 7`.
   - `publish`: `needs: build`, `if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')`, `runs-on: ubuntu-latest`, `timeout-minutes: 10`, `permissions: {contents: write}`. Steps:
     1. `actions/download-artifact@v4`: `name: release-files`, `path: release`.
     2. name `Create GitHub release`: env `GH_TOKEN: ${{ github.token }}`, `GH_REPO: ${{ github.repository }}`, `TAG: ${{ github.ref_name }}`, `VERSION: ${{ needs.build.outputs.version }}`, `PRERELEASE: ${{ needs.build.outputs.prerelease }}`. Template logic: `ARGS=(--verify-tag --title "$TAG")`, `--prerelease` when `PRERELEASE = true`, `--notes-file release/notes.md` when it has non-whitespace content else `--generate-notes`. Then `gh release create "$TAG" "${ARGS[@]}" release/wow_forever.apworld "release/WoWForeverAP-$VERSION.zip" release/SHA256SUMS` (drop the last path if D2 = b).
   - Delete the Docker step, the commented "Check version file" block, the "Other build and publish steps" comment and `packages: write` (D5).
4. Tests (below).
5. D2 = a: in `apworld/wow_forever/docs/setup_en.md`, after the line naming the two files, add one sentence: the release also has `SHA256SUMS` to check the downloads (`sha256sum -c SHA256SUMS` on Linux/macOS, `Get-FileHash` in PowerShell).
6. `CHANGELOG.md` `[Unreleased]` → `Added`: "Release workflow: a version tag builds `wow_forever.apworld` and the addon zip, checks that the tag matches `VERSION` and the stamped versions, and attaches both (with `SHA256SUMS`) to the GitHub release; `scripts/release_dry_run.sh` runs the same steps locally without publishing."
7. Verify: `ruff check .`, `pytest`, `bash scripts/ci.sh` (still builds), `bash scripts/release_dry_run.sh`. With the current repo (`VERSION` 0.0.0, no `## [0.0.0]` section) and D4 = a, the dry run is expected to pass tag, build and verify and then stop at the notes step with the D4 error — report that outcome; do not edit `VERSION` or `CHANGELOG.md` sections to make it pass. Never run `git tag`, `git push --tags` or `gh release`.

## Tests
`tests/test_release_check.py` (module fixture builds once with `build.build(out, "1.2.3")` into `tmp_path_factory`, like `test_build.py`; tamper tests copy the files into their own `tmp_path` first):
- `version_from_tag("v1.2.3")` → `"1.2.3"`; `"v1.2.3-pr2"` → `"1.2.3-pr2"`.
- `"1.2.3"`, `"v1.2"`, `"v01.2.3"`, `"v1.2.3-pr0"`, `"v1.2.3-rc1"` → `ReleaseError`.
- `ensure_tag_matches_version_file` with tmp VERSION `1.2.3\n`: `v1.2.3` → `"1.2.3"`; `v1.2.4` → `ReleaseError` naming both; `v1.2.3-pr1` → error.
- `is_prerelease`: `1.2.3` → False, `1.2.3-pr1` → True.
- `verify_artifacts` on a fresh build → both paths, apworld first.
- built as `1.2.3`, verified as `1.2.4` → error (zip missing).
- apworld rewritten with manifest `world_version` `0.0.0` → error.
- addon zip rewritten with one TOC still holding `@version@` → error.
- extra `dist/stray.txt` → error; `dist/SHA256SUMS` and `dist/notes.md` → allowed.
- build `1.2.3-pr1` → verifies (manifest `1.2.3`, TOCs `1.2.3-pr1`).
- `write_checksums` → each line `sha256(file).hexdigest() + "  " + name`, apworld then zip, trailing newline.
- `release_notes`: middle section returned; last section to EOF returned; asking for `1.2.3` does not return the `## [1.2.3-pr1]` section; absent version → `""`.
- `ensure_notes`: final + empty → error; final + content → ok; pre-release + empty → ok.
- `main(["tag", ...])` with a monkeypatched `VERSION_FILE` prints the two `key=value` lines and returns 0; mismatch → returns 1, stderr starts with `error:`.

`tests/test_workflows.py` additions (PyYAML parses the key `on` as boolean `True`: read `workflow[True]`):
- triggers: `workflow[True]["push"]["tags"]` equals the two patterns; keys of `workflow[True]` == `{"push", "workflow_dispatch"}`; `push` has no `branches`.
- workflow `permissions == {"contents": "read"}`.
- `jobs` keys == `{"test", "build", "publish"}`; `test["uses"] == "./.github/workflows/ci.yml"`; `build["needs"] == "test"`; `publish["needs"] == "build"`.
- `build["permissions"] == {"contents": "read"}`; `publish["permissions"] == {"contents": "write"}`.
- `publish["if"]` contains `github.event_name == 'push'`.
- `publish` steps: none `uses` `actions/checkout`, no `run` contains `python`.
- exactly one `build` step has `run.strip() == "python tools/build.py"`, and that line is in `scripts/ci.sh`.
- `build` step order by `name`: `Check tag against VERSION` < `Build` < `Verify artifacts` < `Release notes` < upload step.
- the publish `run` contains `gh release create`, `--verify-tag`, `release/wow_forever.apworld`, `release/WoWForeverAP-$VERSION.zip`, `release/SHA256SUMS`.
- no step in any job contains `docker` (case-insensitive) in `run` or `uses`.
- `ci.yml` triggers still include `workflow_call`.

## Decisions for the programmer
Resolved 2026-11-17: the programmer accepted every recommendation below (D1 workflow_dispatch dry run + local script; D2 attach SHA256SUMS; D3 read-only build job + write-only publish job via upload/download-artifact; D4 fail a final release without its CHANGELOG section; D5 delete the Docker step and `packages: write`).
- D1 Dry run on GitHub — (a) add `workflow_dispatch`: runs test, build, verify and uploads the files as a 7-day workflow artifact, never publishes; usable only after merge to `main` (b) local `scripts/release_dry_run.sh` only. Recommendation: (a) plus the script; it proves the workflow on GitHub's runner before the first real tag.
- D2 Checksums — (a) attach `SHA256SUMS` (stdlib `hashlib`) (b) none (c) additionally GitHub build-provenance attestations (`actions/attest-build-provenance`, needs `id-token: write` and `attestations: write`). Recommendation: (a); (c) adds write scopes and a new action for little gain now.
- D3 Job split — (a) read-only `build` and write-only `publish` that runs no repo code, using `actions/upload-artifact@v4` / `actions/download-artifact@v4` (first-party GitHub actions, new to this repo) (b) one job with `contents: write` that builds and publishes (no new actions, but the write token is live while repo Python runs). Recommendation: (a).
- D4 Final release whose `CHANGELOG.md` has no `## [X.Y.Z]` section — (a) fail before publishing (b) fall back to `--generate-notes` as the template does. Pre-releases use generated notes either way. Recommendation: (a); `versioning.md` §Release step 4 makes the section mandatory, so its absence means the release commit is wrong.
- D5 Template Docker step — (a) delete it with `packages: write` (no Dockerfile; an image does not fit an apworld + addon) (b) keep it dormant behind `hashFiles('Dockerfile')`, which keeps `packages: write`. Recommendation: (a). Asked because it deletes template content.

## Risks / follow-ups
- `CHANGELOG.md` still has the template stub `## [0.1.0] - YYYY-MM-DD` while `VERSION` is `0.0.0`; the first release must resolve that (programmer's call at release time). With D4 = a, a tag without its section fails safely before publishing.
- `docs/ai/versioning.md` CI table says `release.yml` pushes a Docker image "if there is a Dockerfile"; with D5 = a that stops being true. `docs/ai/*` is the shared guideline set, so this plan leaves it; adding a Dockerfile later would need the step back.
- The workflow does not check that the tagged commit is on `main` (`versioning.md` §Release step 6); possible later with `fetch-depth: 0` and `git merge-base --is-ancestor`. Not requested.
- A failed `publish` after a good `build` leaves the tag without a release; per `versioning.md` the tag is not deleted or moved without asking — re-run the failed job from the Actions UI.
- `workflow_dispatch` (D1) appears in the Actions UI only once `release.yml` is on the default branch, so on this branch the local script is the only dry run.
