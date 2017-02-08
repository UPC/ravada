package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp confess);
use  Data::Dumper;
use  Test::More;

use Ravada;
use Ravada::Auth::SQL;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin wait_request rvd_front init init_vm clean new_pool_name
create_domain
init_ip remote_ip
);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our $FILE_CONFIG_REMOTE = "t/etc/remote_vm.conf";

our ($CONNECTOR, $CONFIG);

our $CONT = 0;
our $CONT_POOL= 0;
our $USER_ADMIN;
our $REMOTE_IP;

my %ARG_CREATE_DOM = (
      kvm => [ id_iso => 1 ]
);

sub user_admin {
    return $USER_ADMIN;
}

sub create_domain {
    my $vm_name = shift;
    my $user = (shift or $USER_ADMIN);

    my $vm = rvd_back()->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    ok($ARG_CREATE_DOM{lc($vm_name)}) or do {
        diag("VM $vm_name should be defined at \%ARG_CREATE_DOM");
        return;
    };
    my @arg_create = @{$ARG_CREATE_DOM{lc($vm_name)}};

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $user->id
                    , @arg_create
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
    return base_domain_name()."_".$CONT++;
}

sub new_pool_name {
    return base_pool_name()."_".$CONT_POOL++;
}

sub rvd_back {
    my ($connector, $config) = @_;
    init($connector,$config)    if $connector;

    return Ravada->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
                , warn_error => 0
    );
}

sub rvd_front {

    return Ravada::Front->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
    );
}

sub init {
    ($CONNECTOR,$CONFIG) = @_;

    confess "Missing connector : init(\$connector,\$config)" if !$CONNECTOR;

    $Ravada::CONNECTOR = $CONNECTOR if !$Ravada::CONNECTOR;
    Ravada::Auth::SQL::_init_connector($CONNECTOR);
    $USER_ADMIN = create_user('admin','admin',1);

    $Ravada::Domain::MIN_FREE_MEMORY = 512*1024;
}

sub init_ip {
    return if !-e $FILE_CONFIG_REMOTE;

    open my $in ,'<', $FILE_CONFIG_REMOTE;
    $REMOTE_IP =<$in>;
    chomp $REMOTE_IP;
    close $in;

    return $REMOTE_IP;
}

sub remote_ip {
    return ($REMOTE_IP or undef);
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

        eval {$domain->remove( $USER_ADMIN ) };
        if ( $@ && $@ =~ /No DB info/i ) {
            eval { $domain->domain->undefine() if $domain->domain };
        }

    }

}

sub _remove_old_domains_kvm {
    my $ip = shift;

    my $vm;
    
    eval {
        if ($ip) {
            $vm = Ravada::VM::KVM->new(host => $ip);
        } else {
            my $rvd_back = rvd_back();
            $vm = $rvd_back->search_vm('KVM');
        }
    };
    diag($@) if $@;
    return if !$vm;

    my $base_name = base_domain_name();
    for my $domain ( $vm->vm->list_all_domains ) {
        next if $domain->get_name !~ /^$base_name/;
        eval { 
            $domain->shutdown();
            sleep 1; 
            $domain->destroy() if $domain->is_active;
        }
            if $domain->is_active;
        warn "WARNING: error $@ trying to shutdown ".$domain->get_name if $@;

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
    _remove_old_domains_kvm($REMOTE_IP) if $REMOTE_IP;
}

sub _remove_old_disks_kvm_local {

    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

#    my $rvd_back= rvd_back();
    my $vm = rvd_back()->search_vm('kvm');
    if (!$vm) {
        return;
    }
#    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img;
    eval { $dir_img = $vm->dir_img() };
    return if !$dir_img;

    eval { $vm->storage_pool->refresh() };
    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    opendir my $ls,$dir_img or return;
    while (my $disk = readdir $ls) {
        next if $disk !~ /^${name}_\d+.*\.(img|ro\.qcow2|qcow2)$/;

        $disk = "$dir_img/$disk";
        next if ! -f $disk;

        unlink $disk or next;#warn "I can't remove $disk";
    }
    $vm->storage_pool->refresh();
}

sub _remove_old_disks_kvm_remote {
    my $ip = shift;

    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

    my $vm;
    if ($ip) {
        $vm = Ravada::VM::KVM->new(host => $ip);
    } else {
        my $rvd_back = rvd_back();
        $vm = $rvd_back->search_vm('KVM');
    }

    if (!$vm) {
        return;
    }
#    ok($vm,"I can't find a KVM virtual manager") or return;

    eval { $vm->storage_pool->refresh() };
    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    for my $volume ( $vm->storage_pool->list_all_volumes()) {
        next if $volume->get_name !~ /^${name}_\d+.*\.(img|ro\.qcow2|qcow2)$/;
        $volume->delete;
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
    _remove_old_disks_kvm_remote();
    _remove_old_disks_kvm_remote($REMOTE_IP)    if $REMOTE_IP;
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
    my $vm = rvd_back->search_vm('kvm') or return;

    for my $pool  ( $vm->vm->list_all_storage_pools) {
        next if $pool->get_name !~ /^test_/;
        diag("Removing ".$pool->get_name." storage_pool");
        $pool->destroy();
        eval { $pool->undefine() };
        warn $@ if$@;
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
1;
