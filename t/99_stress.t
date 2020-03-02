use warnings;
use strict;

use Data::Dumper;
use Test::More;

use Carp qw(confess);
use Cwd;
use IPC::Run3 qw(run3);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada') or BAIL_OUT;

my $RVD_BACK;

my %DOMAIN_INSTALLING;

our %CHECKED;
our %CLONE_N;
my $N_MIN;
#####################################################################3

sub install_base {
    my $vm_name = shift;

    my $name = Test::Ravada::base_domain_name."_$vm_name";

    $DOMAIN_INSTALLING{$vm_name} = $name;

    my $vm = rvd_back->search_vm($vm_name);

    my $id_iso = search_id_iso('debian%64');
    ok($id_iso) or BAIL_OUT;

    my $old_domain = $vm->search_domain($name);

    if ( $old_domain ) {
        return $name if $vm->type eq 'Void';
    }

    my $internal_domain;
    eval { $internal_domain = $vm->vm->get_domain_by_name($name) };
    return $name if $old_domain && $internal_domain;

    if ($internal_domain) {
        rvd_back->import_domain(
            vm => $vm->type
            ,name => $name
            ,user => user_admin->name
        );
        return $name;
    }
    my $domain = $vm->search_domain($name,1);
    $domain->remove(user_admin) if $domain;

    $domain = $vm->create_domain(
        name => $name
        ,id_iso => $id_iso
        ,id_owner => user_admin->id
        ,disk => int(1.3 * 1024 * 1024 * 1024)
    );
    my $ram = 256;
    $domain->add_volume(
        name => $domain->name.".vdb"
        ,swap => 1
        ,size => $ram * 1024 * 1024
    );

    return $name if $vm_name eq 'Void';

    my $iso = $vm->_search_iso($id_iso);
    my @volumes = $domain->list_volumes();

    $domain->domain->undefine();

    my @cmd = qw(virt-install
        --noautoconsole
        --vcpus 1
        --os-type linux
        --os-variant debian9
        --video qxl --channel spicevmc
    );
    my $preseed = getcwd."/t/preseed.cfg";
    ok(-e $preseed,"ERROR: Missing $preseed") or BAIL_OUT;

    push @cmd,('--ram', $ram);
    push @cmd,('--graphics','spice,listen='.$vm->ip);
    push @cmd,('--extra-args', "'console=ttyS0,115200n8 serial'");
    push @cmd,('--initrd-inject',$preseed);
    push @cmd,('--name' => $name );
    push @cmd,('--disk' => $volumes[0]
                            .",bus=virtio"
                            .",cache=unsafe");# only for this test
    push @cmd,('--disk' => $volumes[1]
                            .",bus=virtio"
                            .",cache=unsafe");# only for this test

    push @cmd,('--network' => 'bridge=virbr0,model=virtio');
    push @cmd,('--location' => $iso->{device});

    my ($in, $out, $err);
    run3(\@cmd,\$in, \$out, \$err);
    diag($out);
    diag($err)  if $err;

    return $name;
}

sub _wait_base_installed($vm_name) {
    my $name = $DOMAIN_INSTALLING{$vm_name} or die "No $vm_name domain installing";

    diag("[$vm_name] waiting for $name");
    my $vm = rvd_back->search_vm($vm_name);
    return $name if $vm_name eq 'Void';

    my $domain = $vm->search_domain($name);
    diag("Waiting for shutdown from agent");
    for (;;) {
        last if !$domain->is_active;
        eval {
            $domain->domain->shutdown(Sys::Virt::Domain::SHUTDOWN_GUEST_AGENT);
        };
        warn $@ if $@ && $@ !~ /^libvirt error code: 74,/;
        sleep 1;
    }
    return $name;
}

sub test_create_clones($vm_name, $domain_name, $n_clones=undef) {

    diag("[$vm_name] create clones from $domain_name");
    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name) or return;

    $domain->prepare_base(user_admin)   if !$domain->is_base;
    $domain->is_public(1);

    my $n_users = int($vm->free_memory / 1024 /1024) ;
    $n_users = 3 if $n_users<3;
    $n_users = $n_clones if defined $n_clones;
    diag("creating $n_users");

    my @domain_reqs = $domain->list_requests;
    _wait_requests([@domain_reqs]) if scalar @domain_reqs;

    my @reqs;
    my @clones;
    for my $n ( 1 .. $n_users ) {
        my $user_name = "tstuser-".$domain->id."-".$n;
        my $user = Ravada::Auth::SQL->new(name => $user_name);
        $user = create_user($user_name,$n)   if !$user || !$user->id;
        die "User $user_name not created" if !$user->id;

        my $user2 = Ravada::Auth::SQL->search_by_id($user->id);
        ok($user2, "Expecting user id ".$user->id) or exit;
        my $clone_name = new_clone_name($domain_name);
        my $clone = $vm->search_domain($clone_name);
        push @reqs,(Ravada::Request->remove_domain(
                        uid => user_admin->id
                 ,name => $clone_name
                )
        )   if $clone;

        my $mem = 1024 * 256;
        $mem = 1024 * 128 if $n_users < 3 && $vm_name eq 'Void';
        my $req = Ravada::Request->clone(
            name => $clone_name
            ,uid => $user->id
            ,id_domain => $domain->id
            , memory => $mem
        );
        diag("create $clone_name");
        push @clones,($clone_name);
        push @reqs,($req);
        push @reqs,(random_request($vm))  if rand(10)<2;
    }
    _wait_requests(\@reqs);
    for my $clone_name (@clones) {
        my $clone = rvd_back->search_domain($clone_name);
        ok($clone,"Expecting clone $clone_name created") or exit;
    }
}

sub random_request($vm) {
    my @domains = $vm->list_domains();

    my $domain = $domains[rand($#domains)];
    return if $domain->name =~ /[a-z]$/i;
    my $base = base_domain_name();
    return if $domain->name !~ /^$base/;

    return if $domain->is_base;

    return Ravada::Request->remove_domain(
        uid => $domain->id_owner
        ,name => $domain->name
    )   if rand(10)<2;

    my $ip = '192.168.1.'.int(rand(254)+1);
    if (!$domain->is_active) {
        return Ravada::Request->start_domain(
            remote_ip => $ip
            ,uid => $domain->id_owner
            ,id_domain => $domain->id
        );
    } elsif(rand(30)<10) {
        return Ravada::Request->hybernate(
            uid => $domain->id_owner
            ,id_domain => $domain->id
        )
    } elsif(rand(30)<10) {
        return Ravada::Request->shutdown_domain(
            uid => $domain->id_owner
            ,id_domain => $domain->id
        );
    } else {
        return Ravada::Request->open_iptables(
            uid => $domain->id_owner
            ,id_domain => $domain->id
            ,remote_ip => $ip
        );

    }
}

sub _fill_vm($field, $attrib, $vm, $req_name) {
    if (defined $field->{$attrib} && $field->{$attrib} == 2 && rand(4)<2 ) {
        delete $field->{$attrib};
        return;
    }
    $field->{$attrib} = $vm->type;
    $field->{$attrib} = 'KVM' if $field->{$attrib} =~ /qemu/i;

}

sub _fill_name($field, $attrib, $vm, $req_name) {
    if ($req_name =~ /_hardware$/) {
        _fill_id_domain($field, 'id_domain', $vm, $req_name) if !$field->{id_domain};
        my $domain = Ravada::Domain->open($field->{id_domain});
        my %controllers = $domain->list_controllers();
        my @c_names = keys %controllers;
        $field->{$attrib} = $c_names[int rand(scalar@c_names)];
    } else {
        $field->{$attrib} = new_domain_name($vm->type);
    }
}

sub _fill_remote_ip($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = '192.168.1.'.int(rand(254)+1);
}

sub _fill_id_vm($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = $vm->id;
}

sub _fill_at($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = time + int(rand(30));
}

sub _fill_filename($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = "/var/tmp/$$".int(rand(100)).".txt";
}

sub _select_domains(@list_args) {
    my $domains0 = rvd_front->list_domains( @list_args );
    my @domains;
    for (@$domains0) {
        push @domains,($_) if $_->{name} =~ /^99/;
    }
    return \@domains;
}
sub _select_bases(@list_args) {
    my $domains0 = rvd_front->list_bases( @list_args );
    my @domains;
    for (@$domains0) {
        push @domains,($_) if $_->{name} =~ /^99/;
    }
    return \@domains;
}

sub _fill_id_domain($field, $attrib, $vm, $req_name) {
    my $domains = _select_domains( id_vm => $vm->id );
    my $dom;
    for ( 1 .. 100 ) {
        $dom = $domains->[rand(scalar(@$domains))];
        next if _domain_requested_remove($dom->{id});
        my $base = base_domain_name();
        last if $dom->{name} =~ /^$base.*\d$/;
    }
    $field->{$attrib} = $dom->{id};
}

sub _domain_requested_remove($id_domain) {
    my $domain = Ravada::Domain->open($id_domain);
    for my $req ($domain->list_all_requests) {
        return if $req->command eq 'remove_domain';
    }
    return 0;
}

sub _fill_uid($field, $attrib, $vm, $req_name) {
    my $users = rvd_front->list_users();
    if (rand(5)<3 && exists $field->{id_domain}) {
        _fill_id_domain($field,'id_domain', $vm, $req_name);
        eval {
            my $domain = Ravada::Domain->open($field->{id_domain});
            $field->{$attrib} = $domain->id_owner;
        };
        if($@) {
            diag($@);
            return _fill_uid($field, $attrib, $vm);
       }
    } else {
        $field->{$attrib} = $users->[int(rand(scalar @$users))]->{id};
    }
}

sub _fill_memory($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = int(rand(10)+1)* 1024 * 1024;
}

sub _fill_id_iso($field, $attrib, $vm, $req_name) {
    my $isos = rvd_front->list_iso_images();
    $field->{$attrib} = $isos->[int(rand(@$isos))]->{id};
}

sub _fill_network($field, $attrib, $vm, $req_name) {
    my @networks = $vm->list_networks();
    $field->{$attrib} = $networks[int(rand(scalar @networks))];
}

sub _fill_boolean($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = int(rand(2));
}

sub _fill_timeout($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = int(rand(120));
}

sub _fill_id_option($field, $attrib, $vm, $req_name) {
    _fill_id_domain($field,'id_domain', $vm, $req_name);

    my $domain = Ravada::Domain->open($field->{id_domain});
    my @drivers = Ravada::Domain::drivers(undef, undef, $vm->type);

    if (!scalar(@drivers)) {
        die "No drivers for ".$vm->type." at Ravada::Domain::drivers";
        return;
    }
    my $driver = $drivers[int(rand(scalar(@drivers)))];

    my $driver_type = $domain->drivers($driver->name);

    my @options = $driver_type->get_options();
    my $option;
    for (1 .. 100) {
        $option = $options[int(rand(scalar @options))];
        # unsupported id option Xen in Qemu
        last if exists $option->{id} && $option->{id} != 5;
    }
    confess "No id in ".Dumper($option) if !$option->{id};
    $field->{$attrib} = $option->{id};
}

sub _fill_id_template($field, $attrib, $vm, $req_name) {
    if ( $vm->type eq 'LXC' ) {
        confess "TODO id_template for LXC";
    } else {
        delete $field->{$attrib}
    }
}

sub _fill_iso_file($field, $attrib, $vm, $req_name) {
    my @iso = $vm->search_volume(qr(\.iso));
    $field->{$attrib} = $iso[int(rand(scalar @iso))];
}

sub _fill_id_base($field, $attrib, $vm, $req_name) {
    my $bases = _select_bases( id_vm => $vm->id );
    $field->{$attrib} = $bases->[int(rand($#$bases))]->{id};
}

sub _fill_id_clone($field, $attrib, $vm, $req_name) {
    my $domains = _select_domains(id_vm => $vm->id);
    confess "No domains id_vm => ".$vm->id  if !scalar@$domains;
    my @clones;
    for (@$domains) {
        push @clones,($_)  if $_->{id_base};
    }
    confess "No clones ".Dumper($domains) if !scalar @clones;
    $field->{$attrib} = $clones[int(rand($#clones))]->{id};
}

sub _fill_number($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = int(rand(10));
}

sub _fill_ram($field, $attrib, $vm, $req_name) {
    $field->{$attrib} = int(rand(4 * 1024 * 1024));
}

sub random_request_compliant($vm_name) {

    my $vm = rvd_back->search_vm($vm_name);
    my @requests = keys %Ravada::Request::VALID_ARG;
    my $req_name = $requests[int rand(scalar @requests)];

    return if $vm_name eq 'Void' && $req_name =~ /download|set_driver/;
    return if $req_name eq 'download';

    diag("[$vm_name] Requesting random $req_name");
    my %field = map { $_ => undef } keys %{$Ravada::Request::VALID_ARG{$req_name}};
    return new_request($req_name, \%field, $vm);
}

sub new_request($req_name, $field, $vm) {
    my %fill_attrib = (
        vm => \&_fill_vm
        ,at => \&_fill_at
        ,ram => \&_fill_ram
        ,uid => \&_fill_uid
        ,name => \&_fill_name
        ,swap => \&_fill_memory
        ,disk => \&_fill_memory
        ,value => \&_fill_boolean
        ,id_vm => \&_fill_id_vm
        ,start => \&_fill_boolean
        ,index => \&_fill_number
        ,id_iso => \&_fill_id_iso
        ,number => \&_fill_number
        ,memory => \&_fill_memory
        ,id_base => \&_fill_id_base
        ,timeout => \&_fill_timeout
        ,verbose => \&_fill_boolean
        ,network => \&_fill_network
        ,id_owner => \&_fill_uid
        ,iso_file => \&_fill_iso_file
        ,filename => \&_fill_filename
        ,id_domain => \&_fill_id_domain
        ,id_option => \&_fill_id_option
        ,remote_ip => \&_fill_remote_ip
        ,id_template => \&_fill_id_template
    );
    for my $attrib ( keys %$field ) {
        die "I don't know how to handle field $attrib in $req_name\n".Dumper($field)
            if !$fill_attrib{$attrib};
        $fill_attrib{$attrib}->($field, $attrib, $vm, $req_name);
    }
    clean_request($req_name, $vm->type, $field);
    diag(Dumper($field));

    return Ravada::Request->$req_name(%$field);
}

sub test_requests($vm_name) {
    my $vm = rvd_back->search_vm($vm_name);
    my @requests = sort keys %Ravada::Request::VALID_ARG;
    for my $req_name (@requests) {
        next if $req_name eq 'download';
        my $fields = $Ravada::Request::VALID_ARG{$req_name};
        diag("Testing $req_name ".Dumper($fields));
        my %fields_dom = map { $_ => undef } keys %$fields;
        my $req = new_request($req_name, \%fields_dom, $vm);
        _wait_requests([$req]);

        #remove optional attribs 1 by 1
        for my $attrib (sort keys %$fields ) {
            next if $fields->{$attrib} != 2;
            %fields_dom = map { $_ => undef } keys %$fields;
            delete $fields_dom{$attrib};
            my $req = new_request($req_name, \%fields_dom, $vm);
            _wait_requests([$req]);
        }

        #remove all optional attribs
        my @remove_field;
        for my $attrib (sort keys %$fields ) {
            next if $fields->{$attrib} != 2;
            %fields_dom = map { $_ => undef } keys %$fields;
            push @remove_field,($attrib);
            for (@remove_field) {
                delete $fields_dom{$_};
            }
            diag("Removed fields : ".join(",", sort @remove_field));
            my $req = new_request($req_name, \%fields_dom, $vm);
            _wait_requests([$req]);
        }
        if ($req_name eq 'create_domain') {
            delete $fields_dom{'vm'};
            $fields_dom{id_base} = 1;
            my $req = new_request($req_name, \%fields_dom, $vm);
            _wait_requests([$req]);
        }
    }
}

sub clean_request($req_name,  $vm_name, $field) {
    $vm_name = 'KVM' if $vm_name eq 'qemu';
    my $vm = rvd_back->search_vm($vm_name) or confess "Error, unknown vm called '$vm_name'";
    if ($req_name eq 'start_domain') {
        return if !exists $field->{id_domain} || !exists $field->{name};
        if (rand(2) <1) {
            delete $field->{id_domain};
        } else {
            delete $field->{name};
        }
    } elsif($req_name eq 'create_domain') {
        delete $field->{network} if $vm_name eq 'Void';
        $field->{vm} = $vm_name if !$field->{id_base};
        if ($field->{id_base}) {
            for('swap','disk','iso_file','id_iso') {
                delete $field->{$_};
            }
        }
        warn "cleaned create domain ".Dumper($field);
    } elsif($req_name eq 'remove_domain') {
        my $domain;
        if ($field->{id_domain}) {
            $domain = Ravada::Domain->open($field->{id_domain});
        } elsif($field->{name}) {
            $domain = $vm->search_domain($field->{name});
        }
        return if !$domain;
        my $is_main = 0;
        for my $vm_installing (keys %DOMAIN_INSTALLING) {
            $is_main++ if $DOMAIN_INSTALLING{$vm_installing} eq $domain->name;
        }
        return if !$is_main;
        delete $field->{name};
        delete $field->{id_domain};
    } elsif ($req_name eq 'copy_screenshot') {
        my $domain = Ravada::Domain->open($field->{id_domain});
        if (!$domain->id_base) {
            _fill_id_clone($field, 'id_domain', $vm, $req_name);
            $domain = Ravada::Domain->open($field->{id_domain});
        }
        if ( !$domain->file_screenshot ) {
            my $req = Ravada::Request->screenshot_domain(
                        id_domain => $field->{id_domain}
                        ,filename => "/var/tmp/".$domain->id.".txt"
            );
            diag("Requesting screenshot for $field->{id_domain}");
            _wait_requests([$req]);
        }
    } elsif ($req_name eq 'shutdown_domain') {
        if (!exists $field->{id_domain} && !exists $field->{name}) {
            _fill_id_domain($field, 'id_domain', $vm, $req_name);
        }
    }
    $field->{vm}='KVM' if exists $field->{vm} && $field->{vm} =~ /qemu/i;
}

sub test_random_requests($vm_name0, $count=10) {

    my @reqs;
    for ( 1 .. $count ){
        my $vm_name = $vm_name0;
        $vm_name=$vm_name0->[int rand(scalar @$vm_name0)]  if ref($vm_name0);
        my $vm = rvd_back->search_vm($vm_name);
        my $req = random_request_compliant($vm_name) or next;
        push @reqs,($req);
        if ( $req->command eq 'copy_screenshot' || $req->command =~ /create/i ) {
            _wait_requests(\@reqs);
            @reqs=();
        }
    }
    _wait_requests(\@reqs);
}

sub new_clone_name {
    my $base_name = shift;

    my $clone_name;
    $CLONE_N{$base_name} = $N_MIN if !exists $CLONE_N{$base_name};
    my $n = $CLONE_N{$base_name}++;
    for ( ;; ) {
        $n++;
        $n = "0$n" while length($n)<3;
        $clone_name = "$base_name-$n";

        return $clone_name if !rvd_front->domain_exists($clone_name);
    }
}

sub test_restart($vm_name) {

    my $vm = rvd_back->search_vm($vm_name);

    for my $count ( 1 .. 1 ) {
        my @reqs;
        diag("COUNT $count");

        my $t0 = time;
        my @domains;
        for my $domain ( $vm->list_domains ) {
            my $min_memory = ($vm->min_free_memory or $domain->get_info->{memory}*2);
            next if $domain->is_base;
            next if $domain->name !~ /^99/;
            next if $domain->list_requests;

            diag("request start domain ".$domain->name);
            push @reqs,( Ravada::Request->start_domain(
                        remote_ip => '192.168.1.'.int(rand(254)+1)
                        ,id_domain => $domain->id
                        ,uid => $domain->id_owner
                        )
            );
            push @domains,($domain);
            if ( rand(10) < 2 && $vm->free_memory <= $min_memory ) {
                _shutdown_random_domain();
                _shutdown_random_domain();
                _shutdown_random_domain();
            }
        }
        _wait_requests(\@reqs);

        my $seconds = 60 - ( time - $t0 );
        $seconds = 1 if $seconds <=0 || $vm_name eq 'Void';
        diag("sleeping $seconds");
        sleep($seconds);

        for my $domain (@domains) {
            diag("request shutdown domain ".$domain->name);
            push @reqs,( Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                        ,uid => $domain->id_owner
                        )
            );
        }
        _wait_requests(\@reqs);

        for ( 1 .. 60 ) {
            my $alive = 0;
            my @reqs;
            for my $domain ( @domains ) {
                if ( $domain->is_active() && ! $domain->list_requests ) {
                    $alive++;
                    diag("request shutdown domain ".$domain->name);
                    push @reqs,(Ravada::Request->shutdown_domain(
                        id_domain => $domain->id
                            ,uid => $domain->id_owner
                        )
                    )if !$domain->list_requests;
                }
            }
            _wait_requests(\@reqs);
            last if !$alive;
            diag("$alive domains alive");
            sleep 1;
        }
    }
}

sub test_hibernate {
    my ($vm_name, $n) = @_;

    my $vm = rvd_back->search_vm($vm_name);

    my @reqs;
    my @domains;
    for my $domain ( $vm->list_domains ) {
        next if $domain->is_base;
        next if $domain->name !~ /^99/;
        next if $domain->list_requests();

        push @reqs,( Ravada::Request->start_domain(
                    remote_ip => '192.168.1.'.int(rand(254)+1)
                    ,id_domain => $domain->id
                    ,uid => $domain->id_owner
                    )
        );
        push @domains,($domain);
    }
    _wait_requests(\@reqs);

    for my $domain ( @domains ) {
        next if $domain->is_base || !$domain->is_active;
        diag("request hibernate ".$domain->name);
        push @reqs,( Ravada::Request->hybernate(
                    id_domain => $domain->id
                    ,uid => $domain->id_owner
                    )
        );
    }
    _wait_requests(\@reqs);
}

sub test_make_clones_base {
    my ($vm_name, $domain_name, $n_clones) = @_;

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = $vm->search_domain($domain_name);
    ok($domain,"[$vm_name] Expecting to find domain $domain_name") or confess;

    diag("Making base to clones from ".$domain_name);
    for my $clone ($domain->clones) {
        diag("Prepare base to $clone->{name}");
        my @reqs;
        push @reqs,(Ravada::Request->prepare_base(
                    uid => user_admin->id
                    ,id_domain => $clone->{id}
                )
        );
        test_restart($vm_name);
        test_hibernate($vm_name);
        _wait_requests(\@reqs);
        test_create_clones($vm_name, $clone->{name}, $n_clones);
    }
}

sub _wait_requests($reqs, $buggy = undef) {
    return if !$reqs || !scalar @$reqs;
    diag("Waiting for ".scalar(@$reqs)." requests");
    for ( 1 .. 1000 ) {
        last if _all_reqs_done($reqs, $buggy);
        sleep 1;
    }
    for my $r (@$reqs) {
        next if !$r || $r->status eq 'done';
        next if $r->command eq 'download';
        die ''.localtime(time)." Request not done ".Dumper($r);
        `killall -TERM rvd_back.pl`;
    }
}

sub test_iptables_jump {
    my @cmd = ('iptables','-L','INPUT');
    my ($in, $out, $err);

    run3(\@cmd, \$in, \$out, \$err);

    my $count = 0;
    for my $line ( split /\n/,$out ) {
        $count++ if $line =~ /^RAVADA /;
    }
    ok(!$count || $count == 1,"Expecting 0 or 1 RAVADA iptables jump, got: ".($count or 0))
        or exit;
}

sub _all_reqs_done($reqs, $buggy) {
    for my $cont ( 0 .. scalar @$reqs) {
        my $r = $reqs->[$cont] or next;
        next if !$r->id;
        return 0 if $r->status ne 'done';
        $reqs->[$cont] = undef;
        test_iptables_jump();
        next if $CHECKED{$r->id}++;
        if ($buggy) {
            ok(1);
            next;
        }
        next if !defined $r->error;
        ok(1) and next
            if ( $r->command eq 'remove' && $r->error =~ /already removed/)
            || ( $r->command eq 'start' && $r->error =~ /already running/)
            || ( $r->command eq 'hibernate' && $r->error =~ /not running/)
            || ( $r->command eq 'hybernate' && $r->error =~ /not running/)
            || ( $r->command eq 'clone' && $r->error =~ /already exists/)
            || ( $r->command eq 'prepare_base'
                    && $r->error =~ /already a base/)
            || ( $r->error =~ /Unknown domain/)
            || $r->error =~ /Unable to get port for domain/
            || $r->error =~ /User.*not (allowed|authorized)/i
            || $r->error =~ /Domain .* has \d+ request/
            || $r->error =~ /Bases can't .*start/i
            || $r->error =~ /^INFO:/i
            || $r->error =~ /domain with a managed saved state can't be renamed/i
            || $r->error =~ /Autostart.*on base/i
            || $r->error =~ /only \d+ found/i
            || $r->error =~ /command .* run recently/i
            || $r->error =~ /Unknown base id/i
            || $r->error =~ /CPU too loaded/i
            || $r->error =~ /I don't have the screenshot of the domain/i
            || $r->error =~ /domain .* already running/i
            || $r->error =~ /No free USB ports/i
            || $r->error =~ /User.*missing/i
            || $r->error =~ /Missing user/i
            ;
        if ($r->error =~ /free memory/i) {
            _shutdown_random_domain();
             next;
        }
        is($r->error,'',$r->id." ".$r->command." ".Dumper($r->args)) or exit;
    }
    return 1;
}

sub _shutdown_random_domain() {
    my $domains = rvd_front->list_domains(status => 'active');
    my $active = $domains->[int rand($#$domains)];
    return if !$active;
    diag("request shutdown random domain ".$active->{name});
    Ravada::Request->shutdown_domain(
                id_domain => $active->{id}
                ,uid => $active->{id_owner}
    );

}

sub _ping_backend {
    my $req = Ravada::Request->ping_backend();
    for ( 1 .. 60 ) {
        if ($req->status ne 'done' ) {
            sleep 1;
            next;
        }
        return 1 if $req->error eq '';

        diag($req->error);
    }
    return 0;
}

sub clean_clones($domain_name, $vm_name) {

    my $domain = rvd_back->search_domain($domain_name) or return;

    my $vm = rvd_back->search_vm($vm_name);

    my @reqs;
    for my $clone ($domain->clones) {
        clean_clones($clone->{name}, $vm_name);
        push @reqs,(Ravada::Request->remove_domain(
                name => $clone->{name}
                ,uid => user_admin->id
        ));
    }
    _wait_requests(\@reqs);
}

sub test_remove_base($domain_name, $vm_name) {

    my $domain = rvd_back->search_domain($domain_name) or return;
    my $vm = rvd_back->search_vm($vm_name);

    for my $clone ($domain->clones) {
        clean_clones($clone->{name}, $vm_name);
        my @reqs;
        diag("request remove base $clone->{name}");
        push @reqs,(Ravada::Request->remove_base(
                name => $clone->{name}
                ,uid => user_admin->id
        ));
        test_restart($vm_name);
        test_hibernate($vm_name);
        _wait_requests(\@reqs);
    }
}

sub clean_clone_requests {
    my $sth = rvd_back->connector->dbh->prepare(
        "DELETE FROM requests WHERE command='clone' "
        ." AND status='requested'"
    );
    $sth->execute();
    $sth->finish;
}

sub clean_leftovers($vm_name) {

    clean_clone_requests();

    my $vm = rvd_back->search_vm($vm_name);
    my @reqs;
    DOMAIN:
    for my $domain ( @{rvd_front->list_domains(vm => $vm_name)} ) {
        my ($n) = $domain->{name} =~ /^99_.*?(\d+)$/;
        next if !$n;
        $N_MIN = $n
            if $n =~ /^\d+$/ && (!$N_MIN || $n > $N_MIN);

        for my $vm_installing (keys %DOMAIN_INSTALLING) {
            next DOMAIN if $DOMAIN_INSTALLING{$vm_installing} eq $domain->{name};
        }
        clean_clones($domain->{name}, $vm);
        diag("[$vm_name] cleaning leftover $domain->{name}");
        push @reqs, (
            Ravada::Request->remove_domain(
                name => $domain->{name}
                ,uid => user_admin->id
           )
       );
    }
}

#####################################################################3

flush_rules();
my @vm_names;
for my $vm_name ( 'KVM', 'Void' ) {

    SKIP: {
        if (!$ENV{TEST_STRESS} && !$ENV{"TEST_STRESS_$vm_name"}) {
            diag("Skipped $vm_name stress test. Set environment variable TEST_STRESS or"
                        ." TEST_STRESS_$vm_name to run");
            skip("Skipping stress $vm_name",1000);
        }
        eval {
            $RVD_BACK= Ravada->new();
            init($RVD_BACK->connector,"/etc/ravada.conf");
            clean_clone_requests();
        };
        diag($@)    if $@;
        skip($@,10) if $@ || !$RVD_BACK;

        if ($vm_name eq 'KVM') {
            my $virt_install = `which virt-install`;
            chomp $virt_install;
            ok($virt_install,"Checking virt-install");
            skip("Missing virt-install",10) if ! -e $virt_install;
        }
        ok(_ping_backend(),"ERROR: backend stopped") or next;

        my $vm = $RVD_BACK->search_vm($vm_name);
        ok($vm, "Expecting VM $vm_name not found")  or next;

        clean_leftovers($vm_name);
        ok(install_base($vm_name),"[$vm_name] Expecting domain installing") or next;
        push @vm_names, ( $vm_name );
    }
}

for my $vm_name (reverse sort @vm_names) {
        diag("Testing $vm_name");
        my $domain_name = _wait_base_installed($vm_name);
        clean_clones($domain_name, $vm_name);
        test_create_clones($vm_name, $domain_name,4);
        test_requests($vm_name);
        test_random_requests($vm_name);
        test_restart($vm_name);

        my $vm = rvd_back->search_vm($vm_name);
        test_make_clones_base($vm_name, $domain_name,4);
        test_random_requests($vm_name);

}

for my $n ( 1 .. 10 ) {
    for my $vm_name (@vm_names) {
        test_requests($vm_name);
    }
    test_random_requests(\@vm_names, $n*10) if @vm_names;
    for my $vm_name (@vm_names) {
        test_restart($vm_name);
        next if $n != 1;
        my $domain_name = _wait_base_installed($vm_name);
        test_make_clones_base($vm_name, $domain_name);
    }
}
for my $vm_name (reverse sort @vm_names) {
        test_requests($vm_name);
        my $domain_name = _wait_base_installed($vm_name);
        test_remove_base($vm_name, $domain_name);
        clean_leftovers($vm_name);
}
end() if @vm_names;
done_testing();
