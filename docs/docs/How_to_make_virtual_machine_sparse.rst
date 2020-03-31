How to make a virtual machine disk sparse 
=========================================

When someone had deleted files to reduce the virtual machine img size, you need to do some actions in the server to return this free space to the server.

Steps
-----

1. Install libguestfs-tools

.. prompt:: bash $

	apt install libguestfs-tools

2. Check the real size of the virtual machine size
	
.. prompt:: bash $

	qemu-img info file.qcow2

The output will be something that contains this information: 

	*disk size: 10G*

3. Make a backup copy of the img file

.. prompt:: bash $

	cp -p file.qcow2 /another/directory/file.backup.qcow2

4. Now use virt-sparsify
	
.. prompt:: bash $

	virt-sparsify --in-place file.qcow2

5. Check if the virtual img size has been reduced

.. prompt:: bash $

	qemu-img info file.qcow2

The output now shows that the size has decreased:

	*disk size: 5G*

6. Check if the virtual machine works.

7. If the virtual machine works, then remove the img file backup.

More information about https://pve.proxmox.com/wiki/Shrink_Qcow2_Disk_Files#

