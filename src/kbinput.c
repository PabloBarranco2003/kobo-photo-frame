/* kbinput: waits for ONE input event on the Kobo (button or touch) and prints it.
 *   kbinput MS [IGNORE_MS]
 *   -> "KEY <code>"      button pressed (e.g. 102 = Home, 116 = Power)
 *   -> "TAP <a> <b>"     touch; a,b = RAW panel coordinates (ABS_X, ABS_Y)
 *   -> "TIMEOUT"         if MS milliseconds pass with nothing (MS=0: wait forever)
 * During the first IGNORE_MS ms all events are discarded (residual touch that launched the program).
 * Environment: KB_DEVS="/dev/input/event0:/dev/input/event1" (default: event0..event4)
 *              KB_LOG=path  -> logs the first 400 raw events (diagnostics)
 * Public domain. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/select.h>
#include <sys/time.h>
#include <stdint.h>

struct ev { long sec; long usec; uint16_t type; uint16_t code; int32_t value; }; /* 32-bit layout (ARM) */
#if defined(__LP64__)
struct ev64 { long sec; long usec; uint16_t type; uint16_t code; int32_t value; };
#define EVT struct ev64
#else
#define EVT struct ev
#endif

#define MAXD 8
static int fds[MAXD], nfd = 0;
static long long now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (long long)t.tv_sec*1000 + t.tv_nsec/1000000; }

int main(int argc, char **argv) {
	long long total = (argc > 1) ? atoll(argv[1]) : 0;
	long long ignore = (argc > 2) ? atoll(argv[2]) : 0;
	long long t0 = now_ms();
	const char *devs = getenv("KB_DEVS");
	const char *logp = getenv("KB_LOG");
	FILE *lg = logp ? fopen(logp, "a") : NULL;
	int nlog = 0;
	char buf[512];
	if (!devs) devs = "/dev/input/event0:/dev/input/event1:/dev/input/event2:/dev/input/event3:/dev/input/event4";
	strncpy(buf, devs, sizeof buf - 1); buf[sizeof buf - 1] = 0;
	for (char *p = strtok(buf, ":"); p && nfd < MAXD; p = strtok(NULL, ":")) {
		int fd = open(p, O_RDONLY | O_NONBLOCK);
		if (fd >= 0) fds[nfd++] = fd;
	}
	if (!nfd) { fprintf(stderr, "kbinput: cannot open any /dev/input/event*\n"); return 1; }
	int ax[MAXD] = {0}, ay[MAXD] = {0}, have[MAXD] = {0}, touching[MAXD] = {0}, sawrel = 0;
	long long lastcoord = 0; int dirty = -1;
	for (;;) {
		long long now = now_ms();
		long long wait = 1000;
		if (total > 0) { long long left = total - (now - t0); if (left <= 0) { puts("TIMEOUT"); return 0; } if (left < wait) wait = left; }
		if (dirty >= 0 && !sawrel) { wait = 200 - (now - lastcoord); if (wait < 0) wait = 0; }
		fd_set rs; FD_ZERO(&rs); int mx = 0;
		for (int i = 0; i < nfd; i++) if (fds[i] >= 0) { FD_SET(fds[i], &rs); if (fds[i] > mx) mx = fds[i]; }
		struct timeval tv = { wait / 1000, (wait % 1000) * 1000 };
		int r = select(mx + 1, &rs, NULL, NULL, &tv);
		now = now_ms();
		int ignoring = (now - t0) < ignore;
		if (r == 0 && dirty >= 0 && !sawrel && (now - lastcoord) >= 200 && !ignoring) {
			printf("TAP %d %d\n", ax[dirty], ay[dirty]); return 0; /* no release event: treat as a tap after 200 ms of silence */
		}
		if (r <= 0) continue;
		for (int i = 0; i < nfd; i++) {
			if (fds[i] < 0 || !FD_ISSET(fds[i], &rs)) continue;
			EVT e; ssize_t n;
			while ((n = read(fds[i], &e, sizeof e)) == (ssize_t)sizeof e) {
				if (lg && nlog < 400) { fprintf(lg, "d%d t=%u c=%u v=%d\n", i, e.type, e.code, e.value); fflush(lg); nlog++; }
				if (ignoring || (now_ms() - t0) < ignore) { dirty = -1; have[i] = 0; touching[i] = 0; continue; }
				if (e.type == 3) { /* EV_ABS */
					if (e.code == 0 || e.code == 53) { ax[i] = e.value; have[i] = 1; dirty = i; lastcoord = now_ms(); }
					else if (e.code == 1 || e.code == 54) { ay[i] = e.value; have[i] = 1; dirty = i; lastcoord = now_ms(); }
					else if (e.code == 24) { /* ABS_PRESSURE */
						if (e.value > 0) { touching[i] = 1; }
						else if (touching[i] && have[i]) { sawrel = 1; printf("TAP %d %d\n", ax[i], ay[i]); return 0; }
					} else if (e.code == 57 && e.value < 0 && have[i]) { sawrel = 1; printf("TAP %d %d\n", ax[i], ay[i]); return 0; }
				} else if (e.type == 1) { /* EV_KEY */
					if (e.code == 330) { /* BTN_TOUCH */
						if (e.value) touching[i] = 1;
						else if (have[i]) { sawrel = 1; printf("TAP %d %d\n", ax[i], ay[i]); return 0; }
					} else if (e.value == 1 && e.code < 0x100) { printf("KEY %u\n", e.code); return 0; }
				}
			}
			if (n == 0) { close(fds[i]); fds[i] = -1; }
		}
		int alive = 0; for (int i = 0; i < nfd; i++) if (fds[i] >= 0) alive = 1;
		if (!alive) { fprintf(stderr, "kbinput: devices closed\n"); return 1; }
	}
}
