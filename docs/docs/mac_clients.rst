SPICE client setup for MacOS
============================

Virt-Viewer
===========
If you don't have brew installed, visit `Homebrew <https://brew.sh/>`_.

Follow this steps:

1. Install a working (and compiled) version of `virt-viewer <https://www.spice-space.org/osx-client.html>`_. You may view the homebrew package's upstream source on `GitHub <https://github.com/UPC/homebrew-virt-manager>`_.

::

	brew tap UPC/homebrew-virt-manager
	brew install virt-manager virt-viewer

2. Once that's installed should be able make a call **remote-viewer** with a spice file, for example 405.vv file downloaded from Ravada.
    
::

	remote-viewer 405.vv
	

Associate SPICE files with remove viewer
========================================

We want remote-viewer to automatically start and open the session when we double click the VM entry in Ravada. To do that we need to first create a small helper application.

1. Launch Automator and select Application from the dropdown list, when prompted.

2. Search for shell and drag to the right. The contents:

::

	/usr/local/bin/remote-viewer "$@"

Make sure to select as arguments for passing the input. Save as **~/Applications/ravada-spice-launcher.app**

3. Locate a ravada spice file .vv file or any file with .vv extension, and then hold down the Control key. With the Control key pressed, click on the .vv file, and then right click, open with, look for the .app file you just made, and check the Always Open With checkbox in the bottom of the dialog. This took a couple of tries for it to stick, but eventually remembered.

In Chrome, click on the small arrow on the list of downloads at the bottom, and select "Always open files of this type" and select ravada-spice-launcher app.

If everything is set up correctly you should be able to double-click on the VM and remote-viewer should start up and take care of the rest.

That's all. Enjoy Ravada.


There is another way to do it if you have some troubles, install only RemoteViewer.
RemoteViewer
============

::

	brew install --cask remoteviewer

Usage:
 remote-viewer console.vv

Binary path in my env is /opt/homebrew/bin/remote-viewer.

Remember to allow this application in Settings -> Privacy & Security

You can see this message: 
 "RemoteViewer.app" was blocked from use because it is not from an identified developer
Enable the button: Open Anyway



Problems
========

1. If you have some trouble, check your remote-viewer path. Maybe it is different from /usr/local/bin. 

::
 
 	which remote-viewer

Other path can be: /opt/homebrew/bin/remote-viewer


2. You have a similar repo installed. 

::  

	Error: Formulae found in multiple taps:

Fix with:
 
 ::
 	
	brew untap jeffreywildman/virt-manager
