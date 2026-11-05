/* A stand-in "native build" for end-to-end tests: PSP memory that changes
   over a few frames, with the kit running the launcher's set. */
#include "../silenthills_ra.h"
#include <stdio.h>
#include <string.h>
static uint8_t ram[0x2000000];
static const uint8_t* guest(uint32_t real, void* ud) {
  (void)ud;
  if (real < 0x08000000u || real >= 0x0A000000u) return NULL;
  return ram + (real - 0x08000000u);
}
int main(void) {
  int n = shra_init(guest, NULL);
  printf("watching %d\n", n);
  for (int f = 0; f < 10; f++) {
    if (f == 3) ram[0x812345] = 3;               /* RA 0x00812345 */
    if (f == 5) ram[0x900000] = 1;               /* RA 0x00900000 */
    shra_frame();
  }
  printf("unlocked %d\n", shra_unlocked_count());
  shra_shutdown();
  return 0;
}
