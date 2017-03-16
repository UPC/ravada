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

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin wait_request rvd_front init);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";
our ($CONNECTOR, $CONFIG);

our $CONT = 0;
our $USER_ADMIN;

sub user_admin {
    return $USER_ADMIN;
}
sub base_domain_name {
    my ($name) = $0 =~ m{.*?/(.*)\.t};
    die "I can't find name in $0"   if !$name;
    $name =~ s{/}{_}g;

    return $name;
}

sub new_domain_name {
    return base_domain_name()."_".$CONT++;
}

sub rvd_back {
    my ($connector, $config) = @_;
    init($connector,$config)    if $connector;

    return Ravada->new(
            connector => $CONNECTOR
                , config => ( $CONFIG or $DEFAULT_CONFIG)
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
        eval { 
            $domain->shutdown();
            sleep 1; 
            $domain->destroy() if $domain->is_active;
        }
            if $domain->is_active;
        warn "WARNING: error $@ trying to shutdown ".$domain->get_name if $@;
        eval { $domain->undefine };
        warn $@ if $@;
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

    my $dir_img;
    eval { $dir_img = $vm->dir_img() };
    return if !$dir_img;

    eval { $vm->storage_pool->refresh() };
    ok(!$@,"Expecting error = '' , got '".($@ or '')."'"
        ." after refresh storage pool") or return;
    opendir my $ls,$dir_img or do {warn "$! $dir_img"; return };
    while (my $disk = readdir $ls) {
        next if $disk !~ /^${name}_\d+.*\.(img|ro\.qcow2|qcow2)$/;

        $disk = "$dir_img/$disk";
        next if ! -f $disk;

        unlink $disk or die "I can't remove $disk";
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

sub wait_request {
    my $req = shift;
    for my $cnt ( 0 .. 10 ) {
        diag("Request ".$req->id." ".$req->command." ".$req->status." ".localtime(time))
            if $cnt > 2;
        last if $req->status eq 'done';
        sleep 2;
    }

}


1;
