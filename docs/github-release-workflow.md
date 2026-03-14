# GitHub Release Workflow

## Purpose
- Build a GitHub release ZIP that contains only runtime addon files required by WoW.
- Use the version declared in `ItemScore.toc` as the release version source of truth.
- Prevent release builds unless `## Version:` was increased.

## Workflow File
- `.github/workflows/release-addon.yml`

## Trigger and Gate
- Trigger: push to `main` or `master` when `ItemScore.toc` changes.
- Gate: compare current `## Version:` against the version from the pre-push commit (`github.event.before`).
- Release job runs only when current version is strictly higher (`sort -V` comparison).

## Packaging Rules
- Package root inside ZIP: `ItemScore/`.
- Always include `ItemScore.toc`.
- Include only files declared in `ItemScore.toc` (non-empty, non-comment lines).
- Fail build if a listed runtime file is missing.
- Excludes docs and development files by construction.

## Release Output
- ZIP name: `ItemScore-v<version>.zip`
- GitHub tag: `v<version>`
- GitHub release name: `ItemScore v<version>`
- Release action updates an existing release/tag with the same version if rerun.
