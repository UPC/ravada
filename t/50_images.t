use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

my $ravada = Ravada->new( connector => connector()
    ,config => 't/etc/ravada.conf'
    ,pid_name => "ravada_install".base_domain_name());
$ravada->_install();
$ravada->_update_isos();
my @images = $ravada->list_images();

ok(scalar @images,"No images ".Dumper(\@images));

end();
done_testing();
