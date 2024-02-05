FROM debian:bookworm-slim


LABEL org.opencontainers.image.source https://github.com/erebe/server

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates cron dumb-init wget dovecot-core dovecot-imapd procps curl rspamd fetchmail netbase && \
    wget https://github.com/erebe/personal-server/releases/download/vsmtp/vsmtp.deb && \
    dpkg -i vsmtp.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists *.deb && \
    useradd -ms /bin/bash erebe

#ADD https://github.com/erebe/personal-server/releases/download/vsmtp/vsmtp /usr/sbin/vsmtp
RUN chmod +x /usr/sbin/vsmtp ; mkdir /etc/vsmtp/domain-enabled/erebe.eu/

# Dovcecot configuration
# Disable imaps port, and local network as trusted peer
RUN sed -i 's/#login_trusted_networks =/login_trusted_networks = fd00:cafe::\/32/' /etc/dovecot/dovecot.conf && \
    # The only one user will have its mailbox at /data
    sed -iE 's#mail_location =.*#mail_location = maildir:/data#' /etc/dovecot/conf.d/10-mail.conf && \
    # Disable TLS, managed by tls proxy
    sed -i -e 's#ssl = yes#ssl = no#' \
      -e 's/ssl_cert =/#ssl_cert =/' \
      -e 's/ssl_key =/#ssl_key =/' \
      /etc/dovecot/conf.d/10-ssl.conf && \
    # User passwd db file, need to be mounted as a secret
    sed -i 's#/etc/dovecot/users#/etc/dovecot/users/users#' /etc/dovecot/conf.d/auth-passwdfile.conf.ext && \
    rm -f /etc/dovecot/users && \
    # Enable passwd db
    sed -i 's#\#!include auth-passwdfile.conf.ext#!include auth-passwdfile.conf.ext#' /etc/dovecot/conf.d/10-auth.conf && \
    # Set logging to STDOUT/STDERR
    sed -i -e 's,#log_path = syslog,log_path = /dev/stderr,' \
           -e 's,#info_log_path =,info_log_path = /dev/stdout,' \
           -e 's,#debug_log_path =,debug_log_path = /dev/stdout,' \
        /etc/dovecot/conf.d/10-logging.conf 

COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY dovecot_purge /etc/cron.daily/dovecot_purge
COPY dovecot_reload /etc/cron.weekly/reload_dovecot
#COPY fetchmail_remote /etc/cron.hourly/fetchmail_remote
COPY vsmtp/config.vsl /etc/vsmtp/conf.d/config.vsl
COPY vsmtp/filter.vsl /etc/vsmtp/filter.vsl
COPY vsmtp/erebe.eu /etc/vsmtp/domain-enabled/erebe.eu 

VOLUME /data
VOLUME /etc/dovecot/users
EXPOSE 25
EXPOSE 143

#USER erebe

ENTRYPOINT [ "/usr/bin/dumb-init", "--" ]
CMD ["/docker-entrypoint.sh"]
