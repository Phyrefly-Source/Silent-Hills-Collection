Files shipped beside the exported binary, copied on top of the export:

- `common/`  → both platforms (README.md, licenses/, rebuilds/ manifests)
- `windows/` → Windows only (tools/ffmpeg.exe)
- `linux/`   → Linux only (tools/ffmpeg, static build)

Large binaries like ffmpeg are git-ignored.
