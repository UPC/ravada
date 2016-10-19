package Ravada::VM::Void;

use Carp qw(croak);
use Data::Dumper;
use Encode;
use Encode::Locale;
use Fcntl qw(:flock O_WRONLY O_EXCL O_CREAT);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use LWP::UserAgent;
use Moose;
use Socket qw( inet_aton inet_ntoa );
use Sys::Hostname;
use URI;

use Ravada::Domain::Void;
with 'Ravada::VM';

##########################################################################
#

sub connect {}

sub create_domain {
    my $self = shift;
    my %args = @_;

    $args{active} = 1 if !defined $args{active};
    
    croak "argument name required"       if !$args{name};
    croak "argument id_owner required"       if !$args{id_owner};

    my $domain = Ravada::Domain::Void->new(name => $args{name}, domain => $args{name}
                                                            , id_owner => $args{id_owner}
    );
    $domain->_insert_db(name => $args{name} , id_owner => $args{id_owner}
        , id_base => ($args{id_base} or undef));

    return $domain;
}

sub create_volume {
}

sub list_domains {
    opendir my $ls,$Ravada::Domain::DIR_TMP or return;

    my %domain;
    while (my $file = readdir $ls ) {
        $file =~ s/\.\w+//;
        $domain{$file}++;
    }

    closedir $ls;

    return [keys %domain];
}

sub search_domain {
    my $self = shift;
    my $name = shift;

    my $domain = Ravada::Domain::Void->new( domain => $name);
    my $id;

    eval { $id = $domain->id };
    return if !defined $id && ! -e $domain->disk_device();

    return $domain;
}

sub search_domain_by_id {
}

#########################################################################3

1;
