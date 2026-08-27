#include <sys/statvfs.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

struct disk {
  struct statvfs stats;
  const char* mount_point;

  int used_gb;
  int total_gb;
  int free_gb;
  int usage_percent;
};

static inline void disk_init(struct disk* dsk) {
  dsk->mount_point = "/";
}

static inline void disk_update(struct disk* dsk) {
  if (statvfs(dsk->mount_point, &dsk->stats) != 0) {
    printf("Error: Could not read disk statistics for %s.\n", dsk->mount_point);
    return;
  }

  uint64_t block_size = dsk->stats.f_frsize;
  uint64_t total_bytes = dsk->stats.f_blocks * block_size;
  uint64_t free_bytes = dsk->stats.f_bavail * block_size;
  uint64_t used_bytes = total_bytes - free_bytes;

  dsk->total_gb = (int)(total_bytes / (1024ULL * 1024ULL * 1024ULL));
  dsk->free_gb = (int)(free_bytes / (1024ULL * 1024ULL * 1024ULL));
  dsk->used_gb = (int)(used_bytes / (1024ULL * 1024ULL * 1024ULL));
  dsk->usage_percent = (int)((double)used_bytes / (double)total_bytes * 100.0);
}
