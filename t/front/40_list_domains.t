use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Storable qw(dclone);
use Test::More;
use Ravada::WebSocket;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector() );
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

#########################################################

sub test_create_domain {
    my $vm_name = shift;

    my $ravada = Ravada->new(@ARG_RVD);
    my $vm = $ravada->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub _create_bases_and_clones($vm_name, $base0=undef) {

    my @bases;
    my ($n_bases, $n_domains) = ( 0,0 );
    for my $n ( 1 .. 3 ) {
        my $base;
        if (!$base0) {
            $base = create_domain($vm_name);
        } else {
            $base = $base0->clone(
                name => new_domain_name()
                ,user => user_admin
            );
        }
        push @bases,($base);
        $n_domains++;
        Ravada::Request->prepare_base(uid => user_admin->id
            ,id_domain => $base->id
        );
        wait_request();
        $base->is_public(1);
        next if $n == 1;

        Ravada::Request->clone(uid => user_admin->id
            ,id_domain => $base->id
            ,number => 3
        );
        wait_request();
        $n_domains += 3;
    }
    return (\@bases, scalar(@bases), $n_domains);

}


sub test_list_domains_clones($vm_name) {

    my ($bases, $n_bases, $n_domains) = _create_bases_and_clones($vm_name);

    my $list_domains = rvd_front->list_domains();
    is(scalar@$list_domains, $n_domains ,Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains]));

    $list_domains = rvd_front->list_domains(id_base => undef);
    is(scalar@$list_domains, $n_bases ,Dumper($list_domains));

    for my $base ( @$bases ) {

        $list_domains = rvd_front->list_domains(id_base => $base->id);
        is(scalar@$list_domains, $base->has_clones(1),Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains])) or exit;

        my $curr_n_domains = $n_bases + $base->has_clones;
        $list_domains = rvd_front->list_domains(id_base => [undef, $base->id]);

        is(scalar@$list_domains, $curr_n_domains ,Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains])) or exit;
    }

    my @id_base = ( undef );

    my $curr_n_domains = $n_bases;
    for my $base ( @$bases ) {

        $curr_n_domains += $base->has_clones();
        push @id_base,($base->id);

        $list_domains = rvd_front->list_domains(id_base => \@id_base);
        is(scalar@$list_domains, $curr_n_domains,Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains])) or exit;

    }

    $curr_n_domains = $n_bases;
    @id_base = ( undef );
    for my $base ( @$bases ) {

        $curr_n_domains += $base->has_clones();
        push @id_base,($base->id);

        $list_domains = rvd_front->list_domains(id_base => \@id_base, date_changed => '2024-01-01');
        is(scalar@$list_domains, $curr_n_domains,Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains])) or exit;

    }

    $curr_n_domains = $n_bases;
    @id_base = ( undef );
    my ($clone) = $bases->[-1]->clones();
    for my $base ( @$bases ) {

        $curr_n_domains += $base->has_clones();
        push @id_base,($base->id);

        $list_domains = rvd_front->list_domains(id_base => \@id_base, date_changed => '2024-01-01'
        , name => $clone->{name});

        my $exp = $curr_n_domains;
        my ($found) = grep { $_->{name} eq $clone->{name} } $base->clones;
        $exp++ if !$found;

        is(scalar@$list_domains, $exp, Dumper([map { [$_->{id}." ".$_->{name}, $_->{id_base}] } @$list_domains])) or exit;

    }

    remove_domain(@$bases);
}

sub test_list_domains_active($vm_name) {

    my ($bases, $n_bases, $n_domains) = _create_bases_and_clones($vm_name);

    my ($bases2) = _create_bases_and_clones($vm_name, $bases->[0]);
    my ($bases3) = _create_bases_and_clones($vm_name, $bases2->[0]);
    my ($bases4) = _create_bases_and_clones($vm_name, $bases3->[-1]);

    for my $bases ( $bases3, $bases4 ) {
        my ($clone) = $bases->[1]->clones;
        Ravada::Request->start_domain(uid => user_admin->id
        ,id_domain => $clone->{id}
        );
        wait_request();
        diag($clone->{name});
    }

    my @id_base = ( $bases->[2]->id );
    my %show_clones = map { $_ => 1 } @id_base;

    my %ws_args = ( show_clones => \%show_clones, 'show_active'=>1 , login => user_admin->name );
    my $found = 0;
    my $ws_list_data;
    for ( 1 .. 4 ) {
        my $ws_list = Ravada::WebSocket::_list_machines_tree(rvd_front, \%ws_args);
        #        __dump_list_domains($ws_list->{data});
        if (scalar(@{$ws_list->{data}})) {
            my $active = grep { $_->{status} eq 'active' } @{$ws_list->{data}};
            $ws_list_data = $ws_list->{data};
            if ($active == 2 ) {
                $found++;
                last;
            } else {
                __dump_list_domains($ws_list_data);
            }
        }

        sleep 1;
    }
    ok($found) ||
    __dump_list_domains($ws_list_data);

    my $list_domains = rvd_front->list_domains(id_base => [undef,@id_base], status => 'active');

    my $active = grep { $_->{status} eq 'active' } @{$list_domains};
    is($active,2);

    remove_domain(@$bases3, @$bases2, @$bases);
    exit;

}

sub __dump_list_domains($list_domains=rvd_front->list_domains()) {

    warn Dumper([map { $_->{id}." ".($_->{id_base} or ' ')." "
                .($_->{is_base} or ' ')." "
                .$_->{status}." "
                .$_->{name}
            } @$list_domains]);
}

sub test_list_domains {
    my $vm_name = shift;
    my $domain = shift;

    my $list_domains = rvd_front->list_domains();
    is(scalar@$list_domains,1,Dumper($list_domains));

    is($list_domains->[0]->{remote_ip},undef);

    $domain->start($USER);
    ok($domain->is_active,"Domain should be active, got ".$domain->is_active);
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{remote_ip},undef);
    is($list_domains->[0]->{is_active}, 1 );

    shutdown_domain_internal($domain);
    ok(!$domain->is_active,"Domain should not be active, got ".$domain->is_active);

    rvd_back->_cmd_refresh_vms();
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0, );

    my $remote_ip = '99.88.77.66';
    $domain->start(user => $USER, remote_ip => $remote_ip);
    ok($domain->is_active,"Domain should be active, got ".$domain->is_active);
    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{remote_ip}, $remote_ip);
    is($list_domains->[0]->{is_active}, 1);
    is($list_domains->[0]->{is_hibernated}, 0);

    $domain->hibernate($USER);
    is($domain->is_hibernated, 1);
    is($domain->status, 'hibernated');

    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0);
    is($list_domains->[0]->{is_hibernated}, 1);
    is($list_domains->[0]->{status}, 'hibernated');

    rvd_back->_cmd_refresh_vms();

    $list_domains = rvd_front->list_domains();
    is($list_domains->[0]->{is_active}, 0);
    is($list_domains->[0]->{is_hibernated}, 1);
    is($list_domains->[0]->{status}, 'hibernated');
}

sub test_open_domain {
    my ($vm_name, $domain) = @_;

    my $domain_f = rvd_front->search_domain_by_id($domain->id);
    is($domain_f->id , $domain->id);
    is($domain_f->type, $domain->type);
}

sub test_list_bases {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);

    my $user2 = create_user('malcolm.reynolds','serenity');

    my $base = create_domain($vm_name);
    my $list = rvd_front->list_machines_user($user2);
    is(scalar @$list, 0);

    $base->prepare_base(user_admin);

    $list = rvd_front->list_machines_user($user2);
    is(scalar @$list, 0);

    $list = rvd_front->list_machines_user(user_admin);
    is(scalar @$list, 1);

    $base->remove(user_admin);
    $user2->remove();
}

sub test_list_bases_many_clones($vm) {
    my $base = create_domain($vm);

    my $list = rvd_front->list_machines_user(user_admin);
    my ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);
    is($entry->{is_base},0);
    is($entry->{can_shutdown},0) or die Dumper($entry);
    is($entry->{can_prepare_base},1) or die Dumper($entry);
    is_deeply($entry->{list_clones},[]);

    $base->start(user_admin);
    $list = rvd_front->list_machines_user(user_admin);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    is($entry->{can_shutdown},1) or die Dumper($entry);

    $base->force_shutdown(user_admin);

    $base->prepare_base(user_admin);

    $list = rvd_front->list_machines_user(user_admin);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);
    is($entry->{is_base},1);
    is($entry->{can_prepare_base},0) or die Dumper($entry);

    is($entry->{name}, $base->name) or die Dumper($entry);
    is($entry->{name_clone},undef);
    is_deeply($entry->{list_clones},[]);

    my $clone = $base->clone(user => user_admin
    , name => new_domain_name);

    $list = rvd_front->list_machines_user(user_admin);
    is(scalar @$list, 1);

    ($entry) = grep { $_->{id} == $base->id} @$list;
    is ($entry->{name}, $base->name);
    is(scalar(@{$entry->{list_clones}}), 1) or die Dumper($entry->{list_clones});

    my $clone2 = $base->clone(user => user_admin
    , name => new_domain_name);

    $list = rvd_front->list_machines_user(user_admin);
    is(scalar @$list, 1);

    ($entry) = grep { $_->{id} == $base->id} @$list;
    is(scalar(@{$entry->{list_clones}}), 2);

    my $clone_info = $entry->{list_clones}->[0];
    is(ref($clone_info),'HASH');
    for (qw(id name is_active)) {
        ok(exists $clone_info->{$_},"Expecting $_ in ".Dumper($clone_info));
    }

    remove_domain($base);

}

sub test_list_bases_show_clones($vm) {
    my $base = create_domain($vm);

    my $list = rvd_front->list_machines_user(user_admin);

    $base->prepare_base(user_admin);

    my $clone1 = $base->clone(user => user_admin
    , name => new_domain_name);

    $list = rvd_front->list_machines_user(user_admin);
    my ($entry) = grep { $_->{id} == $base->id} @$list;

    ok($entry);

    $base->is_public(0);
    $base->show_clones(1);

    $list = rvd_front->list_machines_user(user_admin);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);

    $base->show_clones(0);

    $list = rvd_front->list_machines_user(user_admin);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);

    my $user = create_user();
    $list = rvd_front->list_machines_user($user);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok(!$entry);

    $base->is_public(1);
    $list = rvd_front->list_machines_user($user);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);

    is(scalar(@{$entry->{list_clones}}),0);

    my $clone2 = $base->clone(user => $user
    , name => new_domain_name);

    $list = rvd_front->list_machines_user($user);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry);
    ok($entry->{list_clones}->[0]);
    is($entry->{list_clones}->[0]->{name},$clone2->name) or die Dumper($entry);
    is($entry->{list_clones}->[0]->{id},$clone2->id) or die Dumper($entry);

    $base->is_public(0);
    $base->show_clones(1);

    $list = rvd_front->list_machines_user($user);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok($entry) or die Dumper($list);

    ok($entry->{list_clones}->[0]);+    is($entry->{list_clones}->[0]->{name},$clone2->name) or die Dumper($entry);
    is($entry->{list_clones}->[0]->{id},$clone2->id) or die Dumper($entry);

    $base->show_clones(0);

    $list = rvd_front->list_machines_user($user);
    ($entry) = grep { $_->{id} == $base->id} @$list;
    ok(!$entry);

    remove_domain($base);
}

#########################################################

remove_old_domains();
remove_old_disks();


for my $vm_name (reverse sort @VMS) {

    diag("Testing $vm_name VM");
    my $CLASS= "Ravada::VM::$vm_name";


    my $RAVADA;
    eval { $RAVADA = Ravada->new(@ARG_RVD) };

    my $vm;

    eval { $vm = $RAVADA->search_vm($vm_name) } if $RAVADA;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }


        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        use_ok($CLASS);

        test_list_domains_active($vm_name);

        test_list_domains_clones($vm_name);

        test_list_bases_show_clones($vm);

        test_list_bases_many_clones($vm);

        my $domain = test_create_domain($vm_name);
        test_list_domains($vm_name, $domain);

        test_open_domain($vm_name, $domain);
        test_list_bases($vm_name);
        $domain->remove($USER);

    }
}

end();
done_testing();

