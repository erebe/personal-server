FROM alpine:latest

RUN apk update && \
    apk add ca-certificates dovecot su-exec && \
    rm -rf /var/cache/apk/* && \
    adduser -D erebe && \
    mkdir /data && chmod 777 -R /data && \
    # Disable imap port, only allow imaps
    sed -i 's/#port = 143/port = 0/' /etc/dovecot/conf.d/10-master.conf && \
    # The only one user will have its mailbox at /data
    sed -i 's#\#mail_location =#mail_location = maildir:/data#' /etc/dovecot/conf.d/10-mail.conf && \
    # User passwd db file, need to be mounted as a secret
    sed -i 's#/etc/dovecot/users#/etc/dovecot/users/users#' /etc/dovecot/conf.d/auth-passwdfile.conf.ext && \
    rm -f /etc/dovecot/users

VOLUME /data
VOLUME /etc/dovecot/users
EXPOSE 993

CMD chown -R erebe:erebe /data && \
	dovecot -F
