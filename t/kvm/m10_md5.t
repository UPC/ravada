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
my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);

my @VMS = reverse keys %ARG_CREATE_DOM;
init($test->connector);
my $USER = create_user("foo","bar");

############################################3
sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    ok($ARG_CREATE_DOM{lc($vm_name)}) or do {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    };
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;

}

sub test_remove_domain {
    my ($vm_name, $domain) = @_;

    my @volumes = $domain->list_volumes();
    ok(scalar@volumes,"Expecting some volumes, got :".scalar@volumes);

    for my $file (@volumes) {
        ok(-e $file,"Expecting volume $file exists, got : ".(-e $file or 0));
    }
    $domain->remove($USER);
    for my $file (@volumes) {
        ok(!-e $file,"Expecting no volume $file exists, got : ".(-e $file or 0));
    }

}

sub test_isos {
    my $vm = shift;

    diag("testing isos");
    my $sth = $test->connector->dbh->prepare(
        "SELECT * FROM iso_images"
    );
    $sth->execute;

    while (my $row = $sth->fetchrow_hashref) {
        my $iso;
        $iso = $vm->_search_iso($row->{id});

        ok($iso,"Expecting a ISO description");

        like($iso->{url},qr{.iso}) or exit;
        like($iso->{url},qr($row->{file_re})) or exit   if $row->{file_re};
        diag($iso->{file_re}." -> ".$iso->{url})   if $row->{file_re};
    }
    $sth->finish;
}

#######################################################
#

clean();

my $vm_name = 'kvm';
my $vm = rvd_back->search_vm($vm_name);

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    skip($msg,10)   if !$vm;

    my $domain = test_create_domain($vm_name );
    test_remove_domain($vm_name, $domain);

    test_isos($vm);
}

clean();

done_testing();

