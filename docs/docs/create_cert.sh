#!/bin/bash

DIR="/etc/pki/libvirt-spice"

SERVER_IP="$1"
if [ -z "$SERVER_IP" ]; then
    echo "Error, server ip required."
    echo "  Usage: $0 ip"
    exit -1
fi

SUBJECT_DEFAULT="/C=XX/CN=Foo Bar"

if [ -e "subject.txt" ]; then
    subject_old=`cat subject.txt`
    SUBJECT_DEFAULT=$subject_old
fi

echo -n "Subject [$SUBJECT_DEFAULT] : "
read subject2
SUBJECT=${subject2:-$SUBJECT_DEFAULT}

SERVER_KEY=server-key.pem

# creating a key for our ca
if [ ! -e ca-key.pem ]; then
    openssl genrsa -des3 -out ca-key.pem 2048
else
    echo -n Using ca-key created on 
    stat ca-key.pem | tail -1 | awk '{ print " " $2 " " $3 }'
fi


# creating a ca
if [ ! -e ca-cert.pem ] || [ "$SUBJECT" != "$subject_old" ]; then

    openssl req -new -x509 -nodes -sha256 -days 1095 -key ca-key.pem -out ca-cert.pem \
        -subj "${SUBJECT}/CN=my CA"
fi
# create server key
if [ ! -e $SERVER_KEY ]; then
    openssl genrsa -out $SERVER_KEY
fi
# create a certificate signing request (csr)
if [ ! -e server-key.csr ] || [ "$SUBJECT" != "$subject_old" ]; then
    echo "Creating server-key.csr"
    openssl req -new -nodes -key $SERVER_KEY -out server-key.csr -subj "$SUBJECT/CN=$SERVER_IP"
    if [ $? -ne 0 ]; then
        echo $?
        exit
    fi
fi
# signing our server certificate with this ca
if [ ! -e server-cert.pem ] || [ "$SUBJECT" != "$subject_old" ]; then

    openssl x509 -req -days 1095 -in server-key.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out server-cert.pem -sha256 -extfile v3.ext

    echo $SUBJECT > subject.txt
fi

# now create a key that doesn't require a passphrase
openssl rsa -in $SERVER_KEY -out $SERVER_KEY.insecure
mv $SERVER_KEY $SERVER_KEY.secure
mv $SERVER_KEY.insecure $SERVER_KEY

# copy *.pem file to /etc/pki/libvirt-spice
if [ ! -d "$DIR" ]
then
    mkdir -p $DIR
fi
cp ./*.pem $DIR
chown :kvm  $DIR/*pem
chmod g+rx $DIR/*pem

# echo --host-subject
echo "your --host-subject is" \" `openssl x509 -noout -text -in server-cert.pem | grep Subject: | cut -f 10- -d " "` \"
echo "Certificate installed in $DIR"

