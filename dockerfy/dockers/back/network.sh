#!/bin/sh

chmod 666 /dev/kvm
virsh net-create ./default.xml