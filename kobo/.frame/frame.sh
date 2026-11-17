#!/bin/sh
# Photo frame for the Kobo Touch C (stock Nickel left intact). Launched by KFMon when the "frame" icon is opened.
# On start it shows a MENU (pick a photo; FRAME MODE; FIXED PHOTO + POWER OFF; EXIT).
# Leaving the frame (back to Nickel): power button, USB, a .frame/STOP file,
# MAX_CYCLES reached, or battery below MIN_BATT.
D="${FRAME_DIR:-/mnt/onboard/.frame}"
SYS="${SYSFS:-/sys}"
LOG="$D/frame.log"
RA=""
log() { echo "[$(date +'%F %T')] $*" >> "$LOG"; }

# --- Configuration (CRs are stripped in case it was edited on Windows)
INTERVAL=3600; MAX_CYCLES=0; FLASH_EVERY=6; MIN_BATT=10
MENU=1; MENU_TIMEOUT=60; FIXED_OFF=poweroff; MENU_DEBUG=1
if [ -f "$D/config" ]; then
	tr -d '\r' < "$D/config" > /tmp/frame.conf && . /tmp/frame.conf
fi

# Keep the log small: trimmed when it grows past ~100 KB
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 100000 ] && tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
log "=== start (INTERVAL=$INTERVAL MAX_CYCLES=$MAX_CYCLES FLASH_EVERY=$FLASH_EVERY MENU=$MENU)"

# --- FBInk: prefer the full build (with image support) in .frame/fbink
FB=""
for c in "$D/fbink" "$D/fbink-static" /usr/local/kfmon/bin/fbink; do
	if [ -x "$c" ] && "$c" -q -e >/dev/null 2>&1; then FB="$c"; break; fi
done
if [ -z "$FB" ]; then log "ERROR: no fbink binary runs"; exit 1; fi
log "using FBInk: $FB"

# Pre-check (Nickel still alive, no side effects): the FBInk bundled with KFMon CANNOT show images
if "$FB" -q -g file=/nonexistent.png 2>&1 | grep -qi "support is disabled"; then
	log "ERROR: $FB has no image support. The full .frame/fbink is missing."
	"$FB" -q -y 4 "Full FBInk (with images) missing in .frame/fbink"
	exit 1
fi
log "fbink -e: $("$FB" -e 2>&1 | tr '\n' ' ')"

# --- RTC alarm tool: use the first one that returns the RTC time
log "rtc devices: $(ls -l /dev/rtc* 2>&1 | tr '\n' ' ')"
for c in "$D/rtcalarm-static" "$D/rtcalarm"; do
	[ -f "$c" ] || continue
	chmod +x "$c" 2>/dev/null
	out=$("$c" now 2>&1); rc=$?
	log "test $c now -> rc=$rc output='$out'"
	case "$out" in ''|*[!0-9]*) ;; *) RA="$c"; break;; esac
done
[ -n "$RA" ] && log "using rtcalarm: $RA" || log "no rtcalarm works; waiting without suspending"

# Photo list
ls "$D/photos" 2>/dev/null | grep -i -E '\.(png|jpe?g|bmp)$' | sort > /tmp/frame.list
N=$(wc -l < /tmp/frame.list)
if [ "$N" -eq 0 ]; then
	log "ERROR: no photos in $D/photos"
	"$FB" -q -y 4 "No photos in .frame/photos"
	exit 1
fi

batt() {
	for f in "$SYS"/class/power_supply/*/capacity; do
		[ -r "$f" ] && { cat "$f"; return; }
	done
	echo 100
}
if [ "$(batt)" -lt "$MIN_BATT" ]; then
	log "battery low ($(batt)%), not starting"
	"$FB" -q -y 4 "Battery low: frame not started"
	exit 1
fi

# --- From here on Nickel is stopped. Leaving = reboot (the reader comes back).
exit_frame() { log "leaving: $1"; sync; reboot; exit 0; }
killall nickel hindenburg sickel fickel adobehost foxitpdf 2>/dev/null
sleep 2

idx=$(cat "$D/idx" 2>/dev/null); [ -n "$idx" ] || idx=0
[ "$idx" -ge "$N" ] && idx=0
cycle=0

# =====================================================================
#  MENU  (600x800 screen; FBInk text -S 3 => 24 px cells, 25 columns x 33 rows)
# =====================================================================
KB="$D/kbinput"
SP="                                "
sp() { [ "$1" -gt 0 ] && printf "%.${1}s" "$SP"; }
T() { "$FB" -q -S 3 "$@" >/dev/null 2>&1; }          # text (no refresh when -b is passed)
REFRESH() { "$FB" -q -s -w >/dev/null 2>&1; }
# btn ROW COL WIDTH TEXT : inverted 3-row block with centered text
btn() {
	_l=${#4}; _a=$(( ($3 - _l) / 2 )); _b=$(( $3 - _l - _a ))
	T -b -h -y "$1" -x "$2" -- "$(sp "$3")"
	T -b -h -y "$(( $1 + 1 ))" -x "$2" -- "$(sp $_a)$4$(sp $_b)"
	T -b -h -y "$(( $1 + 2 ))" -x "$2" -- "$(sp "$3")"
}
shownum() { T -b -y 4 -x 0 -- "$(sp 8)$(printf '%03d / %03d' "$SEL" "$N")$(sp 8)"; }

draw_menu() {
	"$FB" -q -c -b >/dev/null 2>&1
	T -b -y 1 -m -- "PHOTO FRAME"
	T -b -y 3 -m -- "Photo to show:"
	shownum
	btn 6 0 6 "-10"; btn 6 6 6 "-1"; btn 6 12 6 "+1"; btn 6 18 6 "+10"
	btn 11 0 25 "FRAME MODE";        T -b -y 14 -m -- "cycles from this photo"
	btn 17 0 25 "FIXED PHOTO + OFF"; T -b -y 20 -m -- "keeps it and powers off"
	btn 23 0 25 "EXIT";             T -b -y 26 -m -- "back to the reader"
	T -b -y 29 -m -- "Home: +1 photo"
	T -b -y 30 -m -- "Power: FRAME MODE"
	[ "$MENU_TIMEOUT" -gt 0 ] && T -b -y 31 -m -- "Idle: FRAME MODE in ${MENU_TIMEOUT}s"
	REFRESH
}

# --- Touch calibration: 3 taps (top-left, top-right, bottom-right corners). Saved in touch.cal
CAL="$D/touch.cal"
XAX=""; X0=0; X1=0; Y0=0; Y1=0
load_cal() {
	[ -f "$CAL" ] || return 1
	tr -d '\r' < "$CAL" > /tmp/touch.cal && . /tmp/touch.cal
	[ -n "$XAX" ] && [ "$X1" != "$X0" ] && [ "$Y1" != "$Y0" ]
}
abs() { [ "$1" -lt 0 ] && echo $(( 0 - $1 )) || echo "$1"; }
calib_target() { # n fila col
	"$FB" -q -c -b >/dev/null 2>&1
	T -b -y 12 -m -- "CALIBRATE TOUCH"
	T -b -y 14 -m -- "Tap the black square"
	T -b -y 15 -m -- "($1 of 3)"
	T -b -y 17 -m -- "Home: skip (buttons only)"
	btn "$2" "$3" 3 "X"
	REFRESH
}
calibrate() {
	log "calibrating touch"
	cnt=0
	for t in "1 0 0" "2 0 22" "3 30 22"; do
		set -- $t
		calib_target "$1" "$2" "$3"
		out=$("$KB" 45000 1500 2>>"$LOG"); log "calib $1: $out"
		case "$out" in
			TAP*) set -- $out; eval "ra$cnt=$2; rb$cnt=$3";;
			*) log "calibration skipped ($out)"; return 1;;
		esac
		cnt=$((cnt+1))
	done
	dA=$(abs $(( ra1 - ra0 ))); dB=$(abs $(( rb1 - rb0 )))
	if [ "$dA" -ge "$dB" ]; then XAX=A; X0=$ra0; X1=$ra1; Y0=$rb1; Y1=$rb2
	else XAX=B; X0=$rb0; X1=$rb1; Y0=$ra1; Y1=$ra2; fi
	if [ "$X0" = "$X1" ] || [ "$Y0" = "$Y1" ]; then log "invalid calibration"; XAX=""; return 1; fi
	printf 'XAX=%s\nX0=%s\nX1=%s\nY0=%s\nY1=%s\n' "$XAX" "$X0" "$X1" "$Y0" "$Y1" > "$CAL"
	log "calibration saved: XAX=$XAX X0=$X0 X1=$X1 Y0=$Y0 Y1=$Y1"
	return 0
}
# map RAW_A RAW_B -> SX SY (target centers: x 36..564, y 36..756)
map() {
	if [ "$XAX" = A ]; then vx=$1; vy=$2; else vx=$2; vy=$1; fi
	SX=$(( 36 + (vx - X0) * 528 / (X1 - X0) ))
	SY=$(( 36 + (vy - Y0) * 720 / (Y1 - Y0) ))
}
inband() { [ "$SY" -ge "$1" ] && [ "$SY" -lt "$2" ]; }

# Result: MENU_ACTION = frame | fixed | quit ; SEL = chosen photo (1..N)
menu() {
	SEL=$((idx+1)); MENU_ACTION=frame
	[ -f "$KB" ] && chmod +x "$KB" 2>/dev/null
	if [ ! -x "$KB" ]; then log "no kbinput: no menu"; return; fi
	[ "$MENU_DEBUG" = 1 ] && { : > "$D/kbevents.log"; export KB_LOG="$D/kbevents.log"; }
	if ! load_cal; then calibrate || log "no calibration: buttons only"; load_cal; fi
	have_touch=0; [ -n "$XAX" ] && have_touch=1
	draw_menu
	fails=0
	ms=$(( MENU_TIMEOUT * 1000 ))
	while :; do
		out=$("$KB" "$ms" 1200 2>>"$LOG")
		log "menu: '$out'"
		case "$out" in
			TIMEOUT) log "menu: idle -> FRAME MODE"; MENU_ACTION=frame; return;;
			"") fails=$((fails+1)); [ "$fails" -ge 3 ] && { log "menu: input unavailable -> FRAME MODE"; MENU_ACTION=frame; return; }; sleep 1; continue;;
			"KEY 102") SEL=$((SEL+1)); [ "$SEL" -gt "$N" ] && SEL=1; shownum; REFRESH; continue;;
			"KEY 116") MENU_ACTION=frame; return;;
			KEY*) continue;;
			TAP*)
				[ "$have_touch" = 1 ] || continue
				set -- $out; map "$2" "$3"
				log "tap -> screen $SX,$SY"
				if inband 132 228; then
					if   [ "$SX" -lt 144 ]; then d=-10
					elif [ "$SX" -lt 288 ]; then d=-1
					elif [ "$SX" -lt 432 ]; then d=1
					else d=10; fi
					SEL=$(( SEL + d ))
					while [ "$SEL" -lt 1 ]; do SEL=$((SEL+N)); done
					while [ "$SEL" -gt "$N" ]; do SEL=$((SEL-N)); done
					shownum; REFRESH
				elif inband 252 372; then MENU_ACTION=frame; return
				elif inband 396 516; then MENU_ACTION=fixed; return
				elif inband 540 660; then MENU_ACTION=quit; return
				fi;;
		esac
	done
}

fixed_mode() {
	photo=$(sed -n "${SEL}p" /tmp/frame.list)
	log "FIXED MODE: photo $SEL/$N $photo, off=$FIXED_OFF"
	echo "$SEL" > "$D/idx"
	if ! "$FB" -q -w -f -g file="$D/photos/$photo" >> "$LOG" 2>&1; then exit_frame "failed to draw $photo"; fi
	sync
	usleep 2500000   # let the refresh finish before powering off
	if [ "$FIXED_OFF" = suspend ]; then
		log "suspending to RAM without alarm (Power = back to the reader)"
		echo 1 > "$SYS/power/state-extended" 2>/dev/null
		echo mem > "$SYS/power/state"
		echo 0 > "$SYS/power/state-extended" 2>/dev/null
		exit_frame "wake after fixed mode"
	fi
	log "powering off (poweroff)"
	sync
	poweroff
	sleep 60
	exit_frame "poweroff did not power off"
}

if [ "$MENU" = 1 ]; then
	menu
	log "menu -> $MENU_ACTION (photo $SEL)"
	case "$MENU_ACTION" in
		quit) exit_frame "menu: exit";;
		fixed) fixed_mode;;
		frame) idx=$((SEL-1)); echo "$idx" > "$D/idx";;
	esac
fi

# =====================================================================
#  FRAME MODE
# =====================================================================
while :; do
	[ -e "$D/STOP" ] && { rm -f "$D/STOP"; exit_frame "STOP file"; }
	[ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ] && exit_frame "MAX_CYCLES reached"
	[ "$(batt)" -lt "$MIN_BATT" ] && exit_frame "battery low ($(batt)%)"

	[ "$idx" -ge "$N" ] && idx=0
	photo=$(sed -n "$((idx+1))p" /tmp/frame.list)
	idx=$((idx+1)); echo "$idx" > "$D/idx"
	cycle=$((cycle+1))

	# Full flashing refresh every FLASH_EVERY photos (and on the first) to avoid ghosting
	if [ $(( (cycle-1) % FLASH_EVERY )) -eq 0 ]; then FL="-f"; else FL=""; fi
	log "photo $idx/$N: $photo $FL (battery $(batt)%)"
	if ! "$FB" -q -w $FL -g file="$D/photos/$photo" >> "$LOG" 2>&1; then
		exit_frame "failed to draw $photo"
	fi

	# --- Sleep (suspend to RAM with an RTC alarm via ioctl; this kernel has no sysfs wakealarm)
	WAKE_AT=""
	if [ -n "$RA" ]; then
		S=$INTERVAL; [ "$S" -gt 82800 ] && S=82800; [ "$S" -lt 5 ] && S=5
		WAKE_AT=$("$RA" set "$S" 2>>"$LOG")
		chk=$("$RA" get 2>>"$LOG")
		# On this kernel reading the alarm (get) does not return the exact time; it only has to be non-zero/non-empty
		log "alarm: requested=$WAKE_AT read=$chk"
		if [ -z "$WAKE_AT" ] || [ -z "$chk" ] || [ "$chk" = 0 ]; then
			log "RTC alarm not confirmed (requested=$WAKE_AT read=$chk)"
			"$RA" clear 2>/dev/null; WAKE_AT=""
		fi
	fi

	if [ -n "$WAKE_AT" ]; then
		log "suspending to RAM; RTC wake in ${S}s (target $WAKE_AT)"
		usleep 1500000
		echo 1 > "$SYS/power/state-extended" 2>/dev/null
		sync
		echo mem > "$SYS/power/state"
		echo 0 > "$SYS/power/state-extended" 2>/dev/null
		now2=$("$RA" now 2>>"$LOG"); [ -n "$now2" ] || now2=0
		"$RA" clear 2>/dev/null
		log "awake (RTC $now2, target $WAKE_AT)"
		# If it woke early: power button or USB -> leave
		[ "$now2" -lt $((WAKE_AT - 5)) ] && exit_frame "early wake (button/USB)"
	else
		log "NO RTC alarm: waiting ${INTERVAL}s without suspending (more battery use)"
		i=0
		while [ "$i" -lt "$INTERVAL" ]; do
			[ -e "$D/STOP" ] && break
			sleep 5; i=$((i+5))
		done
	fi
done
