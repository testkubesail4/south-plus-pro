# Changelog

South Plus Pro keeps release notes in `docs/releases/`. The release workflow uses the matching file for each tag, then appends downloads, checksums, and commit history automatically.

## Releases

- [v0.1.11](docs/releases/v0.1.11.md)
- [v0.1.9](docs/releases/v0.1.9.md)
- [v0.1.10](docs/releases/v0.1.10.md)
- [v0.1.8](docs/releases/v0.1.8.md)
- [v0.1.7](docs/releases/v0.1.7.md)
- [v0.1.6](docs/releases/v0.1.6.md)
- [v0.1.4](docs/releases/v0.1.4.md)
- [v0.1.3](docs/releases/v0.1.3.md)
- [v0.1.2](docs/releases/v0.1.2.md)

## Release Note Template

Create `docs/releases/vX.Y.Z.md` before pushing tag `vX.Y.Z`:

```md
# vX.Y.Z

## Added

- New user-facing behavior.

## Improved

- Existing behavior that became better or clearer.

## Fixed

- Bugs fixed in this release.

## Release

- Android ARM64, ARMv7, x86_64, universal APK, AAB, iOS sideload IPA, Windows x64, and SHA256 checksums are built by the release workflow.
```
