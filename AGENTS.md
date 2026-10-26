# Release preference

The user wants every new version published to GitHub Releases automatically.
For version changes, increment the marketing version and build in `project.yml`
and push the source. Create the version tag at that source commit using the
GitHub refs API before publication (the runner token may not tag older commits). The native build and release workflows then compile,
validate, and publish the IPA, manifest, and checksum under the version tag.
Verify that publication succeeded before reporting the version as released.

Development IPAs are unsigned prereleases. Preserve the signing/JIT requirements
and actual device-validation status in release notes. Never replace a published
version with different source or binaries; bump the version instead. If GitHub
blocks publication, report the concrete error and available build download.
