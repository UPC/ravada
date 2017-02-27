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

    ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );


    return $domain;
}

sub test_settings_video {
    my $vm_name = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my @settings = $domain->settings();
    ok(scalar @settings,"Expecting defined settings");
    isa_ok(\@settings,'ARRAY');

    my $setting_video = $domain->settings('video');

    my $value = $setting_video->get_value();
    ok($value);

    my @options = $setting_video->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got ".scalar(@options));

    for my $option (@options) {
        $domain->shutdown_now($USER)    if $domain->is_active;
        for ( 1 .. 10 ) {
            last if !$domain->is_active;
            sleep 1;
        }

        eval { $domain->set_setting(video => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));
        my $value = $domain->get_setting('video');
        is($value , $option->{value});

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_setting('video');
            is($value2 , $option->{value});
        }
        $domain->start($USER)   if !$domain->is_active;

        {
            my $domain2 = $vm->search_domain($domain->name);
            my $value2 = $domain2->get_setting('video');
            is($value2 , $option->{value});

        }

    }
}

sub test_settings_video_clone {
    my $vm_name = shift;

    my $vm =rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);

    my @settings = $domain->settings();
    ok(scalar @settings,"Expecting defined settings");
    isa_ok(\@settings,'ARRAY');

    my $setting_video = $domain->settings('video');

    my $value = $setting_video->get_value();
    ok($value);

    my @options = $setting_video->get_options();
    isa_ok(\@options,'ARRAY');
    ok(scalar @options > 1,"Expecting more than 1 options , got "
                            .scalar(@options));

    for my $option (@options) {
        $domain->shutdown_now($USER)    if $domain->is_active;
        for ( 1 .. 10 ) {
            last if !$domain->is_active;
            sleep 1;
        }

        eval { $domain->set_setting(video => $option->{value}) };
        ok(!$@,"Expecting no error, got : ".($@ or ''));
        my $value = $domain->get_setting('video');
        is($value , $option->{value});

        my $clone_name = new_domain_name();
        my $clone = $domain->clone(user => $USER, name => $clone_name);
        {
            my $domain2 = $vm->search_domain($clone_name);
            is($domain2->get_setting('video'), $option->{value});
        }
        $clone->start($USER)   if !$clone->is_active;

        {
            my $domain2 = $vm->search_domain($clone_name);
            is($domain2->get_setting('video'), $option->{value});

        }
        # try to change the setting in the clone
        for my $option_clone (@options) {
            $clone->shutdown_now($USER)    if $clone->is_active;
            for ( 1 .. 10 ) {
                last if !$clone->is_active;
                sleep 1;
            }
            eval { $clone->set_setting(video => $option_clone->{value}) };
            ok(!$@,"Expecting no error, got : ".($@ or ''));
            is($clone->get_setting('video'), $option_clone->{value});

        }
        # removing the clone and create again, original setting
        $clone->remove($USER);
        my $clone2 = $domain->clone(user => $USER, name => $clone_name);
        is($clone2->get_setting('video'), $option->{value});

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

    test_settings_video($vm_name);
    test_settings_video_clone($vm_name);
};
remove_old_domains();
remove_old_disks();
done_testing();

