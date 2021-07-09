use warnings;
use strict;

use Carp qw(confess);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();
clean();

my $base = "zz-test-base-alpine";

sub _set_no_password() {
    my $sth = connector->dbh->prepare("UPDATE networks set requires_password=0");
}

for my $vm_name ( 'KVM' ) {

    next if $vm_name eq 'KVM' && $>;
    _set_no_password();

    my $domain = import_domain($vm_name, $base);
    is($domain->is_base,1,$domain." should be a base") or next;
    my $clone = $domain->clone(
        user => user_admin
        ,name => new_domain_name
    );
    is($clone->id_base,$domain->id);
    $clone->start(user_admin);
}

end();
done_testing();
