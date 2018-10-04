use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

init($test->connector, $FILE_CONFIG);

sub test_disconnect {
    my $vm = Ravada::VM::Void->new(
        name => 'void_remote',
        host => '1.2.3.4'
    );
}

###########################################################################

clean();

test_disconnect();

clean();

done_testing();
