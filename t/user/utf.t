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
    my $base_name = $base->name;
    my $user_id = $user->id;
    like($clonef->{name},qr/^${base_name}-0+${user_id}$/) or exit;

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

sub test_user_name_surname($vm) {
    my $base = create_domain_v2(vm => $vm);
    $base->is_public(1);
    $base->prepare_base(user_admin);
    diag($base->name);

    for my $sep (qw (. _ -)) {
        my $name = new_domain_name()."${sep}pep${sep}bartroli";
        my $user = create_user($name, $$);
        ok(utf8::valid($user->name));

        my $req = Ravada::Request->clone(
            uid => $user->id
            ,id_domain => $base->id
        );
        wait_request();
        is($req->error,'');
        my ($clonef) = grep { $_->{id_owner} == $user->id } $base->clones();
        ok($clonef,"Expecting a clone owned by ".$user->id) or next;

        ok(utf8::valid($clonef->{name}));
        is($clonef->{name},$base->name."-".$user->name) or exit;

        my $base_name = $base->name;
        is($clonef->{name},"$base_name-$name") or exit;
        is($clonef->{alias},$clonef->{name});

        _test_utf8($user);
        _test_messages_utf8($user);
    }

    remove_domain($base);
}

sub test_user_name_europe($vm) {
    my $base = create_domain_v2(vm => $vm);
    $base->is_public(1);
    $base->prepare_base(user_admin);
    diag($base->name);

    my %replace = (
        'á' => 'a'
        ,'è' => 'e'
        ,'ï' => 'i'
        ,'ò' => 'o'
        ,'ó' => 'o'
        ,'ü' => 'u'
        ,'ç' => 'c'
        ,'À' => 'A'
        ,'È' => 'E'
        ,'Ï' => 'I'
        ,'Ö' => 'O'
        ,'Ú' => 'U'
        ,'â' => 'a'
        ,'Ê' => 'E'
        ,"'" => '_'
        ,'€' => 'E'
        ,'$' => 'S'

    );
    for my $letter (sort keys %replace) {
        my $prefix = new_domain_name();
        my $name = "$prefix.$letter.pep${letter}";
        my $expected =$prefix.".".$replace{$letter}.".pep".$replace{$letter};
        my $user = create_user($name, $$);
        ok(utf8::valid($user->name));

        my $req = Ravada::Request->clone(
            uid => $user->id
            ,id_domain => $base->id
        );
        wait_request();
        is($req->error,'');
        my ($clonef) = grep { $_->{id_owner} == $user->id } $base->clones();
        ok($clonef,"Expecting a clone owned by ".$user->id) or next;

        ok(utf8::valid($clonef->{name}));

        my $base_name = $base->name;
        is($clonef->{name},"$base_name-$expected") or exit;
        is($clonef->{alias},"$base_name-$name");
        isnt($clonef->{alias},$clonef->{name});

        _test_utf8($user);
        _test_messages_utf8($user);

        my $clone = Ravada::Domain->open($clonef->{id});
        ok($clone,"Expecting domain $clonef->{id} $clonef->{name} $clonef->{alias}") or exit;
    }

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

sub test_domain_catalan($vm) {
    my $name0 = new_domain_name();
    my $name = $name0.'á';

    my $domain = create_domain_v2(vm => $vm, name => $name);
    is($domain->_data('name'),$name0.'a') or die Dumper(
        [$domain->_data('name'),$name0.'a']
    );
    remove_domain($domain);

    $name0 = new_domain_name();
    $name = $name0.'Á';

    $domain = create_domain_v2(vm => $vm, name => $name);
    is($domain->_data('name'),$name0.'A');
    remove_domain($domain);

    $name0 = new_domain_name();
    $name = $name0.'áéíóú';

    $domain = create_domain_v2(vm => $vm, name => $name);
    is($domain->_data('name'),$name0.'aeiou');
    remove_domain($domain);

    $name0 = new_domain_name();
    $name = $name0.'ÁÉÍÓÚÇÑ';

    $domain = create_domain_v2(vm => $vm, name => $name);
    is($domain->_data('name'),$name0.'AEIOUCN');
    remove_domain($domain);

    $name0 = new_domain_name();
    $name = $name0.'ÁÉÍÓÚÇÑ'.'пользователя';
    $domain = create_domain_v2(vm => $vm, name => $name);
    my $expected = $name0.'AEIOUCN';
    like($domain->_data('name'),qr/$expected-\w{11}$/);
    remove_domain($domain);

}

sub test_renamed_conflict($vm) {
    my @domain2;
    my %dupe;
    for my $extra ( 'á','€','по') {
        my $name0 = new_domain_name();
        my $name = $name0.$extra;

        my $domain = create_domain_v2(vm => $vm, name => $name);
        push @domain2,($domain);

        for ( 1 .. 3 ) {
            my $domain2 = create_domain_v2(vm => $vm, name => $name);
            my $name2 = $name0;
            my $alias2 = $name0.$extra;
            like($domain2->_data('name'),qr/^$name2.+/) or die Dumper(
                [$domain2->_data('name'),$name0.'a']
            );
            like($domain2->_data('alias'),qr/^$alias2/) or exit;
            push @domain2,($domain2);
            is($dupe{$domain2->_data('name')}++,0);
            is($dupe{$domain2->_data('alias')}++,0);
        }
    }

    remove_domain(@domain2);
}

########################################################################

init();
clean();

for my $vm_name (vm_names()) {
    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $> && $vm_name eq 'KVM') {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;
        test_user_name_surname($vm);
        test_user_name_europe($vm);
        test_renamed_conflict($vm);
        test_domain_catalan($vm);
        test_user_cyrillic($vm);
    }
}

end();

done_testing();
