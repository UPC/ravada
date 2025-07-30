use warnings;
use strict;

use utf8;

use Carp qw(confess);
use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;


my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD);
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

########################################################################

sub _list_pos() {

    my @files;
    my $path = "lib/Ravada/I18N";
    opendir my $ls,$path or die $!;
    while (my $file = readdir $ls) {
        push @files,($file) if $file =~ /\.po$/
        && has_content("$path/$file");
    }
    close $ls;

    return @files;
}

sub has_content($file) {
    open my $in,"<",$file or die "$! $file";
    my $found=0;
    my $count=0;

    while (my $line= <$in>) {
        next if $line !~ /^msgstr "(.*)"/;
        $found++ if $1;
        $count++;
    }
    diag("No content found in $file: found=$found, count=$count") if !$found;
    return $found;
}

sub test_languages($t) {

    $t->get_ok('/translations')->status_is(200);

    my $result = decode_json($t->tx->res->body);
    $result->{'ca-valencia'} = delete $result->{'cat@valencia'};

    my @pos = _list_pos();
    my %pos = map { $_ => 1 } @pos;

    for my $lang (keys %$result) {
        ok($pos{"$lang.po"},"Mising po file for $lang");
    }

    for my $file (@pos) {
        my ($name) = $file =~ m{(.*)\.po$};
        ok($result->{$name},"Expecting $name listed in script/rvd_front");
    }
}

########################################################################

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);

my $t;
$t = Test::Mojo->new($SCRIPT);

my $user_name = new_domain_name();
my $user = create_user($user_name, $$);
mojo_login($t, $user_name, $$);

test_languages($t);

done_testing();
