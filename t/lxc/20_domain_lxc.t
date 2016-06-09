use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::LXC');

my $test = Test::SQL::Data->new( config => 't/etc/ravada.conf');
my $ravada= 'Ravada::Domain::LXC'->new();


my $CONT= 0;

sub test_remove_container {
    my $name = shift;
    my $domain;
    $domain = $ravada->search_container($name,1);
      if ($domain) {
       diag("Removing container $name");
       $ravada->remove_container($name);
        my $domain2 = $ravada->search_container($name,1);
        ok(!$domain2,"Containter $name should be removed");
      }
}


sub test_new_container {
    my $active = shift;

    my ($name) = $0 =~ m{.*/(.*)\.t};
    $name .= "_".$CONT++;

    test_remove_container($name);

    diag("Creating container $name. It may take looong time the very first time.");
    $ravada->create_container($name,1);
#    ok(!$?),"Container $name created");

    return $name;
}


################################################################
test_new_container();
#test_remove_container();


done_testing();
