Qemu Guest Agent
================

Host Qemu Agent Prerequisits
----------------------------

Execute the following commands on your host:

.. prompt:: bash

	sudo mkdir -p /var/lib/libvirt/qemu/channel/target
	sudo chown -R libvirt-qemu:kvm /var/lib/libvirt/qemu/channel

And edit the file /etc/apparmor.d/abstractions/libvirt-qemu adding the following in the end:

.. prompt:: bash

	/var/lib/libvirt/qemu/channel/target/* rw,



Guest Agent Installation (VM)
-----------------------------

This installation must be done in your guest VM if you want to keep the correct time after hibernate.

Ubuntu and Debian
~~~~~~~~~~~~~~~~~

.. prompt:: bash

	sudo apt install qemu-guest-agent

Fedora
~~~~~~

.. prompt:: bash

	dnf install qemu-guest-agent

RedHat and CentOS
~~~~~~~~~~~~~~~~~

.. prompt:: bash

	yum install qemu-guest-agent

Windows
~~~~~~~

Follow the instructions provided by `Linux KVM <https://www.linux-kvm.org/page/WindowsGuestDrivers/Download_Drivers>`_


For VM's older than this functionality
--------------------------------------

If you try to use this function on VM's created before this function was implemented you must do one thing to make it work, first open the machine xml:

.. prompt:: bash

	virsh edit <name-or-id-of-your-machine>

And add the following inside the 'devices' section:

::

	<channel type="unix">
		<source mode="bind"/>
		<target type="virtio" name="org.qemu.guest_agent.0"/>
	</channel>

That's it, enjoy.
