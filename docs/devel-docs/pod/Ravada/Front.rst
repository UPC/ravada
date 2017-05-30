.. highlight:: perl


****
NAME
****


Ravada::Front - Web Frontend library for Ravada

BUILD
=====


Internal constructor


list_bases
==========


Returns a list of the base domains as a listref


.. code-block:: perl

     my $bases = $rvd_front->list_bases();



list_machines_user
==================


Returns a list of machines available to the user

If the user has ever clone the base, it shows this information. It show the
base data if not.

Arguments: user

Returns: listref of machines

sub search_clone_data {
    my $self = shift;
    my %args = @_;
    my $query = "SELECT \* FROM domains WHERE "
        .(join(" AND ", map { "$_ = ? " } sort keys %args));


.. code-block:: perl

     my $sth = $CONNECTOR->dbh->prepare($query);
     $sth->execute( map { $args{$_} } sort keys %args );
     my $row = $sth->fetchrow_hashref;
     return ( $row or {});


}


list_domains
============


Returns a list of the domains as a listref


.. code-block:: perl

     my $bases = $rvd_front->list_domains();



domain_info
===========


Returns information of a domain


.. code-block:: perl

     my $info = $rvd_front->domain_info( id => $id);
     my $info = $rvd_front->domain_info( name => $name);



domain_exists
=============


Returns true if the domain name exists


.. code-block:: perl

     if ($rvd->domain_exists('domain_name')) {
         ...
     }



list_vm_types
=============


Returns a reference to a list of Virtual Machine Managers known by the system


list_iso_images
===============


Returns a reference to a list of the ISO images known by the system


list_lxc_templates
==================


Returns a reference to a list of the LXC templates known by the system


list_users
==========


Returns a reference to a list of the users


create_domain
=============


Request the creation of a new domain or virtual machine


.. code-block:: perl

     # TODO: document the args here
     my $req = $rvd_front->create_domain( ... );



wait_request
============


Waits for a request for some seconds.

Arguments
---------



\* request



\* timeout (optional defaults to $Ravada::Front::TIMEOUT



Returns: the request



ping_backend
============


Checks if the backend is alive.

Return true if alive, false otherwise.


open_vm
=======


Connects to a Virtual Machine Manager ( or VMM ( or VM )).
Returns a read-only connection to the VM.


.. code-block:: perl

   my $vm = $front->open_vm('KVM');



search_vm
=========


Calls to open_vm


search_clone
============


Search for a clone of a domain owned by an user.


.. code-block:: perl

     my $domain_clone = $rvd_front->(id_base => $domain_base->id , id_owner => $user->id);


arguments
---------



id_base : The id of the base domain



id_user



Returns the domain



search_domain
=============


Searches a domain by name


.. code-block:: perl

     my $domain = $rvd_front->search_domain($name);


Returns a Ravada::Domain object


list_requests
=============


Returns a list of ruquests : ( id , domain_name, status, error )


search_domain_by_id
===================



.. code-block:: perl

   my $domain = $ravada->search_domain_by_id($id);



start_domain
============


Request to start a domain.

arguments
---------



user => $user : a Ravada::Auth::SQL user



name => $name : the domain name



remote_ip => $remote_ip: a Ravada::Auth::SQL user



Returns an object: Ravada::Request.


.. code-block:: perl

     my $req = $rvd_front->start_domain(
                user => $user
               ,name => 'mydomain'
         , remote_ip => '192.168.1.1');




list_bases_anonymous
====================


List the available bases for anonymous user in a remote IP


.. code-block:: perl

     my $list = $rvd_front->list_bases_anonymous($remote_ip);



disconnect_vm
=============


Disconnects all the conneted VMs


version
=======


Returns the version of the main module


