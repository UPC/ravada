SPICE client setup for MacOS
============================

RemoteViewer
============

Best option, 

::

	brew install --cask remoteviewer

Usage:
 remote-viewer console.vv

Binary path in my env is /opt/homebrew/bin/remote-viewer.


Virt-Viewer
===========

.. Warning:: We have error reports in the brew package due to changes in source URLs.


1. Install a working (and compiled) version of `virt-viewer <https://www.spice-space.org/osx-client.html>`_. You may view the homebrew package's upstream source on `GitHub <https://github.com/jeffreywildman/homebrew-virt-manager>`_.

::

	brew tap jeffreywildman/homebrew-virt-manager
	brew install virt-viewer

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

Problems
========

If you have some trouble, check your remote-viewer path. Maybe it is different from /usr/local/bin. 

::
 
 	which remote-viewer

Other path can be: /opt/homebrew/bin/remote-viewer

