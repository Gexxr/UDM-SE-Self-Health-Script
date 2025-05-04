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

1. SSH into your UDM-SE as `root`.
2. Upload the provided scripts into `/data/`.
3. Make the scripts executable:

    ```
    chmod +x /data/internet_monitor.sh
    chmod +x /data/on_boot.d/10_internet_monitor.sh
    ```

4. Edit your crontab (`crontab -e`) and add:

    ```
    * * * * * /data/internet_monitor.sh
    0 4 * * * /sbin/reboot
    0 0 * * * /bin/truncate -s 0 /var/log/internet_monitor.log
    ```

5. (Optional) Edit `/etc/profile` to auto-show logs when you SSH:

    ```
    if [ -f /var/log/internet_monitor.log ]; then
        echo ""
        echo "====== Internet Monitor Log ======"
        tail -n 20 /var/log/internet_monitor.log
        echo "==================================="
        echo ""
    fi
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

## 📜 License

MIT License.  
Free to use, modify, and improve.

---
