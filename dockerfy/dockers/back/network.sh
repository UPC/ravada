#!/bin/sh

chmod 666 /dev/kvm
virsh net-define --file default.xml
virsh net-start default
virsh net-autostart --network default