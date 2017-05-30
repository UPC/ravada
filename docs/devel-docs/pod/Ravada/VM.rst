.. highlight:: perl


##########
Ravada::VM
##########

****
NAME
****


Ravada::VM - Virtual Managers library for Ravada


************
Constructors
************


open
====


Opens a Virtual Machine Manager (VM)

Arguments: id of the VM


domain_remove
=============


Remove the domain. Returns nothing.


name
====


Returns the name of this Virtual Machine Manager


.. code-block:: perl

     my $name = $vm->name();



search_domain_by_id
===================


Returns a domain searching by its id


.. code-block:: perl

     $domain = $vm->search_domain_by_id($id);



ip
==


Returns the external IP this for this VM


id
==


Returns the id value of the domain. This id is used in the database
tables and is not related to the virtual machine engine.


default_storage_pool_name
=========================


Set the default storage pool name for this Virtual Machine Manager


.. code-block:: perl

     $vm->default_storage_pool_name('default');



