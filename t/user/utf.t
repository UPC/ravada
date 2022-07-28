use warnings;
use strict;

use utf8;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $N = 1;

########################################################################
sub test_user_cyrillic($vm) {
    my $name = 'пользователя';
    my $user = create_user($name."-".$N++, $$);
    ok($user);
    like($user->name,qr/$name-\d+$/);
    ok(utf8::valid($user->name));

    my $base = create_domain_v2(vm => $vm);
    $base->is_public(1);
    $base->prepare_base(user_admin);

    my $req = Ravada::Request->clone(
        uid => $user->id
        ,id_domain => $base->id
    );
    wait_request();
    is($req->error,'');
    my ($clonef) = $base->clones();

    ok(utf8::valid($clonef->{name}));
    is($clonef->{name},$base->name."-000".$user->id) or exit;

    my $base_name = $base->name;
    like($clonef->{alias},qr/$base_name-$name/) or exit;

    _test_utf8($user);

    my $clone = Ravada::Domain->open($clonef->{id});
    Ravada::Request->start_domain(
            uid => $user->id
            ,id_domain => $clone->id
    );
    _test_requests();
    wait_request();

    Ravada::Request->shutdown_domain(
            uid => $user->id
            ,id_domain => $clone->id
            ,timeout => 3
    );
    _test_requests();
    wait_request();
    _test_messages_utf8($user);

    sleep 3;
    wait_request();
    _test_messages_utf8($user);

    remove_domain($base);
}

sub _test_utf8($user) {
    _test_messages_utf8($user);
    _test_requests();
}

sub _test_requests() {
    my $reqs = rvd_front->list_requests();
    for my $req (@$reqs) {
        ok(utf8::valid($req->{name}))    if $req->{name};
        ok(utf8::valid($req->{message})) if $req->{message};
    }
}

sub _test_messages_utf8($user) {
    for my $msg ($user->unread_messages) {
        ok(utf8::valid($msg->{subject}));
        ok(utf8::valid($msg->{message})) if $msg->{message};

        #        warn Dumper([$msg->{subject}, $msg->{message}]);
    }
}

########################################################################

init();
clean();

for my $vm_name (vm_names()) {
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;
        test_user_cyrillic($vm);
    }
}

end();

done_testing();
