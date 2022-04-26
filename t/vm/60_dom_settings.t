use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user('foo','bar', 1);
our $TIMEOUT_SHUTDOWN = 10;

my %HAS_NOT_VALUE = map { $_ => 1 } qw(image jpeg zlib playback streaming);

################################################################
sub test_create_domain {
    my $vm_name = shift;

    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain;
}

sub test_drivers_type {
    my $vm_name = shift;
    my $type = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers");
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);

    if (!$HAS_NOT_VALUE{$type}) {
        my $value = $driver_type->get_value();
        ok($value,"Expecting value for driver type: $type ".ref($driver_type)."->get_value")
            or exit;
    }

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        _domain_shutdown($domain);

        die "No value for driver ".Dumper($option)  if !$option->{value};

        eval { $domain->set_driver($type => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));

        is($domain->get_driver($type), $option->{value}, $type);
        {
            my $domain_f = Ravada::Front::Domain->open($domain->id);
            is($domain_f->get_driver($type), $option->{value});
            rvd_front->list_machines_user(user_admin);
        }

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});
        }
        next unless ($ENV{TEST_STRESS} || $ENV{"TEST_STRESS_$vm_name}"});

        _domain_shutdown($domain);
        $domain->start($USER)   if !$domain->is_active;
        {
            my $domain_f = Ravada::Front::Domain->open($domain->id);
            is($domain_f->get_driver($type), $option->{value});
            rvd_front->list_machines_user(user_admin);
        }

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});

        }

    }
    $domain->remove($USER);
}

sub test_drivers_type_id {
    my $vm_name = shift;
    my $type = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers");
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);

    if (!$HAS_NOT_VALUE{$type}) {
        my $value = $driver_type->get_value();
        ok($value);
    }

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        _domain_shutdown($domain);

        eval { $domain->set_driver_id($option->{id}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));
        my $value = $domain->get_driver($type);
        is($value , $option->{value});

        is($domain->get_driver_id($type), $option->{id});
        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});
        }
        next unless ($ENV{TEST_STRESS} || $ENV{"TEST_STRESS_$vm_name}"});
        $domain->start($USER)   if !$domain->is_active;

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_driver($type);
            is($value2 , $option->{value});

        }

    }
    $domain->remove($USER);
}


sub test_drivers_clone {
    my $vm_name = shift;
    my $type = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);


    my @drivers = $domain->drivers();
    ok(scalar @drivers,"Expecting defined drivers") or return;
    isa_ok(\@drivers,'ARRAY');

    my $driver_type = $domain->drivers($type);

    isa_ok($driver_type,'Ravada::Domain::Driver') or return;

    if (!$HAS_NOT_VALUE{$type}) {
        my $value = $driver_type->get_value();
        ok($value,"[$vm_name] Expecting value for driver type $type : $driver_type->get_value()");
    }

    my @options = $driver_type->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got "
                            .scalar(@options));

    for my $option (@options) {
        _domain_shutdown($domain);
#        diag("Testing $vm_name $type : $option->{name}");

        eval { $domain->set_driver($type => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or '')) or next;
        is($domain->get_driver($type), $option->{value});

        my $clone_name = new_domain_name();
        my $clone_missing = $vm->search_domain($clone_name);
        ok(!$clone_missing,"Domain $clone_name should not exists, got :"
                            .($clone_missing or ''));

        is($domain->get_driver($type), $option->{value}) or next;
        _domain_shutdown($domain);
        is($domain->get_driver($type), $option->{value}) or next;
        $domain->remove_base($USER) if $domain->is_base;
        $domain->prepare_base( user_admin );
        $domain->is_public(1);
        is($domain->is_base,1);
        my $clone = $domain->clone(user => $USER, name => $clone_name);
        isa_ok($clone,"Ravada::Domain::$vm_name");
        is($domain->get_driver($type), $option->{value}) or next;
        is($clone->get_driver($type), $option->{value},$clone->name);
        {
            my $clone2 = $vm->search_domain($clone_name);
            is($clone2->get_driver($type), $option->{value}) or next;
        }
        $clone->start($USER)   if !$clone->is_active;

        {
            my $domain2 = $vm->search_domain($clone_name);
            is($domain2->get_driver($type), $option->{value});

        }
        # try to change the driver in the clone
        for my $option_clone (@options) {
            _domain_shutdown($clone);
            eval { $clone->set_driver($type => $option_clone->{value}) };
            ok(!$@,"Expecting no error, got : ".($@ or ''));
            is($clone->get_driver($type), $option_clone->{value});
            last unless ($ENV{TEST_STRESS} || $ENV{"TEST_STRESS_$vm_name}"});

            $clone->start($USER)    if !$clone->is_active;
            is($clone->get_driver($type), $option_clone->{value});

        }
        # removing the clone and create again, original driver
        $clone->remove($USER);
        my $clone2 = $domain->clone(user => $USER, name => $clone_name);
        is($clone2->get_driver($type), $option->{value});
        $clone2->remove($USER);
        last unless ($ENV{TEST_STRESS} || $ENV{"TEST_STRESS_$vm_name}"});
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

    my $vm = rvd_back->search_vm($vm_name);
    my @drivers = $vm->list_drivers();
#    @drivers = $vm->list_drivers('image');
    for my $driver ( @drivers ) {
#        diag("Testing drivers for $vm_name ".$driver->name);
        next if $driver->name =~ /display|features/;

        test_drivers_type($vm_name, $driver->name);
        test_drivers_clone($vm_name, $driver->name);
        test_drivers_type_id($vm_name, $driver->name);
    }
}

################################################################

clean();

for my $vm_name ( vm_names() ) {
my $vm;
eval { $vm =rvd_back->search_vm($vm_name) };
SKIP: {
    my $msg = "SKIPPED test: No $vm_name backend found"
                ." error: (".($@ or '').")";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    diag("Testing drivers for $vm_name");
    test_settings($vm_name);
        diag("[$vm_name] Skipping stress test, enable TEST_STRESS or TEST_STRESS_$vm_name}")
            unless ($ENV{TEST_STRESS} || $ENV{"TEST_STRESS_$vm_name}"});

};
}

end();
done_testing();
