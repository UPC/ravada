#!/bin/bash

SERVER_IP="$1"
if [ -z "$SERVER_IP" ]; then
    echo "Error, server ip required."
    echo "  Usage: $0 ip"
    exit -1
fi

# change the next line
SUBJECT="/C=IL/L=Raanana/O=Red Hat"

SERVER_KEY=server-key.pem

# creating a key for our ca
if [ ! -e ca-key.pem ]; then
    openssl genrsa -des3 -out ca-key.pem 2048
fi
# creating a ca
if [ ! -e ca-cert.pem ]; then
    openssl req -new -x509 -nodes -sha256 -days 1095 -key ca-key.pem -out ca-cert.pem \
        -subj "${SUBJECT}/CN=my CA"
fi
# create server key
if [ ! -e $SERVER_KEY ]; then
    openssl genrsa -out $SERVER_KEY
fi
# create a certificate signing request (csr)
if [ ! -e server-key.csr ]; then
    openssl req -new -nodes -key $SERVER_KEY -out server-key.csr -subj "$SUBJECT/CN=$SERVER_IP"
fi
# signing our server certificate with this ca
if [ ! -e server-cert.pem ]; then
    openssl x509 -req -days 1095 -in server-key.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -sha256 -extfile v3.ext
fi

# now create a key that doesn't require a passphrase
openssl rsa -in $SERVER_KEY -out $SERVER_KEY.insecure
mv $SERVER_KEY $SERVER_KEY.secure
mv $SERVER_KEY.insecure $SERVER_KEY

# copy *.pem file to /etc/pki/libvirt-spice
if [ ! -d "/etc/pki/libvirt-spice" ]
then
    mkdir -p /etc/pki/libvirt-spice
fi
cp ./*.pem /etc/pki/libvirt-spice
chown :kvm  /etc/pki/libvirt-spice/*pem
chmod g+rx /etc/pki/libvirt-spice/*pem

# echo --host-subject
echo "your --host-subject is" \" `openssl x509 -noout -text -in server-cert.pem | grep Subject: | cut -f 10- -d " "` \"

