use warnings;
use strict;

use Data::Dumper;
use IPC::Run3 qw(run3);
use YAML qw(DumpFile LoadFile);
use Test::More;

use lib 't/lib';
use Test::Ravada;

use feature qw(signatures);
no warnings "experimental::signatures";

#######################################################################################

sub test_downgrade($field) {

    my $sth = connector->dbh->prepare(
        "ALTER table requests change column $field $field text(80)"
    );
    $sth->execute();
    my $req = Ravada::Request->refresh_vms(
        uid => user_admin->id
        ,$field => '[3,4]'
    );
    eval {
        rvd_back->_sql_create_tables();
        rvd_back->_upgrade_tables();
    };
    is($@,'');

}

#######################################################################################

init('/etc/ravada.conf',0);

test_downgrade('after_request');
test_downgrade('after_request_ok');

end();

done_testing();
