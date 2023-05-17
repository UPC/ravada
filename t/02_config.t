use warnings;
use strict;

use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

#########################################################################

sub check_empty {
    is(Ravada::_check_config( {} ), 1);
    is(Ravada::_check_config( undef ), 1);
}

sub check_fail{
    is(Ravada::_check_config( {fail => 'yes'} ) , 0);
}

sub check_db {
    is(Ravada::_check_config( {
                db => {
                    user => 1
                    , password => 2
                    , hostname => 3
                }
            }) , 1);
    is(Ravada::_check_config( {
                db => {
                    user => 1
                    , password => 2
                    , foo => 3
                }
            }) , 0);

    is(Ravada::_check_config( {
                ldap => {
                    secure => 0
                }
            }),1);
}

#########################################################################

clean();

check_empty();
check_fail();
check_db();

end();

done_testing();

