package Test::Ravada;
use strict;
use warnings;

use  Carp qw(carp);
use  Data::Dumper;
use  Test::More;

use Ravada;
use Ravada::Auth::SQL;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(base_domain_name new_domain_name rvd_back remove_old_disks remove_old_domains create_user);

our $DEFAULT_CONFIG = "t/etc/ravada.conf";

our $CONT = 0;
our $RVD_BACK;

sub base_domain_name {
    my ($name) = $0 =~ m{.*/(.*/.*)\.t};
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
    };
    die $@ if $@;
    return $RVD_BACK;
}

sub _remove_old_domains_kvm {
    my $domain;
    my $vm = rvd_back()->search_vm('kvm');

    for ( 0 .. 10 ) {
        my $dom_name = base_domain_name()."_$_";
        my $domain = $vm->search_domain($dom_name);
        next if !$domain;

        $domain->shutdown_now() if $domain;

        diag("Removing domain $dom_name");
        eval {
            $domain->remove();
        };
        ok(!$@ , "Error removing domain $dom_name ".ref($domain).": $@") or exit;
    }

}
sub remove_old_domains {
    _remove_old_domains_kvm();
}

sub remove_old_disks {
    my ($name) = $0 =~ m{.*/(.*/.*)\.t};
    $name =~ s{/}{_}g;

    my $vm = $RVD_BACK->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager") or return;

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
