/*
 * silenthills_ra.h — RetroAchievements sets in native Silent Hill builds.
 *
 * The console achievement sets on RetroAchievements are written against the
 * console's memory (PS1, PS2, PSP, Wii). A native rebuild that keeps that
 * memory (a static recompilation such as the Origins and Shattered Memories
 * builds) can run those exact sets: this kit evaluates them every frame with
 * RetroAchievements' own evaluator (rcheevos, MIT, bundled in ./rcheevos), and
 * reports each unlock to the Silent Hills launcher.
 *
 * How it fits together:
 *   1. The launcher fetches the set (with the player's own RetroAchievements
 *      key) and, when it starts the game, writes the achievements that are
 *      still locked to a small text file. Its path is in the environment
 *      variable SILENTHILLS_RA_DEFS. Nothing is fetched by the game itself.
 *   2. The game calls shra_init() once and shra_frame() once per frame.
 *   3. shra_frame() reads memory through the game's callback, using
 *      RetroAchievements' address map for the console, so the callback only
 *      has to turn a real console address into a pointer.
 *   4. When an achievement triggers, the kit writes
 *        {"game":"<id>","unlock":"ra:<achievement id>"}
 *      to the launcher's inbox (SILENTHILLS_ACHIEVEMENTS_INBOX), which shows
 *      it and records it. Unlocks are kept by the launcher only; they are
 *      not sent to RetroAchievements.
 *
 * If the game wasn't started from the launcher (no SILENTHILLS_RA_DEFS),
 * shra_init() returns 0 and shra_frame() does nothing.
 *
 * Usage:
 *   static const uint8_t* guest(uint32_t real_address, void* ud) {
 *       return my_memory_base + (real_address & 0x01FFFFFF);   // or NULL if unmapped
 *   }
 *   shra_init(guest, NULL);           // at boot
 *   shra_frame();                     // once per frame, after the game logic
 *   shra_shutdown();                  // at exit (optional)
 *
 * Byte order: the callback must return memory in the console's own byte
 * order (big-endian on Wii). If a runtime keeps big-endian memory swapped
 * in 32-bit words, set SHRA_SWAP32 with shra_set_options().
 *
 * Build: add silenthills_ra.c and rcheevos/src/runtime/*.c,
 * rcheevos/src/util/rc_compat.c to the project, with rcheevos/include on the
 * include path. C99; no other dependencies.
 */
#ifndef SILENTHILLS_RA_H
#define SILENTHILLS_RA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Turns a real console address (e.g. 0x80123456 on Wii, 0x08812345 on PSP,
   0x00123456 on PS1/PS2) into a pointer to that byte, or NULL if unmapped. */
typedef const uint8_t* (*shra_guest_ptr_fn)(uint32_t real_address, void* ud);

enum { SHRA_SWAP32 = 1 };

/* Loads the set the launcher prepared. Returns the number of achievements
   being watched (0 when not started from the launcher or nothing is left). */
int shra_init(shra_guest_ptr_fn guest, void* ud);
void shra_set_options(int flags);

/* Evaluates every achievement once; call once per game frame. */
void shra_frame(void);

/* Number of achievements unlocked this session. */
int shra_unlocked_count(void);

void shra_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
