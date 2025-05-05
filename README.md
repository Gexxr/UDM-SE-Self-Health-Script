![Built for UDM-SE](https://img.shields.io/badge/Built%20for-UDM--SE-blue)
![Production Ready](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)

# UDM-SE Self Health Script

A self-healing internet monitoring and auto-recovery system for the UniFi Dream Machine SE (UDM-SE).

This project provides scripts to automatically detect internet outages, attempt recovery actions, and reboot the device if needed.  
It is designed for high-availability, production environments where minimizing downtime is critical.

---

## ✨ Features

- Monitors internal gateway and external internet every minute
- Automatically attempts WAN bounce and DHCP renewal if connection is lost
- Smart reboot system after recovery attempts or multiple failures
- Fail counter protection to prevent unnecessary reboots
- Daily scheduled soft reboot (4:00 AM)
- Daily log rotation to prevent file bloat
- Live console and syslog output
- Auto-displays recent logs when SSHing into the UDM

---

## 📁 Included Files

| File | Purpose |
|:---|:---|
| `internet_monitor.sh` | Main monitor script. Checks internet status, attempts recovery, logs results, and reboots if needed. |
| `10_internet_monitor.sh` | Boot-time script to auto-create the monitoring cron job after every reboot. |
| `setup_cronjobs.txt` | Example cron jobs for scheduled monitor execution, daily reboot, and daily log rotation. |
| `show_log_on_login.txt` | Instructions to show last 20 lines of the monitor log on SSH login. |

---

## 🛠 Installation Overview

1. SSH into your UDM-SE as `root`
2. Create on_boot.d directory:
    ```
    mkdir -p /mnt/data/on_boot.d
    ```
3. Create a new boot script (10_internet_monitor.sh):
    ```
    vi /mnt/data/on_boot.d/10_internet_monitor.sh
    ```
4. Once in VI, Paste the following: 
    ```
    #!/bin/sh
    /bin/sleep 60
    if ! crontab -l 2>/dev/null | grep -q "/data/internet_monitor.sh"; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /data/internet_monitor.sh") | crontab -
    echo "$(date): Cron job for internet monitor installed." >> /var/log/internet_monitor.log else
    echo "$(date): Cron job already exists. No changes made." >> /var/log/internet_monitor.log fi
    ```
    ```
    Remember: ESC, :wq, Enter
    ```

5. Create the core script (internet_monitor.sh):

    ```
    vi /data/internet_monitor.sh
    ```

6. Copy the following into the .sh:

    ```
    #!/bin/sh
    # UDM-SE Internet Self-Healing Monitor
    # Version: 2025.05.05
    # Company: Atlas 8 Technology
    # License: Proprietary - Internal Use Only
    # Copyright (C) 2025 Atlas 8 Technology
    #
    # This script is proprietary and confidential.
    # It is intended solely for use by Atlas 8 Technology and its authorized representatives.
    # Unauthorized copying, distribution, modification, or use of this script is strictly prohibited.
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
    FAILURE_LOG="/var/log/internet_failures.log"
    TIMESTAMP_FILE="/tmp/last_reboot.timestamp"
    FAIL_COUNTER_FILE="/tmp/internet_fail_counter"
    DOWN_START_FILE="/tmp/internet_down_start.timestamp"
    FAILURE_STAGE_FILE="/tmp/internet_failure_stage.txt"
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
    
    record_down_start() {
        if [ ! -f $DOWN_START_FILE ]; then
            $DATE +%s > $DOWN_START_FILE
        fi
    }
    
    record_failure_stage() {
        echo "$1" > $FAILURE_STAGE_FILE
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
    
    log_permanent_failure() {
        CURRENT_TIME=$($DATE +%s)
    
        if [ -f $DOWN_START_FILE ]; then
            DOWN_START=$(cat $DOWN_START_FILE)
            DURATION=$((CURRENT_TIME - DOWN_START))
            DURATION_MINUTES=$((DURATION / 60))
        else
            DURATION="Unknown"
            DURATION_MINUTES="Unknown"
        fi
    
        if [ -f $FAILURE_STAGE_FILE ]; then
            FAILURE_STAGE=$(cat $FAILURE_STAGE_FILE)
        else
            FAILURE_STAGE="Unknown"
        fi
    
        echo "$($DATE): Internet failure triggered reboot. Downtime duration: ${DURATION_MINUTES} minutes (${DURATION} seconds). Failure stage: ${FAILURE_STAGE}." >> $FAILURE_LOG
    
        $RM -f $DOWN_START_FILE
        $RM -f $FAILURE_STAGE_FILE
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
        [ -f $DOWN_START_FILE ] && $RM -f $DOWN_START_FILE
        [ -f $FAILURE_STAGE_FILE ] && $RM -f $FAILURE_STAGE_FILE
        exit 0
    fi
    
    log "External internet appears down, waiting $CONFIRMATION_WAIT seconds to confirm..."
    $SLEEP $CONFIRMATION_WAIT
    
    check_internet
    if [ $? -eq 0 ]; then
        log "Internet restored after short outage. No reboot needed."
        reset_fail_counter
        [ -f $DOWN_START_FILE ] && $RM -f $DOWN_START_FILE
        [ -f $FAILURE_STAGE_FILE ] && $RM -f $FAILURE_STAGE_FILE
        exit 0
    fi
    
    record_down_start
    
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
        [ -f $DOWN_START_FILE ] && $RM -f $DOWN_START_FILE
        [ -f $FAILURE_STAGE_FILE ] && $RM -f $FAILURE_STAGE_FILE
        exit 0
    fi
    
    record_failure_stage "WAN Bounce Failed"
    
    log "Internet still down after WAN bounce. Attempting DHCP client renewal..."
    $KILLALL -HUP udhcpc
    $SLEEP $POST_DHCP_WAIT
    
    log "Checking internet connectivity after DHCP renewal..."
    check_internet
    if [ $? -eq 0 ]; then
        log "Internet restored after DHCP renewal. No reboot needed."
        reset_fail_counter
        [ -f $DOWN_START_FILE ] && $RM -f $DOWN_START_FILE
        [ -f $FAILURE_STAGE_FILE ] && $RM -f $FAILURE_STAGE_FILE
        exit 0
    fi
    
    record_failure_stage "DHCP Renew Failed"
    
    log "Final check: Internet still down after all recovery attempts."
    
    CURRENT_TIME=$($DATE +%s)
    
    if [ -f $TIMESTAMP_FILE ]; then
        LAST_REBOOT=$(cat $TIMESTAMP_FILE)
        TIME_SINCE_LAST_REBOOT=$((CURRENT_TIME - LAST_REBOOT))
    
        if [ $TIME_SINCE_LAST_REBOOT -lt $COOLDOWN_PERIOD ]; then
            log "Cooldown active ($((COOLDOWN_PERIOD - TIME_SINCE_LAST_REBOOT)) seconds left). No reboot triggered."
            increment_fail_counter
            exit 0
        fi
    fi
    
    increment_fail_counter
    FAILS=$(cat $FAIL_COUNTER_FILE)
    
    if [ "$FAILS" -ge "$MAX_FAILS" ]; then
        log "Maximum fail counter reached. Restarting Dream Machine."
        echo $CURRENT_TIME > $TIMESTAMP_FILE
        log_permanent_failure
        reset_fail_counter
        $REBOOT
    else
        log "Not yet at maximum fail threshold. No reboot triggered."
    fi
    
    exit 0

    ```
    ```
    Remember: ESC, :wq, Enter
    ```
7. Make the scripts executable:

    ```
    chmod +x /data/internet_monitor.sh
    chmod +x /mnt/data/on_boot.d/10_internet_monitor.sh
    ```
8. Edit your crontab (`crontab -e`) and add:

    ```
    * * * * * /data/internet_monitor.sh
    0 4 * * * /sbin/reboot
    0 0 * * * /bin/truncate -s 0 /var/log/internet_monitor.log
    ```

5. (Optional) Edit `/etc/profile` to auto-show logs when you SSH into the machine:

    ```
    if [ -f /var/log/internet_monitor.log ]; then
        echo ""
        echo "====== Internet Monitor Log ======"
        tail -n 20 /var/log/internet_monitor.log
        echo "==================================="
        echo ""
    fi
    ```
7.  (Optional) Test the script:

    ```
    /data/internet_monitor.sh
    ```
    ```
    Disconnect your WAN port just before testing. you will see the results as they come in
    ```
---

## 📋 Requirements

- UniFi Dream Machine SE (UDM-SE)
- Root SSH access
- Basic familiarity with shell scripts and cron
- `/data/` partition available for persistent storage

---

## 📈 Monitoring

- Logs are saved in `/var/log/internet_monitor.log`
- Live monitoring:

    ```
    tail -f /var/log/internet_monitor.log
    ```

- System logs also available:

    ```
    logread -f
    ```

---

## 🧠 Notes

- If WAN interface name is not `eth8`, adjust it in the `internet_monitor.sh`.
- Default internal gateway monitored is `10.0.0.1`, and external IPs `8.8.8.8` and `1.1.1.1`.
- Daily log clearing keeps `/var/log/internet_monitor.log` clean.
- Designed to be lightweight and not interfere with normal UDM operations.

---

## 🚀 Status

**Production ready**.  
Successfully tested under real-world production network loads.



---
