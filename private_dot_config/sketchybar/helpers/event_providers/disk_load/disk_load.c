#include "disk.h"
#include "../sketchybar.h"

int main (int argc, char** argv) {
  float update_freq;
  if (argc < 3 || (sscanf(argv[2], "%f", &update_freq) != 1)) {
    printf("Usage: %s \"<event-name>\" \"<event_freq>\"\n", argv[0]);
    exit(1);
  }

  alarm(0);
  struct disk dsk;
  disk_init(&dsk);

  // Setup the event in sketchybar
  char event_message[512];
  snprintf(event_message, 512, "--add event '%s'", argv[1]);
  sketchybar(event_message);

  char trigger_message[512];
  for (;;) {
    // Acquire new info
    disk_update(&dsk);

    // Prepare the event message
    snprintf(trigger_message,
             512,
             "--trigger '%s' used_gb='%d' total_gb='%d' free_gb='%d' usage_percent='%d'",
             argv[1],
             dsk.used_gb,
             dsk.total_gb,
             dsk.free_gb,
             dsk.usage_percent);

    // Trigger the event
    sketchybar(trigger_message);

    // Wait
    usleep(update_freq * 1000000);
  }
  return 0;
}
