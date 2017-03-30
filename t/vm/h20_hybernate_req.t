use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $RVD_BACK = rvd_back($test->connector);
my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

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

        $domain->start($USER)   if !$domain->is_active;

        my $req = Ravada::Request->hybernate(
            id_domain => $domain->id
                  ,uid=> $USER->id
        );
        ok($req);
        rvd_back->process_requests();
        wait_request($req);

        is($domain->is_active,0);

        $domain->start($USER);
        is($domain->is_active,1);


    }
}

clean();

done_testing();

