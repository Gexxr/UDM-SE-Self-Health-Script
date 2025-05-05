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

## 📜 Legal Notice
This project is owned by Atlas 8 Technology. All scripts, documentation, and related materials are proprietary and confidential. Unauthorized distribution, modification, or sharing of this project is strictly prohibited without explicit permission. Usage of this project is governed by the terms outlined in the Non-Disclosure Agreement (NDA) and License Agreement provided by Atlas 8 Technology. By utilizing or accessing this project, you agree to adhere to these terms.

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
    WAN_INTERFACE="eth8" #CHANGE THIS AS NEEDED
    CONFIRMATION_WAIT=30 #ADJUST HOW LONG IT WAITS TO CONFIRM THE INTERNET IS ACTUALLY DOWN (IN SECONDS)
    WAN_BOUNCE_DOWN_TIME=5
    POST_BOUNCE_WAIT=15
    POST_DHCP_WAIT=15
    COOLDOWN_PERIOD=600  #AFTER REBOOT IF THE NETWORK IS STILL DOWN IT WILL WAIT 10 MINUTES TO RUN ANOTHER CHECK
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
        echo "$($DATE): Internet restored after WAN bounce. No reboot needed." >> /var/log/internet_failures.log
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
        echo "$($DATE): Internet restored after DHCP renewal. No reboot needed." >> /var/log/internet_failures.log
        reset_fail_counter
        exit 0
    fi
    log "Final check: Verifying internet status before deciding to reboot..."
    check_internet
    if [ $? -ne 0 ]; then
        log "Internet still down after all recovery attempts. Immediate reboot triggered!"
        echo "$($DATE): Internet failure triggered reboot after recovery attempts." >> /var/log/internet_failures.log
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
        echo "$($DATE): Internet failure triggered reboot after max fail counter reached." >> /var/log/internet_failures.log
        CURRENT_TIME=$($DATE +%s)
        echo $CURRENT_TIME > $TIMESTAMP_FILE
        log "Maximum fail counter reached. Restarting Dream Machine."
        reset_fail_counter
        $REBOOT
    else
        log "Not yet at maximum fail threshold. No reboot."
        exit 0
    fi
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

## 🚀 Status

**Production ready**.  
Successfully tested under real-world production network loads.



---
