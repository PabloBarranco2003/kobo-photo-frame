/* rtcalarm: set/read/clear the RTC wake alarm on a Kobo via ioctl on /dev/rtc0
 * (the same mechanism the firmware's rtctest uses; this kernel has no sysfs wakealarm interface).
 * Usage: rtcalarm now         -> print the RTC time (UTC epoch)
 *        rtcalarm set SEC     -> alarm in SEC seconds (max < 24 h); prints the target epoch
 *        rtcalarm get         -> print the programmed alarm epoch (0 if disabled)
 *        rtcalarm clear       -> disable the alarm
 * Device: environment variable RTC_DEV (default /dev/rtc0, then /dev/rtc). Public domain. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>

struct rtc_time { int tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst; };
struct rtc_wkalrm { unsigned char enabled, pending; struct rtc_time time; };
#define RTC_AIE_ON     _IO('p', 0x01)
#define RTC_AIE_OFF    _IO('p', 0x02)
#define RTC_ALM_SET    _IOW('p', 0x07, struct rtc_time)
#define RTC_RD_TIME    _IOR('p', 0x09, struct rtc_time)
#define RTC_WKALM_SET  _IOW('p', 0x0f, struct rtc_wkalrm)
#define RTC_WKALM_RD   _IOR('p', 0x10, struct rtc_wkalrm)

static int open_rtc(void) {
	const char *dev = getenv("RTC_DEV");
	int fd;
	if (dev && *dev) { fd = open(dev, O_RDONLY); if (fd < 0) perror(dev); return fd; }
	fd = open("/dev/rtc0", O_RDONLY);
	if (fd < 0) fd = open("/dev/rtc", O_RDONLY);
	if (fd < 0) perror("/dev/rtc0");
	return fd;
}
static time_t to_epoch(const struct rtc_time *r) {
	struct tm t; memset(&t, 0, sizeof t);
	t.tm_sec = r->tm_sec; t.tm_min = r->tm_min; t.tm_hour = r->tm_hour;
	t.tm_mday = r->tm_mday; t.tm_mon = r->tm_mon; t.tm_year = r->tm_year;
	return timegm(&t);
}
static void from_epoch(time_t e, struct rtc_time *r) {
	struct tm t; gmtime_r(&e, &t);
	memset(r, 0, sizeof *r);
	r->tm_sec = t.tm_sec; r->tm_min = t.tm_min; r->tm_hour = t.tm_hour;
	r->tm_mday = t.tm_mday; r->tm_mon = t.tm_mon; r->tm_year = t.tm_year;
	r->tm_wday = t.tm_wday; r->tm_yday = t.tm_yday; r->tm_isdst = 0;
}
int main(int argc, char **argv) {
	struct rtc_time now; struct rtc_wkalrm wk; time_t e;
	int fd;
	if (argc < 2) { fprintf(stderr, "usage: rtcalarm now|set SEC|get|clear\n"); return 2; }
	fd = open_rtc();
	if (fd < 0) return 1;
	if (!strcmp(argv[1], "now")) {
		if (ioctl(fd, RTC_RD_TIME, &now) < 0) { perror("RTC_RD_TIME"); return 1; }
		printf("%ld\n", (long)to_epoch(&now));
		return 0;
	}
	if (!strcmp(argv[1], "set")) {
		long s = (argc > 2) ? atol(argv[2]) : 0;
		if (s < 2 || s > 23 * 3600) { fprintf(stderr, "SEC must be between 2 and %d\n", 23 * 3600); return 2; }
		if (ioctl(fd, RTC_RD_TIME, &now) < 0) { perror("RTC_RD_TIME"); return 1; }
		e = to_epoch(&now) + s;
		memset(&wk, 0, sizeof wk); wk.enabled = 1; from_epoch(e, &wk.time);
		if (ioctl(fd, RTC_WKALM_SET, &wk) < 0) {
			fprintf(stderr, "RTC_WKALM_SET: %s; trying RTC_ALM_SET + AIE_ON\n", strerror(errno));
			if (ioctl(fd, RTC_ALM_SET, &wk.time) < 0) { perror("RTC_ALM_SET"); return 1; }
			if (ioctl(fd, RTC_AIE_ON, 0) < 0) { perror("RTC_AIE_ON"); return 1; }
		}
		printf("%ld\n", (long)e);
		return 0;
	}
	if (!strcmp(argv[1], "get")) {
		memset(&wk, 0, sizeof wk);
		if (ioctl(fd, RTC_WKALM_RD, &wk) < 0) { perror("RTC_WKALM_RD"); return 1; }
		printf("%ld\n", wk.enabled ? (long)to_epoch(&wk.time) : 0L);
		return 0;
	}
	if (!strcmp(argv[1], "clear")) {
		memset(&wk, 0, sizeof wk);
		if (ioctl(fd, RTC_RD_TIME, &now) == 0) from_epoch(to_epoch(&now), &wk.time);
		if (ioctl(fd, RTC_WKALM_SET, &wk) < 0) { ioctl(fd, RTC_AIE_OFF, 0); }
		return 0;
	}
	fprintf(stderr, "unknown command: %s\n", argv[1]);
	return 2;
}
