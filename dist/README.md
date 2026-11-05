Files shipped beside the exported binary, copied on top of the export by packaging/package.py:

- `common/`  → both platforms: README.md, licenses/ (fonts), tools/ and rebuilds/ readmes
- `windows/` → Windows only: tools/ffmpeg.exe, rebuilds/<game>/ packages
- `linux/`   → Linux only: tools/ffmpeg (static build), rebuilds/<game>/ packages

ffmpeg and the rebuild/Enhanced packages are git-ignored (binaries and game-derived
files don't belong in a public repo). Local builds pick them up from here; CI builds
ship without them until a fetch step is added to release.yml.
