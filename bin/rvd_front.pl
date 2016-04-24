#!/usr/bin/env perl
use warnings;
use strict;

use Data::Dumper;
use DBIx::Connector;
use Mojolicious::Lite;

use lib 'lib';

use Ravada::Auth::LDAP;

our $HOST = 'vsertel.upc.es';

our $CON = DBIx::Connector->new("DBI:mysql:ravada"
                        ,undef,undef,{RaiseError => 1
                        , PrintError=> 0 }) or die "I can't connect";

our $TIMEOUT = 120;

any '/' => sub {
  my $c = shift;
    my $login = ($c->param('login') or '');
    my $password = ($c->param('login') or '');
    my $id_base = ($c->param('id_base') or 1);

    if ( $login ) {
        if (Ravada::Auth::LDAP::login($login, $password)) {
            return show_link($c, $id_base, $login);
        }
    }
    $c->render(login => $login ,template => 'index' , id_base => $id_base
                    , base => list_bases());
};

get '/ip' => sub {
    my $c = shift;
    $c->render(template => 'bases', base => list_bases());
};

get '/ip/*' => sub {
    my $c = shift;
    my ($base_name) = $c->req->url->to_abs =~ m{/ip/(.*)};
    my $ip = $c->tx->remote_address();
    show_link($c,base_id($base_name),$ip);
};

#######################################################

sub base_id {
    my $name = shift;

    my $sth = $CON->dbh->prepare("SELECT id FROM bases WHERE name=?");
    $sth->execute($name);
    my ($id) =$sth->fetchrow;
    die "CRITICAL: Unknown base $name" if !defined $id;
    return $id;
}

sub find_uri {
    my $host = shift;
    my $url = `virsh domdisplay $host`;
    warn $url;
    chomp $url;
    return $url;
}

sub provisiona {
    my $c = shift;
    my $id_base = shift;
    my $name = shift;

    die "Missing id_base "  if !defined $id_base;
    die "Missing name "     if !defined $name;

    my $dbh = $CON->dbh;
    my $sth = $dbh->prepare("INSERT INTO domains ( id_base,name) VALUES (?,?)");
    $sth->execute($id_base, $name);
    $sth->finish;

    if (wait_node_up($c,$name)) {
        return find_uri($name);
    }

}

sub wait_node_up {
    my ($c, $name) = @_;

    my $dbh = $CON->dbh;
    my $sth = $dbh->prepare(
        "SELECT created, error, uri FROM domains where name=?"
    );

    for (1 .. $TIMEOUT) {
        sleep 1;
        $sth->execute($name);
        my ($created, $error, $uri ) = $sth->fetchrow;
        warn "$_ : ".$created." ".($error or '');
        if ($error) {
            $c->stash(error => $error) if $error;
            last;
        }
        return $uri if $created !~ /n/i;
    }
}

sub raise_node {
    my ($c, $id_base, $name) = @_;

    my $dbh = $CON->dbh;
    my $sth = $dbh->prepare(
        "SELECT id FROM domains WHERE name=? "
        ." AND id_base=?"
    );
    $sth->execute($name, $id_base);
    my ($id) = $sth->fetchrow;
    $sth->finish;
    warn "Found $id " if $id;
    return provisiona(@_) if !$id;

    $sth = $dbh->prepare(
        "INSERT INTO domains_req (id_domain,start,date_req) "
        ." VALUES (?,'y',NOW())"
    );
    $sth->execute($id);

    $sth = $dbh->prepare("SELECT last_insert_id() FROM domains_req");
    $sth->execute;
    my ($id_request) = $sth->fetchrow or die "Missing last insert id";

    return wait_request_done($c,$id_request);
}

sub wait_request_done {
    my ($c, $id) = @_;
    
    my $req;
    my $sth = $CON->dbh->prepare(
        "SELECT r.* , name "
        ." FROM domains_req r, domains d "
        ." WHERE r.id=? AND r.id_domain = d.id "
    );
    for ( 1 .. $TIMEOUT ) {
        $sth->execute($id);
        $req = $sth->fetchrow_hashref;
        $c->stash(error => $req->{error})   if $req->{error};
        last if $req->{id} && $req->{done};
        sleep 1;
    }
    return 0 if $req->{error};
    return find_uri($req->{name});
}

sub base_name {
    my $id_base = shift;

    my $sth = $CON->dbh->prepare("SELECT name FROM bases where id=?");
    $sth->execute($id_base);
    return $sth->fetchrow;
}

sub show_link {
    my $c = shift;
    my ($id_base, $name) = @_;

    my $base_name = base_name($id_base)
        or die "Unkown id_base '$id_base'";

    my $host = $base_name."-".$name;

    my $uri = ( find_uri($host) or raise_node($c, $id_base,$host));
    if (!$uri) {
        $c->render(template => 'fail', name => $host);
        return;
    }
    $c->redirect_to($uri);
    $c->render(template => 'run', url => $uri , name => $name);
}

sub list_bases {
    my $dbh = $CON->dbh();
    my $sth = $dbh->prepare(
        "SELECT id, name FROM bases"
        ." ORDER BY id"
    );
    $sth->execute;
    my %base;
    while ( my ($id,$name) = $sth->fetchrow) {
        $base{$id} = $name;
    }
    $sth->finish;
    return \%base;
}

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
<h1>Welcome to SPICE !</h1>

<form method="post">
    Name: <input name="login" value ="<%= $login %>" 
            type="text"><br/>
    Base: <select name="id_base">
%       for my $option (sort keys %$base) {
            <option value="<%= $option %>"><%= $base->{$option} %></option>
%       }
    </select><br/>
    <input type="submit" value="launch">
</form>

@@ bases.html.ep
% layout 'default';
<h1>Choose a base</h1>

<ul>
% for my $i (sort values %$base) {
    <li><a href="/ip/<%= $i %>"><%= $i %></a></li>
% }
</ul>

@@ run.html.ep
% layout 'default';
<h1>Run</h1>

Hi <%= $name %>, 
<a href="<%= $url %>">click here</a>

@@ fail.html.ep
% layout 'default';
<h1>Fail</h1>

Sorry <%= $name %>, I couldn't make it.
<pre>ERROR: <%= $error %></pre>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body>
    <%= content %>
    <hr>
        <h2>Requirements</h1>
            <ul>
            <li>Linux: virt-viewer</li>
            <li>Windows: <a href="http://bfy.tw/5Nur">Spice plugin for Firefox</a></li>
            </ul>
        </h2>
  </body>
</html>
