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

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user user_admin);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";

our $CONT = 0;
our $RVD_BACK;
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
    my ($connector, $config ) =@_;

    return $RVD_BACK if !$config && !$connector;

    eval { $RVD_BACK = Ravada->new(
            connector => $connector
                , config => ( $config or $DEFAULT_CONFIG)
            );
            $USER_ADMIN = create_user('admin','admin',1);
    };
    die $@ if $@;
    return $RVD_BACK;
}

sub _remove_old_domains_vm {
    my $vm_name = shift;

    my $domain;
    my $vm = rvd_back()->search_vm($vm_name);
    return if !$vm;

    for (reverse 0 .. 20 ) {
        my $dom_name = base_domain_name()."_$_";
        my $domain = $vm->search_domain($dom_name);
        next if !$domain;

        $domain->shutdown_now() if $domain;

        diag("[$vm_name] Removing domain $dom_name");
        eval {
            $domain->remove( $USER_ADMIN );
        };
        ok(!$@ , "Error removing domain $dom_name ".ref($domain).": $@") or exit;
    }

}
sub remove_old_domains {
    _remove_old_domains_vm('KVM');
    _remove_old_domains_vm('Void');
}

sub _remove_old_disks_kvm {
    my $name = base_domain_name();
    confess "Unknown base domain name " if !$name;

    my $vm = $RVD_BACK->search_vm('kvm') or return;
#    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    $vm->storage_pool->refresh();
    opendir my $ls,$dir_img or die "$! $dir_img";
    while (my $disk = readdir $ls) {
        next if $disk !~ /^${name}_\d+\.(img|ro\.qcow2|qcow2)$/;

        $disk = "$dir_img/$disk";
        next if ! -f $disk;

        diag("Removing previous $disk");
        unlink $disk or die "I can't remove $disk";
    }
    $vm->storage_pool->refresh();
}

sub _remove_old_disks_void {
    my $name = base_domain_name();

    my $dir_img =  $Ravada::Domain::Void::TMP_DIR ;
    opendir my $ls,$dir_img or return;
    while (my $file = readdir $ls ) {
        next if $file !~ /^${name}_\d+\.(img|ro\.qcow2|qcow2)$/;

        my $disk = "$dir_img/$file";
        next if ! -f $disk;

        diag("Removing previous $disk");
        unlink $disk or die "I can't remove $disk";

    }
    closedir $ls;
}

sub remove_old_disks {
    return _remove_old_disks_void();
    return _remove_old_disks_kvm();

}

sub create_user {
    my ($name, $pass, $is_admin) = @_;
    Ravada::Auth::SQL::add_user($name, $pass, $is_admin);

    my $user;
    eval {
        $user = Ravada::Auth::SQL->new(name => $name, password => $pass);
    };
    die $@ if !$user;
    return $user;
}

1;
