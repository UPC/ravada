use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use POSIX qw(WNOHANG);
use Test::More;
use Test::SQL::Data;

no warnings "experimental::signatures";
use feature qw(signatures);


use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
init($test->connector, 't/etc/ravada.conf');

###############################################################################

sub test_request_start($vm_name) {
    my $domain = create_domain($vm_name);
    my $req = Ravada::Request->start_domain(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,remote_ip => '127.0.0.1'
    );
    rvd_back->_process_all_requests_dont_fork();
    is($req->status, 'done');
    is($req->error,'');

    is($domain->remote_ip,'127.0.0.1') if !$>;

    $req = Ravada::Request->start_domain(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,remote_ip => '127.0.0.2'
    );
    rvd_back->_process_all_requests_dont_fork();
    is($req->status, 'done');
    is($req->error,'');

    is($domain->remote_ip,'127.0.0.2')  if !$>;

    $domain->remove(user_admin);
}

sub test_request_iptables($vm_name) {
    my $domain = create_domain($vm_name);
    my $req = Ravada::Request->open_iptables(
        id_domain => $domain->id
        ,uid => user_admin->id
        ,remote_ip => '127.0.0.1'
    );
    rvd_back->_process_all_requests_dont_fork();
    is($req->status, 'done');
    is($req->error,'');

    is(scalar($domain->list_requests), 0);

    is($domain->remote_ip,'127.0.0.1')  if !$>;

    $domain->remove(user_admin);
}

###############################################################################

clean();

for my $vm_name ( vm_names() ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10       if !$vm;

        test_request_start($vm_name);
        test_request_iptables($vm_name);
    }
}

clean();

done_testing();

