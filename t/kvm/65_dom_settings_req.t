use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $FILE_CONFIG = 't/etc/ravada.conf';

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, $FILE_CONFIG);

my $USER = create_user('foo','bar');
my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
);
our $TIMEOUT_SHUTDOWN = 10;

################################################################
sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    if (!$ARG_CREATE_DOM{$vm_name}) {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    }
    my @arg_create = @{$ARG_CREATE_DOM{$vm_name}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , @{$ARG_CREATE_DOM{$vm_name}})
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain;
}

sub test_drivers_id {
    my $vm_name = shift;
    my $type = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers");
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);

    my $value = $driver_type->get_value();
    ok($value);

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        _domain_shutdown($domain);

        my $req = Ravada::Request->set_driver( 
            id_domain => $domain->id
            , uid => $USER->id
            , id_option => $option->{id}
        );
        rvd_back->_process_requests_dont_fork();
        is($req->status,'done') or next;
        is($req->error,'') or next;

        ok(!$@,"Expecting no error, got : ".($@ or ''));
        my $value = $domain->get_driver($type);
        is($value , $option->{value});

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

    for my $driver ( Ravada::Domain::drivers(undef,undef,$vm_name) ) {
        next if $driver->name ne 'video';
        diag("Testing drivers for $vm_name ".$driver->name);
        test_drivers_id($vm_name, $driver->name);
    }
}

################################################################

remove_old_domains();
remove_old_disks();

my $vm_name = 'KVM';
my $vm;
eval { $vm =rvd_back->search_vm($vm_name) };
SKIP: {
    my $msg = "SKIPPED test: No $vm_name backend found"
                ." error: (".($@ or '').")";
    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    test_settings($vm_name);
};
remove_old_domains();
remove_old_disks();
done_testing();

