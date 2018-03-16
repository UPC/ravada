use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(DumpFile);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

init( $test->connector , $FILE_CONFIG );

#######################################################################

sub test_autostart($vm_name) {
    my $domain = create_domain($vm_name);
    is($domain->autostart,0,"[$vm_name] Expecting autostart=0 on domain ".$domain->name);
    is($domain->is_active,0);

    $domain->autostart(1, user_admin);
    is($domain->autostart,1);

    if ($vm_name eq 'KVM') {
        ok($domain->domain->get_autostart);
    } elsif ($vm_name eq 'Void') {
        ok($domain->_value('autostart'));
    } else {
        ok(0,"[$vm_name] I don't know how to test autostart in this VM");
    }
    $domain->remove(user_admin);
}

sub test_autostart_base($vm_name) {
    my $domain = create_domain($vm_name);
    $domain->prepare_base(user_admin);

    is($domain->autostart,0);
    eval { $domain->autostart(1, user_admin) };
    like($@,qr'.',"[$vm_name] Expecting error when setting autostart on base");

    $domain->remove_base(user_admin);
    is($domain->autostart,0);
    eval { $domain->autostart(1, user_admin) };
    is(''.$@,'');

    is($domain->autostart,1);

    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->autostart, 1) or exit;

    $domain->remove(user_admin);
}

sub test_autostart_prepare_base($vm_name) {
    my $domain = create_domain($vm_name);
    $domain->autostart(1, user_admin);
    is($domain->autostart,1);

    $domain->prepare_base(user_admin);
    is($domain->autostart,0);

    my $domain2 = Ravada::Domain->open( $domain->id );
    is($domain2->autostart, 0);

    $domain->remove(user_admin);
}

sub test_autostart_denied($vm_name) {
    my $domain = create_domain($vm_name);
    my $jimmy= create_user("jimmy$domain",$$,0);
    eval { $domain->autostart(1, $jimmy) };
    like($@,qr/not allowed/i);

    my $domain2 = Ravada::Domain->open( $domain->id );
    is($domain2->autostart, 0);

    $domain->remove(user_admin);
}

sub test_autostart_req($vm_name) {
    my $domain = create_domain($vm_name);
    my $req = Ravada::Request->domain_autostart(
               uid => user_admin->id
            ,value => 1
        ,id_domain => $domain->id
    );
    rvd_back->_process_all_requests_dont_fork();
    is($req->status , 'done');
    is($req->error, '');

    is($domain->autostart, 1);

    my $domain2 = Ravada::Domain->open( $domain->id );
    is($domain2->autostart, 1);

    $domain->remove(user_admin);
}

sub test_autostart_front($vm_name) {
    my $domain = create_domain($vm_name);
    is($domain->autostart, 0);

    my $domain_f = Ravada::Front::Domain->new(id => $domain->id);
    is($domain_f->autostart, 0);

    $domain->autostart(1, user_admin);
    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->autostart,1,"[$vm_name] Expecting autostart on domain ".$domain->name) or exit;

    $domain_f = Ravada::Front::Domain->new(id => $domain->id);
    is($domain_f->autostart, 1);

    $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->autostart,1);

    $domain_f = Ravada::Front::Domain->new(id => $domain->id);
    is($domain_f->autostart, 1);

    $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->autostart,1);

    $domain->remove(user_admin);
}

#######################################################################

clean();

for my $vm_name ( 'Void', 'KVM' ) {

    my $vm;

    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_autostart($vm_name);
        test_autostart_base($vm_name);
        test_autostart_prepare_base($vm_name);
        test_autostart_req($vm_name);
        test_autostart_denied($vm_name);
        test_autostart_front($vm_name);

    }
}

clean();

done_testing();

########################################################################
