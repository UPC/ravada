use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');

my $CONFIG_FILE = 't/etc/ravada.conf';

my @rvd_args = (
       config => $CONFIG_FILE
   ,connector => connector()
);

my $RVD_BACK  = rvd_back( $CONFIG_FILE);
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my $USER = create_user('foo','bar',1);

my %CREATE_ARGS = (
    Void => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
    ,KVM => { id_iso => search_id_iso('Alpine'),       id_owner => $USER->id }
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

for my $vm_name (keys %CREATE_ARGS) {

    diag("Testing $vm_name");
    my $vm = $RVD_BACK->search_vm($vm_name);
    my $msg = "Skipping VM $vm_name in this system";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    SKIP: {
    if (!$vm) {
        diag($msg);
        skip($msg,2);
    }
    my $base = create_domain($vm_name);
    $base->prepare_base($USER);
    $base->is_public(1);

    my $clone_name = new_domain_name();
    my $clone = $base->clone( user => $USER, name => $clone_name);
    ok($clone,"[$vm_name] Expecting a clone from ".$base->name);

    my $cloneb = rvd_front->search_clone( id_base => $base->id, id_owner => $USER->id);
    ok($cloneb,"Expecting a clone id_base=".$base->id.", id_owner=".$USER->id);
    is($cloneb->id, $clone->id) if $cloneb;

    $clone->prepare_base($USER);
    is($clone->is_base,1);
    my $clonec = rvd_front->search_clone( id_base => $base->id, id_owner => $USER->id);
    ok(!$clonec,"Expecting no clone from id_base=".$base->id.", id_owner=".$USER->id);

    my $clone2_name = new_domain_name();
    my $clone2 = $base->clone(user => $USER, name => $clone2_name);

    my $clone2b = rvd_front->search_clone( id_base => $base->id, id_owner => $USER->id);
    ok($clone2b,"Expecting a clone id_base=".$base->id.", id_owner=".$USER->id);
    is($clone2b->id,$clone2->id)    if $cloneb;
    } # of SKIP
}

end();
done_testing();
