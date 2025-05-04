#!/bin/sh
# Internet Self-Healing Monitor for Dream Machine SE
CHECK_INTERNAL="10.0.0.1"  
CHECK_HOSTS="8.8.8.8 1.1.1.1"  
PING_COUNT=2
PING_TIMEOUT=2 
WAN_INTERFACE="eth8"
CONFIRMATION_WAIT=30
WAN_BOUNCE_DOWN_TIME=5
POST_BOUNCE_WAIT=15
POST_DHCP_WAIT=15
COOLDOWN_PERIOD=600  
MAX_FAILS=3  
LOG_FILE="/var/log/internet_monitor.log"
TIMESTAMP_FILE="/tmp/last_reboot.timestamp"
FAIL_COUNTER_FILE="/tmp/internet_fail_counter"
PING="/bin/ping"
IP="/sbin/ip"
SLEEP="/bin/sleep"
DATE="/bin/date"
RM="/bin/rm"
REBOOT="/sbin/reboot"
KILLALL="/usr/bin/killall"
LOGGER="/usr/bin/logger"
log() {
    MESSAGE="$($DATE): $1"
    echo "$MESSAGE" | tee -a $LOG_FILE
    $LOGGER -t InternetMonitor "$MESSAGE"
}
check_internal() {
    $PING -c $PING_COUNT -W $PING_TIMEOUT $CHECK_INTERNAL > /dev/null 2>&1
    return $?
}
check_internet() {
    for host in $CHECK_HOSTS; do
        $PING -c $PING_COUNT -W $PING_TIMEOUT $host > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            return 0 
        fi
    done
    return 1 
}
reset_fail_counter() {
    echo 0 > $FAIL_COUNTER_FILE
}
increment_fail_counter() {
    if [ ! -f $FAIL_COUNTER_FILE ]; then
        echo 1 > $FAIL_COUNTER_FILE
    else
        COUNT=$(cat $FAIL_COUNTER_FILE)
        COUNT=$((COUNT + 1))
        echo $COUNT > $FAIL_COUNTER_FILE
    fi
}
log "Starting Internet connectivity check..."
check_internal
if [ $? -ne 0 ]; then
    log "Cannot reach internal gateway ($CHECK_INTERNAL)! Potential local network issue."
else
    log "Internal gateway reachable."
fi
check_internet
if [ $? -eq 0 ]; then
    log "External internet connection OK."
    reset_fail_counter
    [ -f $TIMESTAMP_FILE ] && $RM -f $TIMESTAMP_FILE
    exit 0
fi
log "External internet appears down, waiting $CONFIRMATION_WAIT seconds to confirm..."
$SLEEP $CONFIRMATION_WAIT
check_internet
if [ $? -eq 0 ]; then
    log "Internet restored after short outage. No reboot needed."
    reset_fail_counter
    exit 0
fi
log "Internet still down. Attempting WAN interface bounce ($WAN_INTERFACE)..."
$IP link set $WAN_INTERFACE down
$SLEEP $WAN_BOUNCE_DOWN_TIME
$IP link set $WAN_INTERFACE up
$SLEEP $POST_BOUNCE_WAIT
log "Checking internet connectivity after WAN bounce..."
check_internet
if [ $? -eq 0 ]; then
    log "Internet restored after WAN bounce. No reboot needed."
    reset_fail_counter
    exit 0
fi
log "Internet still down after WAN bounce. Attempting DHCP client renewal..."
$KILLALL -HUP udhcpc
$SLEEP $POST_DHCP_WAIT
log "Checking internet connectivity after DHCP renewal..."
check_internet
if [ $? -eq 0 ]; then
    log "Internet restored after DHCP renewal. No reboot needed."
    reset_fail_counter
    exit 0
fi
log "Final check: Verifying internet status before deciding to reboot..."
check_internet
if [ $? -ne 0 ]; then
    log "Internet still down after all recovery attempts. Immediate reboot triggered!"
    CURRENT_TIME=$($DATE +%s)
    echo $CURRENT_TIME > $TIMESTAMP_FILE
    reset_fail_counter
    $REBOOT
else
    log "Internet restored after recovery attempts. No reboot needed."
    reset_fail_counter
    exit 0
fi
increment_fail_counter
FAILS=$(cat $FAIL_COUNTER_FILE)
log "Internet still down. Fail counter at $FAILS/$MAX_FAILS."

if [ "$FAILS" -ge "$MAX_FAILS" ]; then
    CURRENT_TIME=$($DATE +%s)
    echo $CURRENT_TIME > $TIMESTAMP_FILE
    log "Maximum fail counter reached. Restarting Dream Machine."
    reset_fail_counter
    $REBOOT
else
    log "Not yet at maximum fail threshold. No reboot."
    exit 0
fi
