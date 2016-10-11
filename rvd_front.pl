#!/usr/bin/env perl
use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Getopt::Long;
use Hash::Util qw(lock_hash);
use Mojolicious::Lite;
use YAML qw(LoadFile);

use lib 'lib';

use Ravada::Front;
use Ravada::Auth;

my $help;
my $FILE_CONFIG = "/etc/ravada.conf";

GetOptions(
     'config=s' => \$FILE_CONFIG
         ,help  => \$help
     ) or exit;

if ($help) {
    print "$0 [--help] [--config=$FILE_CONFIG]\n";
    exit;
}

our $RAVADA = Ravada::Front->new(config => $FILE_CONFIG);
our $TIMEOUT = 10;
our $USER;

init();
############################################################################3

any '/' => sub {
    my $c = shift;
    return quick_start($c) if _logged_in($c);
    $c->redirect_to('/login');
};

any '/index.html' => sub {
    my $c = shift;
    return quick_start($c) if _logged_in($c);
    $c->redirect_to('/login');
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

get '/ip' => sub {
    my $c = shift;
    $c->render(template => 'bases', base => list_bases());
};

get '/ip/*' => sub {
    my $c = shift;
    _logged_in($c);
    my ($base_name) = $c->req->url->to_abs =~ m{/ip/(.*)};
    my $ip = $c->tx->remote_address();
    my $base = $RAVADA->search_domain($base_name);
    return quick_start_domain($c,$base->id,$ip);
};

any '/machines' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c)
        || !$USER->is_admin;

    return domains($c);
};


any '/machines/new' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c);
    return new_machine($c);
};

any '/users' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c);
    return users($c);

};

get '/list_vm_types.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_vm_types);
};

get '/list_bases.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_bases_data);
};

get '/list_images.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_iso_images);
};

get '/list_machines.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_domains);
};

get '/list_lxc_templates.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_lxc_templates);
};


# machine commands

get '/machine/info/*.json' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);

    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.json};
    die "No id " if !$id;
    $c->render(json => $RAVADA->search_domain($id));
};

any '/machine/manage/*html' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);

    return manage_machine($c);
};

get '/machine/view/*.html' => sub {
    my $c = shift;
    return view_machine($c);
};

get '/machine/clone/*.html' => sub {
    my $c = shift;
    return clone_machine($c);
};

get '/machine/shutdown/*.html' => sub {
        my $c = shift;
        return shutdown_machine($c);
};
any '/machine/remove/*.html' => sub {
        my $c = shift;
        return remove_machine($c);
};
get '/machine/prepare/*.html' => sub {
        my $c = shift;
        return prepare_machine($c);
};

##############################################
#

get '/request/*.html' => sub {
    my $c = shift;
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};

    return _show_request($c,$id);
};

get '/requests.json' => sub {
    my $c = shift;
    return list_requests($c);
};

any '/messages.html' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c);

    return messages($c);
};

get '/messages.json' => sub {
    my $c = shift;

    return $c->redirect_to('/login') if !_logged_in($c);

    return $c->render( json => [$USER->messages()] );
};

get '/messages/read/*.html' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};
    $USER->mark_message_read($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/view/*.html' => sub {
    my $c = shift;

    return $c->redirect_to('/login') if !_logged_in($c);

    my ($id_message) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};

    return $c->render( json => $USER->show_message($id_message) );
};


###################################################

sub _logged_in {
    my $c = shift;

    confess "missing \$c" if !defined $c;
    $USER = undef;

    my $login = $c->session('login');
    $USER = Ravada::Auth::SQL->new(name => $login)  if $login;

    $c->stash(_logged_in => $login );
    $c->stash(_user => $USER);

    return $USER;
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
        my $auth_ok;
        eval { $auth_ok = Ravada::Auth::login($login, $password)};
        if ( $auth_ok) {
            $c->session('login' => $login);
            return quick_start($c);
        } else {
            warn $@ if $@;
            push @error,("Access denied");
        }
    }
    $c->render(
                    template => 'bootstrap/start' 
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
    if ($c->param('submit')) {
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
    if ( $c->param('submit') && _logged_in($c) && defined $id_base ) {

        return quick_start_domain($c, $id_base, ($login or $c->session('login')));

    }

    $c->render(
                    template => 'bootstrap/logged' 
                    ,id_base => $id_base
                      ,login => $login 
                      ,error => \@error
    );
}

sub quick_start_domain {
    my ($c, $id_base, $name) = @_;

    confess "Missing id_base" if !defined $id_base;
    $name = $c->session('login')    if !$name;

    my $base = $RAVADA->search_domain_by_id($id_base) or die "I can't find base $id_base";

    my $domain_name = $base->name."-".$name;

    my $domain = $RAVADA->search_domain($domain_name);
    $domain = provision($c,  $id_base,  $domain_name)
        if !$domain;

    return show_failure($c, $domain_name) if !$domain;
    return show_link($c,$domain);

}

sub show_failure {
    my $c = shift;
    my $name = shift;
    $c->render(template => 'fail', name => $name);
}


#######################################################

sub domains {
    my $c = shift;

    my @error = ();

    $c->render(template => 'bootstrap/machines');

}

sub messages {
    my $c = shift;

    my @error = ();

    $c->render(template => 'bootstrap/messages');

}

sub users {
    my $c = shift;
    my @users = $RAVADA->list_users();
    $c->render(template => 'bootstrap/users'
        ,users => \@users
    );

}


sub new_machine {
    my $c = shift;
    my @error = ();
    my $ram = ($c->param('ram') or 2);
    my $disk = ($c->param('disk') or 8);
    my $backend = $c->param('backend');
    my $id_iso = $c->param('id_iso');
    my $id_template = $c->param('id_template');

    if ($c->param('submit')) {
        push @error,("Name is mandatory")   if !$c->param('name');
        return _show_request($c, req_new_domain($c))    if !@error;
    }
    warn join("\n",@error) if @error;

    $c->render(template => 'bootstrap/new_machine'
                    ,name => $c->param('name')
                    ,ram => $ram
                    ,disk => $disk
                    ,error => \@error
    );
};

sub req_new_domain {
    my $c = shift;
    my $name = $c->param('name');
    my $req = $RAVADA->create_domain(
           name => $name
        ,id_iso => $c->param('id_iso')
        ,id_template => $c->param('id_template')
        ,vm=> $c->param('backend')
        ,id_owner => $USER->id
    );

    return $req;
}

sub _show_request {
    my $c = shift;
    my $id_request = shift;

    my $request;
    if (!ref $id_request) {
        warn "opening request $id_request";
        eval { $request = Ravada::Request->open($id_request) };
        warn $@ if $@;
        return $c->render(data => "Request $id_request unknown")   if !$request;
    } else {
        $request = $id_request;
    }

    return $c->render(data => "Request $id_request unknown ".Dumper($request))
        if !$request->{id};

    $c->render(
         template => 'bootstrap/request'
        , request => $request
    );
    return if $request->status ne 'done';

    return $c->render(data => "Request $id_request error ".$request->error)
        if $request->error;

    my $name = $request->args('name');
    my $domain = $RAVADA->search_domain($name);

    if (!$domain) {
        return $c->render(data => "Request ".$request->status." , but I can't find domain $name");
    }
    return view_machine($c,$domain);
}

sub _search_req_base_error {
    my $name = shift;
}

sub access_denied {
    
    my $c = shift;

    return $c->render(text => 'Access denied to '.$c->req->url->to_abs->path.' for user '.$USER->name);
}

sub base_id {
    my $name = shift;
    my $base = $RAVADA->search_domain($name);

    return $base->id;
}

sub provision {
    my $c = shift;
    my $id_base = shift;
    my $name = shift;

    die "Missing id_base "  if !defined $id_base;
    die "Missing name "     if !defined $name;

    my $domain = $RAVADA->search_domain(name => $name);
    return $domain if $domain;

    warn "requesting the creation of $name";
    my $req = Ravada::Request->create_domain(
             name => $name
        , id_base => $id_base
        ,id_owner => $USER->id
    );
    $RAVADA->wait_request($req, 1);


    if ( $req->status ne 'done' ) {
        $c->stash(error => "Domain provisioning request ".$req->status);
        return;
    }
    $domain = $RAVADA->search_domain($name);
    if ( $req->error ) {
        $c->stash(error => $req->error) 
    } elsif (!$domain) {
        $c->stash(error => "I dunno why but no domain $name");
    }
    return $domain;
}

sub show_link {
    my $c = shift;
    my $domain = shift or confess "Missing domain";

    confess "Domain is not a ref $domain " if !ref $domain;

    return access_denied($c) if $USER->id != $domain->id_owner && !$USER->is_admin;

    if ( !$domain->is_active ) {
        my $req = Ravada::Request->start_domain($domain->name);

        $RAVADA->wait_request($req);
        warn "ERROR: ".$req->error if $req->error();

        return $c->render(data => 'ERROR starting domain '.$req->error)
            if $req->error && $req->error !~ /already running/i;

        return $c->redirect_to("/request/".$req->id.".html")
            if !$req->status eq 'done';
    }

    my $uri = $domain->display($USER) if $domain->is_active;
    if (!$uri) {
        my $name = '';
        $name = $domain->name if $domain;
        $c->render(template => 'fail', name => $domain->name);
        return;
    }
    $c->redirect_to($uri);
    $c->render(template => 'bootstrap/run', url => $uri , name => $domain->name
                ,login => $c->session('login'));
}


sub check_back_running {
    #TODO;
    return 1;
}

sub init {
    check_back_running() or warn "CRITICAL: rvd_back is not running\n";
}

sub _search_requested_machine {
    my $c = shift;
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};

    return show_failure($c,"I can't find id.html in ".$c->req->url->to_abs->path)
        if !$id;

    my $domain = $RAVADA->search_domain_by_id($id);
    if (!$domain ) {
        return show_failure($c,"I can't find domain id=$id");
    }
    return $domain;
}

sub manage_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my $domain = _search_requested_machine($c);
    if (!$domain) {
        return $c->render(text => "Domain no found");
    }
    return access_denied($c)    if $domain->id_owner != $USER->id
        && !$USER->is_admin;

    Ravada::Request->shutdown_domain($domain->name)   if $c->param('shutdown');
    Ravada::Request->start_domain($domain->name)   if $c->param('start');
    Ravada::Request->suspend_domain($domain->name)   if $c->param('pause');

    $c->stash(domain => $domain);
    $c->stash(uri => $c->req->url->to_abs);

    _enable_buttons($c, $domain);

    $c->render( template => 'bootstrap/manage_machine');
}

sub _enable_buttons {
    my $c = shift;
    my $domain = shift;
    $c->stash(_shutdown_disabled => '');
    $c->stash(_shutdown_disabled => 'disabled') if !$domain->is_active;

    $c->stash(_start_disabled => '');
    $c->stash(_start_disabled => 'disabled')    if $domain->is_active;

}

sub view_machine {
    my $c = shift;
    my $domain = shift;

    return login($c) if !_logged_in($c);

    $domain =  _search_requested_machine($c) if !$domain;
    return show_link($c, $domain);
}

sub clone_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my $base = _search_requested_machine($c);
    return quick_start_domain($c, $base->id);
}

sub shutdown_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my $base = _search_requested_machine($c);
    my $req = Ravada::Request->shutdown_domain($base->name);

    return $c->redirect_to('/machines');
}

sub _do_remove_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my $domain = _search_requested_machine($c);

    my $req = Ravada::Request->remove_domain(
        name => $domain->name
        ,uid => $USER->id
    );

    return $c->redirect_to('/machines');
}

sub remove_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);
    return _do_remove_machine($c,@_)   if $c->param('sure') && $c->param('sure') =~ /y/i;

    return $c->redirect_to('/machines')   if $c->param('sure')
                                            || $c->param('cancel');

    my $domain = _search_requested_machine($c);
    return $c->render( text => "Domain not found")  if !$domain;
    $c->stash(domain => $domain );

    warn "found domain ".$domain->name;

    return $c->render( template => 'bootstrap/remove_machine' );
}


sub prepare_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);

    my $domain = _search_requested_machine($c);

    my $req = Ravada::Request->prepare_base(
        name => $domain->name
        ,uid => $USER->id
    );

    $c->render(template => 'bootstrap/machines');

}

sub list_requests {
    my $c = shift;

    my $list_requests = $RAVADA->list_requests();
    $c->render(json => $list_requests);
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
<pre>ERROR: <%= my $error %></pre>

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
