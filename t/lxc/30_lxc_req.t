use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::LXC');
use_ok('Ravada::VM::LXC');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $RAVADA= Ravada->new( connector => $test->connector);
my $vm_lxc;

my $CONT= 0;
my ($NAME) = $0 =~ m{.*/(.*)\.t$};


sub remove_old {
    for ( 1 .. $CONT ) {
        $vm_lxc->remove_domain("${NAME}_$CONT");
    }
}

sub test_new_req {
    my $name = "${NAME}_".$CONT++;
    my $req;
#    eval { 
        $req = Ravada::Request->create_domain(
            name => $name
            ,id_template => 1
            ,backend => 'LXC'
        );
#    };
    ok(!$@,$@);
    ok($req,"No request created : $@") or return;
    ok(defined $req->args->{name}
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $RAVADA->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain = $RAVADA->search_domain($name);
    ok($domain,"No domain $name found");

    return $domain;
}

################################################################

eval { $vm_lxc = Ravada::VM::LXC->new() };

SKIP: {
    my $msg = "No LXC backend found $@";
    diag($msg)          if !$vm_lxc;
    skip ($msg,10)    if !$vm_lxc;
    remove_old ();
    test_new_req();
};

done_testing();
