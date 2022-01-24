use warnings;
use strict;

use Data::Dumper;
use Test::More;

use HTML::Lint;
use Mojo::DOM;

no warnings "experimental::signatures";
use feature qw(signatures);

sub _check_count_divs($url, $content) {
    my $n = 0;
    my $open = 0;
    for my $line (split /\n/,$content) {
        $n++;
        die "Error: too many divs" if $line =~ m{<div.*<div.*<div};

        next if $line =~ m{<div.*<div.*/div>.*/div>};

        $open++ if $line =~ /<div/;
        $open-- if $line =~ m{</div};

        last if $open<0;
    }
    ok(!$open,"$open open divs in $url line $n") ;
}

sub _remove_embedded_perl($content) {
    my $return = '';
    my $changed = 0;
    for my $line (split /\n/,$$content) {
        if ($line =~ /<%=/) {
            $line =~ s/(.*)<%=.*?%>(.*)/$1$2/;
            $changed++;
        }
        $return .= "$line\n";
    }
    $$content = $return if $changed;
}

sub test_validate_html_local($dir) {
    opendir my $ls,$dir or die "$! $dir";
    while (my $file = readdir $ls) {
        next unless $file =~ /html$/ || $file =~ /.html.ep$/;
        my $path = "$dir/$file";
        open my $in,"<", $path or die "$path";
        my $content = join ("",<$in>);
        close $in;
        _check_html_lint($path,$content, {internal => 1});
    }
}

sub _check_html_lint($url, $content, $option = {}) {
    _remove_embedded_perl(\$content);
    _check_count_divs($url, $content);

    my $lint = HTML::Lint->new;
    #    $lint->only_types( HTML::Lint::Error::STRUCTURE );
    $lint->parse( $content );
    $lint->eof();

    my @errors;
    my @warnings;

    for my $error ( $lint->errors() ) {
        next if $error->errtext =~ /Entity .*is unknown/;
        next if $option->{internal} && $error->errtext =~ /(body|head|html|title).*required/;
        if ( $error->errtext =~ /Unknown element <(footer|header|nav|ldap-groups)/
            || $error->errtext =~ /Entity && is unknown/
            || $error->errtext =~ /should be written as/
            || $error->errtext =~ /Unknown attribute.*%/
            || $error->errtext =~ /Unknown attribute "ng-/
            || $error->errtext =~ /Unknown attribute "(aria|align|autofocus|data-|href|novalidate|placeholder|required|tabindex|role|uib-alert)/
            || $error->errtext =~ /img.*(has no.*attributes|does not have ALT)/
            || $error->errtext =~ /Unknown attribute "(min|max).*input/ # Check this one
            || $error->errtext =~ /Unknown attribute "(charset|crossorigin|integrity)/
            || $error->errtext =~ /Unknown attribute "image.* for tag <div/
            || $error->errtext =~ /Unknown attribute "ipaddress"/
            || $error->errtext =~ /Unknown attribute "sizes" for tag .link/
            || $error->errtext =~ /Unknown attribute "(autocomplete|uib|typeahead).*?" for tag .input/
         ) {
             next;
         }
        if ($error->errtext =~ /attribute.*is repeated/
            || $error->errtext =~ /Unknown attribute/
            # TODO next one
            #|| $error->errtext =~ /img.*(has no.*attributes|does not have ALT)/
            || $error->errtext =~ /attribute.*is repeated/
        ) {
            push @warnings, ($error);
            next;
        }
        push @errors, ($error)
    }
    ok(!@errors, $url) or do {
        my $file_out = $url;
        $url =~ s{^/}{};
        $file_out =~ s{/}{_}g;
        $file_out = "/var/tmp/$file_out";
        open my $out, ">", $file_out or die "$! $file_out";
        print $out $content;
        close $out;
        die "Stored in $file_out\n".Dumper([ map { [$_->where,$_->errtext] } @errors ]);
    };
    ok(!@warnings,$url) or warn Dumper([ map { [$_->where,$_->errtext] } @warnings]);


}

sub _load_file($name) {
    open my $in,"<",$name or die "$! $name";
    my $string = join("",<$in>);
    close $in;
    return $string;
}

sub test_form_new_machine() {
    my $file = "templates/ng-templates/new_machine_template.html.ep";

    my $dom = Mojo::DOM->new(_load_file($file));
    my $form_name = 'new_machineForm';
    my $form = $dom->find('form')->grep( sub {$_->attr('name') eq $form_name});
    ok($form->[0], "Expecting form name=$form_name") or return;
    for my $name ('id_iso', 'name', 'iso_file', 'memory','disk'
        , '_advanced_options'
        , 'swap', 'data') {
        my $inputs = $form->[0]->find("input")
        ->grep( sub { $_->attr('name') eq $name } );
        ok($inputs->[0],"Expecting input name='$name' in $file");
    }

}

##################################################################3

test_form_new_machine();
test_validate_html_local("templates/bootstrap");
test_validate_html_local("templates/main");
test_validate_html_local("templates/ng-templates");

done_testing();
