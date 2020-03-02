use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Test::More;

use feature qw(signatures);
no warnings "experimental::signatures";

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::Request');

my $FILE_CONFIG = 't/etc/ravada.conf';

init();

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => connector);

my $USER = create_user("foo","bar", 1);

my $CHAIN = 'RAVADA';

##########################################################

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

 
    return $domain->name;
}

sub test_fw_domain($vm_name, $domain_name, $remote_ip='99.88.77.66') {

    my $local_ip;
    my $local_port;
    my $domain_id;

    my $vm = rvd_back->search_vm($vm_name);
    {
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"Searching for domain $domain_name") or return;
        $domain->shutdown_now($USER) if $domain->is_active;
        $domain->start( user => $USER, remote_ip => $remote_ip);

        my $display = $domain->display($USER);
        ($local_ip, $local_port) = $display =~ m{(\d+\.\d+\.\d+\.\d+)\:(\d+)};

        ok(defined $local_port, "Expecting a port in display '$display'") or return;
    
        ok($domain->is_active);
        flush_rules_node($vm);
        test_chain($vm_name, $local_ip,$local_port, $remote_ip, 0);
        $domain_id = $domain->id;
    }

    {
        my $req = Ravada::Request->open_iptables(
                   uid => $USER->id
            ,id_domain => $domain_id
            ,remote_ip => $remote_ip

        );
        ok($req);
        ok($req->status);
        wait_request(background=> 0);

        is($req->status,'done');
        is($req->error,'');
        test_chain($vm_name, $local_ip,$local_port, $remote_ip, 1);
        if ($remote_ip eq '127.0.0.1') {
            my $if_ip = $vm->ip;
            isnt($if_ip,'127.0.0.1');
            test_chain($vm_name, $local_ip,$local_port, $if_ip, 1);
        }
    }


}

sub test_fw_domain_public_ip($vm_name, $domain_name, $remote_ip='1.2.3.4') {
    my $vm = rvd_back->search_vm($vm_name);
    $vm->public_ip('127.0.0.2');

    test_fw_domain($vm_name, $domain_name, $remote_ip);
    $vm->public_ip('');
}

sub test_fw_domain_pause {
    my ($vm_name, $domain_name) = @_;
    my $remote_ip = '99.88.77.66';

    my $local_ip;
    my $local_port;

    {

        my $vm = rvd_back->search_vm($vm_name);
        my $domain = $vm->search_domain($domain_name);
        ok($domain,"Searching for domain $domain_name") or return;
        $domain->start( user => $USER, remote_ip => $remote_ip)
            if !$domain->is_active();

        my $display = $domain->display($USER);
        ($local_port) = $display =~ m{\d+\.\d+\.\d+\.\d+\:(\d+)};
        $local_ip = $vm->ip;

        ok(defined $local_port, "Expecting a port in display '$display'") or return;
    
        $domain->pause($USER);
        ok($domain->is_paused);

        test_chain($vm_name, $local_ip,$local_port, $remote_ip, 0);
    }
    {
        my $req = Ravada::Request->resume_domain(
                   uid => $USER->id
            ,name => $domain_name
            ,remote_ip => $remote_ip

        );
        ok($req);
        ok($req->status);

        my @messages = $USER->messages();
        wait_request(background => 0);

        is($req->status,'done');
        is($req->error,'');
        ok(search_rule($local_ip,$local_port, $remote_ip ),"Expecting rule for $local_ip:$local_port <- $remote_ip") or confess;
        my @messages2 = $USER->messages();
        is(scalar @messages2, scalar @messages
            ,"Expecting no new messages ");
    }
}

sub search_rule($local_ip, $local_port, $remote_ip) {

    my @rules = find_ip_rule(remote_ip => $remote_ip
            , local_ip => $local_ip
            , local_port => $local_port
        );
    return if ! scalar@rules;
    return scalar @rules;
}

sub test_chain {
    my $vm_name = shift;
    my $enabled = pop;

    my ($local_ip, $local_port, $remote_ip) = @_;

    my $rule_num = search_rule(@_);

    ok($rule_num,"[$vm_name] Expecting rule for $remote_ip -> $local_ip: $local_port")
            or confess
        if $enabled;
    ok(!$rule_num,"[$vm_name] Expecting no rule for $remote_ip "
                        ."-> $local_ip: $local_port"
                        .", got ".($rule_num or "<UNDEF>"))
        if !$enabled;

}

sub test_fw_domain_down {
    my $vm_name = shift;

    my $domain = create_domain($vm_name);
    $domain->start(user => user_admin, remote_ip => '1.1.1.1');

    my $req = Ravada::Request->shutdown_domain(
               uid => user_admin->id
        ,id_domain => $domain->id
    );

    rvd_back->_process_all_requests_dont_fork();
    is($req->error , '');

    $domain->start(user => user_admin, remote_ip => '1.1.1.1')  if !$domain->is_active;

    $req = Ravada::Request->force_shutdown_domain(
               uid => user_admin->id
        ,id_domain => $domain->id
    );

    rvd_back->_process_all_requests_dont_fork();
    is($req->error , '');


    $domain->remove(user_admin);
}

#######################################################

remove_old_domains();
remove_old_disks();

#TODO: dump current chain and restore in the end
#      maybe ($rv, $out_ar, $errs_ar) = $ipt_obj->run_ipt_cmd('/sbin/iptables
#           -t filter -v -n -L RAVADA');

for my $vm_name (qw( Void KVM )) {

    diag("Testing $vm_name VM");

    my $vm_ok;
    eval {
        my $vm = rvd_back->search_vm($vm_name);
        $vm_ok=1    if $vm;
    };

    SKIP: {
        #TODO: find out if this system has iptables
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_ok && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm_ok = undef;
        }

        diag($msg)      if !$vm_ok;
        skip $msg,10    if !$vm_ok;

        use_ok("Ravada::VM::$vm_name");

        flush_rules();

        my $domain_name = test_create_domain($vm_name);
        test_fw_domain($vm_name, $domain_name, '127.0.0.1');
        test_fw_domain($vm_name, $domain_name);
        test_fw_domain_pause($vm_name, $domain_name);
        test_fw_domain_public_ip($vm_name, $domain_name);

        test_fw_domain_down($vm_name);
    };
}
flush_rules() if !$>;

end();
done_testing();
