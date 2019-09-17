#!/usr/bin/env perl

use warnings;
use strict;

use Data::Dumper;
use Getopt::Long;
use JSON::XS qw(decode_json);

use lib './lib';

use Ravada;
use Ravada::Request;
use Ravada::Utils;

no warnings "experimental::signatures";
use feature qw(signatures);

my $ME = $0;
$ME =~ s{.*/}{};

my $USAGE = $ME." command [--help] [--wait] [options]\n"
."  - help: Help and usage message\n"
."  - wait: Wait for request to complete"
;

my ($command) = shift @ARGV if $ARGV[0] && $ARGV[0] !~ /^-/;
my $WAIT;
my $HELP;

my %option;

$command =~ s/-/_/g if $command;

GetOptions(\%option, valid_options($command)) or exit;

$HELP= delete $option{help} if exists $option{help};
$command = shift @ARGV if !$command && $HELP && $ARGV[0];
$command =~ s/-/_/g if $command;

help($command, $option{doc}) if $HELP;

die "$USAGE\n" if !defined $command;

$WAIT= delete $option{wait} if exists $option{wait};

#################################################################

sub valid_options($command) {
    my @options = ('wait','help','doc=s');
    return @options if !$command;

    my $definition = Ravada::Request::valid_args($command)
        or die "Error: Unknown command $command\n";

    for my $field ( keys %$definition ) {
        $field =~ s/_/-/g;
        if ($field eq 'uid' || $field =~ /^id_/ || $field =~ /^(at|timeout)$/) {
            $field .= "=i";
        } else {
            $field .= "=s";
        }
        push @options,$field;
    }
    return @options;
}

sub help($command, $format=undef) {
    if ($format && $format eq 'rst') {
        print $ME;
        print " $command"  if $command;
        print "\n".("=" x 4)."\n";
    }
    print "$USAGE\n" if !$format || !$command;
    if (!$command) {
        print "\nCommands:\n".('-' x 4)."\n";
        my %valid = Ravada::Request::valid_args();
        for my $field ( sort keys %valid ) {
            print "- $field\n";
        }
        exit;
    }
    my $definition = Ravada::Request::valid_args_cli($command)
        or die "Error: Unknown command $command\n";
    delete $definition->{uid};

    print "\n$command\n".("=" x length($command))."\n";

    my @mandatory = grep { $definition->{$_} == 1 } keys %$definition;
    if (@mandatory) {
        print "Mandatory arguments:\n".('-' x 4)."\n";
        for my $option( sort @mandatory ) {
            next if $definition->{$option} != 1;
            print "- $option".info($option)."\n";
            delete $definition->{$option};
        }
        print "\n";
    }
    if (keys %$definition) {
        print "Optional arguments:\n".('-' x 4)."\n";
        for my $option( sort keys %$definition ) {
            print "- $option".info($option)."\n";
        }
    }
    exit;
}

sub info($option) {
    my %info = (
        uid => "User id that executes the request"
        , at => 'Run at a given time. Format time is seconds since epoch'
        ,after_request =>  'Run after request specified by id is done'
        , id_domain => "Id of the domain or virtual machine"
    );
    my $text = $info{$option};
    return '' if !$text;
    return ": $text";
}

sub fix_options_slash($option) {
    for my $field ( keys %$option ) {
        if ($field =~ /-/) {
            my $field2 = $field;
            $field2 =~ s/-/_/g;
            $option->{$field2} = $option->{$field};
            delete $option->{$field};
        }
    }
}

sub extract_data($option) {
    my $json = $option->{data};
    my $data = decode_json($json);
    $option->{data} = $data;
}

#################################################################

my $RVD_BACK = Ravada->new();

$option{uid} = Ravada::Utils::user_daemon->id if !exists $option{uid};

fix_options_slash(\%option);
extract_data(\%option) if $option{data};

my $request = Ravada::Request->new_request(
    $command
    ,%option
);

print "Requested $command id=".$request->id."\n";
exit if !$WAIT;

my $msg = '';
my $t0 = time;
for (;;) {
    my $msg_curr = $request->status;
    if($request->error) {
        $msg_curr .=" ".$request->error;
    }
    if ($msg_curr ne $msg || time - $t0 > 2) {
        print localtime." ".$msg_curr."\n";
        $msg = $msg_curr;
        $t0 = time;
        next;
    }
    last if $request->status eq 'done';
    sleep 1;
}
print $request->output."\n" if defined $request->output;
