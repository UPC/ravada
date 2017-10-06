package Ravada::Auth::2FA;

# The function below are thanks to Gray Watson
# from https://github.com/j256/perl-two-factor-auth
# 
# ISC License
#
# Copyright 2017, Gray Watson
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use Digest::HMAC_SHA1 qw/ hmac_sha1_hex /;

=head1 NAME

Ravada::Auth:2FA - Second factor authentication library for Ravada

=cut

use Digest::HMAC_SHA1 qw/ hmac_sha1_hex /;

=head2 generateBase32Secret

Generate Base32 secret

	my $base32Secret = Ravada::Auth::2FA->generateBase32Secret();

=cut

sub generateBase32Secret {
    my @chars = ("A".."Z", "2".."7");
    my $length = scalar(@chars);
    my $base32Secret = "";
    for (my $i = 0; $i < 16; $i++) {
	$base32Secret .= $chars[rand($length)];
    }
    return $base32Secret;
}

=head2 generateCurrentNumber

Generate current number (Secret code)

	my $code = Ravada::Auth::2FA->generateCurrentNumber( $base32Secret );

=cut

sub generateCurrentNumber {
    my ($base32Secret) = @_;
    my $TIME_STEP = 30;
    srand(time() ^ $$);

    my $paddedTime = sprintf("%016x", int(time() / $TIME_STEP));

    my $data = pack('H*', $paddedTime);
    my $key = decodeBase32($base32Secret);

    my $hmac = hmac_sha1_hex($data, $key);

    my $offset = hex(substr($hmac, -1));
    my $encrypted = hex(substr($hmac, $offset * 2, 8)) & 0x7fffffff;

    my $token = $encrypted % 1000000;
    return sprintf("%06d", $token);
}

=head2 qrImageUrl

Generate QR Image URL

	my $url = Ravada::Auth::2FA->qrImageUrl( $keyId, $base32Secret );

=cut

sub qrImageUrl {
    my ($keyId, $base32Secret) = @_;
    my $otpUrl = "otpauth://totp/$keyId%3Fsecret%3D$base32Secret";
    return "https://chart.googleapis.com/chart?chs=200x200&cht=qr&chl=200x200&chld=M|0&cht=qr&chl=$otpUrl";
}

=head2 decodeBase32

Decode Base32

	my $key = decodeBase32($base32Secret);

=cut

sub decodeBase32 {
    my ($val) = @_;

    $val =~ tr|A-Z2-7|\0-\37|;
    $val = unpack('B*', $val);

    $val =~ s/000(.....)/$1/g;
    my $len = length($val);
    $val = substr($val, 0, $len & ~7) if $len & 7;

    $val = pack('B*', $val);
    return $val;
}

1;
