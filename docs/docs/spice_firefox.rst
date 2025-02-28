Installing the SPICE virt-viewer in Firefox
===========================================

SPICE is a protocol that lets you access the virtual machine screen.

GNU/Linux
---------

For Spice redirection you will need to install Virt-Manager. It is available
as a package for most of the Linux Distributions.

Ubuntu and Debian based distros
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

  sudo apt install virt-viewer


Microsoft Windows
-----------------

You need to download and install the viewer

https://virt-manager.org/download.html

and the USB drivers

https://www.spice-space.org/download/windows/usbdk/UsbDk_1.0.22_x64.msi

Be aware that in Windows, Spice redirection is not automatic. It may be
necessary to associate the protocol.
To make this possible, copy the content of spice.reg to an ASCII file
and save it with a .reg extension, then execute the file.
Please, make sure you have the right path and release, according to your PC configuration.

::

  Windows Registry Editor Version 5.00
  
  [HKEY_CLASSES_ROOT\spice]
  @="URL:spice"
  "URL Protocol"=""
  
  [HKEY_CLASSES_ROOT\spice\DefaultIcon]
  @="C:\\Program Files\\VirtViewer v9.0-256\\bin\\remote-viewer.exe,1"
  
  [HKEY_CLASSES_ROOT\spice\Extensions]
  [HKEY_CLASSES_ROOT\spice\shell]
  @="open"
  
  [HKEY_CLASSES_ROOT\spice\shell\open]
  [HKEY_CLASSES_ROOT\spice\shell\open\command]
  @="\"C:\\Program Files\\VirtViewer v9.0-256\\bin\\remote-viewer.exe\" \"%1\""


For more information, check the Windows Clients documentation.
http://ravada.readthedocs.io/en/latest/docs/windows_clients.html


macOS
-----

Follow these steps for Spice client setup link .

https://ravada.readthedocs.io/en/latest/docs/macos_spice_client.html

Frequently Asked Questions
==========================

Once installed, SPICE files are not open automatically
------------------------------------------------------

The downloaded file will be in the "Downloads" folder. Right click
on the file and request it to be open always with "remove-viewer".

Clicking on the SPICE URL does nothing
--------------------------------------

The spice URL :  spice://host.address.example:port should call
the viewer when clicking. If not, you can manually add it to your
browser.

1. Click the menu button , click Help and select More Troubleshooting Information.
The Troubleshooting Information tab will open.
Under the Application Basics section next to Profile Directory, click Open
Directory. Your profile folder will open.

2. Click the View menu and select Show Hidden Files if it isn't already checked.

3. Double click the folder marked .mozilla.

4. Double click the folder marked firefox. Your profile folder is within this folder. If you only have one profile, its folder would have "default" in the name.

Copy the handlers.json file to a handlers.json.backup file

Edit handlers.json and add an entry for SPICE:

::

  "spice":{"action":4}}

Add this entry in between the other options with proper comma separation
