#!/usr/bin/env perl
use warnings;
use strict;
#####
use locale ':not_characters';
#####
use Carp qw(confess);
use Data::Dumper;
use Getopt::Long;
use Hash::Util qw(lock_hash);
use Mojolicious::Lite 'Ravada::I18N';
#####
#my $self->plugin('I18N');
#package Ravada::I18N:en;
#####

use YAML qw(LoadFile);

use lib 'lib';

use Ravada::Front;
use Ravada::Auth;
use POSIX qw(locale_h);

my $help;
my $FILE_CONFIG = "/etc/ravada.conf";

plugin Config => { file => 'rvd_front.conf' };
#####
#####
#####
# Import locale-handling tool set from POSIX module.
# This example uses: setlocale -- the function call
#                    LC_CTYPE -- explained below

# query and save the old locale
my $old_locale = setlocale(LC_CTYPE);

setlocale(LC_CTYPE, "en_US.ISO8859-1");
# LC_CTYPE now in locale "English, US, codeset ISO 8859-1"

setlocale(LC_CTYPE, "");
# LC_CTYPE now reset to default defined by LC_ALL/LC_CTYPE/LANG
# environment variables.  See below for documentation.

# restore the old locale
setlocale(LC_CTYPE, $old_locale);
#####
#####
#####
plugin I18N => {namespace => 'Ravada::I18N', default => 'en'};


GetOptions(
     'config=s' => \$FILE_CONFIG
         ,help  => \$help
     ) or exit;

if ($help) {
    print "$0 [--help] [--config=$FILE_CONFIG]\n";
    exit;
}

our $RAVADA = Ravada::Front->new(config => $FILE_CONFIG);
our $USER;

# TODO: get those from the config file
our $DOCUMENT_ROOT = "/var/www";
our $SESSION_TIMEOUT = 300;

init();
############################################################################3

hook before_routes => sub {
  my $c = shift;

  my $url = $c->req->url;

  return access_denied($c)
    if $url =~ /\.json/
    && !_logged_in($c);

  return login($c)
    if     $url !~ /\.css$/
        && $url !~ m{^/(anonymous|login|logout)}
        && $url !~ m{^/(font|img|js)}
        && !_logged_in($c);


};


############################################################################3

any '/' => sub {
    my $c = shift;
    return quick_start($c);
};

any '/index.html' => sub {
    my $c = shift;
    return quick_start($c);
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
    logout($c);
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

get '/anonymous/(#base_id).html' => sub {
    my $c = shift;

    $c->stash(_anonymous => 1 , _logged_in => 0);
    _init_error($c);
    my $base_id = $c->stash('base_id');
    my $base = $RAVADA->search_domain_by_id($base_id);

    $USER = _anonymous_user($c);
    return quick_start_domain($c,$base->id, $USER->name);
};

any '/machines' => sub {
    my $c = shift;

    return access_denied($c)    if !$USER->is_admin;

    return domains($c);
};


any '/machines/new' => sub {
    my $c = shift;

    return access_denied($c)    if !$USER->is_admin;

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

    return access_denied($c) if !_logged_in($c) || !$USER->is_admin;
    return users($c);

};

get '/list_vm_types.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_vm_types);
};

get '/list_bases.json' => sub {
    my $c = shift;

    my $domains = $RAVADA->list_bases();
    my @domains_show = @$domains;
    if (!$USER->is_admin) {
        @domains_show = ();
        for (@$domains) {
            push @domains_show,($_) if $_->{is_public};
        }
    }
    $c->render(json => [@domains_show]);

};

get '/list_images.json' => sub {
    my $c = shift;
    $c->render(json => $RAVADA->list_iso_images);
};

get '/list_machines.json' => sub {
    my $c = shift;

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

get '/machine/info/(#id).json' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    die "No id " if !$id;
    $c->render(json => $RAVADA->domain_info(id => $id));
};

any '/machine/manage/([^/]+).html' => sub {
    my $c = shift;

    return manage_machine($c);
};

get '/machine/view/([^/]+).html' => sub {
    my $c = shift;

    return view_machine($c);
};

get '/machine/clone/([^/]+).html' => sub {
    my $c = shift;
    return clone_machine($c);
};

get '/machine/shutdown/([^/]+).html' => sub {
        my $c = shift;
        return shutdown_machine($c);
};

get '/machine/shutdown/([^/]+).json' => sub {
        my $c = shift;
        return shutdown_machine($c);
};


any '/machine/remove/([^/]+).html' => sub {
        my $c = shift;
        return remove_machine($c);
};
get '/machine/prepare/([^/]+).json' => sub {
        my $c = shift;
        return prepare_machine($c);
};

get '/machine/remove_b/([^/]+).json' => sub {
        my $c = shift;
        return remove_base($c);
};

get '/machine/remove_base/([^/]+).json' => sub {
    my $c = shift;
    return remove_base($c);
};

get '/machine/screenshot/([^/]+).json' => sub {
        my $c = shift;
        return screenshot_machine($c);
};

get '/machine/pause/([^/]+).json' => sub {
        my $c = shift;
        return pause_machine($c);
};

get '/machine/resume/([^/]+).json' => sub {
        my $c = shift;
        return resume_machine($c);
};

get '/machine/start/([^/]+).json' => sub {
        my $c = shift;
        return start_machine($c);
};

get '/machine/exists/#name' => sub {
    my $c = shift;
    my $name = $c->stash('name');
    #TODO
    # return failure if it can't find the name in the URL

    return $c->render(json => $RAVADA->domain_exists($name));

};

get '/machine/rename/([^/]+)' => sub {
    my $c = shift;
    return rename_machine($c);
};

any '/machine/copy' => sub {
    my $c = shift;
    return copy_machine($c);
};

get '/machine/public/([^/]+)' => sub {
    my $c = shift;
    return machine_is_public($c);
};

# Users ##########################################################3

##make admin

get '/users/make_admin/([^/]+).json' => sub {
       my $c = shift;
      return make_admin($c);
};

##remove admin

get '/users/remove_admin/([^/]+).json' => sub {
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
    return messages($c);
};

get '/messages.json' => sub {
    my $c = shift;


    return $c->render( json => [$USER->messages()] );
};

get '/unshown_messages.json' => sub {
    my $c = shift;

    return $c->redirect_to('/login') if !_logged_in($c);

    return $c->render( json => [$USER->unshown_messages()] );
};


get '/messages/read/all.html' => sub {
    my $c = shift;
    $USER->mark_all_messages_read;
    return $c->redirect_to("/messages.html");
};

get '/messages/read/(#id).json' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    warn 'JSON';
    warn $id;
    $USER->mark_message_read($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/read/(#id).html' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    warn 'HTML';
    warn $id;
    $USER->mark_message_read($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/unread/(#id).html' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    $USER->mark_message_unread($id);
    return $c->redirect_to("/messages.html");
};

get '/messages/view/(#id).html' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    return $c->render( json => $USER->show_message($id) );
};

any '/about' => sub {
    my $c = shift;

    $c->stash(version => $RAVADA->version );

    $c->render(template => 'bootstrap/about');
};


any '/requirements' => sub {
    my $c = shift;

    $c->render(template => 'bootstrap/requirements');
};


any '/settings' => sub {
    my $c = shift;

    $c->stash(version => $RAVADA->version );

    $c->render(template => 'bootstrap/settings');
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
    $c->stash(url => undef);

    return $USER;
}


sub login {
    my $c = shift;

    $c->session(login => undef);

    my $login = $c->param('login');
    my $password = $c->param('password');
    my $url = ($c->param('url') or $c->req->url->to_abs->path);
    $url = '/' if $url =~ m{^/login};

    my @error =();
    if (defined $login || defined $password || $c->param('submit')) {
        push @error,("Empty login name")  if !length $login;
        push @error,("Empty password")  if !length $password;
    }

    if (defined $login && defined $password && length $login && length $password ) {
        my $auth_ok;
        eval { $auth_ok = Ravada::Auth::login($login, $password)};
        if ( $auth_ok && !$@) {
            $c->session('login' => $login);
            $c->session(expiration => $SESSION_TIMEOUT);
            return $c->redirect_to($url);
        } else {
            push @error,("Access denied");
        }
    }

    $c->render(
                    template => 'bootstrap/start'
                        ,url => $url
                      ,login => $login
                      ,error => \@error
    );

}

sub logout {
    my $c = shift;

    $USER = undef;
    $c->session(expires => 1);
    $c->session(login => undef);

    warn "logout";
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
        my $log_ok;
        eval { $log_ok = Ravada::Auth::login($login, $password) };
        if ($log_ok) {
            $c->session('login' => $login);
        } else {
            push @error,("Access denied");
        }
    }
    if ( $c->param('submit') && _logged_in($c) && defined $id_base ) {

        return quick_start_domain($c, $id_base, ($login or $c->session('login')));

    }

    return render_machines_user($c);

}

sub render_machines_user {
    my $c = shift;
    return $c->render(
        template => 'bootstrap/list_bases2'
        ,machines => $RAVADA->list_machines_user($USER)
        ,user => $USER
    );
}

sub create_domain {
    my ($c, $id_base, $domain_name, $ram, $disk) = @_;
    return $c->redirect_to('/login') if !$USER;
    my $base = $RAVADA->search_domain_by_id($id_base) or die "I can't find base $id_base";
    my $domain = provision($c,  $id_base,  $domain_name, $ram, $disk);
    return show_failure($c, $domain_name) if !$domain;
    return show_link($c,$domain);

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

    $c->session(expiration => 60) if !$USER->is_admin;
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
        eval { $request = Ravada::Request->open($id_request) };
        return $c->render(data => "Request $id_request unknown")   if !$request;
    } else {
        $request = $id_request;
    }

    return access_denied($c)
        unless $USER->is_admin || $request->{args}->{uid} == $USER->id;

    return $c->render(data => "Request $id_request unknown ".Dumper($request))
        if !$request->{id};

#    $c->stash(url => undef, _anonymous => undef );
    $c->render(
         template => 'bootstrap/request'
        , request => $request
    );
    return if $request->status ne 'done';

    return $c->render(data => "Request $id_request error ".$request->error)
        if $request->error;

    my $name = $request->defined_arg('name');
    return if !$name;

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

    $msg .= ' for user '.$USER->name if $USER && !$USER->is_temporary;

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
    my $ram = shift;
    my $disk = shift;

    die "Missing id_base "  if !defined $id_base;
    die "Missing name "     if !defined $name;

    my $domain = $RAVADA->search_domain(name => $name);
    return $domain if $domain;

    my @create_args = ( memory => $ram ) if $ram;
    push @create_args , ( disk => $disk) if $disk;
    my $req = Ravada::Request->create_domain(
             name => $name
        , id_base => $id_base
       , id_owner => $USER->id
       ,@create_args
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

    my $req;
    if ( !$domain->is_active ) {
        $req = Ravada::Request->start_domain(
                                         uid => $USER->id
                                       ,name => $domain->name
                                  ,remote_ip => _remote_ip($c)
        );

        $RAVADA->wait_request($req);
        warn "ERROR: req id: ".$req->id." error:".$req->error if $req->error();

        return $c->render(data => 'ERROR starting domain '
                ."status:'".$req->status."' ( ".$req->error.")")
            if $req->error
                && $req->error !~ /already running/i
                && $req->status ne 'waiting';

        return $c->redirect_to("/request/".$req->id.".html");
#            if !$req->status eq 'done';
    }
    if ( $domain->is_paused) {
        $req = Ravada::Request->resume_domain(name => $domain->name, uid => $USER->id
                    , remote_ip => _remote_ip($c)
        );

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
    _open_iptables($c,$domain)
        if !$req;
    $c->render(template => 'bootstrap/run', url => $uri , name => $domain->name
                ,login => $c->session('login'));
}

sub _open_iptables {
    my ($c, $domain) = @_;
    my $req = Ravada::Request->open_iptables(
               uid => $USER->id
        ,id_domain => $domain->id
        ,remote_ip => _remote_ip($c)
    );
    $RAVADA->wait_request($req);
    return $c->render(data => 'ERROR opening domain for '._remote_ip($c)." ".$req->error)
            if $req->error;

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

    Ravada::Auth::SQL::make_admin($id);

}

sub remove_admin {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($id) = $c->req->url->to_abs->path =~ m{/(\d+).json};

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
    Ravada::Request->start_domain( uid => $USER->id
                                 ,name => $domain->name
                           , remote_ip => _remote_ip($c)
    )   if $c->param('start');
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
    if (($c->param('pause') && !$domain->is_paused)
        ||($c->param('resume') && $domain->is_paused)) {
        sleep 2;
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
    _init_error($c);

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

    return $c->render( template => 'bootstrap/remove_machine' );
}

sub remove_base {
  my $c = shift;
  return login($c)    if !_logged_in($c);

  my $domain = _search_requested_machine($c);

  $c->render(json => { error => "Domain not found" })
    if !$domain;

  my $req = Ravada::Request->remove_base(
      id_domain => $domain->id
      ,uid => $USER->id
  );

  $c->render(json => { request => $req->id});
}

sub screenshot_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);

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
    return $c->render(json => { error => "Domain ".$domain->name." is locked" })
            if  $domain->is_locked();

    my $file_screenshot = "$DOCUMENT_ROOT/img/screenshots/".$domain->id.".png";
    if (! -e $file_screenshot && $domain->can_screenshot() ) {
        if ( !$domain->is_active() ) {
            Ravada::Request->start_domain(
                       uid => $USER->id
                     ,name => $domain->name
                ,remote_ip => _remote_ip($c)
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
    my $req = Ravada::Request->start_domain( uid => $USER->id
                                           ,name => $domain->name
                                      ,remote_ip => _remote_ip($c)
    );

    return $c->render(json => { req => $req->id });
}

sub copy_machine {
    my $c = shift;

    return login($c) if !_logged_in($c);
    return access_denied($c)    if !$USER->is_admin();

    my $id_base= $c->param('id_base');

    my $ram = $c->param('copy_ram');
    $ram = 0 if $ram !~ /^\d+(\.\d+)?$/;
    $ram = int($ram*1024*1024);

    my $disk= $c->param('copy_disk');
    $disk = 0 if $disk && $disk !~ /^\d+(\.\d+)?$/;
    $disk = int($disk*1024*1024*1024)   if $disk;

    my $rebase = $c->param('copy_rebase');

    my ($param_name) = grep /^copy_name_\d+/,(@{$c->req->params->names});

    my $base = $RAVADA->search_domain_by_id($id_base);
    my $name = $c->req->param($param_name) if $param_name;
    $name = $base->name."-".$USER->name if !$name;

    return create_domain($c, $id_base, $name, $ram, $disk)
       if $base->is_base && !$rebase;

    my $req = Ravada::Request->prepare_base(
        id_domain => $id_base
        ,uid => $USER->id
    );
    return $c->render("Problem preparing base for domain ".$base->name)
        if $rebase && !$req;

    sleep 1;
    # TODO fix requests for the same domain must queue
    my @create_args =( memory => $ram ) if $ram;
    push @create_args , ( disk => $disk ) if $disk;
    $req = Ravada::Request->create_domain(
             name => $name
        , id_base => $id_base
       , id_owner => $USER->id
        ,@create_args
    );
    $c->redirect_to("/machines");#    if !@error;
}

sub machine_is_public {
    my $c = shift;
    my $uri = $c->req->url->to_abs->path;

    my ($id_machine, $value) = $uri =~ m{/.*/(\d+)/(\d+)?$};
    my $domain = $RAVADA->search_domain_by_id($id_machine);

    return $c->render(text => "unknown domain id $id_machine")  if !$domain;

    $domain->is_public($value) if defined $value;

    if ($value && !$domain->is_base) {
        my $req = Ravada::Request->prepare_base(
            id_domain => $domain->id
            ,uid => $USER->id
        );
    }

    return $c->render(json => $domain->is_public);
}

sub rename_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);
    return access_denied($c)    if !$USER->is_admin();

    my $uri = $c->req->url->to_abs->path;

    warn ref($c->req);
    my ($id_domain,$new_name)
       = $uri =~ m{^/machine/rename/(\d+)/(.*)};

    return $c->render(data => "Machine id not found in $uri ")
        if !$id_domain;
    return $c->render(data => "New name not found in $uri")
        if !$new_name;

    my $req = Ravada::Request->rename_domain(    uid => $USER->id
                                               ,name => $new_name
                                          ,id_domain => $id_domain
    );

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
        , url => undef
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

<h1>Run</h1>


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
