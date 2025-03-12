#!/bin/bash

DIR="/etc/pki/libvirt-spice"

SERVER_KEY=server-key.pem

while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--clean)
        CLEAN=1
        shift # past argument
      ;;
    -h|--help)
        HELP=1
        shift
  esac
done

if [ "$HELP" ]; then
    echo "$0 [--help] [--clean] [ip.address]"
    exit 0
fi

if [ "$CLEAN" ]; then
    rm -f "$SERVER_KEY"
    rm -f ca-key.pem ca-cert.pem server-key.csr server-key.pem server-key.pem.secure server-cert.pem
fi

SERVER_IP="$1"
if [ -z "$SERVER_IP" ]; then

    for i in `hostname -I`; do
        if [[ "$i" =~ [0-9]+\. ]];then
            if ! [[ "$i" =~ 192.168.12 ]]; then
                found_ip=$i
                break
            fi
        fi
    done
    read -p "IP address [$found_ip]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$found_ip}

    if [ -z "$SERVER_IP" ]; then
        echo "Error, server ip required."
        echo "  Usage: $0 ip"
        exit -1
    fi

fi

server_name_default=`hostname`

read -p "Server name [$server_name_default]: " server_name
server_name=${server_name:-$server_name_default}

cat >v3.ext <<EOT
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = $server_name
EOT

if [ -e "subject.txt" ]; then
    subject_old=`cat subject.txt`
    SUBJECT_DEFAULT=$subject_old
else
    SUBJECT_DEFAULT="/C=XX/CN=Foo Bar"
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
        -subj "${SUBJECT}/CN=my CA" || exit
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
cp ./*.pem $DIR || exit
chown :kvm  $DIR/*pem || exit
chmod g+rx $DIR/*pem || exit

# echo --host-subject
echo "your --host-subject is" \" `openssl x509 -noout -text -in server-cert.pem | grep Subject: | cut -f 10- -d " "` \"
echo "Certificate installed in $DIR"

