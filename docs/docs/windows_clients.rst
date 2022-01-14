SPICE client setup for Windows
==============================

Download Virt Viewer
--------------------

Windows clients requires the
`virt-viewer <https://virt-manager.org/download/sources/virt-viewer/>`__
tool to connect to their Virtual Machine.

Fix Windows registry
--------------------

If *virt-viewer* won't start automatically after when viewing the
virtual machine, add this to the Registry, or download `spice.reg <https://raw.githubusercontent.com/UPC/ravada/gh-pages/docs/docs/spice.reg>`_. (Thanks to `@gmiranda <https://github.com/gmiranda>`__).

::

    Windows Registry Editor Version 5.00

    [HKEY_CLASSES_ROOT\spice]
    @="URL:spice"
    "URL Protocol"=""

    [HKEY_CLASSES_ROOT\spice\DefaultIcon]
    @="C:\\Program Files\\VirtViewer v5.0-256\\bin\\remote-viewer.exe,1"

    [HKEY_CLASSES_ROOT\spice\Extensions]

    [HKEY_CLASSES_ROOT\spice\shell]
    @="open"

    [HKEY_CLASSES_ROOT\spice\shell\open]


    [HKEY_CLASSES_ROOT\spice\shell\open\command]
    @="\"C:\\Program Files\\VirtViewer v5.0-256\\bin\\remote-viewer.exe\" \"%1\""
