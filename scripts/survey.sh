#!/system/bin/sh
# survey.sh - preinstalled monitoring audit (no root required)
# usage:
#   adb push survey.sh /data/local/tmp/ && adb shell sh /data/local/tmp/survey.sh
#   adb shell sh /data/local/tmp/survey.sh > survey.txt
#
# Reads only package/permission/appops state. Does not modify anything.

echo "########## 0. device ##########"
getprop ro.product.model
getprop ro.product.device
getprop ro.build.version.release
getprop ro.build.display.id
uname -r

echo
echo "########## 1. suspect processes ##########"
# daemon / push / secure / logsystem / telemetry / collector are the usual suspects
ps -A -o PID,RSS,NAME 2>/dev/null | grep -iE "daemon|push|secure|logsystem|telemetry|collect|monitor|analytics|stats" | head -40

echo
echo "########## 2. package state (0=default 1=enabled 2=disabled 3=disabled-user) ##########"
pm list packages -d 2>/dev/null | sed 's/package:/disabled: /'
echo "--- forced-disabled but still running is a red flag ---"

echo
echo "########## 3. shared uids (permission attribution trap) ##########"
cmd package list packages -U 2>/dev/null | awk '{print $NF, $0}' | sort | awk '{
  uid=$1; sub(/.*uid:/,"",uid); count[uid]++; line[uid]=line[uid] "\n  " $0
} END { for (u in count) if (count[u] > 1) printf "uid %s (%d pkgs)%s\n", u, count[u], line[u] }'

echo
echo "########## 4. privileged permissions (per package) ##########"
# edit this list for the packages you care about
for p in $SUSPECTS; do
  echo "-- $p"
  dumpsys package "$p" 2>/dev/null | grep -E "android.permission.(READ_SMS|RECEIVE_SMS|READ_CALL_LOG|READ_CONTACTS|READ_PHONE_STATE|READ_PRIVILEGED_PHONE_STATE|ACCESS_FINE_LOCATION|ACCESS_BACKGROUND_LOCATION|RECORD_AUDIO|CAMERA|READ_LOGS|DUMP|PACKAGE_USAGE_STATS|QUERY_ALL_PACKAGES|WRITE_SECURE_SETTINGS): granted=true" | sed 's/^ */   /' | sort -u
done

echo
echo "########## 5. appops holders ##########"
for op in GET_USAGE_STATS ACCESS_FINE_LOCATION ACCESS_BACKGROUND_LOCATION SYSTEM_ALERT_WINDOW READ_CLIPBOARD; do
  echo "-- $op"
  cmd appops query-op $op allow 2>/dev/null | sed 's/^/   /'
done

echo
echo "########## 6. full-access entry points ##########"
echo -n "accessibility: "; settings get secure enabled_accessibility_services
echo -n "notification listeners: "; settings get secure enabled_notification_listeners
echo -n "always-on vpn: "; settings get secure always_on_vpn_app
echo "device admins:"
dumpsys device_policy 2>/dev/null | grep -E "Admin|provisioningState" | head -10

echo
echo "########## 7. network ##########"
ss -tn 2>/dev/null | head -25

echo
echo "########## 8. boot / connectivity receivers on suspects ##########"
for p in $SUSPECTS; do
  echo "-- $p"
  dumpsys package "$p" 2>/dev/null | grep -A2 -E "BOOT_COMPLETED|SIM_STATE|CONNECTIVITY_CHANGE|USER_PRESENT" | grep -E "Action|com\." | head -6 | sed 's/^ */   /'
done
