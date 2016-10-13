package Ravada::Domain;

use warnings;
use strict;

use Carp qw(confess croak cluck);
use Data::Dumper;
use JSON::XS;
use Moose::Role;

our $TIMEOUT_SHUTDOWN = 20;
our $CONNECTOR;

_init_connector();

requires 'name';
requires 'remove';
requires 'display';

requires 'is_active';
requires 'is_paused';
requires 'start';
requires 'shutdown';
requires 'shutdown_now';
requires 'pause';
requires 'resume';
requires 'prepare_base';

#storage
requires 'add_volume';
requires 'list_volumes';

requires 'disk_device';

has 'domain' => (
    isa => 'Any'
    ,is => 'ro'
);

has 'timeout_shutdown' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => $TIMEOUT_SHUTDOWN
);

has 'readonly' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => 0
);

##################################################################################3
#


##################################################################################3
#
# Method Modifiers
# 

before 'display' => \&_allowed;

before 'remove' => \&_allow_remove;
 after 'remove' => \&_after_remove_domain;

before 'prepare_base' => \&_allow_prepare_base;
 after 'prepare_base' => sub { 
    my $self = shift; 

    my ($user) = @_;

    $self->is_base(1); 
    if ($self->{_was_active} ) {
        $self->resume($user);
    }
    delete $self->{_was_active};
};

before 'start' => \&_allow_manage;
before 'pause' => \&_allow_manage;
before 'resume' => \&_allow_manage;
before 'shutdown' => \&_allow_manage_args;

sub _allow_manage_args {
    my $self = shift;

    confess "Disabled from read only connection"
        if $self->readonly;

    my %args = @_;

    confess "Missing user arg ".Dumper(\%args)
        if !$args{user} ;

    $self->_allowed($args{user});

}
sub _allow_manage {
    my $self = shift;

    confess "Disabled from read only connection"
        if $self->readonly;

    my ($user) = @_;

    $self->_allowed($user);

}

sub _allow_remove {
    my $self = shift;
    my ($user) = @_;

    $self->_allowed($user);
    $self->_check_has_clones();

}

sub _allow_prepare_base { 
    my $self = shift; 
    my ($user) = @_;

    $self->_allowed($user);
    $self->_check_disk_modified();
    $self->_check_has_clones();

    $self->is_base(0);
    if ($self->is_active) {
        $self->pause($user);
        $self->{_was_active} = 1;
    }
};

sub _check_has_clones {
    my $self = shift;
    my @clones;
    
    eval { @clones = $self->clones };
    die $@  if $@ && $@ !~ /No DB info/i;
    die "Domain ".$self->name." has ".scalar @clones." clones : ".Dumper(\@clones)
        if $#clones>=0;
}

sub _check_disk_modified {
    my $self = shift;

    if ( !$self->is_base() ) {
        return;
    }

    my $last_stat_base = 0;
    for my $file_base ( $self->list_files_base ) {
        my @stat_base = stat($file_base);
        $last_stat_base = $stat_base[9] if$stat_base[9] > $last_stat_base;
#        warn $last_stat_base;
    }
    
    my $files_updated = 0;
    for my $file ( $self->disk_device ) {
        my @stat = stat($file) or next;
        $files_updated++ if $stat[9] > $last_stat_base;
#        warn "\ncheck\t$file ".$stat[9]."\n vs \tfile_base $last_stat_base $files_updated\n";
    }
    die "Base already created and no disk images updated"
        if !$files_updated;
}

sub _allowed {
    my $self = shift;

    my ($user) = @_;

    confess "Missing user"  if !defined $user;
    confess "ERROR: User '$user' not class user , it is ".(ref($user) or 'SCALAR')
        if !ref $user || ref($user) !~ /Ravada::Auth/;

    return if $user->is_admin;
    my $id_owner;
    eval { $id_owner = $self->id_owner };
    my $err = $@;

    die "User ".$user->name." [".$user->id."] not allowed to access ".$self->domain
        ." owned by ".($id_owner or '<UNDEF>')."\n".Dumper($self)
            if (defined $id_owner && $id_owner != $user->id );

    confess $err if $err;

}
##################################################################################3

sub _init_connector {
    $CONNECTOR = \$Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR;
}

=head2 id

Returns the id of  the domain

    my $id = $domain->id();

=cut

sub id {
    return $_[0]->_data('id');

}


##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    _init_connector();

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_domain_db( name => $self->name);

    confess "No DB info for domain ".$self->name    if !$self->{_data};
    confess "No field $field in domains"            if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub __open {
    my $self = shift;

    my %args = @_;

    my $id = $args{id} or confess "Missing required argument id";
    delete $args{id};

    my $row = $self->_select_domain_db ( );
    return $self->search_domain($row->{name});
#    confess $row;
}

sub _select_domain_db {
    my $self = shift;
    my %args = @_; 

    if (!keys %args) {
        my $id;
        eval { $id = $self->id  };
        if ($id) {
            %args =( id => $id );
        } else {
            %args = ( name => $self->name );
        }
    }

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM domains WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->{_data} = $row;
    return $row;
}

sub _prepare_base_db {
    my $self = shift;
    my $file_img = shift;

    if (!$self->_select_domain_db) {
        confess "CRITICAL: The data should be already inserted";
#        $self->_insert_db( name => $self->name, id_owner => $self->id_owner );
    }
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO file_base_images "
        ." (id_domain , file_base_img )"
        ." VALUES(?,?)"
    );
    $sth->execute($self->id, $file_img );
    $sth->finish;

    $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains SET is_base=1 "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;

    $self->_select_domain_db();
}

sub _insert_db {
    my $self = shift;
    my %field = @_;

    _init_connector();

    for (qw(name id_owner)) {
        confess "Field $_ is mandatory ".Dumper(\%field)
            if !exists $field{$_};
    }

    my ($vm) = ref($self) =~ /.*\:\:(\w+)$/;
    confess "Unknown domain from ".ref($self)   if !$vm;
    $field{vm} = $vm;

    my $query = "INSERT INTO domains "
            ."(" . join(",",sort keys %field )." )"
            ." VALUES (". join(",", map { '?' } keys %field )." ) "
    ;
    my $sth = $$CONNECTOR->dbh->prepare($query);
    eval { $sth->execute( map { $field{$_} } sort keys %field ) };
    if ($@) {
        #warn "$query\n".Dumper(\%field);
        die $@;
    }
    $sth->finish;

}

sub _after_remove_domain {
    my $self = shift;
    $self->_remove_files_base();
    $self->_remove_domain_db();
}

sub _remove_domain_db {
    my $self = shift;

    $self->_select_domain_db or return;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;
}

sub _remove_files_base {
    my $self = shift;

    for my $file ( $self->list_files_base ) {
        unlink $file or die "$! $file" if -e $file;
    }
}


=head2 is_base

Returns true or  false if the domain is a prepared base

=cut

sub is_base { 
    my $self = shift;
    my $value = shift;
    
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

=head2 id_owner

Returns the id of the user that created this domain

=cut

sub id_owner {
    my $self = shift;
    return $self->_data('id_owner',@_);
}

=head2 id_base

Returns the id from the base this domain is based on, if any.

=cut

sub id_base {
    my $self = shift;
    return $self->_data('id_base',@_);
}

=head2 vm

Returns a string with the name of the VM ( Virtual Machine ) this domain was created on

=cut


sub vm {
    my $self = shift;
    return $self->_data('vm');
}

=head2 clones

Returns a list of clones from this virtual machine

    my @clones = $domain->clones

=cut

sub clones {
    my $self = shift;

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

=head2 list_files_base

Returns a list of the filenames of this base-type domain

=cut

sub list_files_base {
    my $self = shift;

    my $id;
    eval { $id = $self->id };
    return if $@ && $@ =~ /No DB info/i;
    die $@ if $@;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT file_base_img "
        ." FROM file_base_images "
        ." WHERE id_domain=?");
    $sth->execute($self->id);

    my @files;
    while ( my $img = $sth->fetchrow) {
        push @files,($img);
    }
    $sth->finish;
    return @files;
}

=head2 json

Returns the domain information as json

=cut

sub json {
    my $self = shift;

    my $id = $self->_data('id');
    my $data = $self->{_data};
    $data->{is_active} = $self->is_active;

    return encode_json($data);
}
1;
