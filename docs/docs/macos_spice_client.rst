SPICE client setup for MacOS
============================

Virt-Viewer
-----------
If you don't have brew installed, visit `Homebrew <https://brew.sh/>`_.

Follow this steps:

1. Install **virt-viewer** from the `terminal <https://support.apple.com/en-gb/guide/terminal/apd5265185d-f365-44cb-8b09-71a064a42125/mac>`_. The formulae for **virt-manager** and several of its dependencies have since been integrated into homebrew-core.

::

	brew tap jeffreywildman/homebrew-virt-manager
	brew install virt-viewer
	virt-viewer --version

2. Once that's installed should be able make a call **remote-viewer** with a spice file, for example 405.vv file downloaded from Ravada.
    
::

	remote-viewer 405.vv

3. If you want to check the version,

::

	/opt/homebrew/bin/remote-viewer --version
	remote-viewer version 11.0
 	/opt/homebrew/bin/virt-viewer --version
	virt-viewer version 11.0

Associate SPICE files with remote viewer
========================================

We want remote-viewer to automatically start and open the session when we double click the VM entry in Ravada. To do that we need to first create a small helper application.

1. Launch Automator and select Application from the dropdown list, when prompted.

2. Search for shell and drag to the right. The contents:

::

	/usr/local/bin/remote-viewer "$@"

Make sure to select as arguments for passing the input. Save as **~/Applications/ravada-spice-launcher.app**

3. Locate a ravada spice file .vv file or any file with .vv extension, and then hold down the Control key. With the Control key pressed, click on the .vv file, and then right click, open with, look for the .app file you just made, and check the Always Open With checkbox in the bottom of the dialog. This took a couple of tries for it to stick, but eventually remembered.

In Chrome, click on the small arrow on the list of downloads at the bottom, and select "Always open files of this type" and select ravada-spice-launcher app.

In system, right-click on file.vv, then click on Get info. In the Get Info options find Open with section, where you can easily select which application you would like to be the default for opening your file.

If everything is set up correctly you should be able to double-click on the VM and remote-viewer should start up and take care of the rest.

That's all. Enjoy Ravada.

Problems
========

1. If you have some trouble, check your remote-viewer path. Maybe it is different from /usr/local/bin. 

::
 
 	which remote-viewer

Other path can be: /opt/homebrew/bin/remote-viewer


2. You have a similar repo installed.

::  

	Error: Formulae found in multiple taps:

Check with brew tap:
 
 ::
 	
	brew tap

You can remove existing tap with

::

	brew untap <your_existing_tap>
