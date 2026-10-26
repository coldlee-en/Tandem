# GitHub project, Pages, and IPA builds

The repository is ready to publish as a new public project repository, normally
`tandem-ios`. Its Pages site describes the project and its actual development
status. It does not advertise a nonexistent IPA or verified game compatibility.

Publishing requires an authenticated GitHub account with permission to create
the repository, push its workflows, and enable Pages. The publication helper
checks authentication before making changes.

## Publish to the current GitHub account

With Git and an authenticated GitHub CLI installed:

```sh
python3 scripts/publish_github.py
```

This checks authentication before changing anything, creates a new public
`tandem-ios` repository, commits/pushes the source, enables project Pages using
GitHub Actions, and starts both Pages deployment and the native unsigned IPA
build. It uses the authenticated account's GitHub noreply commit address. No
token is printed or stored by the script. A recorded publication can be resumed
from the same checkout. A pre-existing unrelated origin is preserved.

The site deployment and IPA build run independently. Successful dispatch only
means a workflow was queued; check Actions for the actual outcome. In particular,
the experimental native integration may require build fixes on its first Mac
run. The scripts preserve Xcode logs and do not package failed builds.

## GitHub Actions

- **Deploy GitHub Pages** runs on `main` pushes or manual dispatch. It sets the
  site's repository links, then deploys `site/`. The GitHub Pages source must be
  **GitHub Actions**, which the publication script configures.
- **Build unsigned IPA** is manually dispatched with `mode=native` by default.
  It runs on a macOS runner, selects Xcode 26+, installs .NET 8/XcodeGen/Git LFS,
  tests the library, prepares both cores, and archives the actual device app.
- The explicit `interface` mode excludes emulator binaries and has a different
  artifact name. It cannot run games.

After a successful native run, its **Tandem-native-unsigned-IPA** artifact contains
the IPA and build manifest. Re-signing is required before device installation;
Switch still needs a JIT-enabled process. The workflow never claims to provide
an App Store or directly installable signed release. See [IPA.md](IPA.md).

The website keeps release downloads disabled until a real verified release is
available. A published documentation site does not establish native build or
gameplay success. The workflow does not replace a user's existing profile page.
