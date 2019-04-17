# Testing remote nodes

To test remote nodes you need them created in the host you are testing
with KVM.

Install a Linux and allow ssh password-less then write down the configuration
file: t/etc/remote\_vm\_2.conf.

In this example we have two virtual machines called: ztest-1 and ztest-2:

    ztest-1:
        vm:
            - KVM
            - Void
        host: 192.168.122.151
        public_ip: 192.168.122.250
    ztest-2:
        vm:
            - KVM
            - Void
        host: 192.168.122.152
        public_ip: 192.168.122.251


## Configuration

Each entry has the name of the virtual machine as you can see when you virsh list
in KVM.

- vm is the name of the Virtual Managers type it accepts. At least it should contain
- KVM and Void, that is used to test generic mock virtual machines.
- host is the ip of the virtual machine.
- public\_ip is optional and is used to test nodes with more than one IP.
