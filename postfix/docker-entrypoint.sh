#!/bin/sh
# postfix-wrapper.sh, version 0.1.0
#
# You cannot start postfix in some foreground mode and
# it's more or less important that docker doesn't kill
# postfix and its chilren if you stop the container.
#
# Use this script with supervisord and it will take
# care about starting and stopping postfix correctly.
#
# supervisord config snippet for postfix-wrapper:
#
# [program:postfix]
# process_name = postfix
# command = /path/to/postfix-wrapper.sh
# startsecs = 0
# autorestart = false
#

trap "postfix stop" SIGINT
trap "postfix stop" SIGTERM
trap "postfix reload" SIGHUP

# force new copy of hosts there (otherwise links could be outdated)
#cp /etc/hosts /var/spool/postfix/etc/hosts

mail_filter_url=$(curl -s https://api.github.com/repos/erebe/hmailfilter/releases/latest | grep browser_download_url | cut -d '"' -f 4)
curl -L -o hmailclassifier $mail_filter_url
chmod +x hmailclassifier

# Give right to the data volume
chown erebe:erebe -R /data
cp /etc/fetchmail/fetchmailrc /home/erebe/
chmod 600 /home/erebe/fetchmailrc 

# Start spamassassin
sa-update -v
spamd -d -s stderr | tee /proc/1/fd/1

# start postfix
postfix start

# lets give postfix some time to start
sleep 3

counter=-1
# wait until postfix is dead (triggered by trap)
while kill -0 "`cat /var/spool/postfix/pid/master.pid | sed 's/ //g'`"; do

  counter=$(($counter + 1))
  # Fetch mail from fallback mail server every 15min
  if [ $(( $counter % 30 )) -eq 0 ]
  then
    fetchmail --nodetach --nosyslog --ssl -f /home/erebe/fetchmailrc
  fi 

  # Update spamassassin filter every 12hours
  if [ $(( $counter % 1440 )) -eq 0 ]
  then
    sa-update -v
    counter=0
  fi 

  sleep 30
done
