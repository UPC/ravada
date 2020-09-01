package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use File::Path qw(make_path remove_tree);
use YAML qw(DumpFile);
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use Mojo::File 'path';
use  Test::More;
use XML::LibXML;
use YAML qw(Load LoadFile Dump DumpFile);

use feature qw(signatures);
no warnings "experimental::signatures";

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada;
use Ravada::Auth::SQL;
use Ravada::Domain::Void;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin wait_request rvd_front init init_vm clean new_pool_name new_volume_name
create_domain
    import_domain
    test_chain_prerouting
    find_ip_rule
    search_id_iso
    flush_rules_node
    flush_rules
    arg_create_dom
    vm_names

    remote_config
    remote_config_nodes
    clean_remote_node
    arg_create_dom
    search_iptable_remote
    clean_remote
    start_node shutdown_node remove_node hibernate_node
    start_domain_internal   shutdown_domain_internal
    hibernate_domain_internal
    remote_node
    remote_node_2
    add_ubuntu_minimal_iso
    create_ldap_user
    connector
    init_ldap_config

    create_storage_pool
    local_ips

    delete_request

    remove_old_domains_req
    mojo_init
    mojo_clean
    mojo_create_domain
    mojo_login
    mojo_request

    remove_old_user

    mangle_volume
    test_volume_contents
    test_volume_format

    end
);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our $FILE_CONFIG_REMOTE = "t/etc/remote_vm.conf";

$Ravada::Front::Domain::Void = "/var/tmp/test/rvd_void/".getpwuid($>);

our ($CONNECTOR, $CONFIG , $FILE_CONFIG_TMP);
our $DEFAULT_DB_CONFIG = "t/etc/sql.conf";

our $CONT = 0;
our $CONT_POOL= 0;
our $CONT_VOL= 0;
our $USER_ADMIN;
our @USERS_LDAP;
our $CHAIN = 'RAVADA';

our $RVD_BACK;
our $RVD_FRONT;

#LDAP default values
my $ADMIN_GROUP = "test.admin.group";
my $RAVADA_POSIX_GROUP = "rvd_posix_group";
my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");

our %ARG_CREATE_DOM = (
    KVM => []
    ,Void => []
);

our %VM_VALID = ( KVM => 1
    ,Void => 0
);

our @NODES;
my $URL_LOGOUT = '/logout';

my $MOD_NBD= 0;
my $DEV_NBD = "/dev/nbd10";
my $MNT_RVD= "/mnt/test_rvd";
my $QEMU_NBD = `which qemu-nbd`;
chomp $QEMU_NBD;

my $FH_FW;
my $FH_NODE;
my %LOCKED_FH;

sub user_admin {

    return $USER_ADMIN if $USER_ADMIN;

    my $login;
    my $admin_name = base_domain_name();
    my $admin_pass = "$$ $$";
    eval {
        $login = Ravada::Auth::SQL->new(name => $admin_name, password => $admin_pass );
    };
    if ($@ && $@ =~ /Login failed/ ) {
        $login = Ravada::Auth::SQL->new(name => $admin_name);
        $login->remove();
        $login = undef;
    } elsif ($@) {
        die $@;
    }
    $USER_ADMIN = $login if $login && $login->id;
    $USER_ADMIN = create_user($admin_name, $admin_pass,1)
        if !$USER_ADMIN;

    return $USER_ADMIN;
}

sub arg_create_dom {
    my $vm_name = shift;
    confess "Unknown vm $vm_name"
        if !$ARG_CREATE_DOM{$vm_name};
    return @{$ARG_CREATE_DOM{$vm_name}};
}

sub add_ubuntu_minimal_iso {
    my $distro = 'bionic_minimal';
    my %info = ($distro => {
        name => 'Ubuntu Bionic Minimal'
        ,url => 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-i386/current/images/netboot/mini.iso'
        ,xml => 'bionic-i386.xml'
        ,xml_volume => 'bionic32-volume.xml'
        ,rename_file => 'ubuntu_bionic_mini.iso'
        ,arch => 'i386'
        ,md5 => 'c7b21dea4d2ea037c3d97d5dac19af99'
    });
    my $device = "/var/lib/libvirt/images/".$info{$distro}->{rename_file};
    if ( -e $device ) {
        $info{$distro}->{device} = $device;
    }
    $RVD_BACK->_update_table('iso_images','name',\%info);
}

sub vm_names {

   delete $ARG_CREATE_DOM{KVM} if $<;
   return (sort keys %ARG_CREATE_DOM) if wantarray;
   confess;
}

sub import_domain($vm, $name, $import_base=0) {
    my $t0 = time;
    my $domain = $RVD_BACK->import_domain(
        vm => $vm
        ,name => $name
        ,user => user_admin->name
        ,spinoff_disks => 0
        ,import_base => $import_base
    );
    return $domain;
}

sub create_domain {
    my $vm_name = shift;
    my $user = (shift or $USER_ADMIN);
    my $id_iso = (shift or 'Alpine');
    my $swap = (shift or undef);

    $vm_name = 'KVM' if $vm_name eq 'qemu';

    if ( $id_iso && $id_iso !~ /^\d+$/) {
        my $iso_name = $id_iso;
        $id_iso = search_id_iso($iso_name);
        warn "I can't find iso $iso_name" if !defined $id_iso;
    }
    my $vm;
    if (ref($vm_name)) {
        $vm = $vm_name;
        $vm_name = $vm->type;
    } else {
        $vm = rvd_back()->search_vm($vm_name);
        ok($vm,"Expecting VM $vm_name, got ".$vm->type) or return;
    }

    confess "ERROR: Domains can only be created at localhost"
        if $vm->host ne 'localhost';
    confess "Missing id_iso" if !defined $id_iso;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->import_domain($name, $user) };
    die $@ if $@ && $@ !~ /Domain.* not found/i;

    return $domain if $domain;

    my %arg_create = (id_iso => $id_iso);
    $arg_create{swap} = 1024 * 1024 if $swap;

    { $domain = $vm->create_domain(name => $name
                    , id_owner => $user->id
                    , %arg_create
                    , active => 0
                    , memory => 512*1024
                    , disk => 1024 * 1024 * 1024
           );
    };
    is('',''.$@);
    #    exit if time - $t0 > 9;

    return $domain;

}

sub base_domain_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return "tst_$name";
}

sub base_pool_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return "tst_pool_$name";
}

sub new_domain_name {
    my $post = (shift or '');
    $post = $post."_" if $post;
    my $cont = $CONT++;
    $cont = "0$cont"    if length($cont)<2;
    return base_domain_name()."_$post".$cont;
}

sub new_pool_name {
    return base_pool_name()."_".$CONT_POOL++;
}

sub new_volume_name($domain=undef) {
    my $name;
    $name = $domain->name       if $domain;
    $name = new_domain_name()   if !$domain;
    return $name."_".$CONT_VOL++;
}

sub rvd_back($config=undef, $init=1, $sqlite=1) {

    return $RVD_BACK            if $RVD_BACK && !$config;

    $RVD_BACK = 1;
    init($config or $DEFAULT_CONFIG) if $init;

    my @connector;
    @connector = ( connector => connector() ) if $sqlite;
    my $rvd = Ravada->new(
            @connector
                , config => ( $config or $DEFAULT_CONFIG)
                , warn_error => 1
    );
    $rvd->_install();
    $CONNECTOR = $rvd->connector if !$sqlite;

    user_admin();
    $RVD_BACK = $rvd;
    $ARG_CREATE_DOM{KVM} = [ id_iso => search_id_iso('Alpine') , disk => 1024 * 1024 ];
    $ARG_CREATE_DOM{Void} = [ id_iso => search_id_iso('Alpine') ];

    delete $ARG_CREATE_DOM{KVM} if $<;

    Ravada::Utils::user_daemon->_reload_grants();
    return $rvd;
}

sub rvd_front($config=undef) {

    return $RVD_FRONT if $RVD_FRONT;

    $RVD_FRONT = Ravada::Front->new(
            connector => $CONNECTOR
                , config => ( $config or $DEFAULT_CONFIG)
    );
    return $RVD_FRONT;
}

sub init($config=undef, $sqlite = 1) {

    if ($config && ! ref($config) && $config =~ /[A-Z][a-z]+$/) {
        $config = { vm => [ $config ] };
    }

    if ($config && ref($config) ) {
        $FILE_CONFIG_TMP = "/tmp/ravada_".base_domain_name()."_$$.conf";
        DumpFile($FILE_CONFIG_TMP, $config);
        $CONFIG = $FILE_CONFIG_TMP;
    } else {
        $CONFIG = $config;
    }

    if ( $RVD_BACK && ref($RVD_BACK) ) {
        clean();
        # clean removes the temporary config file, so we dump it again
        DumpFile($FILE_CONFIG_TMP, $config) if $config && ref($config);
    }


    rvd_back($config, 0,$sqlite)  if !$RVD_BACK;
    if (!$sqlite) {
        $CONNECTOR = $RVD_BACK->connector;
    } else {
        $Ravada::CONNECTOR = connector();
        Ravada::Auth::SQL::_init_connector($CONNECTOR);
    }

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;

    rvd_front($config)  if !$RVD_FRONT;
    $Ravada::VM::KVM::VERIFY_ISO = 0;
}

sub _load_remote_config() {
    return {} if ! -e $FILE_CONFIG_REMOTE;
    my $conf;
    eval { $conf = LoadFile($FILE_CONFIG_REMOTE) };
    is($@,'',"Error in $FILE_CONFIG_REMOTE\n".$@) or return;
    lock_hash(%$conf);
    return $conf;
}

sub remote_config {
    my $vm_name = shift;
    my $conf = _load_remote_config();
    my $remote_conf;
    for my $node (sort keys %$conf) {
        next if !grep /^$vm_name$/, @{$conf->{$node}->{vm}};
        $remote_conf = {
            name => $node
            ,host=> $conf->{$node}->{host}
        };
        $remote_conf->{public_ip} = $conf->{$node}->{public_ip}
            if $conf->{$node}->{public_ip};
        last;
    }
    if (! $remote_conf) {
        diag("SKIPPED: No $vm_name section in $FILE_CONFIG_REMOTE");
        return ;
    };

    ok($remote_conf->{public_ip} ne $remote_conf->{host},
            "Public IP must be different from host at $FILE_CONFIG_REMOTE")
        if defined $remote_conf->{public_ip};

    $remote_conf->{public_ip} = '' if !exists $remote_conf->{public_ip};

    lock_hash(%$remote_conf);
    return $remote_conf;
}

sub remote_config_nodes {
    my $file_config = shift;
    confess "Missing file $file_config" if !-e $file_config;

    my $conf;
    eval { $conf = LoadFile($file_config) };
    is($@,'',"Error in $file_config\n".($@ or ''))  or return;

    lock_hash((%$conf));

    for my $name (keys %$conf) {
        if ( !$conf->{$name}->{host} ) {
            warn "ERROR: Missing host section in ".Dumper($conf->{$name})
                ."at $file_config\n";
            next;
        }
    }
    return $conf;
}

sub remove_old_domains_req() {
    my $base_name = base_domain_name();
    my $machines = rvd_front->list_machines(user_admin);
    my @reqs;
    for my $machine ( @$machines) {
        my $domain;
        eval { $domain = Ravada::Front::Domain->open($machine->{id}) };
        next if $@ && $@ =~ /nknown domain/i;
        die if $@;
        next if $domain->name !~ /^$base_name/;
        my $n_clones = scalar($domain->clones);
        my $req_clone;
        for my $clone ($domain->clones) {
            $req_clone = Ravada::Request->remove_domain(
                name => $clone->{name}
                ,uid => user_admin->id
            );
        }
        wait_request(debug => 1, background => 1, check_error => 0, timeout => 60+2*$n_clones);

        my $req = Ravada::Request->remove_domain(
            name => $machine->{name}
            ,uid => user_admin->id
        );
        push @reqs,($req);
    }
    if (!@reqs) {
        push @reqs,(Ravada::Request->ping_backend);
    }
    wait_request(debug => 1, background => 1, timeout => 120, check_error => 0);
    return $reqs[-1]->status eq 'done';

}

sub _remove_old_domains_vm($vm_name) {

    confess "Undefined vm_name" if !defined $vm_name;

    my $domain;
    my $vm;

    if (ref($vm_name)) {
        $vm = $vm_name;
    } else {
        return if !$VM_VALID{$vm_name};
        eval {
        my $rvd_back=rvd_back();
        return if !$rvd_back;
        confess if $rvd_back eq 1;
        $vm = $rvd_back->search_vm($vm_name);
        };
        diag($@) if $@ && $@ !~ /Missing qemu-img/;

        if ( !$vm ) {
            $VM_VALID{$vm_name} = 0;
            return;
        }
    }
    my $base_name = base_domain_name();

    my @domains;
    eval { @domains = $vm->list_domains() };
    for my $domain ( sort { $b->name cmp $a->name }  @domains) {
        next if $domain->name !~ /^$base_name/i;

        eval { $domain->shutdown_now($USER_ADMIN); };
        warn "Error shutdown ".$domain->name." $@" if $@ && $@ !~ /No DB info/i;

        $domain = $vm->search_domain($domain->name);
        eval {$domain->remove( $USER_ADMIN ) }  if $domain;
        warn $@ if $@;
        if ( $@ && $@ =~ /No DB info/i ) {
            eval { $domain->domain->undefine() if $domain->domain };
        }

    }

    _remove_old_domains_kvm($vm)    if $vm->type =~ /qemu|kvm/i;
    _remove_old_domains_void($vm)    if $vm->type =~ /void/i;
}

sub _remove_old_domains_void {
    my $vm = shift;
    return _remove_old_domains_void_remote($vm) if !$vm->is_local;
    my $base_name = base_domain_name();

    opendir my $dir, $vm->dir_img or return;
    while ( my $file = readdir($dir) ) {
        next if $file !~ /^$base_name/;
        my $path = $vm->dir_img."/".$file;
        next if ! -f $path
            || $path !~ m{\.(yml|qcow|img)$};
        unlink $path or die "$! $path";
    }
    closedir $dir;
}

sub _remove_old_domains_void_remote($vm) {
    return if !$vm->ping(undef,0);
    eval { $vm->connect };
    warn $@ if $@;
    return if !$vm->_do_is_active;

    my $base_name = base_domain_name();
    $vm->run_command("rm -f ".$vm->dir_img."/$base_name*yml "
                    .$vm->dir_img."/$base_name*qcow "
                    .$vm->dir_img."/$base_name*img"
    );
}

sub _remove_old_domains_kvm {
    return if !$VM_VALID{'KVM'};
    my $vm = shift;

    if (!$vm) {
        eval {
            my $rvd_back = rvd_back();
            $vm = $rvd_back->search_vm('KVM');
        };
        diag($@) if $@;
        return if !$vm;
    }
    return if !$vm->vm;
    _activate_storage_pools($vm);

    my $base_name = base_domain_name();

    my @domains;
    eval { @domains = $vm->vm->list_all_domains() };
    return if $@ && $@ =~ /connect to host/;
    is($@,'') or return;

    for my $domain ( $vm->vm->list_all_domains ) {
        next if $domain->get_name !~ /^$base_name/;
        my $domain_name = $domain->get_name;
        eval { 
            $domain->shutdown();
            sleep 1 if $domain->is_active;
        };
        warn "WARNING: error $@ trying to shutdown ".$domain_name." on ".$vm->name
            if $@ && $@ !~ /error code: (42|55),/;

        eval { $domain->destroy() if $domain->is_active };
        warn $@ if $@;

        warn "WARNING: error $@ trying to shutdown ".$domain_name." on ".$vm->name
            if $@ && $@ !~ /error code: (42|55),/;

        eval {
            $domain->managed_save_remove()
                if $domain->has_managed_save_image();
        };
        warn $@ if $@ && $@ !~ /error code: 42,/;

        eval { $domain->undefine };
        warn $@ if $@ && $@ !~ /error code: 42,/;
    }
}

sub remove_old_domains {
    _remove_old_domains_vm('KVM') if !$<;
    _remove_old_domains_vm('Void');
    _remove_old_domains_kvm()   if !$<;
}

sub mojo_init() {
    my $script = path(__FILE__)->dirname->sibling('../../script/rvd_front');

    my $t = Test::Mojo->new($script);
    $t->ua->inactivity_timeout(900);
    $t->ua->connect_timeout(60);
    return $t;
}

sub mojo_clean {
    return remove_old_domains_req();
}

sub mojo_login( $t, $user, $pass ) {
    $t->ua->get($URL_LOGOUT);

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/);
    #    ->status_is(302);

    return $t->success;
}

sub mojo_create_domain($t, $vm_name) {
    my $name = new_domain_name()."-".$vm_name;
    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => search_id_iso('Alpine%')
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,submit => 1
        }
    )->status_is(302);

    wait_request(debug => 0, background => 1);
    return rvd_front->search_domain($name);

}

sub mojo_request($t, $req_name, $args) {
    $t->post_ok("/request/$req_name/" => json => $args);
    like($t->tx->res->code(),qr/^(200|302)$/);

    my $response = $t->tx->res->json();
    ok(exists $response->{request}) or return;
    wait_request(background => 1);
}

sub _activate_storage_pools($vm) {
    my @sp = $vm->vm->list_all_storage_pools();
    for my $sp (@sp) {
        next if $sp->is_active;
        diag("Activating sp ".$sp->get_name." on ".$vm->name);
        $sp->create();
    }
}
sub _remove_old_disks_kvm {
    return if !$VM_VALID{'KVM'};
    my $vm = shift;

    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

    if (!$vm) {
        my $rvd_back = rvd_back();
        $vm = $rvd_back->search_vm('KVM');
    }

    if (!$vm || !$vm->vm) {
        return;
    }
#    ok($vm,"I can't find a KVM virtual manager") or return;

    eval { $vm->_refresh_storage_pools() };
    return if $@ && $@ =~ /Cannot recv data/;

    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    my @sp = $vm->vm->list_all_storage_pools();
    for my $pool( @sp ) {
        next if !$pool->is_active;
        my @volumes;
        for ( 1 .. 10) {
            eval { @volumes = $pool->list_volumes };
            last if !$@;
            warn $@;
            sleep 1;
        }
        for my $volume  ( @volumes ) {
            next if $volume->get_name !~ /^${name}_\d+.*\.(img|raw|ro\.qcow2|qcow2|void)$/;

            eval { $volume->delete() };
            warn $@ if $@;
        }
    }
    eval {
        $vm->storage_pool->refresh();
    };
    chomp $@ if $@;
    die $@ if $@ && $@ !~ /is not active|libvirt error code: 1,/;
}
sub _remove_old_disks_void($node=undef){
    if (! defined $node || $node->is_local) {
       _remove_old_disks_void_local();
    } else {
       _remove_old_disks_void_remote($node);
    }
}

sub _remove_old_disks_void_remote($node) {
    confess "Remote node must be defined"   if !defined $node;
    return if !$node->ping(undef,0);

    my $cmd = "rm -rfv ".$node->dir_img."/".base_domain_name().'_*';
    $node->run_command($cmd);
}

sub _remove_old_disks_void_local {
    my $name = base_domain_name();

    my $dir_img =  Ravada::Front::Domain::Void::_config_dir();
    opendir my $ls,$dir_img or return;
    while (my $file = readdir $ls ) {
        next if $file !~ /^${name}_\d/;

        my $disk = "$dir_img/$file";
        next if ! -f $disk;

        unlink $disk or die "I can't remove $disk";

    }
    closedir $ls;
}

sub remove_old_disks {
    _remove_old_disks_void();
    _remove_old_disks_kvm() if !$>;
}

sub create_user {
    my ($name, $pass, $is_admin) = @_;

    Ravada::Auth::SQL::add_user(name => $name, password => $pass, is_admin => $is_admin);

    my $user;
    eval {
        $user = Ravada::Auth::SQL->new(name => $name, password => $pass);
    };
    die $@ if !$user;
    return $user;
}

sub create_ldap_user($name, $password) {

    if ( Ravada::Auth::LDAP::search_user($name) ) {
        diag("Removing $name");
        Ravada::Auth::LDAP::remove_user($name)  
    }

    my $user = Ravada::Auth::LDAP::search_user($name);
    ok(!$user,"I shouldn't find user $name in the LDAP server") or return;

    my $user_db = Ravada::Auth::SQL->new( name => $name);
    $user_db->remove();
    # check for the user in the SQL db, he shouldn't be  there
    #
    my $sth = $CONNECTOR->dbh->prepare("SELECT * FROM users WHERE name=?");
    $sth->execute($name);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    ok(!$row->{name},"I shouldn't find $name in the SQL db ".Dumper($row));

    eval { $user = Ravada::Auth::LDAP::add_user($name,$password) };
    is($@,'') or return;

    push @USERS_LDAP,($name);

    my @user = Ravada::Auth::LDAP::search_user($name);
    return $user[0];
}

sub _list_requests {
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM requests "
        ."WHERE status <> 'done'");
    $sth->execute;
    my @req;
    while (my ($id) = $sth->fetchrow) {
        push @req,($id);
    }
    return @req;
}

sub delete_request {
    confess "Error: missing request command to delete" if !@_;

    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM requests WHERE command=?");
    for my $command (@_) {
        $sth->execute($command);
    }
}

sub wait_request {
    my %args;
    if (scalar @_ % 2 == 0 ) {
        %args = @_;
        $args{background} = 0 if !exists $args{background};
    } else {
        $args{request} = [ $_[0] ];
    }
    my $timeout = delete $args{timeout};
    my $request = delete $args{request};
    if (!$request) {
        my @list_requests = map { Ravada::Request->open($_) }
            _list_requests();
        $request = \@list_requests;
    } elsif (!ref($request)) {
        $request = [$request];
    }

    my $background = delete $args{background};
    $background = 1 if !defined $background;

    $timeout = 60 if !defined $timeout && $background;
    my $debug = ( delete $args{debug} or 0 );
    my $skip = ( delete $args{skip} or ['enforce_limits','manage_pools','refresh_vms','set_time'] );
    $skip = [ $skip ] if !ref($skip);
    my %skip = map { $_ => 1 } @$skip;
    %skip = ( enforce_limits => 1 ) if !keys %skip;

    my $check_error = delete $args{check_error};
    $check_error = 1 if !defined $check_error;

    die "Error: uknown args ".Dumper(\%args) if keys %args;
    my $t0 = time;
    my %done;
    for ( ;; ) {
        my $done_all = 1;
        my $prev = join(".",_list_requests);
        my $done_count = scalar keys %done;
        $prev = '' if !defined $prev;
        my @req = _list_requests();
        rvd_back->_process_requests_dont_fork($debug) if !$background;
        for my $req_id ( @req ) {
            my $req;
            eval { $req = Ravada::Request->open($req_id) };
            next if $@ && $@ =~ /I can't find id=$req_id/;
            die $@ if $@;
            next if $skip{$req->command};
            if ( $req->status ne 'done' ) {
                diag("Waiting for request ".$req->id." ".$req->command." ".$req->status
                    ." ".($req->error or '')) if $debug && (time%5 == 0);
                $done_all = 0;
            } elsif (!$done{$req->id}) {
                $t0 = time;
                $done{$req->{id}}++;
                if ($check_error) {
                    if ($req->command eq 'remove') {
                        like($req->error,qr(^$|Unknown domain));
                    } elsif($req->command eq 'set_time') {
                        like($req->error,qr(^$|libvirt error code));
                    } else {
                        is($req->error,'') or confess $req->command;
                    }
                }
            }
        }
        my $post = join(".",_list_requests);
        $post = '' if !defined $post;
        if ( $done_all ) {
            for my $req (@$request) {
                $req = Ravada::Request->open($req) if !ref($req);
                next if $skip{$req->command};
                if ($req->status ne 'done') {
                    $done_all = 0;
                    diag("Waiting for request ".$req->id." ".$req->command);
                    last;
                }
            }
        }
        return if $done_all && $prev eq $post && scalar(keys %done) == $done_count;;
        return if defined $timeout && time - $t0 >= $timeout;
        sleep 1 if $background;
    }
}

sub init_vm {
    my $vm = shift;
    return if $vm->type =~ /void/i;
    _init_vm_kvm($vm)   if $vm->type eq 'KVM';
}

sub _init_vm_kvm($vm) {
    _qemu_storage_pool($vm) if $>;
    _remove_old_disks_kvm($vm);
}

sub _exists_storage_pool {
    my ($vm, $pool_name) = @_;
    my @sp = Ravada::VM::_list_storage_pools($vm->vm);
    for my $pool ( @sp ) {
        return 1 if $pool->get_name eq $pool_name;
    }
    return;
}

sub _qemu_storage_pool {
    my $vm = shift;

    my $pool_name = new_pool_name();

    if (! _exists_storage_pool($vm, $pool_name)) {

        my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c260942');

        my $dir = "/var/tmp/$pool_name";
        mkdir $dir if ! -e $dir;

        my $xml =
        "<pool type='dir'>
        <name>$pool_name</name>
        <uuid>$uuid</uuid>
        <capacity unit='bytes'></capacity>
        <allocation unit='bytes'></allocation>
        <available unit='bytes'></available>
        <source>
        </source>
        <target>
        <path>$dir</path>
        <permissions>
        <mode>0711</mode>
        <owner>0</owner>
        <group>0</group>
        </permissions>
        </target>
        </pool>"
        ;
        my $pool;
        eval { $pool = $vm->vm->create_storage_pool($xml) };
        ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
        ok($pool,"Expecting a pool , got ".($pool or ''));
    }

    $vm->default_storage_pool_name($pool_name);

    return $pool_name;
}

sub remove_qemu_pools {
    return if !$VM_VALID{'KVM'} || $>;
    my $vm;
    eval { $vm = rvd_back->search_vm('KVM') };
    if ($@ && $@ !~ /Missing qemu-img/) {
        warn $@;
    }
    if  ( !$vm ) {
        $VM_VALID{'KVM'} = 0;
        return;
    }

    my $base = base_pool_name();
    for my $pool  ( Ravada::VM::KVM::_list_storage_pools($vm->vm)) {
        my $name = $pool->get_name;
        next if $name !~ qr/^$base/;
        diag("Removing ".$pool->get_name." storage_pool");
        _delete_qemu_pool($pool);
        for my $vol ( $pool->list_volumes ) {
            diag("Removing ".$pool->get_name." vol ".$vol->get_name);
            $vol->delete();
        }
        $pool->destroy();
        eval { $pool->undefine() };
        warn $@ if$@ && $@ !~ /libvirt error code: 49,/;
        ok(!$@ or $@ =~ /Storage pool not found/i);
    }

    opendir my $ls ,"/var/tmp" or die $!;
    while (my $file = readdir($ls)) {
        next if $file !~ qr/^$base/;

        my $dir = "/var/tmp/$file";
        remove_tree($dir,{ safe => 1, verbose => 1}) or die "$! $dir";
    }
}

sub _delete_qemu_pool($pool) {
    my $xml = XML::LibXML->load_xml(string => $pool->get_xml_description());
    my ($path) = $xml->findnodes('/pool/target/path');
    my $dir = $path->textContent();
    rmdir($dir) or die "$! $dir";

}

sub remove_old_pools {
    remove_qemu_pools();
}

sub clean {
    my $file_remote_config = shift;
    remove_old_domains();
    remove_old_disks();
    remove_old_pools();


    if ($file_remote_config) {
        my $config;
        eval { $config = LoadFile($file_remote_config) };
        warn $@ if $@;
        _clean_remote_nodes($config)    if $config;
    }
    unlink $FILE_CONFIG_TMP or die "$! $FILE_CONFIG_TMP"
        if $FILE_CONFIG_TMP && -e $FILE_CONFIG_TMP;
    _clean_db();
    _clean_file_config();
    shutdown_nodes();
}

sub _clean_db {
    my $connector = connector();
    return if $connector->{driver} =~ /mysql/i;

    my $sth = $connector->dbh->prepare(
        "DELETE FROM vms "
    );
    $sth->execute;
    $sth->finish;

    $sth = $connector->dbh->prepare(
        "DELETE FROM domains"
    );
    $sth->execute;
    $sth->finish;

}

sub clean_remote {
    my $config = _load_remote_config() or return;
    return _clean_remote_nodes($config);
}

sub _clean_remote_nodes {
    my $config = shift;
    for my $name (keys %$config) {
        my @vms = @{$config->{$name}->{vm}};
        die "Error: $name has no vms ".Dumper($config->{$name})
            if !scalar @vms;
        delete $config->{$name}->{vm};
        $config->{$name}->{name} = $name;
        for my $type (@vms) {
            diag("Cleaning $name $type");
            my $node;
            my $vm = rvd_back->search_vm($type);
            eval { $node = $vm->new($config->{$name}) };
            warn $@ if $@;

            start_node($node);
            clean_remote_node($node);
            $node->remove();
        }
    }
}

sub clean_remote_node {
    my $node = shift;

    _remove_old_domains_vm($node);
    wait_request(debug => 0);
    _remove_old_disks($node);
    flush_rules_node($node)  if !$node->is_local() && $node->is_active;
}

sub _remove_old_disks {
    my $node = shift;
    if ( $node->type eq 'KVM' ) {
        _remove_old_disks_kvm($node);
    }elsif ($node->type eq 'Void') {
        _remove_old_disks_void($node);
    }   else {
        die "I don't know how to remove ".$node->type." disks";
    }
}

sub remove_old_user($user_name=undef) {

    if (!$user_name) {
        if ($USER_ADMIN) {
            $user_name = $USER_ADMIN->name;
            $USER_ADMIN->remove;
        }
    }
    return if !$user_name;

    my $user = Ravada::Auth::SQL->new(name => $user_name);
    $user->remove if $user;

    confess "Undefined connector" if !defined $CONNECTOR;
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM users WHERE name = ?");
    $sth->execute($user_name);
}

sub remove_old_user_ldap {
    for my $name (@USERS_LDAP ) {
        if ( Ravada::Auth::LDAP::search_user($name) ) {
            Ravada::Auth::LDAP::remove_user($name)  
        }
    }
}

sub search_id_iso {
    my $name = shift;
    connector() if !$CONNECTOR;
    rvd_back();
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name like ?"
    );
    $sth->execute("$name%");
    my ($id) = $sth->fetchrow;
    die "There is no iso called $name%" if !$id;
    return $id;
}

sub _search_cd {
    my $name = shift;
    connector() if !$CONNECTOR;
    rvd_back();
    my $sth = $CONNECTOR->dbh->prepare("SELECT device FROM iso_images "
        ." WHERE name like ?"
    );
    $sth->execute("$name%");
    my ($cd) = $sth->fetchrow;
    die "There is no CD in iso called $name%" if !$cd;
    return $cd;
}


sub search_iptable_remote {
    my %args = @_;
    my $node = delete $args{node};
    my $remote_ip = delete $args{remote_ip};
    my $local_ip = delete $args{local_ip};
    my $local_port= delete $args{local_port};
    my $jump = (delete $args{jump} or 'ACCEPT');
    my $table = (delete $args{table} or 'filter');
    my $chain = (delete $args{chain} or $CHAIN);
    my $to_dest = delete $args{'to-destination'};

    confess "Error: unknown args ".Dumper(\%args) if keys %args;

    my $iptables = $node->iptables_list();

    $remote_ip .= "/32" if defined $remote_ip && $remote_ip !~ m{/};
    $local_ip .= "/32"  if defined $local_ip && $local_ip !~ m{/};

    my @found;

    my $count = 0;
    for my $line (@{$iptables->{$table}}) {
        my %args = @$line;
        next if $args{A} ne $chain;
        $count++;
        $args{s} = "0.0.0.0/0" if !exists $args{s} && exists $args{dport};

        if(
              (!defined $jump      || exists $args{j} && $args{j} eq $jump )
           && (!defined $remote_ip || exists $args{s} && $args{s} eq $remote_ip )
           && (!defined $local_ip  || exists $args{d} && $args{d} eq $local_ip )
           && (!defined $local_port|| exists $args{dport} && $args{dport} eq $local_port)
           && (!defined $to_dest   || exists $args{'to-destination'}
                && $args{'to-destination'} eq $to_dest)
        ){

            push @found,($count);
        }
    }
    return @found   if wantarray;
    return if !scalar@found;
    return $found[0];
}

sub _lock_fh($fh) {
    flock($fh, LOCK_EX);
    seek($fh, 0, SEEK_END) or die "Cannot seek - $!\n";
    print $fh,$$." ".localtime(time)." $0\n";
    $fh->flush();
    $LOCKED_FH{$fh} = $fh;
}

sub _unlock_fh($fh) {
    flock($fh,LOCK_UN) or die "Cannot unlock - $!\n";
    close $fh;
}

sub _lock_fw {
    return if $FH_FW;
    open $FH_FW,">>","/var/tmp/fw.lock" or die "$!";
    _lock_fh($FH_FW);
}

sub _lock_node {
    return if $FH_NODE;
    open $FH_NODE,">>","/var/tmp/node.lock" or die "$!";
    _lock_fh($FH_NODE);
}


sub _unlock_all {
    for my $key (keys %LOCKED_FH) {
        _unlock_fh($LOCKED_FH{$key});
        delete $LOCKED_FH{$key};
    }
}

sub flush_rules_node($node) {
    _lock_fw();
    $node->create_iptables_chain($CHAIN);
    my ($out, $err) = $node->run_command("iptables","-F", $CHAIN);
    is($err,'');
    ($out, $err) = $node->run_command("iptables","-D","INPUT","-j",$CHAIN);
    is($err,'');
    ($out, $err) = $node->run_command("iptables","-X", $CHAIN);
    is($err,'') or die `iptables-save`;

    # flush forward too. this is only supposed to run on test servers
    ($out, $err) = $node->run_command("iptables","-F", 'FORWARD');
    is($err,'');
}

sub flush_rules {
    return if $>;

    _lock_fw();
    my @cmd = ('iptables','-t','nat','-F','PREROUTING');
    my ($in,$out,$err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    @cmd = ('iptables','-L','INPUT');
    run3(\@cmd, \$in, \$out, \$err);
    is($err,'');

    my $count = -2;
    my @found;
    for my $line ( split /\n/,$out ) {
        $count++;
        next if $line !~ /^RAVADA /;
        push @found,($count);
    }
    @cmd = ('iptables','-D','INPUT');
    for my $n (reverse @found) {
        run3([@cmd, $n], \$in, \$out, \$err);
        warn $err if $err;
    }
    run3(["iptables","-F", $CHAIN], \$in, \$out, \$err);
    like($err,qr(^$|chain/target/match by that name));
    ($out, $err) = run3(["iptables","-D","INPUT","-j",$CHAIN],\$in, \$out, \$err);
    like($err,qr(^$|chain/target/match by that name));
    run3(["iptables","-X", $CHAIN], \$in, \$out, \$err);
    like($err,qr(^$|chain/target/match by that name));

    # flush forward too. this is only supposed to run on test servers
    run3(["iptables","-F","FORWARD" ], \$in, \$out, \$err);
    is($err,'');

}

sub _domain_node($node) {
    my $vm = rvd_back->search_vm('KVM','localhost');
    ok($vm) or die Dumper(rvd_back->_create_vm);
    my $domain = $vm->search_domain($node->name, 1);
    $domain = rvd_back->import_domain(name => $node->name
            ,user => user_admin->name
            ,vm => 'KVM'
            ,spinoff_disks => 0
    )   if !$domain || !$domain->is_known;

    ok($domain->id,"Expecting an ID for domain ") or exit;
    $domain->_set_vm($vm, 'force');
    return $domain;
}

sub hibernate_node($node) {
    if ($node->is_active) {
        for my $domain ($node->list_domains()) {
            $domain->shutdown_now(user_admin);
        }
    }

    for (;;) {
        $node->disconnect;
        my $domain_node = _domain_node($node);
        eval { $domain_node->hibernate( user_admin ) };
        my $error = $@;
        warn $error if $error;
        last if !$error || $error =~ /is not active/;
    }

    my $max_wait = 30;
    my $ping;
    for ( 1 .. $max_wait ) {
        diag("Waiting for node ".$node->name." to be inactive ...")  if !($_ % 10);
        $ping = $node->ping(undef, 0);
        last if !$ping;
        sleep 1;
    }
    is($ping,0, "Expecting node ".$node->name." hibernated not pingable");
}

sub shutdown_node($node) {

    if ($node->_do_is_active(1)) {
        eval {
		$node->run_command("service lightdm stop");
        $node->run_command("service gdm stop");
	};
	confess $@ if $@ && $@ !~ /ssh error|error connecting|control command failed/i;
        for my $domain ($node->list_domains()) {
            diag("Shutting down ".$domain->name." on node ".$node->name);
            $domain->shutdown_now(user_admin);
        }
    }
    $node->disconnect;
    my $domain_node = _domain_node($node);
    eval {
        $domain_node->shutdown(user => user_admin);# if !$domain_node->is_active;
    };
    sleep 2 if !$node->ping(undef, 0);

    my $max_wait = 180;
    for ( reverse 1 .. $max_wait ) {
        last if !$node->ping(undef, 0);
        if ( !($_ % 10) ) {
            eval { $domain_node->shutdown(user => user_admin) };
            warn $@ if $@;
            diag("Waiting for node ".$node->name." to be inactive ... $_");
        }
        sleep 1;
    }
    $domain_node->shutdown_now(user_admin) if $domain_node->is_active;
    is($node->ping(undef,0),0);
}

sub start_node($node) {

    confess "Undefined node"    if !defined $node;
    confess "Undefined node " if!$node;

    $node->disconnect;
    $node->clear_netssh();
    if ( $node->_do_is_active(1) ) {
        my $connect;
        eval { $connect = $node->connect };
        return if $connect;
        warn "I can't connect";
    }

    my $domain = _domain_node($node);

    ok($domain->_vm->host eq 'localhost');

    $domain->start(user => user_admin, remote_ip => '127.0.0.1')  if !$domain->is_active;

    for ( 1 .. 60 ) {
        last if $node->ping(undef,0); # no cache
        sleep 1;
        diag("Waiting for ping node ".$node->name." ".$node->ip." $_");#  if !($_ % 10);
    }

    is($node->ping('debug',0),1,"[".$node->type."] Expecting ping node ".$node->name) or exit;

    for my $try ( 1 .. 3) {
        my $is_active;
        for ( 1 .. 60 ) {
            eval {
                $node->disconnect;
                $node->clear_netssh();
                $node->connect();
                $is_active = $node->is_active(1)
            };
            warn $@ if $@;
            last if $is_active;
            sleep 1;
            diag("Waiting for active node ".$node->name." $_") if !($_ % 10);
        }
        last if $is_active;
        if ($try == 1 ) {
            $domain->shutdown(user => user_admin);
            sleep 2;
        } elsif ( $try == 2 ) {
            $domain->shutdown_now(user_admin);
            sleep 2;
        }
        $domain->start(user => user_admin, remote_ip => '127.0.0.1');
    }
    is($node->_do_is_active,1,"Expecting active node ".$node->name) or exit;

    my $connect;
    for ( 1 .. 20 ) {
        eval { $connect = $node->connect };
        warn $@ if $@;
        last if $connect;
        sleep 1;
        diag("Waiting for connection to node ".$node->type." "
            .$node->name." $_") if !($_ % 5);
    }
    is($connect,1
            ,"[".$node->type."] "
                .$node->name." Expecting connection") or exit;
    for ( 1 .. 60 ) {
        $domain = _domain_node($node);
        last if $domain->ip;
        sleep 1;
        diag("Waiting for domain from node ".$node->type." "
            .$node->name." $_") if !($_ % 5);
    }
    ok($domain->ip,"Make sure the virtual machine ".$domain->name." has installed the qemu-guest-agent") or exit;

    $node->is_active(1);
    $node->enabled(1);
    for ( reverse 1 .. 120 ) {
        my $node2 = Ravada::VM->open(id => $node->id);
        last if $node2->is_active(1) && $node->ssh;
        diag("Waiting for node ".$node2->name." active ... $_")  if !($_ % 10);
        $node2->disconnect();
        $node2->connect();
        $node2->clear_netssh();
        sleep 1;
    }
    eval { $node->run_command("hwclock","--hctosys") };
    is($@,'',"Expecting no error setting clock on ".$node->name." ".($@ or ''));
}

sub remove_node($node) {
    eval { $node->remove() };
    is(''.$@,'');

    my $node2;
    eval { $node2 = Ravada::VM->open($node->id) };
    like($@,qr"can't find VM");
    ok(!$node2, "Expecting no node ".$node->id);
}

sub hibernate_domain_internal($domain) {
    start_domain_internal($domain)  if !$domain->is_active;
    if ($domain->type eq 'KVM') {
        $domain->domain->managed_save();
    } elsif ($domain->type eq 'Void') {
        $domain->_store(is_hibernated => 1 );
    } else {
        confess "ERROR: I don't know how to hibernate internal domain of type ".$domain->type;
    }
}

sub _iptables_list {
    my ($in, $out, $err);
    run3(['iptables-save'], \$in, \$out, \$err);
    my ( %tables, $ret );

    my ($current_table);
    for my $line (split /\n/, $out) {
        chomp $line;

        next if ( $line eq "COMMIT" );
        next if ( $line =~ m/^#/ );
        next if ( $line =~ m/^:/ );

        if ( $line =~ m/^\*([a-z]+)$/ ) {
            $current_table = $1;
            $tables{$current_table} = [];
            next;
        }

        #my @parts = grep { ! /^\s+$/ && ! /^$/ } split (/(\-\-?[^\s]+\s[^\s]+)/i, $line);
        my @parts = grep { !/^\s+$/ && !/^$/ } split( /^\-\-?|\s+\-\-?/i, $line );

        my @option = ();
        for my $part (@parts) {
            my ( $key, $value ) = split( /\s/, $part, 2 );
            push( @option, $key => $value );
        }

        push( @{ $ret->{$current_table} }, \@option );

    }

    return $ret;
}

sub find_ip_rule {
    my %args = @_;
    my $remote_ip = delete $args{remote_ip};
    my $local_ip = delete $args{local_ip};
    my $local_port= delete $args{local_port};
    my $jump = ( delete $args{jump} or 'ACCEPT');

    die "ERROR: Unknown args ".Dumper(\%args)  if keys %args;

    my $iptables = _iptables_list();
    $remote_ip .= "/32" if defined $remote_ip && $remote_ip !~ m{/};
    $local_ip .= "/32"  if defined $local_ip && $local_ip !~ m{/};

    my @found;

    my $count = 0;
    for my $line (@{$iptables->{filter}}) {
        my %line= @$line;
        next if $line{A} ne $CHAIN;
        $line{s} = '0.0.0.0/0'  if !exists $line{s} && $line{p} =~ m/.cp$/;
        $count++;
        if((!defined $jump || ( exists $line{j} && $line{j} eq $jump ))
           && ( !defined $remote_ip || (exists $line{s} && $line{s} eq $remote_ip ))
           && ( !defined $local_ip || ( exists $line{d} && $line{d} eq $local_ip ))
           && ( !defined $local_port || ( exists $line{dport} && $line{dport} eq $local_port)))
        {

            push @found,($count);
        }
    }
    return if !scalar@found || !defined $found[0];
    return @found   if wantarray;
    return $found[0];
}

sub local_ips($vm) {
    my ($out, $err) = $vm->run_command("/bin/ip","address");
    confess $err if $err;
    my @ips = map { m{^\s+inet (.*?)/};$1 }
                grep { m{^\s+inet } }
                split /\n/,$out;
    return @ips;
}

sub shutdown_domain_internal($domain) {
    if ($domain->type eq 'KVM') {
        $domain->domain->destroy();
    } elsif ($domain->type eq 'Void') {
        $domain->_store(is_active => 0 );
    } else {
        confess "ERROR: I don't know how to shutdown internal domain of type ".$domain->type;
    }
}

sub start_domain_internal($domain) {
    if ($domain->type eq 'KVM') {
        $domain->_set_spice_ip(1,$domain->_vm->ip);
        $domain->domain->create();
    } elsif ($domain->type eq 'Void') {
        $domain->_store(is_active => 1 );
    } else {
        confess "ERROR: I don't know how to shutdown internal domain of type ".$domain->type;
    }
}

sub _clean_file_config {
    if ( $FILE_CONFIG_TMP && -e $FILE_CONFIG_TMP ) {
        unlink $FILE_CONFIG_TMP or warn "$! $FILE_CONFIG_TMP";
        $CONFIG = $DEFAULT_CONFIG;
    }
}

sub remote_node($vm_name) {
    _lock_node();
    my $remote_config = remote_config($vm_name);
    SKIP: {
        if (!keys %$remote_config) {
            my $msg = "skipped, missing the remote configuration for $vm_name in the file "
            .$Test::Ravada::FILE_CONFIG_REMOTE;
            diag($msg);
            skip($msg,10);
        }
        return _do_remote_node($vm_name, $remote_config);
    }
}

sub remote_node_2($vm_name) {
    _lock_node();
    my $remote_config = _load_remote_config();

    my @nodes;
    for my $name ( sort keys %$remote_config ) {
        if ( !grep /^$vm_name$/, @{ $remote_config->{$name}->{vm}} ) {
            warn "Remote test node $name doesn't support $vm_name "
                .Dumper($remote_config->{$name});
            next;
        }
        my %config = %{$remote_config->{$name}};
        $config{name} = $name;
        delete $config{vm};
        push @nodes,(_do_remote_node($vm_name, \%config));
    }
    return @nodes;
}

sub _do_remote_node($vm_name, $remote_config) {
    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    my @list_nodes0 = rvd_front->list_vms;

    if (! $remote_config->{public_ip}) {
        unlock_hash(%$remote_config);
        delete $remote_config->{public_ip};
        lock_hash(%$remote_config);
    }
    eval { $node = $vm->new(%{$remote_config}) };
    ok(!$@,"Expecting no error connecting to $vm_name at ".Dumper($remote_config
        ).", got :'"
        .($@ or '')."'") or return;
    push @NODES,($node) if !grep { $_->name eq $node->name } @NODES;
    ok($node) or return;

    is($node->type,$vm->type) or return;

    is($node->host,$remote_config->{host});
    is($node->name,$remote_config->{name}) or return;

    eval { $node->ping };
    is($@,'',"[$vm_name] ping ".$node->name);

    if ( $node->ping(undef,0) && !$node->_connect_ssh() ) {
        my $ssh;
        for ( 1 .. 60 ) {
            eval { $ssh = $node->_connect_ssh() };
            last if $ssh;
            sleep 1;
            warn $@ if $@;
            next if !$ssh;
            diag("I can ping node ".$node->name." but I can't connect to ssh");
        }
        if (! $ssh ) {
            shutdown_node($node);
        }
    }
    start_node($node)   if !$node->is_active();

    clean_remote_node($node);

    eval { $node->vm };
    is($@,'')   or return;
    ok($node->id) or return;
    is($node->is_active,1) or return;

    ok(!$node->is_local,"[$vm_name] node remote");

    return $node;
}

sub _dir_db {
    my $dir_db = "/run/ravada/$>/db";
    if (! -e $dir_db ) {
        eval {
            make_path $dir_db
        };
        die $@ if $@ && $@ !~ /Permission denied/;
        if ($@) {
                warn "$! on mkdir $dir_db";
                $dir_db = "t/.db";
                make_path $dir_db or die "$! $dir_db";
        }
    }
    return $dir_db;
}

sub _file_db {
    my $file_db = shift;
    my $dir_db = _dir_db();

    if (! $file_db ) {
        $file_db = $0;
        $file_db =~ s{t/}{};
        $file_db =~ tr{/}{_};
        $file_db =~ s{(.*)\.\w+$}{$dir_db/$1\.db};
    }
    if ( -e $file_db ) {
        unlink $file_db or die("$! $file_db");
    }
    return $file_db;
}

sub _execute_sql($connector, $sql) {
    eval { $connector->dbh->do($sql) };
    warn $sql   if $@;
    confess "FAILED SQL:\n$@" if $@;
}
sub _load_sql_file {
    my $connector = shift;
    my $file_sql = shift;

    open my $h_sql,'<',$file_sql or die "$! $file_sql";
    my $sql = '';
    while (my $line = <$h_sql>) {
        $sql .= $line;
        if ($line =~ m{;$}) {
            warn "_load_sql_file: $sql" if $ENV{DEBUG};
            _execute_sql($connector,$sql);
            $sql = '';
        }
    }
    close $h_sql;

}

sub _create_db_tables($connector, $file_config = $DEFAULT_DB_CONFIG ) {
    my $config = LoadFile($file_config);
    my $sql = $config->{sql};

    for my $file ( @$sql ) {
        _load_sql_file($connector,"t/etc/$file");
    }
}

sub connector {
    return $CONNECTOR if $CONNECTOR;

    my $file_db = _file_db();
    my $connector = DBIx::Connector->new("DBI:SQLite:".$file_db
                ,undef,undef
                ,{sqlite_allow_multiple_statements=> 1 
                        , AutoCommit => 1
                        , RaiseError => 1
                        , PrintError => 1
                });

    _create_db_tables($connector);

    $CONNECTOR = $connector;
    return $connector;
}

# this must be in DESTROY because users got removed in END
sub DESTROY {
    shutdown_nodes();
    remove_old_user_ldap() if $CONNECTOR;
    _unlock_all();
}

sub end {
    clean();
    _unlock_all();
    _file_db();
    rmdir _dir_db();
}

sub init_ldap_config($file_config='t/etc/ravada_ldap.conf'
                    , $with_admin=0
                    , $with_posix_group=0) {

    if ( ! -e $file_config) {
        my $config = {
        ldap => {
            admin_user => { dn => $LDAP_USER , password => $LDAP_PASS }
            ,base => "dc=example,dc=com"
            ,admin_group => $ADMIN_GROUP
            ,auth => 'match'
            ,ravada_posix_group => $RAVADA_POSIX_GROUP
        }
        };
        DumpFile($file_config,$config);
    }
    my $config = LoadFile($file_config);
    delete $config->{ldap}->{admin_group}   if !$with_admin;
    if ($with_posix_group) {
        if ( !exists $config->{ldap}->{ravada_posix_group}
                || !$config->{ldap}->{ravada_posix_group}) {
            $config->{ldap}->{ravada_posix_group} = $RAVADA_POSIX_GROUP;
            diag("Adding ravada_posix_group = $RAVADA_POSIX_GROUP in $file_config");
        }
    } else {
        delete $config->{ldap}->{ravada_posix_group};
    }

    $config->{vm}=['KVM','Void'];
    delete $config->{ldap}->{ravada_posix_group}   if !$with_posix_group;

    my $fly_config = "/var/tmp/ravada_".base_domain_name().".conf";
    DumpFile($fly_config, $config);

    $RVD_BACK = undef;
    $RVD_FRONT = undef;

    init($fly_config);
    return $fly_config;
}

sub shutdown_nodes {
    for my $node (@NODES) {
        shutdown_node($node);
    }
}

sub create_storage_pool($vm) {
    if (!ref($vm)) {
        $vm = rvd_back->search_vm($vm);
    }
    my $uuid = Ravada::VM::KVM::_new_uuid('68663afc-aaf4-4f1f-9fff-93684c2609'
        .int(rand(10)).int(rand(10)));

    my $capacity = 1 * 1024 * 1024;

    my $pool_name = new_pool_name();
    my $dir = "/var/tmp/$pool_name";

    mkdir $dir if ! -e $dir;

    my $xml =
"<pool type='dir'>
  <name>$pool_name</name>
  <uuid>$uuid</uuid>
  <capacity unit='bytes'>$capacity</capacity>
  <allocation unit='bytes'></allocation>
  <available unit='bytes'>$capacity</available>
  <source>
  </source>
  <target>
    <path>$dir</path>
    <permissions>
      <mode>0711</mode>
      <owner>0</owner>
      <group>0</group>
    </permissions>
  </target>
</pool>"
;
    my $pool;
    eval { $pool = $vm->vm->create_storage_pool($xml) };
    ok(!$@,"Expecting \$@='', got '".($@ or '')."'") or return;
    ok($pool,"Expecting a pool , got ".($pool or ''));

    return $pool_name;

}

sub mangle_volume($vm,$name,@vol) {
    for my $file (@vol) {

        if ($file =~ /\.void$/) {
            my $data = Load($vm->read_file($file));
            $data->{$name} = "c" x 20;
            $vm->write_file($file, Dump($data));

        } elsif ($file =~ /\.qcow2$/) {
            _mount_qcow($vm, $file);
            open my $out,">","/mnt/test_rvd/$name";
            print $out ("c" x 20)."\n";
            close $out;
            _umount_qcow();
        } elsif ($file =~ /\.iso$/) {
            # do nothing
        } else {
            confess "Error: I don't know how to mangle volume $file";
        }
    }
}

sub _mount_qcow($vm, $vol) {
    my ($in,$out, $err);
    if (!$MOD_NBD++) {
        my @cmd =("/sbin/modprobe","nbd", "max_part=63");
        run3(\@cmd, \$in, \$out, \$err);
        die join(" ",@cmd)." : $? $err" if $?;
    }
    my @cmd = ($QEMU_NBD,"-d", $DEV_NBD);
    ($out,$err) = $vm->run_command(@cmd);
    die "@cmd : $err" if $err;
    for ( 1 .. 10 ) {
        ($out, $err) = $vm->run_command($QEMU_NBD,"-c",$DEV_NBD, $vol);
        last if !$err;
        diag("$_: $out\n$err");
        sleep 1;
    }
    confess "qemu-nbd -c $DEV_NBD $vol\n?:$?\n$out\n$err" if $? || $err;
    _create_part($DEV_NBD);
    ($out, $err) = $vm->run_command("/sbin/mkfs.ext4","${DEV_NBD}p1");
    die "Error on mkfs $err" if $?;
    mkdir "$MNT_RVD" if ! -e $MNT_RVD;
    $vm->run_command("/bin/mount","${DEV_NBD}p1",$MNT_RVD);
    exit if $?;
}

sub _create_part($dev) {
    my @cmd = ("/sbin/fdisk","-l",$dev);
    my ($in,$out, $err);
    for my $retry ( 1 .. 10 ) {
        run3(\@cmd, \$in, \$out, \$err);
        last if !$err && $err =~ /(Input\/output error|Unexpected end-of-file)/i;
        warn $err if $err && $retry>2;
        sleep 1;
    }
    confess join(" ",@cmd)."\n$?\n$out\n$err\n" if $err || $?;

    return if $out =~ m{/dev/\w+\d+p\d+}mi;

    for (1 .. 10) {
        @cmd = ("/sbin/fdisk",$dev);
        $in = "n\np\n1\n\n\n\nw\np\n";

        run3(\@cmd, \$in, \$out, \$err);
        chomp $err;
        last if !$err || $err !~ /evice.*busy/;
        diag($err." retrying");
        sleep 1;
    }
    ok(!$err) or die join(" ",@cmd)."\n$?\nIN: $in\nOUT:\n$out\nERR:\n$err";
}
sub _umount_qcow() {
    mkdir $MNT_RVD if ! -e $MNT_RVD;
    my @cmd = ("umount",$MNT_RVD);
    my ($in, $out, $err);
    for ( ;; ) {
        run3(\@cmd, \$in, \$out, \$err);
        last if $err !~ /busy/i || $err =~ /not mounted/;
        sleep 1;
    }
    die $err if $err && $err !~ /busy/ && $err !~ /not mounted/;
    `qemu-nbd -d $DEV_NBD`;
}

sub _mangle_vol2($vm,$name,@vol) {
    for my $file (@vol) {

        if ($file =~ /\.void$/) {
            my $data = Load($vm->read_file($file));
            $data->{$name} = "c" x 20;
            $vm->write_file($file, Dump($data));

        } elsif ($file =~ /\.qcow2$/) {
            _mount_qcow($vm, $file);
            open my $out,">","/mnt/test_rvd/$name";
            print $out ("c" x 20)."\n";
            close $out;
            _umount_qcow();
        }
    }
}


sub _test_file_exists($vm, $vol, $name, $expected=1) {
    _mount_qcow($vm,$vol);
    my $ok = -e $MNT_RVD."/".$name;
    _umount_qcow();
    return 1 if $ok && $expected;
    return 1 if !$ok && !$expected;
    return 0;
}

sub _test_file_not_exists($vm, $vol) {
    return test_file_exists($vm,$vol, 0);
}

sub test_volume_contents($vm, $name, $file, $expected=1) {
    if ($file =~ /\.void$/) {
        my $data = LoadFile($file);
        if ($expected) {
            ok(exists $data->{$name}, "Expecting $name in ".Dumper($file,$data)) or confess;
        } else {
            ok(!exists $data->{$name}, "Expecting no $name in ".Dumper($file,$data)) or confess;
        }
    } elsif ($file =~ /\.qcow2$/) {
            _test_file_exists($vm, $file, $name, $expected);
    } elsif ($file =~ /\.iso$/) {
        my $file_type = `file $file`;
        chomp $file_type;
        if ($file_type =~ /ASCII/) {
            my $data = LoadFile($file);
            ok($data->{iso},Dumper($file,$data)) or confess;
        } else {
            like($file_type , qr/DOS\/MBR/);
        }
    } else {
        confess "I don't know how to check vol contents of '$file'";
    }
}

sub _check_file($volume,$expected) {
    my ($in, $out, $err);
    run3(['file',$volume->file],\$in, \$out, \$err);
    like($out,$expected) or confess;
}

sub _check_yaml($filename) {
    _check_file($filename,qr(: ASCII text));
}

sub _check_qcow2($filename) {
    _check_file($filename,qr(: QEMU QCOW2));
}

sub test_volume_format(@volume) {
    for my $volume (@volume) {
        next if !$volume->file;
        my ($extension) = $volume->file =~ /\.(\w+)$/;
        return if $extension eq 'iso';
        my %sub = (
            qcow2 => \&_check_qcow2
            ,void => \&_check_yaml
        );
        is($volume->info->{driver_type}, $extension) or confess Dumper($volume->file, $volume->info);
        my $exec = $sub{$extension} or confess "Error: I don't know how to check "
            .$volume->file." [$extension]";
        $exec->($volume);
        next if $extension eq 'void';
        if ($volume->backing_file) {
            like($volume->info->{backing},qr(backingStore.*type.*file),"Expecting Backing for ".$volume->file." in ".$volume->domain->name)
                or confess Dumper($volume->info);
        } else {
            # backing store info missing or only with <backingStore/>
            if (!exists $volume->info->{backing} ) {
                ok(1);
            } else {
                is($volume->info->{backing},'<backingStore/>',"Expecting empty backing for "
                    .Dumper($volume->domain->name,$volume->info)) or exit;
            }
        }
    }
}


1;
