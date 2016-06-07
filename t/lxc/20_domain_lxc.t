use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::LXC');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada = Ravada->new( connector => $test->connector);

my $CONT= 0;

sub test_remove_domain {
    my $name = shift;
	my @info = ('lxc-info','-n',$name);
        
        my ($in,$out,$err);
        run3(\@info,\$in,\$out,\$err);
        ok($? = 256,"@info \$?=$? , it should be 256 $err $out.");

    if ($err) {
        diag("Removing domain $name");
   	    $ravada->remove($name);
    }
}

sub search_domain_db {
    my $name = shift;
    my $sth = $test->dbh->prepare("SELECT * FROM domains WHERE name=? ");
    $sth->execute($name);
    my $row =  $sth->fetchrow_hashref;
    return $row;
}

sub test_new_domain {
    my $active = shift;

    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;

    test_remove_domain($name);

    diag("Creating domain $name");
    my @domain = ('lxc-create','-n',$name, '-t','ubuntu');
    my ($in,$out,$err);
    run3(\@domain,\$in,\$out,\$err);
    ok(!$?,"@domain \$?=$? , it should be 0 $err $out.");

    #my $exp_ref= 'Ravada::Domain::LXC';
    #ok(ref $domain eq $exp_ref, "Expecting $exp_ref , got ".ref($domain))
    #    if $domain;

    my @cmd = ('lxc-info','-n',$name);
    #my ($in,$out,$err);
    run3(\@cmd,\$in,\$out,\$err);
    ok(!$?,"@cmd \$?=$? , it should be 0 $err $out");

    #my $row =  search_domain_db($name);
    #ok($row->{name} && $row->{name} eq $name,"I can't find the domain at the db");

    return $name;
}


################################################################
#test_new_domain();
test_remove_domain();


done_testing();
