use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada::Front');

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my $rvd = Ravada::Front->new( connector => $test->connector);

# twice so it won't warn it is only used once
ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");
ok($Ravada::CONNECTOR,"\$Ravada::Connector wasn't set");

sub test_empty {

    my $bases = $rvd->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");

    my $domains = $rvd->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 0, "There should be no domains");

}


sub test_add_domain_db {

    my $sth = $test->dbh->prepare("INSERT INTO domains "
            ."(name) VALUES (?)");
    $sth->execute('a');
    
    my $domains = $rvd->list_domains();
    ok($domains,"No domains list returned");
    ok(scalar @$domains == 1, "There should be one domain ".Dumper($domains));
    
    my $bases = $rvd->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 0, "There should be no bases");
    
    $test->dbh->do("UPDATE DOMAINS set is_base='y' WHERE name='a'");
    
    $bases = $rvd->list_bases();
    ok($bases,"No bases list returned");
    ok(scalar @$bases == 1, "There should 1 base");
    
    for my $base ( @$bases ) {
        ok($base->{is_base} =~ /y/i);
    }
}

test_empty();
test_add_domain_db();
 
done_testing();
