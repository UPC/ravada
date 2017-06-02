Work in progress

1- Add a new virtio disk (a small one, even 100mb will be enough. We will not be using it)
2- Boot the machine
3- Make sure Windows recognises the disk controller and has the drivers for it (the disk should be visible in diskmgmt.msc)
4- Set boot to fail safe mode [http://triplescomputers.com/blog/uncategorized/solution-switch-windows-10-from-raidide-to-ahci-operation/]
5- Shut down
6- Change the main disk to virtio
7- Boot. Now get into the admin prompt and disable failsafe mode.
8- Reboot and make sure everything works.
9- Now you can shut down the machine and remove the small virtio disk
