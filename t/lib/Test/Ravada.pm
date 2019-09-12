package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use Data::Dumper;
use File::Path qw(make_path);
use YAML qw(DumpFile);
use Hash::Util qw(lock_hash unlock_hash);
use IPC::Run3 qw(run3);
use  Test::More;
use YAML qw(LoadFile DumpFile);

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
    vm_names
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
    create_ldap_user
    init_ldap_config

    create_storage_pool
    local_ips
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

sub user_admin {

    return $USER_ADMIN if $USER_ADMIN;

    my $login;
    my $admin_name = base_domain_name();
    my $admin_pass = "$$ $$";
    eval {
        $login = Ravada::Auth::SQL->new(name => $admin_name );
    };
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
    return sort keys %ARG_CREATE_DOM;
}

sub create_domain {
    my $vm_name = shift;
    my $user = (shift or $USER_ADMIN);
    my $id_iso = (shift or 'Alpine');

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

    my %arg_create = (id_iso => $id_iso);

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $user->id
                    , %arg_create
                    , active => 0
                    , memory => 1024*1024
                    , disk => 1024 * 1024 * 1024
           );
    };
    is('',''.$@);

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

sub rvd_back($config=undef, $init=1) {

    return $RVD_BACK            if $RVD_BACK && !$config;

    $RVD_BACK = 1;
    init($config or $DEFAULT_CONFIG) if $init;

    my $rvd = Ravada->new(
            connector => connector()
                , config => ( $config or $DEFAULT_CONFIG)
                , warn_error => 1
    );
    $rvd->_install();

    user_admin();
    $RVD_BACK = $rvd;
    $ARG_CREATE_DOM{KVM} = [ id_iso => search_id_iso('Alpine') , disk => 1024 * 1024 ];

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

sub init($config=undef) {

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

    $Ravada::CONNECTOR = connector();
    Ravada::Auth::SQL::_init_connector($CONNECTOR);

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;

    rvd_back($config, 0)  if !$RVD_BACK;
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
    return if !$vm->ping;
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
    _remove_old_domains_vm('KVM');
    _remove_old_domains_vm('Void');
    _remove_old_domains_kvm();
}

sub _activate_storage_pools($vm) {
    for my $sp ($vm->vm->list_all_storage_pools()) {
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

    for my $pool( $vm->vm->list_all_storage_pools ) {
        for my $volume  ( $pool->list_volumes ) {
            next if $volume->get_name !~ /^${name}_\d+.*\.(img|raw|ro\.qcow2|qcow2|void)$/;
            $volume->delete();
        }
    }
    $vm->storage_pool->refresh();
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
    return if !$node->ping;

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
    _remove_old_disks_kvm();
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

sub wait_request {
    my %args;
    if (scalar @_ % 2 == 0 ) {
        %args = @_;
        $args{background} = 0 if !exists $args{background};
    } else {
        $args{request} = [ $_[0] ];
    }
    my $timeout = delete $args{timeout};
    my $request = ( delete $args{request} or [] );

    my $background = delete $args{background};
    $background = 1 if !defined $background;

    $timeout = 60 if !defined $timeout && $background;
    my $debug = ( delete $args{debug} or 0 );
    my $skip = ( delete $args{skip} or [] );
    $skip = [ $skip ] if !ref($skip);
    my %skip = map { $_ => 1 } @$skip;

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
            my $req = Ravada::Request->open($req_id);
            next if $skip{$req->command};
            if ( $req->status ne 'done' ) {
                $done_all = 0;
            } elsif (!$done{$req->id}) {
                $done{$req->{id}}++;
                is($req->error,'') or confess if $check_error;
            }
        }
        my $post = join(".",_list_requests);
        $post = '' if !defined $post;
        if ( $done_all ) {
            for my $req (@$request) {
                if ($req->status ne 'done') {
                    $done_all = 0;
                    diag("Waiting for request ".$req->id." ".$req->command);
                    last;
                }
            }
        }
        return if $done_all && $prev eq $post && scalar(keys %done) == $done_count;;
        return if defined $timeout && time - $t0 >= $timeout;
        sleep 1 if !$background;
    }
}

sub init_vm {
    my $vm = shift;
    return if $vm->type =~ /void/i;
    _qemu_storage_pool($vm) if $vm->type =~ /qemu/i;
}

sub _exists_storage_pool {
    my ($vm, $pool_name) = @_;
    for my $pool ($vm->vm->list_storage_pools) {
        return 1 if $pool->get_name eq $pool_name;
    }
    return;
}

sub _qemu_storage_pool {
    my $vm = shift;

    my $pool_name = new_pool_name();

    if ( _exists_storage_pool($vm, $pool_name)) {
        $vm->default_storage_pool_name($pool_name);
        return;
    }

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

    $vm->default_storage_pool_name($pool_name);
}

sub remove_qemu_pools {
    return if !$VM_VALID{'KVM'} || $>;
    my $vm;
    eval { $vm = rvd_back->search_vm('kvm') };
    if ($@ && $@ !~ /Missing qemu-img/) {
        warn $@;
    }
    if  ( !$vm ) {
        $VM_VALID{'KVM'} = 0;
        return;
    }

    my $base = base_pool_name();
    for my $pool  ( $vm->vm->list_all_storage_pools) {
        my $name = $pool->get_name;
        next if $name !~ qr/^$base/;
        diag("Removing ".$pool->get_name." storage_pool");
        for my $vol ( $pool->list_volumes ) {
            diag("Removing ".$pool->get_name." vol ".$vol->get_name);
            $vol->delete();
        }
        $pool->destroy();
        eval { $pool->undefine() };
        warn $@ if$@ && $@ !~ /libvirt error code: 49,/;
        ok(!$@ or $@ =~ /Storage pool not found/i);
    }

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
    my $sth = $CONNECTOR->dbh->prepare(
        "DELETE FROM vms "
    );
    $sth->execute;
    $sth->finish;

    $sth = $CONNECTOR->dbh->prepare(
        "DELETE FROM domains"
    );
    $sth->execute;
    $sth->finish;

}

sub clean_remote {
    my $conf = _load_remote_config() or return;
    for my $vm_name (keys %$conf) {
        my $vm;
        eval { $vm = rvd_back->search_vm($vm_name) };
        warn $@ if $@;
        next if !$vm;

        my $node;
        eval { $node = $vm->new(%{$conf->{$vm_name}}) };
        next if ! $node;
        if ( !$node->_do_is_active ) {
            $node->remove;
            next;
        }

        clean_remote_node($node);
        _remove_old_domains_vm($node);
        _remove_old_disks_kvm($node) if $vm_name =~ /^kvm/i;
        $node->remove();
    }
}

sub _clean_remote_nodes {
    my $config = shift;
    for my $name (keys %$config) {
        diag("Cleaning $name");
        my $node;
        my $vm = rvd_back->search_vm($config->{$name}->{type});
        eval { $node = $vm->new($config->{$name}) };
        warn $@ if $@;
        next if !$node || !$node->_do_is_active;

        clean_remote_node($node);

    }
}

sub clean_remote_node {
    my $node = shift;

    _remove_old_domains_vm($node);
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

sub remove_old_user {
    $USER_ADMIN->remove if $USER_ADMIN;
    confess "Undefined connector" if !defined $CONNECTOR;
    my $sth = $CONNECTOR->dbh->prepare("DELETE FROM users WHERE name=?");
    $sth->execute(base_domain_name());
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

    confess "Error: Unknown args ".Dumper(\%args) if keys %args;

    my $iptables = $node->iptables_list();

    $remote_ip .= "/32" if defined $remote_ip && $remote_ip !~ m{/};
    $local_ip .= "/32"  if defined $local_ip && $local_ip !~ m{/};

    my @found;

    my $count = 0;
    for my $line (@{$iptables->{$table}}) {
        my %args = @$line;
        next if $args{A} ne $chain;
        $count++;

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

sub flush_rules_node($node) {
    $node->create_iptables_chain($CHAIN);
    $node->run_command("/sbin/iptables","-F", $CHAIN);
    $node->run_command("/sbin/iptables","-X", $CHAIN);
}

sub flush_rules {
    return if $>;

    my @cmd = ('iptables','-t','nat','-F','PREROUTING');
    my ($in,$out,$err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;

    @cmd = ('iptables','-L','INPUT');
    run3(\@cmd, \$in, \$out, \$err);

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
    $node->disconnect;

    my $domain_node = _domain_node($node);
    $domain_node->hibernate( user_admin );

    my $max_wait = 30;
    my $ping;
    for ( 1 .. $max_wait ) {
        diag("Waiting for node ".$node->name." to be inactive ...")  if !($_ % 10);
        $ping = $node->ping;
        last if !$ping;
        sleep 1;
    }
    is($ping,0, "Expecting node ".$node->name." hibernated not pingable");
}

sub shutdown_node($node) {

    if ($node->is_active) {
        $node->run_command("service lightdm stop");
        $node->run_command("service gdm stop");
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
    sleep 2 if !$node->ping;

    my $max_wait = 120;
    for ( 1 .. $max_wait / 2 ) {
        diag("Waiting for node ".$node->name." to be inactive ...")  if !($_ % 10);
        last if !$node->ping;
        sleep 1;
    }
    is($node->ping,0);
}

sub start_node($node) {

    confess "Undefined node"    if !defined $node;
    confess "Undefined node " if!$node;

    $node->disconnect;
    if ( $node->_do_is_active ) {
        my $connect;
        eval { $connect = $node->connect };
        return if $connect;
        warn "I can't connect";
    }

    my $domain = _domain_node($node);

    ok($domain->_vm->host eq 'localhost');

    $domain->start(user => user_admin, remote_ip => '127.0.0.1')  if !$domain->is_active;

    for ( 1 .. 60 ) {
        last if $node->ping ;
        sleep 1;
        diag("Waiting for ping node ".$node->name." ".$node->ip." $_") if !($_ % 10);
    }

    is($node->ping('debug'),1,"[".$node->type."] Expecting ping node ".$node->name) or exit;

    for ( 1 .. 60 ) {
        my $is_active;
        eval {
            $node->connect();
            $is_active = $node->is_active(1)
        };
        warn $@ if $@;
        last if $is_active;
        sleep 1;
        diag("Waiting for active node ".$node->name." $_") if !($_ % 10);
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
    $node->is_enabled(1);
    for ( 1 .. 60 ) {
        my $node2 = Ravada::VM->open(id => $node->id);
        last if $node2->is_active(1);
        diag("Waiting for node ".$node->name." active ...")  if !($_ % 10);
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
    run3(['/sbin/iptables-save'], \$in, \$out, \$err);
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

    if ( $node->ping && !$node->_connect_ssh() ) {
        my $ssh;
        for ( 1 .. 60 ) {
            $ssh = $node->_connect_ssh();
            last if $ssh;
            sleep 1;
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
    my $dir_db= $0;
    $dir_db =~ s{(t)/(.*)/.*}{$1/.db/$2};
    $dir_db =~ s{(t)/.*}{$1/.db} if !defined $2;
    if (! -e $dir_db ) {
            make_path $dir_db or die "$! $dir_db";
    }
    return $dir_db;
}

sub _file_db {
    my $file_db = shift;
    my $dir_db = _dir_db();

    if (! $file_db ) {
        $file_db = $0;
        $file_db =~ s{.*/(.*)\.\w+$}{$dir_db/$1\.db};
        mkpath $dir_db or die "$! '$dir_db'" if ! -d $dir_db;
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

1;
