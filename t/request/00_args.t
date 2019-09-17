use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();
clean();

##########################################################################

sub test_shutdown($domain) {

    my $valid = Ravada::Request::valid_args('shutdown_domain');
    is($valid->{machine},2);
    is($valid->{name},2);
    is($valid->{id_domain},2);
    is($valid->{timeout},2);

    my $valid_cli = Ravada::Request::valid_args_cli('shutdown');
    is($valid_cli->{machine},1);
    is($valid_cli->{timeout},2);
    is($valid_cli->{name},2);

    my $req = Ravada::Request->new_request(
        'shutdown'
        , machine => $domain->name
        , uid => user_admin->id
    );
    wait_request(request => $req, background => 0);
    $req = Ravada::Request->new_request(
        'shutdown'
        , machine => $domain->id
        , uid => user_admin->id
    );
    wait_request(request => $req, background => 0);
    $req = Ravada::Request->new_request(
        'shutdown'
        , name => $domain->name
        , uid => user_admin->id
    );
    wait_request(request => $req, background => 0);

}
sub test_rename($domain) {
    my $req = Ravada::Request->new_request(
        'rename_domain'
        , name => $domain->name."-2"
        , machine => $domain->name
        , uid => user_admin->id
    );
    wait_request(request => $req, background => 0);

}
##########################################################################

my $domain =create_domain('void');
test_shutdown($domain);
test_rename($domain);

clean();
done_testing();
