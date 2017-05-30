.. highlight:: perl


NAME
====


Ravada::Domain::KVM - KVM Virtual Machines library for Ravada


name
====


Returns the name of the domain


list_disks
==========


Returns a list of the disks used by the virtual machine. CDRoms are not included


.. code-block:: perl

   my@ disks = $domain->list_disks();



remove_disks
============


Remove the volume files of the domain


pre_remove_domain
=================


Cleanup operations executed before removing this domain


.. code-block:: perl

     $self->pre_remove_domain



remove
======


Removes this domain. It removes also the disk drives and base images.


disk_device
===========


Returns the file name of the disk of the domain.


.. code-block:: perl

   my $file_name = $domain->disk_device();


sub _create_swap_base {
    my $self = shift;


.. code-block:: perl

     my @swap_img;
 
     my $base_name = $self->name;
     for  my $base_img ( $self->list_volumes()) {
 
       next unless $base_img =~ 'SWAP';
 
         confess "ERROR: missing $base_img"
             if !-e $base_img;
         my $swap_img = $base_img;
 
         $swap_img =~ s{\.\w+$}{\.ro.img};
 
         push @swap_img,($swap_img);
 
         my @cmd = ('qemu-img','convert',
                 '-O','raw', $base_img
                 ,$swap_img
         );
 
         my ($in, $out, $err);
         run3(\@cmd,\$in,\$out,\$err);
         warn $out if $out;
         warn $err if $err;
 
         if (! -e $swap_img) {
             warn "ERROR: Output file $swap_img not created at ".join(" ",@cmd)."\n";
             exit;
         }
 
         chmod 0555,$swap_img;
         $self->_prepare_base_db($swap_img);
     }
     return @swap_img;


}


prepare_base
============


Prepares a base virtual machine with this domain disk


get_xml_base
============


Returns the XML definition for the base, only if prepare_base has been run befor


display
=======


Returns the display URI


is_active
=========


Returns whether the domain is running or not


start
=====


Starts the domain


shutdown
========


Stops the domain


shutdown_now
============


Shuts down uncleanly the domain


force_shutdown
==============


Shuts down uncleanly the domain


pause
=====


Pauses the domain


resume
======


Resumes a paused the domain


is_hibernated
=============


Returns if the domain has a managed saved state.


is_paused
=========


Returns if the domain is paused


can_hybernate
=============


Returns true (1) for KVM domains


hybernate
=========


Take a snapshot of the domain's state and save the information to a
managed save location. The domain will be automatically restored with
this state when it is next started.


.. code-block:: perl

     $domain->hybernate();



add_volume
==========


Adds a new volume to the domain


.. code-block:: perl

     $domain->add_volume(name => $name, size => $size);
     $domain->add_volume(name => $name, size => $size, xml => 'definition.xml');



BUILD
=====


internal build method


list_volumes
============


Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.


.. code-block:: perl

     my @volumes = $domain->list_volumes();



list_volumes_target
===================


Returns a list of the disk volumes. Each element of the list is a string with the filename.
For KVM it reads from the XML definition of the domain.


.. code-block:: perl

     my @volumes = $domain->list_volumes_target();



screenshot
==========


Takes a screenshot, it stores it in file.


can_screenshot
==============


Returns if a screenshot of this domain can be taken.


storage_refresh
===============


Refreshes the internal storage. Used after removing files such as base images.


get_info
========


This is taken directly from Sys::Virt::Domain.

Returns a hash reference summarising the execution state of the
domain. The elements of the hash are as follows:


maxMem
 
 The maximum memory allowed for this domain, in kilobytes
 


memory
 
 The current memory allocated to the domain in kilobytes
 


cpu_time
 
 The amount of CPU time used by the domain
 


n_virt_cpu
 
 The current number of virtual CPUs enabled in the domain
 


state
 
 The execution state of the machine, which will be one of the
 constants &Sys::Virt::Domain::STATE_\*.
 



set_max_mem
===========


Set the maximum memory for the domain


get_max_mem
===========


Get the maximum memory for the domain


set_memory
==========


Sets the current available memory for the domain


rename
======


Renames the domain


.. code-block:: perl

     $domain->rename("new name");



disk_size
=========


Returns the size of the domains disk or disks
If an array is expected, it returns the list of disks sizes, if it
expects an scalar returns the first disk as it is asumed to be the main one.


.. code-block:: perl

     my $size = $domain->disk_size();


sub rename_volumes {
    my $self = shift;
    my $new_dom_name = shift;


.. code-block:: perl

     for my $disk ($self->_disk_devices_xml) {
 
         my ($source) = $disk->findnodes('source');
         next if !$source;
 
         my $volume = $source->getAttribute('file') or next;
 
         confess "ERROR: Domain ".$self->name
                 ." volume '$volume' does not exists"
             if ! -e $volume;
 
         $self->domain->create if !$self->is_active;
         $self->domain->detach_device($disk);
         $self->domain->shutdown;
 
         my $cont = 0;
         my $new_volume;
         my $new_name = $new_dom_name;
 
         for (;;) {
             $new_volume=$volume;
             $new_volume =~ s{(.*)/.*\.(.*)}{$1/$new_name.$2};
             last if !-e $new_volume;
             $cont++;
             $new_name = "$new_dom_name.$cont";
         }
         warn "copy $volume -> $new_volume";
         copy($volume, $new_volume) or die "$! $volume -> $new_volume";
         $source->setAttribute(file => $new_volume);
         unlink $volume or warn "$! removing $volume";
         $self->storage->refresh();
         $self->domain->attach_device($disk);
     }
 }



spinoff_volumes
===============


Makes volumes indpendent from base


clean_swap_volumes
==================


Clean swap volumes. It actually just creates an empty qcow file from the base


get_driver
==========


Gets the value of a driver

Argument: name


.. code-block:: perl

     my $driver = $domain->get_driver('video');



set_driver
==========


Sets the value of a driver

Argument: name , driver


.. code-block:: perl

     my $driver = $domain->set_driver('video','"type="qxl" ram="65536" vram="65536" vgamem="16384" heads="1" primary="yes"');



pre_remove
==========


Code to run before removing the domain. It can be implemented in each domain.
It is not expected to run by itself, the remove function calls it before proceeding.
In KVM it removes saved images.


.. code-block:: perl

     $domain->pre_remove();  # This isn't likely to be necessary
     $domain->remove();      # Automatically calls the domain pre_remove method


