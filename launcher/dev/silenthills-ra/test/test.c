/* Builds the kit against fake console memory and checks unlocks reach the inbox. */
#include "../silenthills_ra.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

static uint8_t ram[0x4000000];
static uint8_t mem2[0x4000000];
static uint32_t base_real = 0;

static const uint8_t* guest(uint32_t real, void* ud) {
  (void)ud;
  if (base_real == 0x80000000u && real >= 0x90000000u && real < 0x94000000u)
    return mem2 + (real - 0x90000000u);
  uint32_t off = real - base_real;
  if (off >= sizeof(ram)) return NULL;
  return ram + off;
}

static int count_inbox(const char* dir, const char* want) {
  DIR* d = opendir(dir); struct dirent* e; int n = 0; char p[2048];
  if (!d) return 0;
  while ((e = readdir(d))) {
    if (!strstr(e->d_name, ".json") || strstr(e->d_name, ".part")) continue;
    snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
    FILE* f = fopen(p, "rb"); char buf[256] = {0}; fread(buf, 1, 255, f); fclose(f);
    if (!want || strstr(buf, want)) n++;
  }
  closedir(d);
  return n;
}

static int fails = 0;
#define CHECK(c, msg) do { if (c) printf("PASS %s\n", msg); else { printf("FAIL %s\n", msg); fails++; } } while (0)

int main(int argc, char** argv) {
  const char* inbox = argv[1];
  const char* tmp = argv[2];
  char defs[1024];
  setenv("SILENTHILLS_ACHIEVEMENTS_INBOX", inbox, 1);
  setenv("SILENTHILLS_GAME_ID", "sh1", 1);

  /* PS1: RA address == real address. */
  snprintf(defs, sizeof defs, "%s/ps1.tsv", tmp);
  FILE* f = fopen(defs, "wb");
  fprintf(f, "#console\t12\n#game\tsh1\n");
  fprintf(f, "101\t5\t0xH001234=5\tSimple byte\n");
  fprintf(f, "102\t10\t0xH001000=1.3.\tHeld for 3 frames\n");
  fprintf(f, "103\t10\t0xH002000=1_d0xH002000=0\tChanged from 0 to 1\n");
  fprintf(f, "104\t25\t0xX003000=100000_R:0xH003004=1\tWith a reset\n");
  fprintf(f, "105\t5\t0xH001234=5_0xH004000=9S0xH004001=1S0xH004002=1\tAlt groups\n");
  fprintf(f, "106\t5\t0xH005000=1\tAlready true at start\n");
  fclose(f);
  setenv("SILENTHILLS_RA_DEFS", defs, 1);
  memset(ram, 0, sizeof ram);
  ram[0x5000] = 1;   /* true before the game starts: must not fire until it goes false then true */
  int n = shra_init(guest, NULL);
  CHECK(n == 6, "loaded six achievements");
  shra_frame(); shra_frame();
  CHECK(count_inbox(inbox, "ra:106") == 0, "already-true achievement waits");
  ram[0x1234] = 5;
  shra_frame();
  CHECK(count_inbox(inbox, "ra:101") == 1, "simple byte unlocks");
  ram[0x1000] = 1;
  shra_frame(); shra_frame();
  CHECK(count_inbox(inbox, "ra:102") == 0, "hit count not reached after 2 frames");
  shra_frame();
  CHECK(count_inbox(inbox, "ra:102") == 1, "hit count reached after 3 frames");
  ram[0x2000] = 1; shra_frame();
  CHECK(count_inbox(inbox, "ra:103") == 1, "delta (0 to 1) unlocks");
  *(uint32_t*)&ram[0x3000] = 100000; ram[0x3004] = 1; shra_frame();
  CHECK(count_inbox(inbox, "ra:104") == 0, "ResetIf blocks");
  ram[0x3004] = 0; shra_frame();
  CHECK(count_inbox(inbox, "ra:104") == 1, "32-bit value unlocks once reset clears");
  ram[0x4000] = 9; shra_frame();
  CHECK(count_inbox(inbox, "ra:105") == 0, "core true, alt false: no unlock");
  ram[0x4001] = 1; shra_frame();
  CHECK(count_inbox(inbox, "ra:105") == 1, "alt group true: unlock");
  ram[0x5000] = 0; shra_frame(); ram[0x5000] = 1; shra_frame();
  CHECK(count_inbox(inbox, "ra:106") == 1, "fires after going false then true");
  shra_frame(); shra_frame();
  CHECK(count_inbox(inbox, "ra:101") == 1, "each unlock reported once");
  CHECK(shra_unlocked_count() == 6, "six unlocked this session");
  shra_shutdown();

  /* Wii: RA 0x00000000 = 0x80000000, MEM2 RA 0x10000000 = 0x90000000; big-endian values. */
  snprintf(defs, sizeof defs, "%s/wii.tsv", tmp);
  f = fopen(defs, "wb");
  fprintf(f, "#console\t19\n");
  fprintf(f, "201\t5\t0xG000100=305419896\tMEM1 32-bit big-endian\n");
  fprintf(f, "202\t5\t0xH10000010=7\tMEM2 byte\n");
  fclose(f);
  setenv("SILENTHILLS_RA_DEFS", defs, 1);
  setenv("SILENTHILLS_GAME_ID", "shattered-memories", 1);
  base_real = 0x80000000u;
  memset(ram, 0, sizeof ram);
  n = shra_init(guest, NULL);
  CHECK(n == 2, "Wii set loaded");
  shra_frame();
  ram[0x100] = 0x12; ram[0x101] = 0x34; ram[0x102] = 0x56; ram[0x103] = 0x78;   /* 0x12345678 as stored on the console */
  mem2[0x10] = 7;   /* 0x90000010: MEM2, RA address 0x10000010 */
  shra_frame();
  CHECK(count_inbox(inbox, "ra:201") == 1, "Wii MEM1 big-endian read");
  CHECK(count_inbox(inbox, "ra:202") == 1, "Wii MEM2 mapped through the address map");
  shra_shutdown();

  /* PSP: RA 0x00800000 = 0x08800000. */
  snprintf(defs, sizeof defs, "%s/psp.tsv", tmp);
  f = fopen(defs, "wb");
  fprintf(f, "#console\t41\n301\t5\t0xH00812345=3\tPSP user memory\n");
  fclose(f);
  setenv("SILENTHILLS_RA_DEFS", defs, 1);
  base_real = 0x08000000u;
  memset(ram, 0, sizeof ram);
  n = shra_init(guest, NULL);
  shra_frame();
  ram[0x812345] = 3; shra_frame();
  CHECK(n == 1 && count_inbox(inbox, "ra:301") == 1, "PSP address map");
  shra_shutdown();

  unsetenv("SILENTHILLS_RA_DEFS");
  CHECK(shra_init(guest, NULL) == 0, "does nothing when not started from the launcher");
  printf("%s\n", fails ? "FAILURES" : "ALL PASS");
  return fails ? 1 : 0;
}
