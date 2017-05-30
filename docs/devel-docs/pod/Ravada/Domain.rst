.. highlight:: perl


****
NAME
****


Ravada::Domain - Domains ( Virtual Machines ) library for Ravada

id
Returns the id of  the domain
    my $id = $domain->id();
=cut
=================================================================


sub id {
    return $_[0]->_data('id');

}

##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";


.. code-block:: perl

     _init_connector();
 
     return $self->{_data}->{$field} if exists $self->{_data}->{$field};
     $self->{_data} = $self->_select_domain_db( name => $self->name);
 
     confess "No DB info for domain ".$self->name    if !$self->{_data};
     confess "No field $field in domains"            if !exists$self->{_data}->{$field};
 
     return $self->{_data}->{$field};
 }


sub __open {
    my $self = shift;


.. code-block:: perl

     my %args = @_;
 
     my $id = $args{id} or confess "Missing required argument id";
     delete $args{id};
 
     my $row = $self->_select_domain_db ( );
     return $self->search_domain($row->{name});
 #    confess $row;
 }



is_known
========


Returns if the domain is known in Ravada.


spice_password
==============


Returns the password defined for the spice viewers


pre_remove
==========


Code to run before removing the domain. It can be implemented in each domain.
It is not expected to run by itself, the remove function calls it before proceeding.


.. code-block:: perl

     $domain->pre_remove();  # This isn't likely to be necessary
     $domain->remove();      # Automatically calls the domain pre_remove method



is_base
Returns true or  false if the domain is a prepared base
=cut
====================================================================


sub is_base {
    my $self = shift;
    my $value = shift;


.. code-block:: perl

     $self->_select_domain_db or return 0;
 
     if (defined $value ) {
         my $sth = $$CONNECTOR->dbh->prepare(
             "UPDATE domains SET is_base=? "
             ." WHERE id=?");
         $sth->execute($value, $self->id );
         $sth->finish;
 
         return $value;
     }
     my $ret = $self->_data('is_base');
     $ret = 0 if $self->_data('is_base') =~ /n/i;
 
     return $ret;
 };



is_locked
Shows if the domain has running or pending requests. It could be considered
too as the domain is busy doing something like starting, shutdown or prepare base.
Returns true if locked.
=cut
=====================================================================================================================================================================================================


sub is_locked {
    my $self = shift;


.. code-block:: perl

     $self->_init_connector() if !defined $$CONNECTOR;
 
     my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM requests "
         ." WHERE id_domain=? AND status <> 'done'");
     $sth->execute($self->id);
     my ($id) = $sth->fetchrow;
     $sth->finish;
 
     return ($id or 0);
 }



id_owner
Returns the id of the user that created this domain
=cut
=================================================================


sub id_owner {
    my $self = shift;
    return $self->_data('id_owner',@_);
}


id_base
Returns the id from the base this domain is based on, if any.
=cut
==========================================================================


sub id_base {
    my $self = shift;
    return $self->_data('id_base',@_);
}


vm
Returns a string with the name of the VM ( Virtual Machine ) this domain was created on
=cut
===============================================================================================


sub vm {
    my $self = shift;
    return $self->_data('vm');
}


clones
Returns a list of clones from this virtual machine
    my @clones = $domain->clones
=cut
===============================================================================================


sub clones {
    my $self = shift;


.. code-block:: perl

     _init_connector();
 
     my $sth = $$CONNECTOR->dbh->prepare("SELECT id, name FROM domains "
             ." WHERE id_base = ?");
     $sth->execute($self->id);
     my @clones;
     while (my $row = $sth->fetchrow_hashref) {
         # TODO: open the domain, now it returns only the id
         push @clones , $row;
     }
     return @clones;
 }



has_clones
Returns the number of clones from this virtual machine
    my $has_clones = $domain->has_clones
=cut
===============================================================================================================


sub has_clones {
    my $self = shift;


.. code-block:: perl

     _init_connector();
 
     return scalar $self->clones;
 }



list_files_base
Returns a list of the filenames of this base-type domain
=cut
=============================================================================


sub list_files_base {
    my $self = shift;
    my $with_target = shift;


.. code-block:: perl

     return if !$self->is_known();
 
     my $id;
     eval { $id = $self->id };
     return if $@ && $@ =~ /No DB info/i;
     die $@ if $@;
 
     my $sth = $$CONNECTOR->dbh->prepare("SELECT file_base_img, target "
         ." FROM file_base_images "
         ." WHERE id_domain=?");
     $sth->execute($self->id);
 
     my @files;
     while ( my ($img, $target) = $sth->fetchrow) {
         push @files,($img)          if !$with_target;
         push @files,[$img,$target]  if $with_target;
     }
     $sth->finish;
     return @files;
 }



list_files_base_target
======================


Returns a list of the filenames and targets of this base-type domain


json
Returns the domain information as json
=cut
================================================


sub json {
    my $self = shift;


.. code-block:: perl

     my $id = $self->_data('id');
     my $data = $self->{_data};
     $data->{is_active} = $self->is_active;
 
     return encode_json($data);
 }



can_screenshot
Returns wether this domain can take an screenshot.
=cut
======================================================================


sub can_screenshot {
    return 0;
}

sub _convert_png {
    my $self = shift;
    my ($file_in ,$file_out) = @_;


.. code-block:: perl

     my $in = Image::Magick->new();
     my $err = $in->Read($file_in);
     confess $err if $err;
 
     $in->Write("png24:$file_out");
 
     chmod 0755,$file_out or die "$! chmod 0755 $file_out";
 }



remove_base
Makes the domain a regular, non-base virtual machine and removes the base files.
=cut
=================================================================================================


sub remove_base {
    my $self = shift;
    return $self->_do_remove_base();
}

sub _do_remove_base {
    my $self = shift;
    $self->is_base(0);
    for my $file ($self->list_files_base) {
        next if ! -e $file;
        unlink $file or die "$! unlinking $file";
    }
    $self->storage_refresh()    if $self->storage();
}

sub _pre_remove_base {
    _allow_manage(@_);
    _check_has_clones(@_);
    $_[0]->spinoff_volumes();
}

sub _post_remove_base {
    my $self = shift;
    $self->_remove_base_db(@_);
    $self->_post_remove_base_domain();
}

sub _pre_shutdown_domain {}

sub _post_remove_base_domain {}

sub _remove_base_db {
    my $self = shift;


.. code-block:: perl

     my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM file_base_images "
         ." WHERE id_domain=?");
 
     $sth->execute($self->id);
     $sth->finish;


}


clone
=====


Clones a domain

arguments
---------



user => $user : The user that owns the clone



name => $name : Name of the new clone





can_hybernate
=============


Returns wether a domain supports hybernation


add_volume_swap
===============


Adds a swap volume to the virtual machine

Arguments:


.. code-block:: perl

     size => $kb
     name => $name (optional)



open_iptables
=============


Open iptables for a remote client


user



remote_ip




is_public
=========


Sets or get the domain public


.. code-block:: perl

     $domain->is_public(1);
 
     if ($domain->is_public()) {
         ...
     }



clean_swap_volumes
==================


Check if the domain has swap volumes defined, and clean them


.. code-block:: perl

     $domain->clean_swap_volumes();



drivers
=======


List the drivers available for a domain. It may filter for a given type.


.. code-block:: perl

     my @drivers = $domain->drivers();
     my @video_drivers = $domain->drivers('video');



set_driver_id
=============


Sets the driver of a domain given it id. The id must be one from
the table domain_drivers_options


.. code-block:: perl

     $domain->set_driver_id($id_driver);



