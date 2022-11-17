FROM alpine:3.17 
#newer version does not have procmail binary (due to being unmaintened and CVEs)

LABEL org.opencontainers.image.source https://github.com/erebe/server

RUN apk update && \
    apk add ca-certificates postfix procmail spamassassin spamassassin-client curl fetchmail dumb-init && \
    rm -rf /var/cache/apk/* && \
    adduser -D erebe && \
    mkdir /etc/fetchmail && \
    mkdir /home/erebe/procmail && chown erebe:erebe -R /home/erebe && \
    mkdir /data && chmod 777 -R /data && chown erebe:erebe -R /data && \
    # Generate virtual alias map
    echo '@erebe.eu erebe' > /etc/postfix/virtual && \
    postmap /etc/postfix/virtual && \
    newaliases  

ADD docker-entrypoint.sh /usr/bin/docker-entrypoint.sh
ADD procmailrc /etc/postfix/procmailrc
ADD main.cf /etc/postfix/main.cf
ADD master.cf /etc/postfix/master.cf
ADD fetchmailrc /etc/fetchmail

VOLUME /etc/ssl/postfix
VOLUME /data
EXPOSE 25
EXPOSE 465

ENTRYPOINT [ "/usr/bin/dumb-init", "--" ]
CMD ["/usr/bin/docker-entrypoint.sh"]

