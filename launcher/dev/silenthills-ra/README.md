# silenthills-ra: RetroAchievements sets in native builds

The RetroAchievements sets for the classic games are written against the
console's memory. A native build that still has that memory (a static
recompilation keeps the console's RAM as a block) can run the sets exactly as
an emulator would. This kit does that with RetroAchievements' own evaluator
(`rcheevos`, MIT, bundled in `rcheevos/`), and reports unlocks to the Silent
Hills launcher.

| Game | RA set | Console | Native build | How it runs the set |
|---|---|---|---|---|
| Silent Hill: Origins | [3927](https://retroachievements.org/game/3927) | PSP | own static recompilation | **this kit**: guest memory, PSP map |
| Silent Hill: Shattered Memories | [19179](https://retroachievements.org/game/19179) | Wii | own static recompilation (NWiiRecomp) | **this kit**: guest memory, Wii map |
| Silent Hill | [11252](https://retroachievements.org/game/11252) | PlayStation | decomp-based PC port | this kit, with a PS1-address → native-variable table from the decomp (see below) |
| Silent Hill 2 | [1324](https://retroachievements.org/game/1324) | PlayStation 2 | PC release (+ Enhanced Edition) | the set's conditions translated to the PC game's memory, or events from the patch (see below) |
| Silent Hill 3 | [1335](https://retroachievements.org/game/1335) | PlayStation 2 | PC release + SH3 Enhanced | as Silent Hill 2 |
| Silent Hill 4: The Room | [1336](https://retroachievements.org/game/1336) | PlayStation 2 | PC release | as Silent Hill 2 |

The launcher already shows every set (with badges) in each game's
Achievements, merges unlocks from your RetroAchievements account (emulator
play), and records native unlocks. `"native": true` in a game's `ra` block in
`data/games.json` turns on the native path for it (Origins and Shattered
Memories now).

Native unlocks stay in the launcher. They are not sent to RetroAchievements:
RA only accepts unlocks from its approved emulators.

## Using the kit in a build

```c
#include "silenthills_ra.h"

/* Real console address -> host pointer (NULL if unmapped). */
static const uint8_t* guest(uint32_t real_address, void* ud) {
    return Memory::GetPointer(real_address);      /* PPSSPP-style runtime */
}

shra_init(guest, NULL);    /* once, after memory is set up */
shra_frame();              /* once per game frame (end of the frame) */
shra_shutdown();           /* at exit */
```

Add `silenthills_ra.c`, `rcheevos/src/runtime/*.c` and `rcheevos/src/util/*.c`
to the build, with `rcheevos/include` on the include path. Plain C99, no other
dependencies; builds with MSVC, clang, GCC and llvm-mingw.

- **Addresses**: the kit maps RetroAchievements addresses to real console
  addresses with rcheevos' own table, so the callback only sees addresses as
  the game does: PSP `0x08000000`–`0x0BFFFFFF`, Wii MEM1 `0x80000000`… and
  MEM2 `0x90000000`…, PS1 `0x00000000`–`0x001FFFFF` and scratchpad
  `0x1F800000`.
- **Byte order**: return memory as the console stores it (Wii is
  big-endian). If a runtime keeps big-endian memory as host-order 32-bit
  words, call `shra_set_options(SHRA_SWAP32)`.
- **When**: once per frame, after the game's update. RetroAchievements sets
  count frames (hit counts, deltas), so call it exactly once per game frame,
  not per render frame when those differ.
- **Not started from the launcher**: `shra_init` returns 0 and nothing runs.

### What the launcher passes

- `SILENTHILLS_RA_DEFS`: a text file with the achievements still locked:
  `#console<TAB>41`, `#game<TAB>origins`, then
  `id<TAB>points<TAB>memaddr<TAB>title` per line. Written from the set saved
  in `data\achievements\ra\<set>.json`, so starting a game never waits for the
  network.
- `SILENTHILLS_ACHIEVEMENTS_INBOX`: where unlocks go. The kit writes
  `{"game":"origins","unlock":"ra:<id>"}` (to a `.part` file, then renames it).
- `SILENTHILLS_GAME_ID`.

## Per game

**Origins** (PSP recompilation, PPSSPP-derived runtime): `guest` is
`Memory::GetPointer`. Call `shra_frame()` from the frame flip (the same place
the port's per-frame hooks run, e.g. next to the menu integration in
`ShoGame.cpp`).

**Shattered Memories** (NWiiRecomp): `guest` returns the runtime's MEM1/MEM2
pointer for the address. Check the runtime's byte order: if it stores guest
memory byte-swapped per word, set `SHRA_SWAP32`. Call `shra_frame()` once per
VI frame.

**Silent Hill** (decomp-based PC port): the game's variables are native
globals, not a PS1 RAM block. Because the decomp is matching, every PS1
address the set reads belongs to a known symbol. Generate a table
`{ps1_address, size, &symbol}` from the decomp's symbol map for the addresses
used by the set (the launcher's saved set lists them in `memaddr`), and make
`guest` look the address up there. Structures the port changed (pointers
widened to 64 bits) need a hand-written entry.

**Silent Hill 2, 3 and 4** (PC releases): the PS2 sets read PS2 memory, which
the PC games don't have. Two ways:
1. Translate: find the PC counterpart of each PS2 variable the set reads
   (same code base, different addresses) and have the Enhanced patch's
   `guest` callback serve PS2 addresses from those. The sets use a small
   number of distinct addresses, so this is a table per game.
2. Events: have the patch report the moments directly through the bridge
   (`dev/achievements-bridge.h`: `{"unlock":"ra:<id>"}`).

**Homecoming**: the Xbox 360 list (32, 1000G) is in
`data/achievements/homecoming.json`. Each entry unlocks on a bridge event with
its id as the name (`{"game":"homecoming","event":"six-feet-under"}`) or on
`{"unlock":"six-feet-under"}`. Homecoming Enhanced sends them when it hooks the
matching moments.

## Tests

`./build_test.sh` builds the kit with fake console memory and checks byte,
32-bit, hit counts, deltas, ResetIf, alt groups, the "must be false first"
rule, the PSP and Wii address maps, big-endian reads, and the inbox files.
`tests/ra_e2e.gd` in the launcher runs `test/fake_game.c` end to end.
