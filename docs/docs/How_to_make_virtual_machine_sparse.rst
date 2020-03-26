How to make a virtual machine disk sparse 
=========================================

When someone had deleted files to reduce the virtual machine img size, you need to do some actions in the server to return this free space to the server.

1. Install libguestfs-tools
	
	apt install libguestfs-tools

2. Check the real size of the virtual machine size
	
	qemu-img info file.qcow2

The output will be something like that: 

	disk size: 10G

3. Make a backup copy of the img file

	cp -p file.qcow2 /another/directory/file.backup.qcow2

4. Now use virt-sparsify
	
	virt-sparsify --in-place file.qcow2

5. Check if the virtual img size has been reduced

	qemu-img infor file.qcow2

	disk size: 5G

6. Check if the virtual machine works.
