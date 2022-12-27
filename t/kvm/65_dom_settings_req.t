use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

init();

my $USER = create_user(new_domain_name().'.foo','bar', 1);
our $TIMEOUT_SHUTDOWN = 10;

our %SKIP_DEFAULT_VALUE = map { $_ => 1 } qw(image jpeg playback streaming zlib);

################################################################
sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my %arg_create = arg_create_dom($vm_name);
    my %options = %{$arg_create{options}};
    confess if !keys %options;

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , %arg_create
                     );
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub test_driver_id_64bits_options($vm_name, $type) {
    next if $vm_name ne 'KVM';
    my $vm =rvd_back->search_vm($vm_name);
    my $domain = create_domain_v2(vm_name => $vm_name
        ,swap => 1
        ,data => 1
        ,iso_name => 'Alpine%64'
    );

    test_drivers_id($vm_name, $type, $domain);

}

sub _keep_only_two_usb_ports($domain) {

    my $usb = $domain->info(user_admin)->{hardware}->{usb};
    if (scalar(@$usb)>2) {
        for my $index (reverse 2 .. scalar(@$usb)-1) {
            Ravada::Request->remove_hardware(
                name => 'usb'
                ,id_domain => $domain->id
                ,uid => user_admin->id
                ,index => $index
            );
        }
        wait_request();
    }
}

sub test_drivers_id($vm_name, $type, $domain=undef) {

    my $vm =rvd_back->search_vm($vm_name);
    $domain = test_create_domain($vm_name) if !$domain;

    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers");
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);

    if ($driver_type eq 'usb controller') {
    }

    if (!$SKIP_DEFAULT_VALUE{$type}) {
        my $value = $driver_type->get_value();
        ok($value,"[$vm_name] Expecting a value for driver $type");
    }

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    my $usb = $domain->info(user_admin)->{hardware}->{usb};

    if ($type eq 'usb controller') {
        _keep_only_two_usb_ports($domain);
    } else {
        my $req_add_usb = Ravada::Request->add_hardware(
            id_domain => $domain->id
            , uid => $USER->id
            , name => 'usb'
            , number => 3
        );
        wait_request(debug => 0);
    }

    for my $option (@options) {

        # this drivers implies changes to the VM and can't be tested easily
        next if $type eq 'usb controller'
        && $option->{value} eq 'piix3-uhci';

        _domain_shutdown($domain);

        my $req = Ravada::Request->set_driver( 
            id_domain => $domain->id
            , uid => $USER->id
            , id_option => $option->{id}
        );
        rvd_back->_process_requests_dont_fork();
        is($req->status,'done') or next;
        is($req->error,'') or die Dumper($domain->name,$option);

        ok(!$@,"Expecting no error, got : ".($@ or ''));
        my $value = $domain->get_driver($type);
        is($value , $option->{value}) or exit;

        is($domain->needs_restart,0);

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});
        }
        $domain->start($USER)   if !$domain->is_active;

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});

        }

    }
    $domain->remove($USER);
}


sub _domain_shutdown {
    my $domain = shift;
    $domain->shutdown_now($USER) if $domain->is_active;
    for ( 1 .. $TIMEOUT_SHUTDOWN) {
        last if !$domain->is_active;
        sleep 1;
    }
}

sub test_settings {
    my $vm_name = shift;

    for my $driver (reverse Ravada::Domain::drivers(undef,undef,$vm_name) ) {
        next if $driver->name =~ /features|display/;
        diag("Testing drivers for $vm_name ".$driver->name);
        test_driver_id_64bits_options($vm_name, $driver->name);
        test_drivers_id($vm_name, $driver->name);

    }
}

sub test_needs_shutdown {
    my $vm_name = shift;

    my $domain = test_create_domain($vm_name);

    my ($type) = grep { $_->name !~ /(features)/ }
        Ravada::Domain::drivers(undef,undef,$vm_name);

    my $driver_type = $domain->drivers($type->name);

    ok($driver_type,"Expecting driver of type $type") or exit;

    my @options = $driver_type->get_options();
    my ($option) = @options;

    $domain->start(user_admin);

    is($domain->is_active,1);

    my $req = Ravada::Request->set_driver( 
            id_domain => $domain->id
            , uid => $USER->id
            , id_option => $option->{id}
    );
    rvd_back->_process_requests_dont_fork();
    is($req->status,'done') or return;
    is($req->error,'') or return;

    ok(!$@,"Expecting no error, got : ".($@ or ''));

    {
        my $domain_f = Ravada::Front::Domain->open($domain->id);
        my $value = $domain_f->get_driver($type->name);
        is($value , $option->{value});
        ;

        is($domain_f->needs_restart, 1);
    }

    $domain->shutdown_now(user_admin);
    is($domain->needs_restart, 0);

    {
        my $domain_f = Ravada::Front::Domain->open($domain->id);
        my $value = $domain_f->get_driver($type->name);
        is($value , $option->{value});

        is($domain_f->needs_restart, 0) or exit;
    }
    $domain->remove(user_admin);
}

################################################################

remove_old_domains();
remove_old_disks();

my $vm_name = 'KVM';
my $vm;
eval { $vm =rvd_back->search_vm($vm_name) } if !$<;
SKIP: {
    my $msg = "SKIPPED test: No $vm_name backend found"
                ." error: (".($@ or '').")";
    if ($vm && $vm_name eq 'KVM' && $>) {
        $vm = undef;
        $msg = "SKIPPED: Test must run as root";
    }
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    test_needs_shutdown($vm_name);

    test_settings($vm_name);

};

end();
done_testing();

