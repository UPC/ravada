use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada::Front');

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.t};
$DOMAIN_NAME = 'front_'.$DOMAIN_NAME;
my $CONT= 0;

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my @rvd_args = (
       config => 't/etc/ravada.conf' 
   ,connector => $test->connector 
);

my $RVD_BACK  = Ravada->new( @rvd_args );
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

my %CREATE_ARGS = (
    kvm => { id_iso => 1 }
    ,lxc => { id_template => 1 }
);

###################################################################

sub _new_name {
    return $DOMAIN_NAME."_".$CONT++;
}

sub create_args {
    my $backend = shift;

    die "Unknown backend $backend" if !$CREATE_ARGS{$backend};
    return %{$CREATE_ARGS{$backend}};
}


for my $backend ('kvm','lxc') {

    my $name = _new_name();
    my $req = $RVD_FRONT->create_domain( name => $name 
        , backend => $backend
        , create_args($backend)
    );
    ok($req, "Request $name not created");

    $RVD_FRONT->wait_request($req);

    ok($req->status eq 'done',"Request for create $backend domain ".$req->status);
}
done_testing();
