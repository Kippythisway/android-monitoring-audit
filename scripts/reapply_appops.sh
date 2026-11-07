#!/system/bin/sh
# reapply_appops.sh - re-apply appops hardening after every reboot.
#
# appops changes are session-scoped on most OEM builds: they are lost on reboot.
# Run this from a boot hook (root) or manually after each boot.
#
# usage:
#   adb push reapply_appops.sh /data/local/tmp/
#   adb shell "TARGETS='com.a com.b' sh /data/local/tmp/reapply_appops.sh"
#
# TARGETS defaults to the vivo/OriginOS case study list; override for your device.

OPS="READ_SMS RECEIVE_SMS READ_CALL_LOG GET_USAGE_STATS FINE_LOCATION COARSE_LOCATION RECORD_AUDIO CAMERA READ_CLIPBOARD"
TARGETS="${TARGETS:-com.vivo.abe com.vivo.safecenter com.iqoo.secure com.vivo.daemonService com.vivo.pushservice com.vivo.gamecube com.bbk.iqoo.logsystem}"

fail=0
for p in $TARGETS; do
  # skip packages that are not installed
  pm list packages 2>/dev/null | grep -q "^package:$p$" || { echo "skip $p (not installed)"; continue; }
  for op in $OPS; do
    out=$(cmd appops set "$p" "$op" ignore 2>&1)
    case "$out" in
      *rror*|*xception*) echo "FAIL $p $op :: $out"; fail=$((fail+1));;
    esac
  done
done

echo "---- summary (ok = ignore) ----"
for p in $TARGETS; do
  pm list packages 2>/dev/null | grep -q "^package:$p$" || continue
  printf "%-30s " "$p"
  for op in READ_SMS READ_CALL_LOG GET_USAGE_STATS FINE_LOCATION RECORD_AUDIO CAMERA; do
    v=$(cmd appops get "$p" "$op" 2>/dev/null | head -1)
    case "$v" in
      *ignore*) printf "ok " ;;
      *default*) printf "n/a " ;;   # op not requested by this package
      *) printf "CHECK(%s) " "$op" ;;
    esac
  done
  echo
done
echo "failures=$fail"
