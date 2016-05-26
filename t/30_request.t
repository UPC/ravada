use warnings;
use strict;

use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Request');

my $test = Test::SQL::Data->new(config => 't/etc/ravada.conf');

my $ravada = Ravada->new(connector => $test->connector);

my ($DOMAIN_NAME) = $0 =~ m{.*/(.*)\.};
my $DOMAIN_NAME_SON=$DOMAIN_NAME."_son";

sub test_empty_request {
    my $request = $ravada->request();
    ok($request);
}

sub test_remove_domain {
    my $name = shift;

    my $domain = $name if ref($name);
    $domain = $ravada->search_domain($name);

    if ($domain) {
        diag("Removing domain $name");
        eval { $domain->remove() };
        ok(!$@ , "Error removing domain $name : $@") or exit;

        ok(! -e $domain->file_base_img ,"Image file was not removed "
                    . $domain->file_base_img )
                if  $domain->file_base_img;

    }
    $domain = $ravada->search_domain($name);
    ok(!$domain, "I can't remove old domain $name") or exit;

}

sub test_req_create_domain_iso {

    my $name = $DOMAIN_NAME."_iso";
    my $req = Ravada::Request->create_domain( 
        name => $name
        ,id_iso => 1
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name");
    return $domain;
}

sub test_req_create_base {

    my $name = $DOMAIN_NAME."_base";
    my $req = Ravada::Request->create_domain( 
        name => $name
        ,id_iso => 1
        ,is_base => 1
    );
    ok($req);
    ok($req->status);
    ok(defined $req->args->{name} 
        && $req->args->{name} eq $name
            ,"Expecting args->{name} eq $name "
             ." ,got '".($req->args->{name} or '<UNDEF>')."'");

    ok($req->status eq 'requested'
        ,"Status of request is ".$req->status." it should be requested");

    $ravada->process_requests();

    ok($req->status eq 'done'
        ,"Status of request is ".$req->status." it should be done");
    ok(!$req->error,"Error ".$req->error." creating domain ".$name);

    my $domain =  $ravada->search_domain($name);

    ok($domain,"I can't find domain $name");
    ok($domain && $domain->is_base,"Domain $name should be base");
    return $domain;
}


sub test_req_remove_domain_obj {
    my $domain = shift;

    my $req = Ravada::Request->remove_domain($domain);
    $ravada->process_requests();

    my $domain2 =  $ravada->search_domain($domain->name);
    ok(!$domain2,"Domain ".$domain->name." should be removed");
    ok(!$req->error,"Error ".$req->error." removing domain ".$domain->name);

}

sub test_req_remove_domain_name {
    my $name = shift;

    my $req = Ravada::Request->remove_domain($name);

    $ravada->process_requests();

    my $domain =  $ravada->search_domain($name);
    ok(!$domain,"Domain $name should be removed");
    ok(!$req->error,"Error ".$req->error." removing domain $name");

}


################################################

test_remove_domain($DOMAIN_NAME."_iso");

{
    my $domain = test_req_create_domain_iso();
    test_req_remove_domain_obj($domain)         if $domain;
}

{
    my $domain = test_req_create_domain_iso();
    test_req_remove_domain_name($domain->name)  if $domain;
}

{
    my $domain = test_req_create_base();
    test_req_remove_domain_name($domain->name)  if $domain;
}


test_remove_domain($DOMAIN_NAME."_iso");

done_testing();
