use warnings;
use strict;

use Data::Dumper;
use IPC::Run3 qw(run3);
use YAML qw(DumpFile LoadFile);
use Test::More;

use lib 't/lib';
use Test::Ravada;

sub test_types {
    my $sth = connector->dbh->prepare(
        "SELECT * FROM domain_drivers_types"
        ." WHERE name = 'streaming' AND vm = 'Void'"
    );
    $sth->execute;
    my @found;
    while (my $row = $sth->fetchrow_hashref) {
        push @found,($row);
    }

    is(scalar @found,1,Dumper(\@found)) or die;
}


sub test_options {
    my $sth = connector->dbh->prepare(
        "SELECT * FROM domain_drivers_options "
        ." WHERE name = 'streaming.off'"
    );
    $sth->execute;
    my @found;
    while (my $row = $sth->fetchrow_hashref) {
        push @found,($row);
    }

    is(scalar @found,1,Dumper(\@found)) or die;
}

init();

rvd_back();

test_types();
test_options();

rvd_back->_update_domain_drivers_types();

test_types();
test_options();

rvd_back->_update_domain_drivers_types();

test_types();
test_options();

end();

done_testing();
