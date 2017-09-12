use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $CONFIG_FILE = 't/etc/ravada.conf';

my @rvd_args = (
       config => $CONFIG_FILE
   ,connector => $test->connector
);

my $RVD_BACK  = rvd_back( $test->connector, $CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar');

my %CREATE_ARGS = (
    Void => { id_iso => 1,       id_owner => $USER->id }
    ,KVM => { id_iso => 1,       id_owner => $USER->id }
    ,LXC => { id_template => 1, id_owner => $USER->id }
);


###################################################################

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}

###################################################################

remove_old_domains();
remove_old_disks();

SKIP: {
for my $vm_name (keys %CREATE_ARGS) {

    my $vm = $RVD_BACK->search_vm($vm_name);
    my $msg = "Skipping VM $vm_name in this system";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    if (!$vm) {
        diag($msg);
        skip($msg,10);
    }
    my $base = create_domain($vm_name);
    $base->prepare_base($USER);
    $base->is_public(1);

    my $clone_name = new_domain_name();
    my $clone = $base->clone( user => $USER->id, name => $clone_name);

    my $cloneb = rvd_front->search_clone( id_base => $base->id, id_owner => $USER->id);
    is($cloneb->id, $clone->id);

    $clone->prepare_base($USER);
    is($clone->is_base,1);
    my $clonec = rvd_front->search_clone( id_base => $base->id, id_owner => $USER->id);
    is($clonec->id, $clone->id);
}
}

remove_old_domains();
remove_old_disks();

done_testing();
