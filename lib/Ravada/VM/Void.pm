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
use Ravada::NetInterface::Void;

with 'Ravada::VM';

has 'vm' => (
    is => 'rw'
);

has 'type' => (
    is => 'ro'
    ,isa => 'Str'
    ,default => 'void'
);

##########################################################################
#

sub connect {}
sub disconnect {}
sub reconnect {}

sub create_domain {
    my $self = shift;
    my %args = @_;

    croak "argument name required"       if !$args{name};
    croak "argument id_owner required"       if !$args{id_owner};

    my $domain = Ravada::Domain::Void->new(
                                           %args
                                           , domain => $args{name}
                                           , _vm => $self
    );
    $domain->_insert_db(name => $args{name} , id_owner => $args{id_owner}
        , id_base => $args{id_base} );

    if ($args{id_base}) {
        my $domain_base = $self->search_domain_by_id($args{id_base});

        confess "I can't find base domain id=$args{id_base}" if !$domain_base;

        for my $file_base ($domain_base->list_files_base) {
            my ($dir,$vol_name,$ext) = $file_base =~ m{(.*)/(.*?)(\..*)};
            my $new_name = "$vol_name-$args{name}$ext";
            $domain->add_volume(name => $new_name
                                , path => "$dir/$new_name"
                                 ,type => 'file');
        }
    }
#    $domain->start();
    return $domain;
}

sub create_volume {
}

sub list_domains {
    opendir my $ls,$Ravada::Domain::Void::DIR_TMP or return;

    my %domain;
    while (my $file = readdir $ls ) {
        next if $file !~ /\.yml$/;
        $file =~ s/\.\w+//;
        $file =~ s/(.*)\.qcow.*$/$1/;
        next if $file !~ /\w/;
        $domain{$file}++;
    }

    closedir $ls;

    return sort keys %domain;
}

sub search_domain {
    my $self = shift;
    my $name = shift or confess "ERROR: Missing name";

    for my $name_vm ( $self->list_domains ) {
        next if $name_vm ne $name;

        my $domain = Ravada::Domain::Void->new( 
            domain => $name
            ,readonly => $self->readonly
                 ,_vm => $self
        );
        my $id;

        eval { $id = $domain->id };
        return if !defined $id;#
        return $domain;
    }
}

sub list_networks {
    return Ravada::NetInterface::Void->new();
}

#########################################################################3

1;
