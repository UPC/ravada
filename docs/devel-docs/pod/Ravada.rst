.. highlight:: perl


Ravada - Remove Virtual Desktop Manager
=======================================

********
SYNOPSIS
********



.. code-block:: perl

   use Ravada;
 
   my $ravada = Ravada->new()


BUILD
=====


Internal constructor


display_ip
==========


Returns the default display IP read from the config file


disconnect_vm
=============


Disconnect all the Virtual Managers connections.


create_domain
=============


Creates a new domain based on an ISO image or another domain.


.. code-block:: perl

   my $domain = $ravada->create_domain(
          name => $name
     , id_iso => 1
   );
 
 
   my $domain = $ravada->create_domain(
          name => $name
     , id_base => 3
   );



remove_domain
=============


Removes a domain


.. code-block:: perl

   $ravada->remove_domain($name);



search_domain
=============



.. code-block:: perl

   my $domain = $ravada->search_domain($name);



search_domain_by_id
===================



.. code-block:: perl

   my $domain = $ravada->search_domain_by_id($id);



list_domains
============


List all created domains


.. code-block:: perl

   my @list = $ravada->list_domains();



list_domains_data
=================


List all domains in raw format. Return a list of id => { name , id , is_active , is_base }


.. code-block:: perl

    my $list = $ravada->list_domains_data();
 
    $c->render(json => $list);



list_bases
==========


List all base domains


.. code-block:: perl

   my @list = $ravada->list_domains();



list_bases_data
===============


List information about the bases


list_images
===========


List all ISO images


list_images_data
================


List information about the images

sub _list_images_lxc {
    my $self = shift;
    my @domains;
    my $sth = $CONNECTOR->dbh->prepare(
        "SELECT \* FROM lxc_templates ORDER BY name"
    );
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        push @domains,($row);
    }
    $sth->finish;
    return @domains;
}

sub _list_images_data_lxc {
    my $self = shift;
    my @data;
    for ($self->list_images_lxc ) {
        push @data,{ id => $_->{id} , name => $_->{name} };
    }
    return \@data;
}


remove_volume
=============



.. code-block:: perl

   $ravada->remove_volume($file);



clean_killed_requests
=====================


Before processing requests, old killed requests must be cleaned.


process_requests
================


This is run in the ravada backend. It processes the commands requested by the fronted


.. code-block:: perl

   $ravada->process_requests();



process_long_requests
=====================


Process requests that take log time. It will fork on each one


process_all_requests
====================


Process all the requests, long and short


list_vm_types
=============


Returnsa list ofthe types of Virtual Machines available on this system


open_vm
=======


Opens a VM of a given type


.. code-block:: perl

   my $vm = $ravada->open_vm('KVM');



search_vm
=========


Searches for a VM of a given type


.. code-block:: perl

   my $vm = $ravada->search_vm('kvm');



import_domain
=============


Imports a domain in Ravada


.. code-block:: perl

     my $domain = $ravada->import_domain(
                             vm => 'KVM'
                             ,name => $name
                             ,user => $user_name
     );



version
=======


Returns the version of the module



******
AUTHOR
******


Francesc Guasch-Ortiz	, frankie@telecos.upc.edu


********
SEE ALSO
********


Sys::Virt

