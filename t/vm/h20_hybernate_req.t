use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

################################################################

clean();

for my $vm_name ( @{rvd_front->list_vm_types}) {

    my $vm = rvd_back->search_vm($vm_name);

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        my $domain = create_domain($vm_name, $USER) or next;

        next if !$domain->can_hybernate();

        for my $fork ( 0, 1 ) {
        $domain->start($USER)   if !$domain->is_active;
        for ( 1 .. 10 ) {
            last if $domain->is_active;
            sleep 1;
        }
        is($domain->is_active, 1) or exit;

        my $req = Ravada::Request->hybernate(
            id_domain => $domain->id
                  ,uid=> $USER->id
        );
        ok($req);
        if($fork) {
            rvd_back->process_requests();
        } else {
            rvd_back->_process_all_requests_dont_fork();
        }
        wait_request( background => $fork );

        $domain = rvd_back->search_domain($domain->name);
        is($domain->is_active,0);

        $domain->start($USER)   if !$domain->is_active;
        if (!$domain->is_active) {
            sleep(1);
            $domain->start($USER)   if !$domain->is_active;
        }

        is($domain->is_active,1);

        }# for my $fork

    }
}

end();
done_testing();
