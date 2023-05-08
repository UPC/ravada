use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;

init();
clean();

###########################################################

for my $vm_name ( reverse vm_names() ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        if ($vm_name eq 'Void') {
            $BASE = create_domain($vm);
        } else {
            $BASE = import_domain($vm);
        }

        my $domain = $BASE->clone(name => new_domain_name()
        ,user=> user_admin);
        $domain->start(user_admin);
        for ( 1 .. 30 ) {
            last if $domain->ip;
            sleep 1;
        }
        $domain->_open_iptables_state();
        my $local_net = $domain->ip;
        $local_net =~ s{(.*)\.\d+}{$1.0/24};

        my $found = $vm->_search_iptables(
        A => 'FORWARD'
        ,m => 'state'
        ,d => $local_net
        ,state => 'NEW,RELATED,ESTABLISHED'
        ,j => 'ACCEPT'
        );
        ok($found) or exit;

        $domain->_open_iptables_state();

        my $iptables = $vm->iptables_list();
        my %dupe;
        for my $table (keys %$iptables) {
            for my $rule (@{$iptables->{$table}}) {

                my $string = join(" ", map { $_ or '' } @$rule);
                next if $string eq 'A POSTROUTING j LIBVIRT_PRT';
                die Dumper($rule) if $dupe{$string}++;
            }
        }


    }
}

end();

done_testing();
