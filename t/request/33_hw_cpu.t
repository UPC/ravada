use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

###############################################################################
sub test_add_vcpu($domain) {
    my $info = $domain->info(user_admin);
    my $cpu = $info->{hardware}->{cpu};
    my $n = $info->{n_virt_cpu};

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { n_virt_cpu => $n+2 }
        ,hardware => 'vcpus'
    );
    wait_request();

    my $domain2 = Ravada::Domain->open($domain->id);
    my $info2 = $domain2->info(user_admin);
    is($info2->{n_virt_cpu},$n+2);

    return if ($domain->type eq 'Void');

    is($info2->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},$n+2)
            or die $domain->name."\n".Dumper($info2->{hardware}->{cpu});

    $domain->start(user_admin);
    $n+=2;

    my $req2 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { n_virt_cpu => $n+2 }
        ,hardware => 'vcpus'
    );
    wait_request();

    $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->_data('needs_restart'),1) or exit;

    my $info3 = $domain->info(user_admin);
    is($info3->{n_virt_cpu},$n);

}

sub test_less_vcpu_down($domain) {
    $domain->shutdown_now(user_admin);
    my $info = $domain->info(user_admin);
    my $cpu = $info->{hardware}->{cpu};
    my $n = $info->{n_virt_cpu};

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { n_virt_cpu => $n-1 }
        ,hardware => 'vcpus'
    );
    wait_request();

    my $domain2 = Ravada::Domain->open($domain->id);
    my $info2 = $domain2->info(user_admin);
    if ($domain->type eq 'KVM') {
        is($info2->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},$n-1)
            or die Dumper($info2->{hardware}->{cpu});
    }
    is($info2->{n_virt_cpu},$n-1) or die $domain->name."\n"
        .Dumper($info2->{hardware}->{cpu}->[0]);

    is($domain2->_data('needs_restart'),0) or exit;
}

sub test_less_vcpu_up($domain) {
    $domain->start(user_admin);
    my $info = $domain->info(user_admin);
    my $cpu = $info->{hardware}->{cpu};
    my $n = $info->{n_virt_cpu};

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,data => { n_virt_cpu => $n-1 }
        ,hardware => 'vcpus'
    );
    wait_request();

    my $domain2 = Ravada::Domain->open($domain->id);
    my $info2 = $domain2->info(user_admin);

    is($info2->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},$n-1)
    if $domain->type eq 'KVM';

    if ( $domain->type eq 'Void') {
        is($info2->{n_virt_cpu},$n-1);
    } elsif ($domain->type eq 'KVM') {
        is($info2->{n_virt_cpu},$n);
    }

    is($domain2->_data('needs_restart'),1) or exit;

    $domain->shutdown_now(user_admin);
    $domain->start(user_admin);

    my $domain3 = Ravada::Domain->open($domain->id);
    my $info3 = $domain3->info(user_admin);

    is($info3->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},$n-1)
    if $domain->type eq 'KVM';

    is($info3->{n_virt_cpu},$n-1) or die $domain->name;
    $domain->shutdown_now(user_admin);
}

sub test_add_cpu($domain) {
    return if $domain->type ne 'KVM';

    my $info = $domain->info(user_admin);
    my $n = $info->{hardware}->{cpu}->[0]->{vcpu}->{'#text'};

    $domain->shutdown_now(user_admin);
    my $req0 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,'data' => { vcpu => { '#text' => $n+1 }}
    );
    wait_request();

    my $domain2 = Ravada::Domain->open($domain->id);
    my $info2 = $domain2->info(user_admin);
    my $n2 = $info2->{hardware}->{cpu}->[0]->{vcpu}->{'#text'};
    is($n2, $n+1) or die $domain->name;

}


sub test_add_threads($domain) {

    return if $domain->type ne 'KVM';

    $domain->shutdown_now(user_admin);
    my $req0 = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,'data' => { vcpu => { '#text' => 1 }}
    );
    wait_request();

    my $req = Ravada::Request->change_hardware(
        uid => user_admin->id
        ,id_domain => $domain->id
        ,hardware => 'cpu'
        ,'data' => {
            '_order' => 0,
            'vcpu' => {
                '#text' => undef,
                'placement' => 'static'
            },
            'cpu' => {
                'model' => {
                    '#text' => 'qemu64',
                    'fallback' => 'forbid'
                },
                'check' => 'full',
                'topology' => {
                    'threads' => 2
                },
                'mode' => 'custom',
                'match' => 'exact',
            }
        }
    );
    wait_request();
    $domain = Ravada::Domain->open($domain->id);

    my $info = $domain->info(user_admin);
    my $n = $info->{hardware}->{cpu}->[0]->{vcpu}->{'#text'};
    is($n, 2) or die $domain->name;

    is($info->{n_virt_cpu},2) or die $domain->name;
}

###############################################################################

clean();

for my $vm_name ( vm_names() ) {
    diag($vm_name);

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) } if !$< || $vm_name eq 'Void';

    SKIP: {

        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;
        my $domain = create_domain($vm);
        test_add_vcpu($domain);
        test_less_vcpu_down($domain);
        test_less_vcpu_up($domain);

        test_add_cpu($domain);
        test_add_threads($domain) if $vm_name eq 'KVM';
    }
}

done_testing()
