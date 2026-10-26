Native emulator artifacts belong here. They are deliberately not fetched at app
runtime. The setup/build scripts pin source revisions; the native project embeds
and signs its core dependencies at build time. See ../docs/BUILDING.md.
