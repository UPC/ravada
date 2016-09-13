use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my @rvd_args = (
       config => 't/etc/ravada.conf' 
   ,connector => $test->connector 
);

my $RVD_BACK  = Ravada->new( @rvd_args);
my $RVD_FRONT = Ravada::Front->new( @rvd_args
    , backend => $RVD_BACK
);

# twice so it won't warn it is only used once
ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");
ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");

sub test_empty {

    my $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");

    my $domains = $RVD_FRONT->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 0, "There should be no domains");

}


sub test_add_domain_db {

    my $sth = $test->dbh->prepare("INSERT INTO domains "
            ."(name) VALUES (?)");
    $sth->execute('a');
    
    my $domains = $RVD_FRONT->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 1, "There should be one domain ".Dumper($domains));
    
    my $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");
    
    $test->dbh->do("UPDATE DOMAINS set is_base='y' WHERE name='a'");
    
    $bases = $RVD_FRONT->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 1, "There should 1 base");
    
    for my $base ( @$bases ) {
        ok($base->{is_base} =~ /y/i);
    }
}

sub test_vm_types {
    my $vm_types;
    eval { $vm_types = $RVD_FRONT->list_vm_types() };
    if ($@ =~ /timeout/i ) {
    }

}

my $ping = $RVD_FRONT->ping_backend();

SKIP: {
    diag("SKIPPING: No backend found at ping")    if !$ping;
    skip("No backend found at ping",10) if !$ping;
    test_empty();
    test_add_domain_db();
    test_vm_types();
}
 
done_testing();
