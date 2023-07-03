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

    my $req2 = Ravada::Request->change_hardware(
        hardware => 'vcpus'
        ,data => { n_virt_cpu => 3 }
        ,id_domain => $domain->id
        ,uid => user_admin->id
    );
    wait_request();
}

sub _custom_cpu_susana($domain) {

    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);
    my ($vcpu) = $xml->findnodes("/domain/vcpu");
    $vcpu->setAttribute('placement' => 'static');
    $vcpu->setAttribute('current' => '2');

    my ($vcpu_max) = $xml->findnodes("/domain/vcpu/text()");
    $vcpu_max->setData('4');

    my ($cpu) = $xml->findnodes("/domain/cpu");
    my %data = ( mode => 'custom' , match => 'exact', check => 'partial');
    for my $field( keys %data) {
        $cpu->setAttribute( $field => $data{$field});
    }
    $cpu->removeChildNodes();
    my $model = $cpu->addNewChild(undef,'model');
    $model->setAttribute('fallback' => 'allow');
    $model->appendText('qemu64');

    $domain->reload_config($xml);

}

sub test_change_vcpu_topo($vm) {
    return if $vm->type ne 'KVM';

    my $domain = create_domain($vm);
    _custom_cpu_susana($domain);

    my %data = (
         'hardware' => 'cpu',
          'id_domain' => $domain->id,
          'uid' => user_admin->id,
          'index' => 0,
          'data' => {
                      '_can_edit' => 1,
                      'vcpu' => {
                                  'placement' => 'static',
                                  '#text' =>undef
                                },
                      '_cat_remove' => 0,
                      '_order' => 0,
                      'cpu' => {
                                 'model' => {
                                              '#text' => 'qemu64',
                                              'fallback' => 'allow'
                                            },
                                 'check' => 'partial',
                                 'match' => 'exact',
                                 'mode' => 'custom',
                                 'topology' => {
                                                 'sockets' => 2
                                               },
                                 'feature' => [
                                                {
                                                  'name' => 'svm',
                                                  '$$hashKey' => 'object:64',
                                                  'policy' => 'optional'
                                                }
                                              ]
                               }
                    }
                );
    my $req = Ravada::Request->change_hardware(%data);
    wait_request();

    my $domain2 = Ravada::Front::Domain->open($domain->id);
    my $info = $domain2->info(user_admin);
    is($info->{n_virt_cpu},2);
    is($info->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},2);

    _custom_cpu_susana($domain);
    delete $data{data}->{cpu}->{topology};
    $data{data}->{vcpu}->{'#text'}=3;

    Ravada::Request->change_hardware(%data);
    wait_request(debug => 0);

    my $domain3 = Ravada::Front::Domain->open($domain->id);
    my $info3 = $domain3->info(user_admin);
    is($info3->{n_virt_cpu},3) or die $domain3->name;

    is($info3->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},3);

    _custom_cpu_susana($domain);

    $data{data}->{n_virt_cpu} = 5;
    $data{hardware} = 'vcpus';
    delete $data{data}->{vcpu};
    delete $data{data}->{cpu};

    my $req3 = Ravada::Request->change_hardware(%data);
    wait_request(debug => 0);

    my $domain4 = Ravada::Front::Domain->open($domain->id);
    my $info4 = $domain4->info(user_admin);
    is($info4->{n_virt_cpu},5);
    is($info4->{hardware}->{cpu}->[0]->{vcpu}->{'#text'},5);

    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);
    my ($cpu) = $xml->findnodes("/domain/vcpu");

    $domain->remove(user_admin);
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

        test_change_vcpu_topo($vm);

        my $domain = create_domain($vm);
        test_add_vcpu($domain);
        test_less_vcpu_down($domain);
        test_less_vcpu_up($domain);

        test_add_cpu($domain);
        test_add_threads($domain) if $vm_name eq 'KVM';
    }
}

done_testing()
