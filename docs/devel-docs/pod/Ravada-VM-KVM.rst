.. highlight:: perl


Ravada::VM::KVM - KVM Virtual Managers library for Ravada
=========================================================

disconnect
==========


Disconnect from the Virtual Machine Manager


connect
=======


Connect to the Virtual Machine Manager


storage_pool
============


Returns a storage pool usable by the domain to store new volumes.


search_volume
=============


Searches for a volume in all the storage pools known to the Virtual Manager

Argument: the filenaname;
Returns the volume as a Sys::Virt::StorageGol. If called in array context returns a
list of all the volumes.


.. code-block:: perl

     my $iso = $vm->search_volume("debian-8.iso");
 
     my @disk = $vm->search_volume("windows10-clone.img");



search_volume_path
==================


Searches for a volume in all the storage pools known to the Virtual Manager

Argument: the filenaname;
Returns the path of the volume. If called in array context returns a
list of all the paths to all the matching volumes.


.. code-block:: perl

     my $iso = $vm->search_volume("debian-8.iso");
 
     my @disk = $vm->search_volume("windows10-clone.img");



search_volume_re
================


Searches for a volume in all the storage pools known to the Virtual Manager

Argument: a regular expression;
Returns the volume. If called in array context returns a
list of all the matching volumes.


.. code-block:: perl

     my $iso = $vm->search_volume(qr(debian-\d+\.iso));
 
     my @disk = $vm->search_volume(qr(windows10-clone.*\.img));



search_volume_path_re
=====================


Searches for a volume in all the storage pools known to the Virtual Manager

Argument: a regular expression;
Returns the volume path. If called in array context returns a
list of all the paths of all the matching volumes.


.. code-block:: perl

     my $iso = $vm->search_volume(qr(debian-\d+\.iso));
 
     my @disk = $vm->search_volume(qr(windows10-clone.*\.img));



dir_img
=======


Returns the directory where disk images are stored in this Virtual Manager


create_domain
=============


Creates a domain.


.. code-block:: perl

     $dom = $vm->create_domain(name => $name , id_iso => $id_iso);
     $dom = $vm->create_domain(name => $name , id_base => $id_base);



search_domain
=============


Returns true or false if domain exists.


.. code-block:: perl

     $domain = $vm->search_domain($domain_name);



list_domains
============


Returns a list of the created domains


.. code-block:: perl

   my @list = $vm->list_domains();



create_volume
=============


Creates a new storage volume. It requires a name and a xml template file defining the volume


.. code-block:: perl

    my $vol = $vm->create_volume(name => $name, name => $file_xml);



list_networks
=============


Returns a list of networks known to this VM. Each element is a Ravada::NetInterface object


import_domain
=============


Imports a KVM domain in Ravada


.. code-block:: perl

     my $domain = $vm->import_domain($name, $user);



