FROM ubuntu:14.04
MAINTAINER Thomas VIAL

# Packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update -q --fix-missing && \
	apt-get -y upgrade && \
	apt-get -y install --no-install-recommends \
	postfix dovecot-core dovecot-imapd dovecot-pop3d gamin amavisd-new spamassassin razor pyzor \
	clamav clamav-daemon libnet-dns-perl libmail-spf-perl bzip2 file gzip p7zip unzip zip rsyslog \
    opendkim opendkim-tools opendmarc curl fail2ban ed iptables && \
	curl -sk http://neuro.debian.net/lists/trusty.de-m.libre > /etc/apt/sources.list.d/neurodebian.sources.list && \
	apt-key adv --recv-keys --keyserver hkp://pgp.mit.edu:80 0xA5D32F012649A5A9 && \
	apt-get update -q --fix-missing && apt-get -y upgrade fail2ban && \
    apt-get autoclean && rm -rf /var/lib/apt/lists/*

# Configures Dovecot
RUN sed -i -e 's/include_try \/usr\/share\/dovecot\/protocols\.d/include_try \/etc\/dovecot\/protocols\.d/g' /etc/dovecot/dovecot.conf
ADD target/dovecot/auth-passwdfile.inc /etc/dovecot/conf.d/
ADD target/dovecot/10-*.conf /etc/dovecot/conf.d/

# Enables Spamassassin and CRON updates
RUN sed -i -r 's/^(CRON|ENABLED)=0/\1=1/g' /etc/default/spamassassin

# Enables Amavis
RUN sed -i -r 's/#(@|   \\%)bypass/\1bypass/g' /etc/amavis/conf.d/15-content_filter_mode
RUN adduser clamav amavis
RUN adduser amavis clamav
RUN useradd -u 5000 -d /home/docker -s /bin/bash -p $(echo docker | openssl passwd -1 -stdin) docker

# Configure Fail2ban
ADD target/fail2ban/jail.conf /etc/fail2ban/jail.conf
# ADD target/fail2ban/filter.d/dovecot.conf /etc/fail2ban/filter.d/dovecot.conf
# RUN echo "ignoreregex =" >> /etc/fail2ban/filter.d/postfix-sasl.conf

# Enables Clamav
RUN chmod 644 /etc/clamav/freshclam.conf
RUN (crontab; echo "0 0,6,12,18 * * * /usr/bin/freshclam --quiet") | sort - | uniq - | crontab -
RUN freshclam

# Enables Pyzor and Razor
USER amavis
RUN razor-admin -create && razor-admin -register && pyzor discover
USER root

# Configure DKIM (opendkim)
# DKIM config files
ADD target/opendkim/opendkim.conf /etc/opendkim.conf
ADD target/opendkim/default-opendkim /etc/default/opendkim

# Configure DMARC (opendmarc)
ADD target/opendmarc/opendmarc.conf /etc/opendmarc.conf
ADD target/opendmarc/default-opendmarc /etc/default/opendmarc

# Configures Postfix
ADD target/postfix/main.cf target/postfix/master.cf /etc/postfix/
ADD target/bin/generate-ssl-certificate target/bin/generate-dkim-config /usr/local/bin/
RUN chmod +x /usr/local/bin/*

# Configuring Logs
RUN sed -i -r "/^#?compress/c\compress\ncopytruncate" /etc/logrotate.conf
RUN mkdir -p /var/log/mail && chown syslog:root /var/log/mail
RUN touch /var/log/mail/clamav.log && chown -R clamav:root /var/log/mail/clamav.log
RUN touch /var/log/mail/freshclam.log &&  chown -R clamav:root /var/log/mail/freshclam.log
RUN sed -i -r 's|/var/log/mail|/var/log/mail/mail|g' /etc/rsyslog.d/50-default.conf
RUN sed -i -r 's|LogFile /var/log/clamav/|LogFile /var/log/mail/|g' /etc/clamav/clamd.conf
RUN sed -i -r 's|UpdateLogFile /var/log/clamav/|UpdateLogFile /var/log/mail/|g' /etc/clamav/freshclam.conf
RUN sed -i -r 's|/var/log/clamav|/var/log/mail|g' /etc/logrotate.d/clamav-daemon
RUN sed -i -r 's|/var/log/clamav|/var/log/mail|g' /etc/logrotate.d/clamav-freshclam
RUN sed -i -r 's|/var/log/mail|/var/log/mail/mail|g' /etc/logrotate.d/rsyslog

# Get LetsEncrypt signed certificate
RUN curl -s https://letsencrypt.org/certs/lets-encrypt-x1-cross-signed.pem > /etc/ssl/certs/lets-encrypt-x1-cross-signed.pem
RUN curl -s https://letsencrypt.org/certs/lets-encrypt-x2-cross-signed.pem > /etc/ssl/certs/lets-encrypt-x2-cross-signed.pem

# Start-mailserver script
ADD target/start-mailserver.sh /usr/local/bin/start-mailserver.sh
RUN chmod +x /usr/local/bin/start-mailserver.sh

# SMTP ports
EXPOSE 25 587

# IMAP ports
EXPOSE 143 993

# POP3 ports
EXPOSE 110 995

CMD /usr/local/bin/start-mailserver.sh
