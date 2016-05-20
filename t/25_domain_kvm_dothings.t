use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::KVM');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada = Ravada->new( connector => $test->connector);
my @PIDS;
my $REMOTE_VIEWER = `which remote-viewer`;
chomp $REMOTE_VIEWER;

##############################################################
#

sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $ravada->search_domain($name);

    if ($domain) {
        diag("Removing domain $name");
        $domain->remove();
    }
    $domain = $ravada->search_domain($name);
    die "I can't remove old domain $name"
        if $domain;

}

sub show_domain {
    my $domain = shift;

    $SIG{CHLD} = 'IGNORE';
    return;

    my $pid = fork();
    if (!defined $pid) {
        warn "I can't fork";
        return;
    }
    if ($pid) {
        push @PIDS,($pid);
        return;
    }
    my @cmd = ($REMOTE_VIEWER,$domain->display);
    system(@cmd);
    exit;
}

#
##############################################################

END {
    return if !@PIDS;
    diag("Killing ".join(",",@PIDS));
    kill(15,@PIDS);
    kill(7,@PIDS);
};

my ($name) = $0 =~ m{.*/(.*)\.t};

test_remove_domain($name);

my $domain = $ravada->create_domain(name => $name, id_iso => 1 , active => 0);


ok($domain,"Domain not created") and do {
    show_domain($domain);
    $domain->shutdown(timeout => 5) if !$domain->is_active;

    for ( 1 .. 10 ){
        last if !$domain->is_active;
        diag("Waiting for domain $name to shut down");
        sleep 1;
    }
    if ( $domain->domain->is_active() ) {
        $domain->domain->destroy;
        sleep 2;
    }

    ok(! $domain->is_active, "I can't shut down the domain") and do {
        $domain->start();
        ok($domain->is_active,"I don't see the domain active");
        show_domain($domain)    if $domain->is_active();

        if ($domain->is_active) {
            $domain->shutdown(timeout => 3);
        }
        ok(!$domain->is_active."Domain won't shut down") and do {
            test_remove_domain($name);
        };
    };
};

done_testing();


