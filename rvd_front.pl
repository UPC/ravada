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

our $DOCUMENT_ROOT = "/var/www";

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

any '/test' => sub {
    my $c = shift;
    my $logged = _logged_in($c);
    my $count = $c->session('count');
    $c->session(count => ++$count);

    my $name_mojo = $c->signed_cookie('mojolicious');

    my $dump_log = ''.(Dumper($logged) or '');
    return $c->render(text => "$count ".($name_mojo or '')."<br> ".$dump_log
        ."<br>"
        ."<script>alert(window.screen.availWidth"
        ."+\" \"+window.screen.availHeight)</script>"
    );
};

any '/logout' => sub {
    my $c = shift;
    $c->session(expires => 1);
    $c->session(login => undef);
    $c->redirect_to('/');
};

get '/anonymous' => sub {
    my $c = shift;
#    $c->render(template => 'bases', base => list_bases());
    $USER = _anonymous_user($c);
    return list_bases_anonymous($c);
};

get '/anonymous_logout.html' => sub {
    my $c = shift;
    $c->session('anonymous_user' => '');
    return $c->redirect_to('/');
};

get '/anonymous/*.html' => sub {
    my $c = shift;

    $c->stash(_anonymous => 1 , _logged_in => 0);
    my ($base_id) = $c->req->url->to_abs =~ m{/anonymous/(.*).html};
    my $base = $RAVADA->search_domain_by_id($base_id);

    $USER = _anonymous_user($c);
    return quick_start_domain($c,$base->id, $USER->name);
};

any '/machines' => sub {
    my $c = shift;

    return login($c)            if !_logged_in($c);
    return access_denied($c)    if !$USER->is_admin;

    return domains($c);
};


any '/machines/new' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c);
    return new_machine($c);
};

get '/domain/new.html' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c) || !$USER->is_admin();
    $c->stash(error => []);
    return $c->render(template => "bootstrap/new_machine");

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
    $c->render(json => $RAVADA->list_bases);
};

get '/list_images.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_iso_images);
};

get '/list_machines.json' => sub {
    my $c = shift;
    # shouldn't this be "list_bases" ?
    $c->render(json => $RAVADA->list_domains);
};

get '/list_bases_anonymous.json' => sub {
    my $c = shift;

    # shouldn't this be "list_bases" ?
    $c->render(json => $RAVADA->list_bases_anonymous(_remote_ip($c)));
};

get '/list_users.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_users);
};

get '/list_lxc_templates.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_lxc_templates);
};

get '/pingbackend.json' => sub {

    my $c = shift;
    $c->render(json => $RAVADA->ping_backend);
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
    return $c->redirect_to('/login') if !_logged_in($c);

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

get '/machine/shutdown/*.json' => sub {
        my $c = shift;
        return shutdown_machine($c);
};


any '/machine/remove/*.html' => sub {
        my $c = shift;
        return remove_machine($c);
};
get '/machine/prepare/*.json' => sub {
        my $c = shift;
        return prepare_machine($c);
};

get '/machine/screenshot/*.json' => sub {
        my $c = shift;
        return screenshot_machine($c);
};

get '/machine/pause/*.json' => sub {
        my $c = shift;
        return pause_machine($c);
};

get '/machine/resume/*.json' => sub {
        my $c = shift;
        return resume_machine($c);
};

get '/machine/start/*.json' => sub {
        my $c = shift;
        return start_machine($c);
};
##make admin

get '/users/make_admin/*.json' => sub {
       my $c = shift;
      return make_admin($c);
};

##remove admin

get '/users/remove_admin/*.json' => sub {
       my $c = shift;
       return remove_admin($c);
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

get '/messages/read/all.html' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);
    $USER->mark_all_messages_read;
    return $c->redirect_to("/messages.html");
};

get '/messages/read/*.html' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};
    $USER->mark_message_read($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/read/*.json' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.json};
    $USER->mark_message_read($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/unread/*.html' => sub {
    my $c = shift;
    return $c->redirect_to('/login') if !_logged_in($c);
    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};
    $USER->mark_message_unread($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/view/*.html' => sub {
    my $c = shift;

    return $c->redirect_to('/login') if !_logged_in($c);

    my ($id_message) = $c->req->url->to_abs->path =~ m{/(\d+)\.html};

    return $c->render( json => $USER->show_message($id_message) );
};


###################################################

sub _init_error {
    my $c = shift;
    $c->stash(error_title => '');
    $c->stash(error => []);
    $c->stash(link => '');
    $c->stash(link_msg => '');

}

sub _logged_in {
    my $c = shift;

    confess "missing \$c" if !defined $c;
    $USER = undef;

    _init_error($c);
    $c->stash(_logged_in => undef , _user => undef, _anonymous => 1);

    my $login = $c->session('login');
    $USER = Ravada::Auth::SQL->new(name => $login)  if $login;

    $c->stash(_logged_in => $login );
    $c->stash(_user => $USER);
    $c->stash(_anonymous => !$USER);

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
                    template => 'bootstrap/list_bases' 
                    ,id_base => $id_base
                      ,login => $login 
                  ,_anonymous => 0
                      ,error => \@error
    );
}

sub quick_start_domain {
    my ($c, $id_base, $name) = @_;

    return $c->redirect_to('/login') if !$USER;

    confess "Missing id_base" if !defined $id_base;
    $name = $c->session('login')    if !$name;

    my $base = $RAVADA->search_domain_by_id($id_base) or die "I can't find base $id_base";

    my $domain_name = $base->name."-".$name;
    my $domain = $RAVADA->search_clone(id_base => $base->id, id_owner => $USER->id);

    $domain = provision($c,  $id_base,  $domain_name)
        if !$domain;

    return show_failure($c, $domain_name) if !$domain;
    return show_link($c,$domain);

}

sub show_failure {
    my $c = shift;
    my $name = shift;
    $c->render(template => 'bootstrap/fail', name => $name);
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
    if ($c->param('submit')) {
        push @error,("Name is mandatory")   if !$c->param('name');
        req_new_domain($c);
        $c->redirect_to("/machines")    if !@error;
    }
    warn join("\n",@error) if @error;


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
        ,memory => int($c->param('memory')*1024*1024)
        ,disk => int($c->param('disk')*1024*1024*1024)
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
    my $msg = 'Access denied to '.$c->req->url->to_abs->path;

    $msg .= ' for user '.$USER->name if $USER;
    
    return $c->render(text => $msg);
}

sub base_id {
    my $name = shift;
    my $base = $RAVADA->search_domain($name);

    return $base->id;
}

sub provision {
    my $c = shift;
    my $id_base = shift;
    my $name = shift or confess "Missing name";

    die "Missing id_base "  if !defined $id_base;
    die "Missing name "     if !defined $name;

    my $domain = $RAVADA->search_domain(name => $name);
    return $domain if $domain;

    warn "requesting the creation of $name for ".$USER->id;

    my $req = Ravada::Request->create_domain(
             name => $name
        , id_base => $id_base
       , id_owner => $USER->id
    );
    $RAVADA->wait_request($req, 60);

    if ( $req->status ne 'done' ) {
        $c->stash(error_title => "Request ".$req->command." ".$req->status());
        $c->stash(error => 
            "Domain provisioning request not finished, status='".$req->status."'.");

        $c->stash(link => "/request/".$req->id.".html");
        $c->stash(link_msg => '');
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
        my $req = Ravada::Request->start_domain(name => $domain->name, uid => $USER->id);

        $RAVADA->wait_request($req);
        warn "ERROR: ".$req->error if $req->error();

        return $c->render(data => 'ERROR starting domain '.$req->error)
            if $req->error && $req->error !~ /already running/i;

        return $c->redirect_to("/request/".$req->id.".html")
            if !$req->status eq 'done';
    }
    if ( $domain->is_paused) {
        my $req = Ravada::Request->resume_domain(name => $domain->name, uid => $USER->id);

        $RAVADA->wait_request($req);
        warn "ERROR: ".$req->error if $req->error();

        return $c->render(data => 'ERROR resuming domain '.$req->error)
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
    my ($id,$type) = $c->req->url->to_abs->path =~ m{/(\d+)\.(\w+)$};

    return show_failure($c,"I can't find id in ".$c->req->url->to_abs->path)
        if !$id;

    my $domain = $RAVADA->search_domain_by_id($id) or do {
        $c->stash( error => "Unknown domain id=$id");
        return;
    };

    return ($domain,$type) if wantarray;
    return $domain;
}

sub make_admin {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+).json};
    
    warn "id usuari $id";
    
    Ravada::Auth::SQL::make_admin($id);
        
}

sub remove_admin {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+).json};
    
    warn "id usuari $id";
    
    Ravada::Auth::SQL::remove_admin($id);
        
}

sub manage_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain) = _search_requested_machine($c);
    if (!$domain) {
        return $c->render(text => "Domain no found");
    }
    return access_denied($c)    if $domain->id_owner != $USER->id
        && !$USER->is_admin;

    Ravada::Request->shutdown_domain(name => $domain->name, uid => $USER->id)   if $c->param('shutdown');
    Ravada::Request->start_domain(name => $domain->name, uid => $USER->id)   if $c->param('start');
    Ravada::Request->pause_domain(name => $domain->name, uid => $USER->id)   
        if $c->param('pause');

    Ravada::Request->resume_domain(name => $domain->name, uid => $USER->id)   if $c->param('resume');

    $c->stash(domain => $domain);
    $c->stash(uri => $c->req->url->to_abs);

    _enable_buttons($c, $domain);

    $c->render( template => 'bootstrap/manage_machine');
}

sub _enable_buttons {
    my $c = shift;
    my $domain = shift;
    warn "is_paused=".$domain->is_paused;
    if (($c->param('pause') && !$domain->is_paused)
        ||($c->param('resume') && $domain->is_paused)) {
        sleep 2;
        warn "  -> is_paused=".$domain->is_paused;
    }
    $c->stash(_shutdown_disabled => '');
    $c->stash(_shutdown_disabled => 'disabled') if !$domain->is_active;

    $c->stash(_start_disabled => '');
    $c->stash(_start_disabled => 'disabled')    if $domain->is_active;

    $c->stash(_pause_disabled => '');
    $c->stash(_pause_disabled => 'disabled')    if $domain->is_paused
                                                    || !$domain->is_active;

    $c->stash(_resume_disabled => '');
    $c->stash(_resume_disabled => 'disabled')    if !$domain->is_paused;



}

sub view_machine {
    my $c = shift;
    my $domain = shift;

    return login($c) if !_logged_in($c);

    $domain =  _search_requested_machine($c) if !$domain;
    return $c->render(template => 'bootstrap/fail') if !$domain;
    return show_link($c, $domain);
}

sub clone_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my $base = _search_requested_machine($c);
    if (!$base ) {
        $c->stash( error => "Unknown base ") if !$c->stash('error');
        return $c->render(template => 'bootstrap/fail');
    };
    return quick_start_domain($c, $base->id);
}

sub shutdown_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->shutdown_domain(name => $domain->name, uid => $USER->id);

    return $c->redirect_to('/machines') if $type eq 'html';
    return $c->render(json => { req => $req->id });
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


sub screenshot_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);

    warn ref($c);

    my $domain = _search_requested_machine($c);

    my $file_screenshot = "$DOCUMENT_ROOT/img/screenshots/".$domain->id.".png";
    my $req = Ravada::Request->screenshot_domain (
        id_domain => $domain->id
        ,filename => $file_screenshot
    );
    $c->render(json => { request => $req->id});
}

sub prepare_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);

    my $domain = _search_requested_machine($c);

    my $file_screenshot = "$DOCUMENT_ROOT/img/screenshots/".$domain->id.".png";
    if (! -e $file_screenshot && $domain->can_screenshot() ) {
        if ( !$domain->is_active() ) {
            Ravada::Request->start_domain( name => $domain->name
                ,uid => $USER->id
            );
            sleep 3;
        }
        Ravada::Request->screenshot_domain (
            id_domain => $domain->id
            ,filename => $file_screenshot
        );
    }

    my $req = Ravada::Request->prepare_base(
        id_domain => $domain->id
        ,uid => $USER->id
    );

    $c->render(json => { request => $req->id});

}

sub start_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->start_domain(name => $domain->name, uid => $USER->id);

    return $c->render(json => { req => $req->id });
}

sub pause_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->pause_domain(name => $domain->name, uid => $USER->id);

    return $c->render(json => { req => $req->id });
}

sub resume_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->resume_domain(name => $domain->name, uid => $USER->id);

    return $c->render(json => { req => $req->id });
}



sub list_requests {
    my $c = shift;

    my $list_requests = $RAVADA->list_requests();
    $c->render(json => $list_requests);
}

sub list_bases_anonymous {
    my $c = shift;

    my $bases_anonymous = $RAVADA->list_bases_anonymous(_remote_ip($c));

    return access_denied($c)    if !scalar @$bases_anonymous;

    $c->render(template => 'bootstrap/list_bases'
        , _logged_in => undef
        , _anonymous => 1
        , _user => undef
    );
}

sub _remote_ip {
    my $c = shift;
    return (
            $c->req->headers->header('X-Forwarded-For')
                or
            $c->req->headers->header('Remote-Addr')
                or
            $c->tx->remote_address
    );
}

sub _anonymous_user {
    my $c = shift;

    $c->stash(_user => undef);
    my $name = $c->session('anonymous_user');

    if (!$name) {
        $name = _new_anonymous_user($c);
        $c->session(anonymous_user => $name);
    }
    my $user= Ravada::Auth::SQL->new( name => $name );

    confess "user ".$user->name." has no id, may not be in table users"
        if !$user->id;

    return $user;
}

sub _random_name {
    my $length = shift;
    my $ret = 'O'.substr($$,3);
    my $max = ord('z') - ord('a');
    for ( 0 .. $length ) {
        my $n = int rand($max + 1);
        $ret .= chr(ord('a') + $n);
    }
    return $ret;
}

sub _new_anonymous_user {
    my $c = shift;

    my $name_mojo = $c->signed_cookie('mojolicious');
    $name_mojo = _random_name(32)    if !$name_mojo;

    $name_mojo =~ tr/[^a-z][^A-Z][^0-9]/___/c;

    my $name;
    for my $n ( 4 .. 32 ) {
        $name = substr($name_mojo,0,$n);
        my $user;
        eval { 
            $user = Ravada::Auth::SQL->new( name => $name );
            $user = undef if !$user->id;
        };
        last if !$user;
    }
    warn "\n*** creating temporary user $name";
    Ravada::Auth::SQL::add_user(name => $name, is_temporary => 1);

    return $name;
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
