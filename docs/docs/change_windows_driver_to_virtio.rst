How to change the controller driver of a Windows VM to VirtIO
------------------------------------------------------

#) Add a new virtio disk (a small one, even 100mb will be enough. We will not be using it)
   - Use virt manager
   - or ``virsh edit``
#) Boot the machine
#) Make sure Windows recognises the disk controller and has the drivers for it (the disk should be visible in diskmgmt.msc)
#) Set boot to fail safe mode
   - Launch an elevated command prompt
   - Type ``bcdedit /set {current} safeboot minimal``
#) Shut down
#) Change the main disk to virtio
#) Boot. Now get into the admin prompt and disable failsafe mode.
   - Launch an elevated command prompt
   - Type ``bcdedit /deletevalue {current} safeboot``
#) Reboot and make sure everything works.
#) Now you can shut down the machine and remove the small virtio disk

Source: http://triplescomputers.com/blog/uncategorized/solution-switch-windows-10-from-raidide-to-ahci-operation/
