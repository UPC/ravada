package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use  Data::Dumper;
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use  Test::More;
use YAML qw(LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada;
use Ravada::Auth::SQL;

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
    search_iptable_remote
    clean_remote
    start_node shutdown_node
    start_domain_internal   shutdown_domain_internal
    connector
    create_ldap_user
    init_ldap_config
);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our $DEFAULT_DB_CONFIG = "t/etc/sql.conf";
our ($CONNECTOR, $CONFIG);

our $CONT = 0;
our $CONT_POOL= 0;
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
    confess "Missing id_iso" if !defined $id_iso;

    my $vm;
    if (ref($vm_name)) {
        $vm = $vm_name;
        $vm_name = $vm->type;
    } else {
        $vm = rvd_back()->search_vm($vm_name);
        ok($vm,"Expecting VM $vm_name, got ".$vm->type) or return;
    }

    my $name = new_domain_name();

    my %arg_create = (id_iso => $id_iso);

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $user->id
                    , %arg_create
                    , active => 0
		    , disk => 1024 * 1024
           );
    };
    is($@,'');

    return $domain;

}

sub base_domain_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return $name;
}

sub base_pool_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return "test_$name";
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

sub rvd_back($config=undef) {

    return $RVD_BACK            if $RVD_BACK && !$config;

    $RVD_BACK = 1;
    init($config or $DEFAULT_CONFIG,0);

    my $rvd = Ravada->new(
            connector => connector()
                , config => ( $config or $DEFAULT_CONFIG)
                , warn_error => 0
    );
    $rvd->_install();
    my $login;
    my $admin_name = base_domain_name();
    my $admin_pass = "$$ $$";
    eval {
        $login = Ravada::Auth::SQL->new(name => $admin_name );
    };
    $USER_ADMIN = $login if $login && $login->id;
    $USER_ADMIN = create_user($admin_name, $admin_pass,1)
        if !$USER_ADMIN;

    $ARG_CREATE_DOM{KVM} = [ id_iso => search_id_iso('Alpine') , disk => 1024 * 1024 ];

    $RVD_BACK = $rvd;
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

sub init($config=undef, $create_user=1) {

    $create_user = 1 if !defined $create_user;

    $Ravada::CONNECTOR = connector() if !$Ravada::CONNECTOR;
    Ravada::Auth::SQL::_init_connector($CONNECTOR);

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;

    rvd_back($config)  if !$RVD_BACK;
    rvd_front($config)  if !$RVD_FRONT;
    $Ravada::VM::KVM::VERIFY_ISO = 0;
}

sub _remove_old_domains_vm {
    my $vm_name = shift;

    my $domain;

    my $vm;
    eval {
        my $rvd_back=rvd_back();
        return if !$rvd_back;
        $vm = $rvd_back->search_vm($vm_name);
    };
    diag($@) if $@;

    return if !$vm;

    my $base_name = base_domain_name();

    my @domains;
    eval { @domains = $vm->list_domains() };

    for my $dom_name ( sort { $b cmp $a }  @domains) {
        next if $dom_name !~ /^$base_name/i;

        my $domain;
        eval {
            $domain = $vm->search_domain($dom_name);
        };
        next if !$domain;

        eval { $domain->shutdown_now($USER_ADMIN); };
        warn "Error shutdown ".$domain->name." $@" if $@ && $@ !~ /No DB info/i;

        $domain = $vm->search_domain($dom_name);
        eval {$domain->remove( $USER_ADMIN ) }  if $domain;
        if ( $@ && $@ =~ /No DB info/i ) {
            eval { $domain->domain->undefine() if $domain->domain };
        }

    }

}

sub _remove_old_domains_kvm {

    my $vm;
    
    eval {
        my $rvd_back = rvd_back();
        $vm = $rvd_back->search_vm('KVM');
    };
    diag($@) if $@;
    return if !$vm;

    my $base_name = base_domain_name();
    for my $domain ( $vm->vm->list_all_domains ) {
        next if $domain->get_name !~ /^$base_name/;
        my $domain_name = $domain->get_name;
        eval { 
            $domain->shutdown();
            sleep 1; 
            eval { $domain->destroy() if $domain->is_active };
            warn $@ if $@;
        }
            if $domain->is_active;
        warn "WARNING: error $@ trying to shutdown ".$domain_name
            if $@ && $@ !~ /error code: 42,/;

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

sub _remove_old_disks_kvm {
    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

#    my $rvd_back= rvd_back();
    my $vm = rvd_back()->search_vm('kvm');
    if (!$vm) {
        return;
    }
#    ok($vm,"I can't find a KVM virtual manager") or return;

    $vm->_refresh_storage_pools();

    for my $pool( $vm->vm->list_all_storage_pools ) {
        for my $volume  ( $pool->list_volumes ) {
            next if $volume->get_name !~ /^${name}_\d+.*\.(img|raw|ro\.qcow2|qcow2)$/;
            $volume->delete();
        }
    }
    $vm->storage_pool->refresh();
}

sub _remove_old_disks_void {
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
    my $vm = rvd_back->search_vm('kvm') or return;

    for my $pool  ( $vm->vm->list_all_storage_pools) {
        next if $pool->get_name !~ /^test_/;
        diag("Removing ".$pool->get_name." storage_pool");
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
    remove_old_domains();
    remove_old_disks();
    remove_old_pools();
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
    my $sth = $CONNECTOR->dbh->prepare("SELECT id FROM iso_images "
        ." WHERE name like ?"
    );
    $sth->execute("$name%");
    my ($id) = $sth->fetchrow;
    die "There is no iso called $name%" if !$id;
    return $id;
}

sub flush_rules {
    return if $>;
    my $ipt = open_ipt();
    $ipt->flush_chain('filter', $CHAIN);
    $ipt->delete_chain('filter', 'INPUT', $CHAIN);

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

sub _dir_db {
    my $dir_db= $0;
    $dir_db =~ s{(t)/(.*)/.*}{$1/.db/$2};
    $dir_db =~ s{(t)/.*}{$1/.db} if !defined $2;
    if (! -e $dir_db ) {
            warn "mkdir $dir_db";
            mkdir $dir_db,0700 or die "$! $dir_db";
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
                        , PrintError => 0
                });

    _create_db_tables($connector);

    $CONNECTOR = $connector;
    return $connector;
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

sub END {
    remove_old_user() if $CONNECTOR;
    remove_old_user_ldap() if $CONNECTOR;
}
1;
