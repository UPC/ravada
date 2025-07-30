use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::Front');

my $USER;
my $RVD_BACK;
my $RVD_FRONT;


sub _init() {
    $USER = create_user('foo','bar', 1);
    $RVD_BACK  = rvd_back( );
    $RVD_FRONT = rvd_front();

    # twice so it won't warn it is only used once
    ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");
    ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");

    ok($RVD_BACK->connector());
}

sub test_empty {

    my $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");

    my $domains = $RVD_FRONT->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 0, "There should be no domains");

}


sub test_add_domain_db {

    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);

    my $domain_name = new_domain_name();

    my $domain = $vm->create_domain( 
        name => $domain_name 
        , id_owner => $USER->id
        , arg_create_dom($vm_name)
    );

    my $domain2 = $vm->search_domain($domain_name);
    ok($domain2,"[$vm_name] Expecting domain $domain_name") or exit;

    my $domain_f = $RVD_FRONT->search_domain($domain_name);
    ok($domain_f,"[$vm_name] Expecting domain $domain_name") or exit;

    my $domains = $RVD_FRONT->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 1, "There should be one domain ".Dumper($domains));
    
    my $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");
    
    connector->dbh->do("UPDATE Domains set is_base=1,is_public=1 WHERE name='$domain_name'");
    
    $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 1, "There should 1 base, got ".scalar(@$bases)) or exit;

    is($bases->[0]->{name}, $domain_name);
    
    for my $base ( @$bases ) {
        ok($base->{is_base},"[$vm_name] Expecting base for ".Dumper($base) );
    }
}

sub test_vm_types {
    my $vm_types;
    eval { $vm_types = $RVD_FRONT->list_vm_types() };
    if ($@ =~ /timeout/i ) {
    }

}


init();
clean();

SKIP: {
    _init();
    for my $vm_name ( 'Void') {
        test_empty();
        test_add_domain_db($vm_name);
        test_vm_types();
    }
}

end();
done_testing();
