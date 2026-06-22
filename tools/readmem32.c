#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static uint64_t parse_u64(const char *s)
{
	char *end = NULL;
	errno = 0;
	uint64_t v = strtoull(s, &end, 0);
	if (errno || !end || *end) {
		fprintf(stderr, "invalid integer: %s\n", s);
		exit(2);
	}
	return v;
}

int main(int argc, char **argv)
{
	if (argc < 2 || argc > 3) {
		fprintf(stderr, "usage: %s <phys_addr> [count_words]\n", argv[0]);
		return 2;
	}

	uint64_t addr = parse_u64(argv[1]);
	uint64_t count = argc == 3 ? parse_u64(argv[2]) : 1;
	long page_size = sysconf(_SC_PAGESIZE);
	uint64_t page = addr & ~((uint64_t)page_size - 1);
	uint64_t off = addr - page;
	size_t map_len = off + count * sizeof(uint32_t);

	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) {
		fprintf(stderr, "open /dev/mem: %s\n", strerror(errno));
		return 1;
	}

	void *map = mmap(NULL, map_len, PROT_READ, MAP_SHARED, fd, (off_t)page);
	if (map == MAP_FAILED) {
		fprintf(stderr, "mmap 0x%016" PRIx64 ": %s\n", page, strerror(errno));
		close(fd);
		return 1;
	}

	volatile uint32_t *p = (volatile uint32_t *)((char *)map + off);
	for (uint64_t i = 0; i < count; i++)
		printf("0x%016" PRIx64 ": 0x%08" PRIx32 "\n",
		       addr + i * 4, p[i]);

	munmap(map, map_len);
	close(fd);
	return 0;
}
