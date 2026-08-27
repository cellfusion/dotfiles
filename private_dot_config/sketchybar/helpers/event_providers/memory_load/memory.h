#include <mach/mach.h>
#include <stdbool.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/sysctl.h>

struct memory {
  host_t host;
  mach_msg_type_number_t count;
  vm_statistics64_data_t stats;
  vm_size_t page_size;
  uint64_t total_bytes;

  int used_mb;
  int total_mb;
  int usage_percent;
};

static inline void memory_init(struct memory* mem) {
  mem->host = mach_host_self();
  mem->count = HOST_VM_INFO64_COUNT;

  host_page_size(mem->host, &mem->page_size);

  int mib[2] = { CTL_HW, HW_MEMSIZE };
  size_t len = sizeof(mem->total_bytes);
  sysctl(mib, 2, &mem->total_bytes, &len, NULL, 0);

  mem->total_mb = (int)(mem->total_bytes / (1024 * 1024));
}

static inline void memory_update(struct memory* mem) {
  mem->count = HOST_VM_INFO64_COUNT;
  kern_return_t error = host_statistics64(mem->host,
                                          HOST_VM_INFO64,
                                          (host_info64_t)&mem->stats,
                                          &mem->count                );

  if (error != KERN_SUCCESS) {
    printf("Error: Could not read memory host statistics.\n");
    return;
  }

  uint64_t used_pages = mem->stats.active_count
                        + mem->stats.wire_count
                        + mem->stats.compressor_page_count;

  uint64_t used_bytes = used_pages * mem->page_size;
  mem->used_mb = (int)(used_bytes / (1024 * 1024));
  mem->usage_percent = (int)((double)used_bytes / (double)mem->total_bytes * 100.0);
}
