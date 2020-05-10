FROM ubuntu:18.04
LABEL maintainer="ravada@telecos.upc.edu"
LABEL description="Ravada Backend + KVM"
ARG DEBIAN_FRONTEND=noninteractive
ENV RAVADA_BRANCH="develop"

RUN  apt-get update \
 &&  apt-get install -y -q --no-install-recommends \
    perl libmojolicious-perl libauthen-passphrase-perl \
    libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl \
    libproc-pid-file-perl libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl \
    libmoose-perl libjson-xs-perl perlmagick libmoosex-types-netaddr-ip-perl libsys-statistics-linux-perl \
    libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl liblocale-maketext-lexicon-perl \
    libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl debconf adduser libdigest-sha-perl libnet-ssh2-perl \
    libfile-rsync-perl libdate-calc-perl libparallel-forkmanager-perl libdatetime-perl libencode-locale-perl netcat-openbsd \
    liblwp-useragent-determined-perl libvirt-clients supervisor net-tools openssh-client apt-utils curl libpbkdf2-tiny-perl \
    libio-stringy-perl libvirt-daemon-system libvirt-clients netcat-openbsd qemu-kvm qemu-utils iproute2 wget bridge-utils firewalld dnsmasq iptables ebtables \
    tzdata unzip \
 && apt-get clean && \
   echo "**** download ravada files ****" && \
   mkdir /ravada && \
   curl -o \
   /tmp/ravada.zip -L \
   "https://github.com/UPC/ravada/archive/${RAVADA_BRANCH}.zip" && \
   unzip /tmp/ravada.zip -d /tmp/ravadatmp && \
   cp -r /tmp/ravadatmp/ravada-develop/* /ravada && \
   cp /ravada/dockerfy/dockers/back/network.sh / && \
   cp /ravada/dockerfy/dockers/back/default.xml / && \
   cp /ravada/dockerfy/dockers/back/ravada.conf /etc/ && \
   cp /ravada/dockerfy/dockers/back/supervisord.conf /etc/ \
 && rm -rf \ 
   /var/lib/apt/lists/* \
   /tmp/*

ADD http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb /tmp/
RUN dpkg -i /tmp/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb \
 && rm /tmp/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb \
 && echo "listen_tls = 0" >> /etc/libvirt/libvirtd.conf \
 && echo 'listen_tcp = 1' >> /etc/libvirt/libvirtd.conf \
#  && mkdir -p /root/.ssh \
#  && echo "Host ravada-kvm StrictHostKeyChecking no" >/root/.ssh/config \
#  && chmod 600 /root/.ssh/config \
 && mkdir -p /var/log/supervisor \
 && mkdir -p /run/sshd
 



EXPOSE 5900-5950
EXPOSE 55900-55950



#RUN mkdir /ravada
#ADD src/ravada /ravada

WORKDIR /ravada

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
