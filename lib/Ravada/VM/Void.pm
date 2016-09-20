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

use Ravada::Domain::KVM;

with 'Ravada::VM';

##########################################################################
#

sub connect {}

sub create_domain {
}

sub create_volume {
}

sub list_domains {
    return [];
}

sub search_domain {
}

sub search_domain_by_id {
}

#########################################################################3

1;
