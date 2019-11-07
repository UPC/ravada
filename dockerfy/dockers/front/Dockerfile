FROM ubuntu:18.04
LABEL maintainer="ravada@telecos.upc.edu"
LABEL description="Ravada Frontend"

RUN apt-get update \
 && apt-get install -y -q --no-install-recommends \
    perl libmojolicious-perl libauthen-passphrase-perl \
    libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl \
    libproc-pid-file-perl libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl \
    libmoose-perl libjson-xs-perl perlmagick libmoosex-types-netaddr-ip-perl libsys-statistics-linux-perl \
    libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl liblocale-maketext-lexicon-perl \
    libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl debconf adduser libdigest-sha-perl libnet-ssh2-perl \
    libfile-rsync-perl libdate-calc-perl libparallel-forkmanager-perl libdatetime-perl libencode-locale-perl netcat-openbsd \
    libio-stringy-perl libvirt-clients liblwp-useragent-determined-perl supervisor net-tools apt-utils lsof mysql-client \
	curl bash vim wget \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ADD http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb /tmp/
RUN dpkg -i /tmp/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb \
 && rm /tmp/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb \
 && mkdir -p /var/log/supervisor \
 && mkdir -p /run/sshd

EXPOSE 3000

ENV PERL5LIB /root/local/lib/perl5:/root/lib/:/ravada

COPY supervisord.conf /etc/supervisord.conf

#RUN mkdir /ravada
#ADD src/ravada /ravada
COPY ravada.conf /etc/ravada.conf
WORKDIR /ravada

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
