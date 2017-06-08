Hardening Spice security with TLS
=================================

TLS support allows to encrypt all/some of the channels Spice uses for its communication. A separate port is used for the encrypted channels.


For example in this VM with id 1, the connection is possible both through TLS and without any encryption:

::
    <graphics type='spice' autoport='yes' listen='172.17.0.1' keymap='es'>


::
    $ virsh domdisplay 1
    spice://172.17.0.1:5901?tls-port=5902

For example in VM with id 2, you can edit the libvirt graphics node if you want to change that behaviour and only allow connections through TLS: 

::
    <graphics type='spice' autoport='yes’ listen='171.17.0.1' defaultMode='secure'>

::
    $ virsh domdisplay 2
    spice://171.17.0.1?tls-port=5900


More information `about <https://www.spice-space.org/docs/manual/>`_
