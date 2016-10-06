package Ravada::Domain;

use warnings;
use strict;

use Carp qw(confess croak cluck);
use Data::Dumper;
use Moose::Role;

our $TIMEOUT_SHUTDOWN = 20;

requires 'name';
requires 'remove';
requires 'display';

requires 'is_active';
requires 'start';
requires 'shutdown';
requires 'shutdown_now';
requires 'pause';
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


##################################################################################3
#

our $CONNECTOR = \$Ravada::CONNECTOR;

##################################################################################3
#
# Method Modifiers
# 

before 'display' => \&_allowed;

before 'remove' => \&_allow_remove;
 after 'remove' => \&_remove_domain_db;

before 'prepare_base' => \&_allow_prepare_base;
 after 'prepare_base' => sub { my $self = shift; $self->is_base(1) };

# TODO _check_readonly

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

    $self->shutdown();
    $self->is_base(0);
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
    my $file_base = $self->file_base_img;
    confess "Missing file_base_img" if !$file_base;

    my @stat_base = stat($file_base);
    
    my $files_updated = 0;
    for my $file ( $self->disk_device ) {
        my @stat = stat($file) or next;
        $files_updated++ if $stat[9] > $stat_base[9];
#        warn "\ncheck\t$file ".$stat[9]."\n vs \t$file_base ".$stat_base[9]." $files_updated\n";
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
sub id {
    return $_[0]->_data('id');

}
sub file_base_img {
    my $file;
    eval { $file = $_[0]->_data('file_base_img') };
    return $file ;
}

##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_domain_db( name => $self->name);

    confess "No DB info for domain ".$self->name    if !$self->{_data};
    confess "No field $field in domains"            if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub open {
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

sub _remove_domain_db {
    my $self = shift;

    $self->_select_domain_db or return;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains "
        ." WHERE id=?");
    $sth->execute($self->id);
    $sth->finish;
}


=head2 is_base

Returns true or  false if the domain is a prepared base

=cut

sub is_base { 
    my $self = shift;
    $self->_select_domain_db or return 0;

    return 0 if $self->_data('is_base') =~ /n/i;
    return $self->_data('is_base');
};


sub id_owner {
    my $self = shift;
    return $self->_data('id_owner',@_);
}

sub id_base {
    my $self = shift;
    return $self->_data('id_base',@_);
}


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

sub list_files_base {
    my $self = shift;

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

1;
