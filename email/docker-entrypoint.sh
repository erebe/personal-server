#!/bin/bash 

# move it to be able to chmod it. k8s secret is read only fs
cp /etc/fetchmail/fetchmailrc /home/erebe/
chmod 600 /home/erebe/fetchmailrc

chown -R erebe:erebe /data
mkdir /data/mail-tmp

mail_filter_url=$(curl -s https://api.github.com/repos/erebe/hmailfilter/releases/latest | grep browser_download_url | cut -d '"' -f 4)
curl -L -o hmailclassifier $mail_filter_url
chmod +x hmailclassifier

cron -f &
/usr/bin/rspamd -c /etc/rspamd/rspamd.conf -f -i &
dovecot -F &
(while true; do vsmtp -c /etc/vsmtp/vsmtp.vsl --no-daemon --stdout --timeout 6h ; done) &

while true 
do 
  for email_pre_spam in $(find /data/mail-tmp -name '*.eml')
  do
    echo "Moving email ${email_pre_spam}"
    email="${email_pre_spam}.spam"

    rspamc --mime < ${email_pre_spam} > ${email} 
    folder=$(./hmailclassifier < ${email} | sed -E 's#^\.([^/]+)/$#\1#')
    doveadm mailbox create -u erebe $folder 2> /dev/null

    # If not spam put it also in INBOX for easy ready on mobile
    if [ "$folder" != "Spam" ]
    then
      /usr/lib/dovecot/dovecot-lda -d erebe -m INBOX < ${email}
    fi
    /usr/lib/dovecot/dovecot-lda -d erebe -m "$folder" < ${email}


    rm ${email_pre_spam} ${email}


  done

  sleep 1
done

