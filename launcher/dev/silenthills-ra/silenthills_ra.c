/* silenthills_ra.c — see silenthills_ra.h. */
#include "silenthills_ra.h"

#include "rc_runtime.h"
#include "rc_consoles.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#endif

typedef struct {
  uint32_t id;
  char title[128];
} shra_ach;

static rc_runtime_t g_runtime;
static int g_active = 0;
static int g_flags = 0;
static uint32_t g_console = 0;
static char g_game[64];
static char g_inbox[1024];
static shra_guest_ptr_fn g_guest = NULL;
static void* g_ud = NULL;
static const rc_memory_regions_t* g_regions = NULL;
static shra_ach* g_achs = NULL;
static int g_count = 0;
static int g_unlocked = 0;

static const char* env(const char* name) {
  const char* v = getenv(name);
  return (v && *v) ? v : NULL;
}

/* RetroAchievements address -> console address -> host pointer. */
static const uint8_t* ra_ptr(uint32_t ra_address) {
  uint32_t i;
  if (!g_regions)
    return NULL;
  for (i = 0; i < g_regions->num_regions; i++) {
    const rc_memory_region_t* r = &g_regions->region[i];
    if (ra_address >= r->start_address && ra_address <= r->end_address) {
      if (r->type == RC_MEMORY_TYPE_UNUSED)
        return NULL;
      return g_guest(r->real_address + (ra_address - r->start_address), g_ud);
    }
  }
  return NULL;
}

static uint32_t RC_CCONV read_memory(uint32_t address, uint8_t* buffer, uint32_t num_bytes, void* ud) {
  uint32_t i;
  (void)ud;
  for (i = 0; i < num_bytes; i++) {
    uint32_t a = address + i;
    const uint8_t* p;
    if (g_flags & SHRA_SWAP32) {
      /* memory kept as host-order 32-bit words: find the byte's real place */
      p = ra_ptr(a & ~3u);
      if (!p)
        return i;
      buffer[i] = p[3 - (a & 3u)];
    } else {
      p = ra_ptr(a);
      if (!p)
        return i;
      buffer[i] = *p;
    }
  }
  return num_bytes;
}

static void write_unlock(uint32_t id) {
  char path[1200];
  char tmp[1208];
  FILE* f;
  static unsigned seq = 0;
  if (!g_inbox[0])
    return;
  snprintf(path, sizeof(path), "%s/ra-%s-%u-%lu-%u.json", g_inbox, g_game, id, (unsigned long)time(NULL), seq++);
  /* write under another name first so the launcher never reads half a file */
  snprintf(tmp, sizeof(tmp), "%s.part", path);
  f = fopen(tmp, "wb");
  if (!f)
    return;
  fprintf(f, "{\"game\":\"%s\",\"unlock\":\"ra:%u\"}\n", g_game, id);
  fclose(f);
#ifdef _WIN32
  MoveFileExA(tmp, path, MOVEFILE_REPLACE_EXISTING);
#else
  rename(tmp, path);
#endif
}

static void RC_CCONV on_event(const rc_runtime_event_t* e) {
  if (e->type == RC_RUNTIME_EVENT_ACHIEVEMENT_TRIGGERED) {
    write_unlock(e->id);
    rc_runtime_deactivate_achievement(&g_runtime, e->id);
    g_unlocked++;
  } else if (e->type == RC_RUNTIME_EVENT_ACHIEVEMENT_DISABLED) {
    rc_runtime_deactivate_achievement(&g_runtime, e->id);
  }
}

/* The launcher's file: comment lines, "#console<TAB>n", "#game<TAB>id", then
   one achievement per line: id<TAB>points<TAB>memaddr<TAB>title */
static int load(const char* path) {
  FILE* f = fopen(path, "rb");
  char* line;
  size_t cap = 65536;
  int n = 0;
  if (!f)
    return 0;
  line = (char*)malloc(cap);
  while (fgets(line, (int)cap, f)) {
    char* fields[4];
    int nf = 0;
    char* p = line;
    size_t len = strlen(line);
    while (len && (line[len - 1] == '\n' || line[len - 1] == '\r'))
      line[--len] = 0;
    if (line[0] == '#') {
      if (strncmp(line, "#console\t", 9) == 0)
        g_console = (uint32_t)strtoul(line + 9, NULL, 10);
      else if (strncmp(line, "#game\t", 6) == 0 && !env("SILENTHILLS_GAME_ID")) {
        strncpy(g_game, line + 6, sizeof(g_game) - 1);
      }
      continue;
    }
    while (nf < 4) {
      fields[nf++] = p;
      p = strchr(p, '\t');
      if (!p)
        break;
      *p++ = 0;
    }
    if (nf < 3)
      continue;
    {
      uint32_t id = (uint32_t)strtoul(fields[0], NULL, 10);
      if (!id || !fields[2][0])
        continue;
      if (rc_runtime_activate_achievement(&g_runtime, id, fields[2], NULL, 0) == RC_OK) {
        g_achs = (shra_ach*)realloc(g_achs, sizeof(shra_ach) * (size_t)(g_count + 1));
        g_achs[g_count].id = id;
        strncpy(g_achs[g_count].title, nf > 3 ? fields[3] : "", sizeof(g_achs[g_count].title) - 1);
        g_achs[g_count].title[sizeof(g_achs[g_count].title) - 1] = 0;
        g_count++;
        n++;
      }
    }
  }
  free(line);
  fclose(f);
  return n;
}

int shra_init(shra_guest_ptr_fn guest, void* ud) {
  const char* defs = env("SILENTHILLS_RA_DEFS");
  const char* inbox = env("SILENTHILLS_ACHIEVEMENTS_INBOX");
  const char* game = env("SILENTHILLS_GAME_ID");
  if (g_active || !guest || !defs)
    return 0;
  g_guest = guest;
  g_ud = ud;
  memset(g_game, 0, sizeof(g_game));
  if (game)
    strncpy(g_game, game, sizeof(g_game) - 1);
  g_inbox[0] = 0;
  if (inbox)
    strncpy(g_inbox, inbox, sizeof(g_inbox) - 1);
  rc_runtime_init(&g_runtime);
  if (load(defs) == 0) {
    rc_runtime_destroy(&g_runtime);
    return 0;
  }
  g_regions = rc_console_memory_regions(g_console);
  if (!g_regions || g_regions->num_regions == 0) {
    rc_runtime_destroy(&g_runtime);
    return 0;
  }
  g_active = 1;
  return g_count;
}

void shra_set_options(int flags) {
  g_flags = flags;
}

void shra_frame(void) {
  if (g_active)
    rc_runtime_do_frame(&g_runtime, on_event, read_memory, NULL, NULL);
}

int shra_unlocked_count(void) {
  return g_unlocked;
}

void shra_shutdown(void) {
  if (!g_active)
    return;
  rc_runtime_destroy(&g_runtime);
  free(g_achs);
  g_achs = NULL;
  g_count = 0;
  g_active = 0;
}
