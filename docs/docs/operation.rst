Operation
=========


.. note:: Must run from the command line interface (CLI)

Create users
------------

.. prompt:: bash

    sudo ./usr/sbin/rvd_back --add-user=username
    sudo ./usr/sbin/rvd_back --add-user-ldap=username

Import KVM virtual machines
---------------------------

Usually, virtual machines are created within ravada, but they can be
imported from existing KVM domains. Once the domain is created :

.. prompt:: bash

    sudo ./usr/sbin/rvd_back --import-domain=a

It will ask the name of the user the domain will be owned by. You must
enter a valid username that will own the virtual machine within Ravada.

Also you will be asked wether you want to spinoff the disk volumes or
not.

.. ::

  Do you want to spinoff the virtual machine volumes ?
  This will flatten the volumes out of backing files. Please answer y/n [no]:

You probably want to answer **no**. You should answer *yes* if you created
the volumes with a backend file and want to flatten them out just. It may
be the case if you migrated the virtual machine from another server.

View all rvd\_back options
--------------------------

In order to manage your backend easily, rvd\_back has a few flags that
lets you made different things (like changing the password for an user).

If you want to view the full list, execute:

.. prompt:: bash

    sudo rvd_back --help

Admin
-----

.. note:: Must run from the frontend

Create Virtual Machine
~~~~~~~~~~~~~~~~~~~~~~

Go to Admin -> Machines and press *New Machine* button.

If anything goes wrong check Admin -> Messages for information from the
Ravada backend.

ISO MD5 missmatch
~~~~~~~~~~~~~~~~~

When downloading the ISO, it may fail or get old. Check the error
message for the name of the ISO file and the ID.

Option 1: clean ISO and MD5
~~~~~~~~~~~~~~~~~~~~~~~~~~~

-  Remove the ISO file shown at the error message
-  Clean the MD5 entry in the database:

.. prompt:: bash

    mysql -u rvd_user -p ravada mysql > update iso_images set md5='' WHERE id=*ID*

Then you have to create the machine again from scratch and make it
download the ISO file.

Option 2: refresh the ISO table
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you followed *Option 1* and it still fails you may have an old
version of the information in the *isoimages* table. Remove that entry
and insert the data again:

.. prompt:: bash

    mysql -u rvd_user -p ravada -e "DELETE FROM iso_images WHERE id=_ID_"

Insert the data from the SQL file installed with the package:

.. prompt:: bash

    mysql -u rvd_user -p ravada -f < /usr/share/doc/ravada/sql/data/insert_iso_images.sql

It will report duplicated entry errors, but the removed row should be
inserted again.


Create base of a Virtual Machine
--------------------------------

Go to Admin tools -> Virtual Machines

1st Base
~~~~~~~~

If you have configured your Virtual Machine, now you can do the Base:

-  Select the Base checkbox.

The Virtual Machine will be published if you select the Public checkbox.

2nd base or more
~~~~~~~~~~~~~~~~

In this case, you have a previous Base and you've made some changes at the machine. Now you must prepare a Base again.

Steps:

1.  Remove all clones of this Virtual Machine.

2.  Select the Base checkbox to prepare base.
