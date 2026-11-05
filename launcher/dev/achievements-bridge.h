/* Silent Hills achievement bridge: single-header helper for mods, ASI
 * plugins and recomp projects.
 *
 *   #define SH_BRIDGE_IMPLEMENTATION   (in exactly one .c/.cpp file)
 *   #include "achievements-bridge.h"
 *
 *   sh_ach_event("leonard_defeated");        // count an event
 *   sh_ach_add("kills", 1);                   // add to a counter
 *   sh_ach_set("kills", 40);                  // set a counter
 *   sh_ach_unlock("the-end");                 // unlock an entry directly
 *
 * Messages go to the launcher's named pipe. If the launcher isn't running,
 * they're written to its inbox folder (when the game was started from
 * Silent Hills, which sets SILENTHILLS_ACHIEVEMENTS_INBOX) and picked up the
 * next time it runs. The game id comes from SILENTHILLS_GAME_ID, or from
 * sh_ach_set_game() for games started some other way.
 *
 * Names should be plain ASCII without quotes or backslashes.
 */
#ifndef SH_ACHIEVEMENTS_BRIDGE_H
#define SH_ACHIEVEMENTS_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif

void sh_ach_set_game(const char *game_id);
int  sh_ach_event(const char *name);
int  sh_ach_add(const char *name, int count);
int  sh_ach_set(const char *name, int value);
int  sh_ach_unlock(const char *achievement_id);
int  sh_ach_send_raw(const char *json_line);   /* one JSON object, no newline */

#ifdef __cplusplus
}
#endif

#ifdef SH_BRIDGE_IMPLEMENTATION
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

static char sh__game[64];

void sh_ach_set_game(const char *game_id) {
  strncpy(sh__game, game_id ? game_id : "", sizeof(sh__game) - 1);
}

static const char *sh__game_id(void) {
  if (!sh__game[0]) { const char *e = getenv("SILENTHILLS_GAME_ID"); if (e) sh_ach_set_game(e); }
  return sh__game;
}

static int sh__inbox(const char *line) {
  const char *dir = getenv("SILENTHILLS_ACHIEVEMENTS_INBOX");
  char path[1024]; FILE *f; static unsigned seq;
  if (!dir) return -1;
#ifdef _WIN32
  _snprintf(path, sizeof(path), "%s\\%lu-%u.json", dir, (unsigned long)GetTickCount(), seq++);
#else
  snprintf(path, sizeof(path), "%s/%lu-%u.json", dir, (unsigned long)time(NULL), seq++);
#endif
  f = fopen(path, "wb");
  if (!f) return -1;
  fputs(line, f); fputs("\n", f); fclose(f);
  return 0;
}

int sh_ach_send_raw(const char *line) {
#ifdef _WIN32
  HANDLE h; DWORD wrote = 0; int ok;
  const char *pipe = getenv("SILENTHILLS_ACHIEVEMENTS_PIPE");
  if (!pipe) pipe = "\\\\.\\pipe\\SilentHills-Achievements";
  h = CreateFileA(pipe, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) return sh__inbox(line);
  ok = WriteFile(h, line, (DWORD)strlen(line), &wrote, NULL) && WriteFile(h, "\n", 1, &wrote, NULL);
  CloseHandle(h);
  return ok ? 0 : sh__inbox(line);
#else
  return sh__inbox(line);
#endif
}

static int sh__send(const char *verb, const char *name, const char *extra) {
  char line[512];
  const char *g = sh__game_id();
  if (g[0]) snprintf(line, sizeof(line), "{\"game\":\"%s\",\"%s\":\"%s\"%s}", g, verb, name, extra ? extra : "");
  else snprintf(line, sizeof(line), "{\"%s\":\"%s\"%s}", verb, name, extra ? extra : "");
  return sh_ach_send_raw(line);
}

int sh_ach_event(const char *name) { return sh__send("event", name, NULL); }
int sh_ach_add(const char *name, int count) { char x[40]; snprintf(x, sizeof(x), ",\"count\":%d", count); return sh__send("event", name, x); }
int sh_ach_set(const char *name, int value) { char x[40]; snprintf(x, sizeof(x), ",\"value\":%d", value); return sh__send("set", name, x); }
int sh_ach_unlock(const char *id) { return sh__send("unlock", id, NULL); }
#endif /* SH_BRIDGE_IMPLEMENTATION */
#endif /* SH_ACHIEVEMENTS_BRIDGE_H */
