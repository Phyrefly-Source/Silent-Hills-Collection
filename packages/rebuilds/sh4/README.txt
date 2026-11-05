Silent Hill 4 Enhanced package.

To make it live:
  1. copy the built dsound.dll from E:\Games\Silent Hill 4 into files\
     (only the DLL: SH4Enhanced.cfg is the patch's own settings file and must NOT be in the payload)
  2. set "version" in manifest.pending.json
  3. rename manifest.pending.json -> manifest.json

The launcher ignores the package until the manifest has its real name.
