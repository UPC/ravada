Spinoff Clone
=============

Spinoff clone releases a virtual machine from its bases. It becomes
independent and you can use it on its own.

Clones
------

In this example we have bases with nested bases and clones.

.. image:: ../../img/spinoff_before.jpg

Proceed to Spinoff
------------------

We want to spinoff the virtual machine *alpine-2-1*, so we click in its name
and then in the *Base" tab with press *Spinoff clone*.

.. image:: ../../img/spinoff_button.jpg

After confirm this is what we want Ravada will proceed to spinoff the clone
from all its bases.

.. image:: ../../img/spinoff_after.jpg

What happened behind the scenes ?
---------------------------------

These are the disk volumes for the machine *alpine-2-1* before the spinoff.
All of them are base-chained to alpine-2 and then to alpine.

Volume files before spinoff:

::

    <source file='/home/images.2/alpine-2-1-vda.alpine-2-av-vda.qcow2'/>
        <source file='/home/images.2/alpine-2-av-vda.ro.qcow2'/>
            <source file='/home/images.2/alpine-vda.ro.qcow2'/>

Volume files after spinoff:

::

    <source file='/home/images.2/alpine-2-1-vda.alpine-2-av-vda.qcow2' index='4'/>

When we inspect the disk files volumes after  the spinoff we can see it
has no dependencies. So its contents are not incremental from other disk volumes.
