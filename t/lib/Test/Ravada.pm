package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use Data::Dumper;
use YAML qw(DumpFile);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use  Test::More;
use YAML qw(LoadFile);

use feature qw(signatures);
no warnings "experimental::signatures";

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada;
use Ravada::Auth::SQL;
use Ravada::Domain::Void;

$Ravada::Domain::Void::DIR_TMP = "/var/tmp/test/rvd_void";

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin wait_request rvd_front init init_vm clean new_pool_name
create_domain
    test_chain_prerouting
    find_ip_rule
    search_id_iso
    flush_rules open_ipt
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
);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our $FILE_CONFIG_REMOTE = "t/etc/remote_vm.conf";

our ($CONNECTOR, $CONFIG , $FILE_CONFIG_TMP);

our $CONT = 0;
our $CONT_POOL= 0;
our $USER_ADMIN;
our $CHAIN = 'RAVADA';

our %ARG_CREATE_DOM = (
    KVM => []
    ,Void => []
);

our %VM_VALID = ( KVM => 1
    ,Void => 0
);

sub user_admin {
    return $USER_ADMIN;
}

sub arg_create_dom {
    my $vm_name = shift;
    confess "Unknown vm $vm_name"
        if !$ARG_CREATE_DOM{$vm_name};
    return @{$ARG_CREATE_DOM{$vm_name}};
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
                    , memory => 256*1024
           );
    };
    is($@,'');

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
    return base_domain_name()."_".$CONT++;
}

sub new_pool_name {
    return base_pool_name()."_".$CONT_POOL++;
}

sub rvd_back {
    my ($connector, $config) = @_;
    init($connector,$config,0)    if $connector;

    my $rvd = Ravada->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
                , warn_error => 0
    );
    $rvd->_update_isos();
    $USER_ADMIN = create_user('admin','admin',1)    if !$USER_ADMIN;

    $ARG_CREATE_DOM{KVM} = [ id_iso => search_id_iso('Alpine') ];

    return $rvd;
}

sub rvd_front {

    return Ravada::Front->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
    );
}

sub init {
    my ($config, $create_user);
    ($CONNECTOR, $config, $create_user) = @_;

    $create_user = 1 if !defined $create_user;

    confess "Missing connector : init(\$connector,\$config)" if !$CONNECTOR;

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

    clean();
    # clean removes the temporary config file, so we dump it again
    DumpFile($FILE_CONFIG_TMP, $config) if $config && ref($config);

    $Ravada::CONNECTOR = $CONNECTOR;# if !$Ravada::CONNECTOR;
    Ravada::Auth::SQL::_init_connector($CONNECTOR);
    eval {
    $USER_ADMIN = create_user('admin','admin',1)    if $create_user;
    };

    die $@ if $@ && $@ !~ /UNIQUE constraint failed: users.name/;

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;

}

sub remote_config {
    my $vm_name = shift;
    return { } if !-e $FILE_CONFIG_REMOTE;

    my $conf;
    eval { $conf = LoadFile($FILE_CONFIG_REMOTE) };
    is($@,'',"Error in $FILE_CONFIG_REMOTE\n".$@) or return;

    my $remote_conf = $conf->{$vm_name} or do {
        diag("SKIPPED: No $vm_name section in $FILE_CONFIG_REMOTE");
        return ;
    };
    for my $field ( qw(host user password security public_ip name)) {
        delete $remote_conf->{$field};
    }
    die "Unknown fields in remote_conf $vm_name, valids are : host user password name\n"
        .Dumper($remote_conf)   if keys %$remote_conf;

    $remote_conf = LoadFile($FILE_CONFIG_REMOTE);
    ok($remote_conf->{public_ip} ne $remote_conf->{host},
            "Public IP must be different from host at $FILE_CONFIG_REMOTE")
        if defined $remote_conf->{public_ip};

    $remote_conf->{public_ip} = '' if !exists $remote_conf->{public_ip};

    lock_hash(%$remote_conf);
    return $remote_conf->{$vm_name};
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

sub _remove_old_domains_vm {
    my $vm_name = shift;

    return if !$VM_VALID{$vm_name};

    my $domain;

    my $vm;

    if (ref($vm_name)) {
        $vm = $vm_name;
    } else {
        eval {
        my $rvd_back=rvd_back();
        return if !$rvd_back;
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

    opendir my $dir, $vm->dir_img or return;
    while ( my $file = readdir($dir) ) {
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
    $vm->run_command("rm -f ".$vm->dir_img."/*yml "
                    .$vm->dir_img."/*qcow "
                    .$vm->dir_img."/*img"
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
        eval { 
            $domain->shutdown() if $domain->is_active;
            sleep 1; 
            $domain->destroy() if $domain->is_active;
        };
        warn "WARNING: error $@ trying to shutdown ".$domain->get_name
            if $@ && $@ !~ /error code: 55/;

        $domain->managed_save_remove()
            if $domain->has_managed_save_image();

        eval { $domain->undefine };
        warn $@ if $@;
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

    eval { $vm->refresh_storage_pools() };
    return if $@ && $@ =~ /Cannot recv data/;

    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    for my $volume ( $vm->storage_pool->list_all_volumes()) {
        next if $volume->get_name !~ /^${name}_\d+.*\.(img|ro\.qcow2|qcow2)$/;
        $volume->delete;
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
    my $cmd = "rm -rfv ".$node->dir_img."/".base_domain_name().'_*';
    $node->run_command($cmd);
}

sub _remove_old_disks_void_local {
    my $name = base_domain_name();

    my $dir_img =  $Ravada::Domain::Void::DIR_TMP ;
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

sub wait_request {
    my $req = shift;
    for my $cnt ( 0 .. 10 ) {
        diag("Request ".$req->id." ".$req->command." ".$req->status." ".localtime(time))
            if $cnt > 2;
        last if $req->status eq 'done';
        sleep 2;
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
    _clean_db();
    _clean_file_config();
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
    return if ! -e $FILE_CONFIG_REMOTE;

    my $conf;
    eval { $conf = LoadFile($FILE_CONFIG_REMOTE) };
    return if !$conf;
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
    _flush_rules_remote($node)  if !$node->is_local();
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

sub search_id_iso {
    my $name = shift;
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
    my $iptables = $node->iptables_list();

    $remote_ip .= "/32" if defined $remote_ip && $remote_ip !~ m{/};
    $local_ip .= "/32"  if defined $local_ip && $local_ip !~ m{/};

    my @found;

    my $count = 0;
    for my $line (@{$iptables->{filter}}) {
        my %args = @$line;
        next if $args{A} ne $CHAIN;
        $count++;
        if(exists $args{j} && defined $jump         && $args{j} eq $jump
           && exists $args{s} && defined $remote_ip && $args{s} eq $remote_ip
           && exists $args{d} && defined $local_ip  && $args{d} eq $local_ip
           && exists $args{dport} && defined $local_port && $args{dport} eq $local_port) {

            push @found,($count);
        }
    }
    return @found   if wantarray;
    return if !scalar@found;
    return $found[0];
}

sub _flush_rules_remote($node) {
    $node->create_iptables_chain($CHAIN);
    $node->run_command("iptables -F $CHAIN");
    $node->run_command("iptables -X $CHAIN");
}

sub flush_rules {
    my $ipt = open_ipt();
    $ipt->flush_chain('filter', $CHAIN);
    $ipt->delete_chain('filter', 'INPUT', $CHAIN);

    my @cmd = ('iptables','-t','nat','-F','PREROUTING');
    my ($in,$out,$err);
    run3(\@cmd, \$in, \$out, \$err);
    die $err if $err;
}

sub open_ipt {
    my %opts = (
    	'use_ipv6' => 0,         # can set to 1 to force ip6tables usage
	    'ipt_rules_file' => '',  # optional file path from
	                             # which to read iptables rules
	    'iptout'   => '/tmp/iptables.out',
	    'ipterr'   => '/tmp/iptables.err',
	    'debug'    => 0,
	    'verbose'  => 0,

	    ### advanced options
	    'ipt_alarm' => 5,  ### max seconds to wait for iptables execution.
	    'ipt_exec_style' => 'waitpid',  ### can be 'waitpid',
	                                    ### 'system', or 'popen'.
	    'ipt_exec_sleep' => 1, ### add in time delay between execution of
	                           ### iptables commands (default is 0).
	);

	my $ipt_obj = IPTables::ChainMgr->new(%opts)
    	or die "[*] Could not acquire IPTables::ChainMgr object";

}

sub _domain_node($node) {
    my $vm = rvd_back->search_vm('KVM','localhost');
    my $domain = $vm->search_domain($node->name);
    $domain = rvd_back->import_domain(name => $node->name
            ,user => user_admin->name
            ,vm => 'KVM'
            ,spinoff_disks => 0
    )   if !$domain || !$domain->is_known;

    ok($domain->id,"Expecting an ID for domain ".Dumper($domain)) or exit;
    $domain->_set_vm($vm, 'force');
    return $domain;
}

sub hibernate_node($node) {
    diag("hibernate node ".$node->type." ".$node->name);
    if ($node->is_active) {
        for my $domain ($node->list_domains()) {
            diag("Shutting down ".$domain->name." on node ".$node->name);
            $domain->shutdown_now(user_admin);
        }
    }
    $node->disconnect;

    my $domain_node = _domain_node($node);
    $domain_node->hibernate( user => user_admin);

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

    diag("shutdown node ".$node->type." ".$node->name);
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

    diag("start node ".$node->type." ".$node->name);
    confess "Undefined node " if!$node;

    $node->disconnect;
    if ( $node->_do_is_active ) {
        $node->connect && return;
        warn "I can't connect";
    }

    my $domain = _domain_node($node);

    ok($domain->_vm->host eq 'localhost');

    $domain->start(user => user_admin, remote_ip => '127.0.0.1')  if !$domain->is_active;

    for ( 1 .. 30 ) {
        last if $node->ping ;
        sleep 1;
        diag("Waiting for ping node ".$node->name." $_") if !($_ % 10);
    }

    is($node->ping('debug'),1,"[".$node->type."] Expecting ping node ".$node->name) or exit;

    for ( 1 .. 20 ) {
        last if $node->_do_is_active;
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
        diag("Waiting for connection to node ".$node->name." $_") if !($_ % 5);
    }
    is($connect,1
            ,"[".$node->type."] "
                .$node->name." Expecting connection") or exit;

    $node->run_command("hwclock","--hctosys");
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

sub _do_remote_node($vm_name, $remote_config) {
    my $vm = rvd_back->search_vm($vm_name);

    my $node;
    my @list_nodes0 = rvd_front->list_vms;

    eval { $node = $vm->new(%{$remote_config}) };
    ok(!$@,"Expecting no error connecting to $vm_name at ".Dumper($remote_config
).", got :'"
        .($@ or '')."'") or return;
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

sub DESTROY {
    _clean_file_config();
}

1;
