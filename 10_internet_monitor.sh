#!/bin/sh
# Auto-setup cron job for internet monitor after reboot
/bin/sleep 60
if ! crontab -l 2>/dev/null | grep -q "/data/internet_monitor.sh"; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * /data/internet_monitor.sh") | crontab -
    echo "$(date): Cron job for internet monitor installed." >> /var/log/internet_monitor.log
else
    echo "$(date): Cron job already exists. No changes made." >> /var/log/internet_monitor.log
fi
