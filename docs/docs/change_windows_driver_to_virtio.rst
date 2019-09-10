How to change the controller driver of a Windows VM to VirtIO
-------------------------------------------------------------

1. Add a new virtio disk (a small one, even 100mb will be enough. We will not be using it)
  - Use virt manager
  - or ``virsh edit``
2. Boot the machine
3. Make sure Windows recognises the disk controller and has the drivers for it (the disk should be visible in diskmgmt.msc)
4. Set boot to fail safe mode
   - Launch an elevated command prompt
   - Type ``bcdedit /set {current} safeboot minimal``
5. Shut down
6. Change the main disk to virtio
7. Boot. Now get into the admin prompt and disable failsafe mode.
 - Launch an elevated command prompt
 - Type ``bcdedit /deletevalue {current} safeboot``
8. Reboot and make sure everything works.
9. Now you can shut down the machine and remove the small virtio disk

Source: http://triplescomputers.com/blog/uncategorized/solution-switch-windows-10-from-raidide-to-ahci-operation/
