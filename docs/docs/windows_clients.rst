Windows SPICE Clients
=====================

Download Virt Viewer
--------------------

Windows clients requires the
`virt-viewer <https://virt-manager.org/download/sources/virt-viewer/virt-viewer-x86-5.0.msi>`__
tool to connect to their Virtual Machine.

Fix Windows registry
--------------------

If *virt-viewer* won't start automatically after when viewing the
virtual machine, add this to the Registry, thanks to
`@gmiranda <https://github.com/gmiranda>`__.

.. literalinclude:: https://raw.githubusercontent.com/UPC/ravada/gh-pages/docs/docs/spice.reg
