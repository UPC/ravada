# Windows SPICE Clients

## Download Virt Viewer

Windows clients requires the [_virt-viewer_]( https://virt-manager.org/download/sources/virt-viewer/virt-viewer-x86-5.0.msi) tool to connect to their Virtual Machine.

## Fix Windows registry

If _virt-viewer_ won't start automatically after when viewing the virtual machine,
add  this to the Registry, thanks to [@gmiranda](https://github.com/gmiranda)

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
