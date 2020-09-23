Keeping the Base updated
========================

Base volumes
------------

Once a base is prepared and clones are made the base becomes *read only*.
This is required because the clones disk volumes depend of the data stored
in the bases. So it is not possible to change the base because the clones
storage would become corrupted.

.. image:: images/base_clone_volumes.png

Rebasing
--------

There is a way to keep the base updated for all the clones. This require
you create a new base from the old one and make all the clones depend from
the new one. This is called *rebase* and requires careful preparation in adavance.

