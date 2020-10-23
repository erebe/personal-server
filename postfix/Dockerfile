FROM alpine:3.11 
#newer version does not have procmail binary (due to being unmaintened and CVE)

RUN apk update && \
    apk add ca-certificates postfix procmail spamassassin spamassassin-client curl && \
    rm -rf /var/cache/apk/* && \
    adduser -D erebe && \
    mkdir /home/erebe/procmail && \
    mkdir /data && chmod 777 -R /data && chown erebe:erebe -R /data && \
    # Generate virtual alias map
    echo '@erebe.eu erebe' > /etc/postfix/virtual && \
    postmap /etc/postfix/virtual && \
    ################################
    ## EDIT CONFIG
    ################################
    sed -i -e 's|#mydomain = domain.tld$|mydomain = erebe.eu|' \
    	   -e 's|#myhostname = host.domain.tld$|myhostname = erebe.eu|' \
    	   -e 's|#mydestination = $myhostname, localhost.$mydomain, localhost$|mydestination = $myhostname, localhost.$mydomain, localhost, mail.$mydomain|' \
    	   -e 's|#mynetworks_style = host$|mynetworks_style = host|' \
    	   -e 's|#mailbox_command = /some/where/procmail$|mailbox_command = procmail /etc/postfix/procmailrc -a "$EXTENSION"|' \
    	   -e 's|#alias_maps = hash:/etc/aliases$|alias_maps = hash:/etc/postfix/aliases|' \
	   /etc/postfix/main.cf && \
    echo 'smtpd_tls_security_level = may' >> /etc/postfix/main.cf && \
    echo 'smtpd_tls_cert_file = /etc/ssl/postfix/tls.crt' >> /etc/postfix/main.cf && \
    echo 'smtpd_tls_key_file = /etc/ssl/postfix/tls.key' >> /etc/postfix/main.cf && \
    echo 'message_size_limit = 204800000' >> /etc/postfix/main.cf && \
    echo 'maillog_file = /dev/stdout' >> /etc/postfix/main.cf && \
    echo 'inet_interfaces = all' >> /etc/postfix/main.cf && \
    ###################################
    ## GENERATE ALIAS DB
    ###################################
    newaliases  


ADD docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
ADD procmailrc /etc/postfix/procmailrc

VOLUME /etc/ssl/postfix
VOLUME /data
EXPOSE 25
EXPOSE 465

CMD ["/usr/bin/docker-entrypoint.sh"]

