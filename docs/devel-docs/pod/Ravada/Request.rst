.. highlight:: perl


****
NAME
****


Ravada::Request - Requests library for Ravada

Request a command to the ravada backend

BUILD
=====



.. code-block:: perl

     Internal object builder, do not call



open
====


Opens the information of a previous request by id


.. code-block:: perl

   my $req = Ravada::Request->open($id);



create_domain
=============



.. code-block:: perl

     my $req = Ravada::Request->create_domain( name => 'bla'
                     , id_iso => 1
     );



remove_domain
=============



.. code-block:: perl

     my $req = Ravada::Request->remove_domain( name => 'bla'
                     , uid => $user->id
     );



start_domain
============


Requests to start a domain


.. code-block:: perl

   my $req = Ravada::Request->start_domain( name => 'name', uid => $user->id );



pause_domain
============


Requests to pause a domain


.. code-block:: perl

   my $req = Ravada::Request->pause_domain( name => 'name', uid => $user->id );



resume_domain
=============


Requests to pause a domain


.. code-block:: perl

   my $req = Ravada::Request->resume_domain( name => 'name', uid => $user->id );



force_shutdown_domain
=====================


Requests to stop a domain now !


.. code-block:: perl

   my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id );



shutdown_domain
===============


Requests to stop a domain


.. code-block:: perl

   my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id );
   my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id
                                             ,timeout => $timeout );



prepare_base
============


Returns a new request for preparing a domain base


.. code-block:: perl

   my $req = Ravada::Request->prepare_base( $name );



remove_base
===========


Returns a new request for making a base regular domain. It marks it
as 'non base' and removes the files.

It must have not clones. All clones must be removed before calling
this method.


.. code-block:: perl

   my $req = Ravada::Request->remove_base( $name );



ping_backend
============


Returns wether the backend is alive or not


domdisplay
==========


Returns the domdisplay of a domain

Arguments:

\* domain name


status
======


Returns or sets the status of a request


.. code-block:: perl

   $req->status('done');
 
   my $status = $req->status();



result
======



.. code-block:: perl

   Returns the result of the request if any
 
   my $result = $req->result;



command
=======


Returns the requested command


args
====


Returns the requested command


.. code-block:: perl

   my $command = $req->command;



args
====


Returns the arguments of a request or the value of one argument field


.. code-block:: perl

   my $args = $request->args();
   print $args->{name};
 
   print $request->args('name');



defined_arg
===========


Returns if an argument is defined


screenshot_domain
=================


Request the screenshot of a domain.

Arguments:

- optional filename , defaults to "storage_path/$id_domain.png"

Returns a Ravada::Request;


open_iptables
=============


Request to open iptables for a remote client


rename_domain
=============


Request to rename a domain


set_driver
==========


Sets a driver to a domain


.. code-block:: perl

     $domain->set_driver(
         id_domain => $domain->id
         ,uid => $USER->id
         ,id_driver => $driver->id
     );



hybernate
=========


Hybernates a domain.


.. code-block:: perl

     Ravada::Request->hybernate(
         id_domain => $domain->id
              ,uid => $user->id
     );



download
========


Downloads a file. Actually used only to download iso images
for KVM domains.


