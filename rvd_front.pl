#!/usr/bin/env perl
use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use DBIx::Connector;
use Getopt::Long;
use Hash::Util qw(lock_hash);
use Mojolicious::Lite;
use YAML qw(LoadFile);

use lib 'lib';

use Ravada::Auth;

my $FILE_CONFIG = "/etc/ravada.conf";
my $help;
GetOptions(
        config => \$FILE_CONFIG
         ,help  => \$help
     ) or exit;

if ($help) {
    print "$0 [--help] [--config=$FILE_CONFIG]\n";
    exit;
}

our $CONFIG = LoadFile($FILE_CONFIG);
our $CON;

our $TIMEOUT = 120;

init();
############################################################################3

any '/' => sub {
    my $c = shift;

    return quick_start($c);
};

any '/login' => sub {
    my $c = shift;
    return login($c);
};

any '/logout' => sub {
    my $c = shift;
    $c->session(expires => 1);
    $c->session(login => undef);
    $c->redirect_to('/');
};

sub _logged_in {
    my $c = shift;
    $c->stash(_logged_in => $c->session('login'));
    return 1 if $c->session('login');
}

sub login {
    my $c = shift;

    return quick_start($c)    if _logged_in($c);

    my $login = $c->param('login');
    my $password = $c->param('password');
    my @error =();
    if ($c->param('submit') && $login) {
        push @error,("Empty login name")  if !length $login;
        push @error,("Empty password")  if !length $password;
    }

    if ( $login && $password ) {
        if (Ravada::Auth::login($login, $password)) {
            $c->session('login' => $login);
            return quick_start($c);
        } else {
            push @error,("Access denied");
        }
    }
    $c->render(
                    template => 'bootstrap/login' 
                      ,login => $login 
                      ,error => \@error
    );

}

sub quick_start {
    my $c = shift;

    _logged_in($c);

    my $login = $c->param('login');
    my $password = $c->param('password');
    my $id_base = $c->param('id_base');

    my @error =();
    if ($c->param('submit') && $login) {
        push @error,("Empty login name")  if !length $login;
        push @error,("Empty password")  if !length $password;
    }

    if ( $login && $password ) {
        if (Ravada::Auth::login($login, $password)) {
            $c->session('login' => $login);
        } else {
            push @error,("Access denied");
        }
    }
    return show_link($c, $id_base, $login)
        if $c->param('submit') && _logged_in($c) && defined $id_base;

    $c->render(
                    template => 'bootstrap/start' 
                    ,id_base => $id_base
                      ,login => $login 
                      ,error => \@error
                       ,base => list_bases()
    );
}

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

any '/bases' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c);
    my @error = ();
    $c->render(template => 'bootstrap/new_base'
                    ,image => _list_images()
                    ,error => \@error
    );
};

#######################################################

sub access_denied {
    my $c = shift;
    $c->render(data => "Access denied");
}

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

    confess "Empty id_base" if !$id_base;

    my $base_name = base_name($id_base)
        or die "Unkown id_base '$id_base'";

    my $host = $base_name."-".$name;

    my $uri = ( find_uri($host) or raise_node($c, $id_base,$host));
    if (!$uri) {
        $c->render(template => 'fail', name => $host);
        return;
    }
    $c->redirect_to($uri);
    $c->render(template => 'bootstrap/run', url => $uri , name => $name
                ,login => $c->session('login'));
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

sub _list_images {
    my $dbh = $CON->dbh();
    my $sth = $dbh->prepare(
        "SELECT * FROM iso_images"
        ." ORDER BY name"
    );
    $sth->execute;
    my %image;
    while ( my $row = $sth->fetchrow_hashref) {
        $image{$row->{id}} = $row;
    }
    $sth->finish;
    lock_hash(%image);
    return \%image;
}


sub _init_db {
    my $db_user = ($CONFIG->{db}->{user} or getpwnam($>));;
    my $db_password = ($CONFIG->{db}->{password} or undef);
    $CON = DBIx::Connector->new("DBI:mysql:ravada"
                        ,$db_user,$db_password,{RaiseError => 1
                        , PrintError=> 0 }) or die "I can't connect";


}

sub init {
    _init_db();
    Ravada::Auth::init($CONFIG,$CON);
}

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
<h1>Welcome to SPICE !</h1>

<form method="post">
    User Name: <input name="login" value ="<%= $login %>" 
            type="text"><br/>
    Password: <input type="password" name="password" value=""><br/>
    Base: <select name="id_base">
%       for my $option (sort keys %$base) {
            <option value="<%= $option %>"><%= $base->{$option} %></option>
%       }
    </select><br/>
    
    <input type="submit" name="submit" value="launch">
</form>
% if (scalar @$error) {
        <ul>
%       for my $i (@$error) {
            <li><%= $i %></li>
%       }
        </ul>
% }

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
