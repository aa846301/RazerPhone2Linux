// SPDX-License-Identifier: BSD-3-Clause
/*
 * Minimal Qualcomm DIAG socket capture client for andersson/diag-router.
 *
 * It connects to diag-router's abstract UNIX socket (@diag), enables the
 * broad message/event/log masks that diag-router knows how to broadcast to
 * QRTR DIAG peripherals, then prints all packets it receives.
 */

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define DIAG_CMD_LOGGING_CONFIGURATION          0x73
#define DIAG_CMD_OP_SET_LOG_MASK                3
#define DIAG_CMD_EXTENDED_MESSAGE_CONFIGURATION 0x7d
#define DIAG_CMD_OP_SET_ALL_MSG_MASK            5
#define DIAG_CMD_SET_MASK                       0x82
#define DIAG_CMD_EVENT_REPORT_CONTROL           0x60

#define DIAG_CMD_RSP_BAD_COMMAND                0x13
#define DIAG_CMD_RSP_BAD_PARAMS                 0x14
#define DIAG_CMD_RSP_BAD_LENGTH                 0x15

#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))

static const uint32_t log_code_last_tbl[] = {
	0x0, 0x1A02, 0x0, 0x0,
	0x4910, 0x5420, 0x0, 0x74FF,
	0x0, 0x0, 0xA38A, 0xB201,
	0x0, 0xD1FF, 0x0, 0x0,
};

static uint64_t now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000ULL + ts.tv_nsec / 1000000ULL;
}

static void print_hex(const uint8_t *buf, size_t len)
{
	size_t i;

	for (i = 0; i < len; i++) {
		if (i % 16 == 0)
			printf("  %04zx:", i);
		printf(" %02x", buf[i]);
		if (i % 16 == 15 || i == len - 1)
			printf("\n");
	}
}

static void print_strings(const uint8_t *buf, size_t len)
{
	char tmp[256];
	size_t pos = 0;
	size_t i;

	for (i = 0; i <= len; i++) {
		int ch = i < len ? buf[i] : 0;

		if (i < len && (isprint(ch) || ch == '\t')) {
			if (pos + 1 < sizeof(tmp))
				tmp[pos++] = (char)ch;
			continue;
		}

		if (pos >= 4) {
			tmp[pos] = '\0';
			printf("  str: %s\n", tmp);
		}
		pos = 0;
	}
}

static int connect_diag(void)
{
	struct sockaddr_un addr;
	int fd;

	fd = socket(AF_UNIX, SOCK_SEQPACKET, 0);
	if (fd < 0) {
		perror("socket");
		return -1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	memcpy(addr.sun_path, "\0diag", 5);

	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("connect @diag");
		close(fd);
		return -1;
	}

	return fd;
}

static int send_packet(int fd, const char *name, const uint8_t *buf, size_t len)
{
	ssize_t n;

	n = write(fd, buf, len);
	if (n < 0) {
		fprintf(stderr, "send %s failed: %s\n", name, strerror(errno));
		return -1;
	}
	if ((size_t)n != len) {
		fprintf(stderr, "send %s short write: %zd/%zu\n", name, n, len);
		return -1;
	}

	printf("sent %s (%zu bytes)\n", name, len);
	return 0;
}

static void put_le16(uint8_t *p, uint16_t v)
{
	p[0] = v & 0xff;
	p[1] = (v >> 8) & 0xff;
}

static void put_le32(uint8_t *p, uint32_t v)
{
	p[0] = v & 0xff;
	p[1] = (v >> 8) & 0xff;
	p[2] = (v >> 16) & 0xff;
	p[3] = (v >> 24) & 0xff;
}

static int enable_msg_mask(int fd)
{
	uint8_t pkt[7];

	memset(pkt, 0, sizeof(pkt));
	pkt[0] = DIAG_CMD_EXTENDED_MESSAGE_CONFIGURATION;
	pkt[1] = DIAG_CMD_OP_SET_ALL_MSG_MASK;
	pkt[2] = 0;
	put_le32(&pkt[3], 0xffffffffU);

	return send_packet(fd, "set-all-f3-msg-mask", pkt, sizeof(pkt));
}

static int enable_events(int fd)
{
	uint8_t ctl[] = { DIAG_CMD_EVENT_REPORT_CONTROL, 1 };
	uint16_t num_bits = 0x0b40;
	size_t mask_len = (num_bits + 7) / 8;
	size_t len = 6 + mask_len;
	uint8_t *pkt;
	int ret;

	ret = send_packet(fd, "event-report-control-on", ctl, sizeof(ctl));
	if (ret)
		return ret;

	pkt = calloc(1, len);
	if (!pkt)
		return -1;

	pkt[0] = DIAG_CMD_SET_MASK;
	pkt[1] = 0;
	put_le16(&pkt[2], 0);
	put_le16(&pkt[4], num_bits);
	memset(&pkt[6], 0xff, mask_len);

	ret = send_packet(fd, "set-event-mask-all", pkt, len);
	free(pkt);
	return ret;
}

static int enable_log_masks(int fd)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(log_code_last_tbl); i++) {
		uint32_t num_items = log_code_last_tbl[i] & 0x0fff;
		size_t mask_len = (num_items + 7) / 8;
		size_t len = 8 + 8 + mask_len;
		uint8_t *pkt;
		int ret;

		if (!num_items)
			continue;

		pkt = calloc(1, len);
		if (!pkt)
			return -1;

		pkt[0] = DIAG_CMD_LOGGING_CONFIGURATION;
		put_le32(&pkt[4], DIAG_CMD_OP_SET_LOG_MASK);
		put_le32(&pkt[8], i);
		put_le32(&pkt[12], num_items);
		memset(&pkt[16], 0xff, mask_len);

		ret = send_packet(fd, "set-log-mask", pkt, len);
		free(pkt);
		if (ret)
			return ret;
	}

	return 0;
}

static int configure_masks(int fd, int f3_only)
{
	int ret = 0;

	ret |= enable_msg_mask(fd);
	if (f3_only)
		return ret;

	ret |= enable_events(fd);
	ret |= enable_log_masks(fd);

	return ret;
}

static void describe_packet(const uint8_t *buf, size_t len)
{
	if (!len)
		return;

	switch (buf[0]) {
	case DIAG_CMD_RSP_BAD_COMMAND:
		printf("  diag-router response: bad command\n");
		break;
	case DIAG_CMD_RSP_BAD_PARAMS:
		printf("  diag-router response: bad params\n");
		break;
	case DIAG_CMD_RSP_BAD_LENGTH:
		printf("  diag-router response: bad length\n");
		break;
	case DIAG_CMD_EXTENDED_MESSAGE_CONFIGURATION:
		printf("  packet type: extended message config / F3 msg\n");
		break;
	case DIAG_CMD_LOGGING_CONFIGURATION:
		printf("  packet type: log config/log response\n");
		break;
	case DIAG_CMD_EVENT_REPORT_CONTROL:
	case DIAG_CMD_SET_MASK:
		printf("  packet type: event config/event response\n");
		break;
	case 0x79:
		printf("  packet type: DIAG_EXT_MSG_F candidate\n");
		break;
	default:
		printf("  packet type: cmd 0x%02x\n", buf[0]);
		break;
	}
}

static int capture_loop(int fd, int duration_sec)
{
	uint64_t start = now_ms();
	uint64_t end = start + (uint64_t)duration_sec * 1000ULL;
	unsigned int count = 0;

	while (now_ms() < end) {
		uint8_t buf[16384];
		struct timeval tv;
		fd_set rfds;
		ssize_t n;
		int ret;

		FD_ZERO(&rfds);
		FD_SET(fd, &rfds);
		tv.tv_sec = 0;
		tv.tv_usec = 250000;

		ret = select(fd + 1, &rfds, NULL, NULL, &tv);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			perror("select");
			return -1;
		}
		if (!ret)
			continue;

		n = read(fd, buf, sizeof(buf));
		if (n == 0) {
			fprintf(stderr, "diag socket disconnected\n");
			return -1;
		}
		if (n < 0) {
			if (errno == EAGAIN || errno == EINTR)
				continue;
			fprintf(stderr, "read diag failed: %s\n", strerror(errno));
			return -1;
		}

		printf("packet #%u at +%llums len=%zd\n",
		       ++count, (unsigned long long)(now_ms() - start), n);
		describe_packet(buf, (size_t)n);
		print_strings(buf, (size_t)n);
		print_hex(buf, (size_t)n);
		fflush(stdout);
	}

	printf("capture complete: %u packets in %d seconds\n", count, duration_sec);
	return 0;
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [-d seconds] [-n]\n"
		"\n"
		"  -d seconds   capture duration after sending masks (default: 20)\n"
		"  -n           do not send masks, only capture\n"
		"  -F           enable only the F3 message mask\n",
		argv0);
}

int main(int argc, char **argv)
{
	int duration_sec = 20;
	int no_masks = 0;
	int f3_only = 0;
	int fd;
	int c;

	while ((c = getopt(argc, argv, "d:nFh")) != -1) {
		switch (c) {
		case 'd':
			duration_sec = atoi(optarg);
			if (duration_sec <= 0)
				duration_sec = 20;
			break;
		case 'n':
			no_masks = 1;
			break;
		case 'F':
			f3_only = 1;
			break;
		case 'h':
		default:
			usage(argv[0]);
			return c == 'h' ? 0 : 2;
		}
	}

	fd = connect_diag();
	if (fd < 0)
		return 1;

	printf("connected to diag-router @diag\n");

	if (!no_masks && configure_masks(fd, f3_only))
		fprintf(stderr, "one or more mask commands failed; continuing capture\n");

	return capture_loop(fd, duration_sec) ? 1 : 0;
}
