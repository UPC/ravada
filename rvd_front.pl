#!/usr/bin/env perl
use warnings;
use strict;
#####
use locale ':not_characters';
#####
use Carp qw(confess);
use Data::Dumper;
use Digest::SHA qw(sha256_hex);
use Hash::Util qw(lock_hash);
use Mojolicious::Lite 'Ravada::I18N';
use Time::Piece;
#use Mojolicious::Plugin::I18N;
use Mojo::Home;
#####
#my $self->plugin('I18N');
#package Ravada::I18N:en;
#####

use lib 'lib';

use Ravada::Front;
use Ravada::Auth;
use POSIX qw(locale_h);

my $help;

my $FILE_CONFIG = "/etc/rvd_front.conf";

my $error_file_duplicated = 0;
for my $file ( "/etc/rvd_front.conf" , ($ENV{HOME} or '')."/rvd_front.conf") {
    warn "WARNING: Found config file at $file and at $FILE_CONFIG\n"
        if -e $file && $FILE_CONFIG;
    $FILE_CONFIG = $file if -e $file;
    $error_file_duplicated++;
}
warn "WARNING: using $FILE_CONFIG\n"    if$error_file_duplicated>2;

my $FILE_CONFIG_RAVADA;
for my $file ( "/etc/ravada.conf" , ($ENV{HOME} or '')."/ravada.conf") {
    warn "WARNING: Found config file at $file and at $FILE_CONFIG_RAVADA\n"
        if -e $file && $FILE_CONFIG_RAVADA;
    $FILE_CONFIG_RAVADA = $file if -e $file;
}

my $CONFIG_FRONT = plugin Config => { default => {
                                                hypnotoad => {
                                                pid_file => 'log/rvd_front.pid'
                                                ,listen => ['http://*:8081']
                                                }
                                              ,login_bg_file => '/img/intro-bg.jpg'
                                              ,login_header => 'Welcome'
                                              ,login_message => ''
                                              ,secrets => ['changeme0']
                                              ,guide => 0
                                              ,login_custom => ''
                                              ,footer => 'bootstrap/footer'
                                              ,monitoring => 0
                                              ,guide_custom => ''
                                              ,admin => {
                                                    hide_clones => 15
                                              }
                                              ,config => $FILE_CONFIG_RAVADA
                                              }
                                      ,file => $FILE_CONFIG
};
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
plugin 'RenderFile';

my %config;
%config = (config => $CONFIG_FRONT->{config}) if $CONFIG_FRONT->{config};
our $RAVADA = Ravada::Front->new(%config);

our $USER;

# TODO: get those from the config file
our $DOCUMENT_ROOT = "/var/www";

# session times out in 5 minutes
our $SESSION_TIMEOUT = ($CONFIG_FRONT->{session_timeout} or 5 * 60);
# session times out in 15 minutes for admin users
our $SESSION_TIMEOUT_ADMIN = ($CONFIG_FRONT->{session_timeout_admin} or 15 * 60);

init();
############################################################################3

hook before_routes => sub {
  my $c = shift;

  $c->stash(version => $RAVADA->version);
  my $url = $c->req->url->to_abs->path;
  $c->stash(css=>['/css/sb-admin.css']
            ,js=>[
                '/js/ravada.js'
                ]
            ,csssnippets => []
            ,navbar_custom => 0
            ,url => undef
            ,_logged_in => undef
            ,_anonymous => undef
            ,_user => undef
            ,footer=> $CONFIG_FRONT->{footer}
            ,monitoring => $CONFIG_FRONT->{monitoring}
            ,guide => $CONFIG_FRONT->{guide}
            );

  return access_denied($c)
    if $url =~ /(screenshot|\.json)/
    && !_logged_in($c);

  if ($url =~ m{^/machine/display/} && !_logged_in($c)) {
      $USER = _get_anonymous_user($c);
      return if $USER->is_temporary;
  }
  return login($c)
    if
        $url !~ m{^/(anonymous|login|logout|requirements|request|robots.txt)}
        && $url !~ m{^/(css|font|img|js)}
        && !_logged_in($c);

    _logged_in($c)  if $url =~ m{^/requirements};
};


############################################################################3

any '/robots.txt' => sub {
    my $c = shift;
    warn "robots";
    return $c->render(text => "User-agent: *\nDisallow: /\n", format => 'text');
};

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

any '/admin/(#type)' => sub {
  my $c = shift;

  return admin($c)  if $c->stash('type') eq 'machines'
                        && $USER->is_operator;

  return access_denied($c)    if !$USER->is_operator;

  return admin($c);
};

any '/new_machine' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER->can_create_domain;
    return new_machine($c);
};

get '/domain/new.html' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c) || !$USER->is_admin();
    $c->stash(error => []);
    return $c->render(template => "main/new_machine");

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

    my $vm_name = $c->param('backend');

    $c->render(json => $RAVADA->list_iso_images($vm_name or undef));
};

get '/iso_file.json' => sub {
    my $c = shift;
    my @isos =('<NONE>');
    push @isos,(@{$RAVADA->iso_file});
    $c->render(json => \@isos);
};

get '/list_machines.json' => sub {
    my $c = shift;

    return access_denied($c) if !_logged_in($c) || !$USER->is_admin();
    $c->render(json => $RAVADA->list_domains);
};

get '/list_bases_anonymous.json' => sub {
    my $c = shift;

    # shouldn't this be "list_bases" ?
    $c->render(json => $RAVADA->list_bases_anonymous(_remote_ip($c)));
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

get '/machine/info/(:id).(:type)' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    die "No id " if !$id;

    my ($domain) = _search_requested_machine($c);
    return access_denied($c)    if !$domain;

    return access_denied($c) unless $USER->is_admin
                              || $domain->id_owner == $USER->id;

    $c->render(json => $RAVADA->domain_info(id => $id));
};

any '/machine/settings/(:id).(:type)' => sub {
   	 my $c = shift;
	 return access_denied($c)     if !$USER->can_change_settings();
	 return settings_machine($c);
};

any '/machine/manage/(:id).(:type)' => sub {
    my $c = shift;

    my ($domain) = _search_requested_machine($c);
    return access_denied($c)    if !$domain;

    return access_denied($c) unless $USER->is_admin
                              || $domain->id_owner == $USER->id;

    return manage_machine($c);
};

get '/machine/view/(:id).(:type)' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    my $type = $c->stash('type');

    my ($domain) = _search_requested_machine($c);
    return access_denied($c)    if !$domain;

    return access_denied($c) unless $USER->is_admin
                              || $domain->id_owner == $USER->id;

    return view_machine($c);
};

get '/machine/clone/(:id).(:type)' => sub {
    my $c = shift;      
    return access_denied($c)	     if !$USER->can_clone();
    return clone_machine($c);
};

get '/machine/shutdown/(:id).(:type)' => sub {
        my $c = shift;
	return access_denied($c)        if !$USER ->can_shutdown_all();
        return shutdown_machine($c);
};

get '/machine/shutdown/(:id).(:type)' => sub {
        my $c = shift;
	return access_denied($c)        if !$USER ->can_shutdown_all();
        return shutdown_machine($c);
};


any '/machine/remove/(:id).(:type)' => sub {
        my $c = shift;
	return access_denied($c)       if (!$USER -> can_remove());
        return remove_machine($c);
};

any '/machine/remove_clones/(:id).(:type)' => sub {
    my $c = shift;

    # TODO : call to $domain->_allow_remove();
	return access_denied($c)
        unless
            $USER -> can_remove_clone_all()
	        || $USER ->can_remove_clone();
    return remove_clones($c);
};

get '/machine/prepare/(:id).(:type)' => sub {
        my $c = shift;
        return prepare_machine($c);
};

get '/machine/remove_b/(:id).(:type)' => sub {
        my $c = shift;
        return remove_base($c);
};

get '/machine/remove_base/(:id).(:type)' => sub {
    my $c = shift;
    return remove_base($c);
};

get '/machine/screenshot/(:id).(:type)' => sub {
        my $c = shift;
        return access_denied($c)   if !$USER->can_screenshot();
        return screenshot_machine($c);
};

get '/machine/copy_screenshot/(:id).(:type)' => sub {
        my $c = shift;
        return access_denied($c) if !$USER->is_admin();
        return copy_screenshot($c);
};

get '/machine/pause/(:id).(:type)' => sub {
        my $c = shift;
        return pause_machine($c);
};

get '/machine/hybernate/(:id).(:type)' => sub {
        my $c = shift;
	return access_denied($c)   if !$USER ->can_hibernate_all();
        return hybernate_machine($c);
};

get '/machine/resume/(:id).(:type)' => sub {
        my $c = shift;
        return resume_machine($c);
};

get '/machine/start/(:id).(:type)' => sub {
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

get '/machine/rename/#id' => sub {
    my $c = shift;
    return access_denied($c)       if !$USER -> can_rename();
    return rename_machine($c);
};

get '/machine/rename/#id/#value' => sub {
    my $c = shift;
    return rename_machine($c);
};

any '/machine/copy' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER -> can_clone_all();
    return copy_machine($c);
};

get '/machine/public/#id' => sub {
    my $c = shift;
    return machine_is_public($c);
};

get '/machine/public/#id/#value' => sub {
    my $c = shift;
    return machine_is_public($c);
};

get '/machine/display/#id' => sub {
    my $c = shift;

    my $id = $c->stash('id');

    my $domain = $RAVADA->search_domain_by_id($id);
    return $c->render(text => "unknown machine id=$id") if !$id;

    return access_denied($c)
        if $USER->id ne $domain->id_owner
        && !$USER->is_admin;

    $c->res->headers->content_type('application/x-virt-viewer');
    $c->res->headers->content_disposition(
        "attachment;filename=".$domain->id.".vv");

    return $c->render(data => $domain->display_file($USER));
};

# Users ##########################################################3

##add user

any '/users/register' => sub {

       my $c = shift;
       return register($c);
};

any '/admin/user/(:id).(:type)' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->can_manage_users();

    my $user = Ravada::Auth::SQL->search_by_id($c->stash('id'));

    return $c->render(text => "Unknown user id: ".$c->stash('id'))
        if !$user;

    if ($c->param('make_admin')) {
        $USER->make_admin($c->stash('id'))  if $c->param('is_admin');
        $USER->remove_admin($c->stash('id'))if !$c->param('is_admin');
        $user = Ravada::Auth::SQL->search_by_id($c->stash('id'));
    }
    if ($c->param('grant')) {
        return access_denied($c)    if !$USER->can_grant();
        my %grant;
        for my $param_name (@{$c->req->params->names}) {
            if ( $param_name =~ /^perm_(.*)/ ) {
                $grant{$1} = 1;
            } elsif ($param_name =~ /^off_perm_(.*)/) {
                $grant{$1} = 0 if !exists $grant{$1};
            }
        }
        for my $perm (keys %grant) {
            if ( $grant{$perm} ) {
                $USER->grant($user, $perm);
            } else {
                $USER->revoke($user, $perm);
            }
        }
    }
    $c->stash(user => $user);
    return $c->render(template => 'main/manage_user');
};

##############################################


get '/request/(:id).(:type)' => sub {
    my $c = shift;
    my $id = $c->stash('id');

    return _show_request($c,$id);
};

get '/anonymous/request/(:id).(:type)' => sub {
    my $c = shift;
    my $id = $c->stash('id');

    $USER = _anonymous_user($c);

    return _show_request($c,$id);
};

get '/requests.json' => sub {
    my $c = shift;
    return list_requests($c);
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
    return $c->render(inline => "1");
};

get '/messages/read/(#id).json' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    $USER->mark_message_read($id);
    return $c->render(inline => "1");
};

get '/messages/unread/(#id).json' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    $USER->mark_message_unread($id);
    return $c->render(inline => "1");
};

get '/messages/view/(#id).html' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    return $c->render( json => $USER->show_message($id) );
};

any '/ng-templates/(#template).html' => sub {
  my $c = shift;
  my $id = $c->stash('template');
  return $c->render(template => 'ng-templates/'.$id);
};

any '/about' => sub {
    my $c = shift;

    $c->render(template => 'main/about');
};


any '/requirements' => sub {
    my $c = shift;

    $c->render(template => 'main/requirements');
};


any '/settings' => sub {
    my $c = shift;

    $c->stash(version => $RAVADA->version );

    $c->render(template => 'main/settings');
};

any '/admin/monitoring' => sub {
    my $c = shift;

    $c->render(template => 'main/monitoring');
};

any '/auto_view/(#value)/' => sub {
    my $c = shift;
    my $value = $c->stash('value');
    if ($value =~ /toggle/i) {
        $value = $c->session('auto_view');
        if ($value) {
            $value = 0;
        } else {
            $value = 1;
        }
    }
    $c->session('auto_view' => $value);
    return $c->render(json => {auto_view => $c->session('auto_view') });
};

get '/auto_view' => sub {
    my $c = shift;
    return $c->render(json => {auto_view => $c->session('auto_view') });
};

###################################################

## user_settings

any '/user_settings' => sub {
    my $c = shift;
    user_settings($c);
};

sub user_settings {
    my $c = shift;
    my $changed_lang;
    my $changed_pass;
    if ($c->req->method('POST')) {
        $USER->language($c->param('tongue'));
        $changed_lang = $c->param('tongue');
        _logged_in($c);
    }
    $c->param('tongue' => $USER->language);
    my @errors;
    if ($c->param('button_click')) {
        if (($c->param('password') eq "") || ($c->param('conf_password') eq "") || ($c->param('current_password') eq "")) {
            push @errors,("Some of the password's fields are empty");
        }
        else {
            if ($c->param('password') eq $c->param('conf_password')) {
                eval {
                    $USER->change_password($c->param('password'));
                    _logged_in($c);
                };
                if ($@ =~ /Password too small/) {
                    push @errors,("Password too small")
                }
                else {
                    $changed_pass = 1;
                }
            }
            else {
                    push @errors,("Password fields aren't equal")
            }
        }
    }
    $c->render(template => 'bootstrap/user_settings', changed_lang=> $changed_lang, changed_pass => $changed_pass
      ,errors =>\@errors);
};

get '/img/screenshots/:file' => sub {
    my $c = shift;

    my $file = $c->param('file');
    my $path = $DOCUMENT_ROOT."/".$c->req->url->to_abs->path;

    my ($id_domain ) =$path =~ m{/(\d+)\..+$};
    if (!$id_domain) {
        warn"ERROR : no id domain in $path";
        return $c->reply->not_found;
    }
    if (!$USER->is_admin) {
        my $domain = $RAVADA->search_domain_by_id($id_domain);
        return $c->reply->not_found if !$domain;
        unless ($domain->is_base && $domain->is_public) {
            return access_denied($c) if $USER->id != $domain->id_owner;
        }
    }
    return $c->reply->not_found  if ! -e $path;
    return $c->render_file(
                      filepath => $path
        ,'content_disposition' => 'inline'
    );
};

get '/iso/download/(#id).json' => sub {
    my $c = shift;

    return access_denied($c)    if !$USER->is_admin;
    my $id = $c->stash('id');

    my $req = Ravada::Request->download(
        id_iso => $id
        ,uid => $USER->id
    );

    return $c->render(json => {request => $req->id});
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
    if ($login) {
        $USER = Ravada::Auth::SQL->new(name => $login);
        #Mojolicious::Plugin::I18N::
        $c->languages($USER->language);

        $c->stash(_logged_in => $login );
        $c->stash(_user => $USER);
        $c->stash(_anonymous => !$USER);

    }
    $c->stash(url => undef);

    return $USER;
}


sub login {
    my $c = shift;

    $c->session(login => undef);

    my $login = $c->param('login');
    my $password = $c->param('password');
    my $form_hash = $c->param('login_hash');
    my $url = ($c->param('url') or $c->req->url->to_abs->path);
    $url = '/' if $url =~ m{^/login};

    my @error =();

    # TODO: improve this hash
    my ($time) = time =~ m{(.*)...$};
    my $login_hash1 = $time.($CONFIG_FRONT->{secrets}->[0] or '');

    # let login varm be valid for 60 seconds
    ($time) = (time-60) =~ m{(.*)...$};
    my $login_hash2 = $time.($CONFIG_FRONT->{secrets}->[0] or '');

    if (defined $login || defined $password || $c->param('submit')) {
        push @error,("Empty login name")  if !length $login;
        push @error,("Empty password")  if !length $password;
        push @error,("Session timeout")
            if $form_hash ne sha256_hex($login_hash1)
                && $form_hash ne sha256_hex($login_hash2);
    }

    if ( !@error && defined $login && defined $password) {
        my $auth_ok;
        eval { $auth_ok = Ravada::Auth::login($login, $password)};
        if ( $auth_ok && !$@) {
            $c->session('login' => $login);
            my $expiration = $SESSION_TIMEOUT;
            $expiration = $SESSION_TIMEOUT_ADMIN    if $auth_ok->is_admin;

            $c->session(expiration => $expiration);
            return $c->redirect_to($url);
        } else {
            push @error,("Access denied");
        }
    }

    my @css_snippets = ["\t.intro {\n\t\tbackground:"
                    ." url($CONFIG_FRONT->{login_bg_file})"
                    ." no-repeat bottom center scroll;\n\t}"];

    sleep 5 if scalar(@error);
    $c->render(
                    template => ($CONFIG_FRONT->{login_custom} or 'main/start')
                        ,css => ['/css/main.css']
                        ,csssnippets => @css_snippets
                        ,js => ['/js/main.js']
                        ,navbar_custom => 1
                      ,login => $login
                      ,login_hash => sha256_hex($login_hash1)
                      ,error => \@error
                      ,login_header => $CONFIG_FRONT->{login_header}
                      ,login_message => $CONFIG_FRONT->{login_message}
                      ,monitoring => $CONFIG_FRONT->{monitoring}
                      ,guide => $CONFIG_FRONT->{guide}
    );
}

sub logout {
    my $c = shift;

    $USER = undef;
    $c->session(expires => 1);
    $c->session(login => undef);

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

    if ($CONFIG_FRONT->{guide_custom}) {
        push @{$c->stash->{js}}, $CONFIG_FRONT->{guide_custom};
    } else {
        push @{$c->stash->{js}}, '/js/ravada_guide.js';
    }
    return $c->render(
        template => 'main/list_bases2'
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

    $domain_name =~ tr/[\.]/[\-]/;
    my $domain = $RAVADA->search_clone(id_base => $base->id, id_owner => $USER->id);

    $domain = provision($c,  $id_base,  $domain_name)
        if !$domain || $domain->is_base;

    return show_failure($c, $domain_name) if !$domain;

    return show_link($c,$domain);

}

sub show_failure {
    my $c = shift;
    my $name = shift;
    $c->render(template => 'main/fail', name => $name);
}


#######################################################

sub admin {
    my $c = shift;
    my $page = $c->stash('type');
    my @error = ();

    push @{$c->stash->{css}}, '/css/admin.css';
    push @{$c->stash->{js}}, '/js/admin.js';

    if ($page eq 'users') {
        $c->stash(list_users => []);
        $c->stash(name => $c->param('name' or ''));
        if ( $c->param('name') ) {
            $c->stash(list_users => $RAVADA->list_users($c->param('name') ))
        }
    }
    if ($page eq 'machines') {
        $c->stash(hide_clones => 0 );
        my $list_domains = $RAVADA->list_domains();

        $c->stash(hide_clones => 1 )
            if scalar @$list_domains
                        > $CONFIG_FRONT->{admin}->{hide_clones};

        # count clones from list_domains grepping those that have id_base
        $c->stash(n_clones => scalar(grep { $_->{id_base} } @$list_domains) );

        # if we find no clones do not hide them. They may be created later
        $c->stash(hide_clones => 0 ) if !$c->stash('n_clones');
    }
    $c->render( template => 'main/admin_'.$page);
};

sub new_machine {
    my $c = shift;
    my @error ;
    if ($c->param('submit')) {
        push @error,("Name is mandatory")   if !$c->param('name');
        push @error,("Invalid name '".$c->param('name')."'"
                .".It can only contain words and numbers.")
            if $c->param('name') && $c->param('name') !~ /^[a-zA-Z0-9]+$/;
        if (!@error) {
            req_new_domain($c);
            $c->redirect_to("/admin/machines");
        }
    } else {
        my $req = Ravada::Request->refresh_storage();
        # TODO handle possible errors
    }
    $c->stash(errors => \@error);
    push @{$c->stash->{js}}, '/js/admin.js';
    my %valid_vm = map { $_ => 1 } @{$RAVADA->list_vm_types};
    $c->render(template => 'main/new_machine'
        , name => $c->param('name')
        , valid_vm => \%valid_vm
    );
};

sub req_new_domain {
    my $c = shift;
    my $name = $c->param('name');
    my $swap = ($c->param('swap') or 0);
    my $vm = ( $c->param('backend') or 'KVM');
    $swap *= 1024*1024*1024;

    my %args = (
           name => $name
        ,id_iso => $c->param('id_iso')
        ,id_template => $c->param('id_template')
        ,iso_file => $c->param('iso_file')
        ,vm=> $vm
        ,id_owner => $USER->id
        ,swap => $swap
    );
    $args{memory} = int($c->param('memory')*1024*1024)  if $c->param('memory');
    $args{disk} = int($c->param('disk')*1024*1024*1024) if $c->param('disk');
    $args{id_template} = $c->param('id_template')   if $vm =~ /^LX/;
    $args{id_iso} = $c->param('id_iso')             if $vm eq 'KVM';

    return $RAVADA->create_domain(%args);
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
         template => 'main/request'
        , request => $request
    );
    return if $request->status ne 'done';

    return $c->render(data => "Request $id_request error ".$request->error)
        if $request->error
            &&  !($request->command eq 'start' && $request->error =~ /already running/);

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

    my $domain;
    $domain = $RAVADA->search_domain($name) if $RAVADA->domain_exists($name);
    return $domain if $domain && !$domain->is_base;

    if ($domain) {
        my $count = 2;
        my $name2;
        while ($domain && $domain->is_base) {
            $name2 = "$name-$count";
            $domain = $RAVADA->search_domain($name2);
            $count++;
        }
        return $domain if $domain;
        $name = $name2;
    }

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

        my $req_link = "/request/".$req->id.".html";
        $req_link = "/anonymous$req_link"   if $USER->is_temporary;

        $c->stash(link => $req_link);
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

        my $req_link = "/request/".$req->id.".html";
        $req_link = "/anonymous$req_link"   if $USER->is_temporary;
        return $c->redirect_to($req_link);
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
    my $uri_file = "/machine/display/".$domain->id;
    $c->stash(url => $uri_file)  if $c->session('auto_view') && ! $domain->spice_password;
    my ($display_ip, $display_port) = $uri =~ m{\w+://(\d+\.\d+\.\d+\.\d+):(\d+)};
    my $description = $domain->description;
    if (!$description && $domain->id_base) {
        my $base = Ravada::Domain->open($domain->id_base);
        $description = $base->description();
    }
    $c->stash(description => $description);
    $c->stash(domain => $domain );
    $c->stash(msg_timeout => _message_timeout($domain));
    $c->render(template => 'main/run'
                ,name => $domain->name
                ,password => $domain->spice_password
                ,url_display => $uri
                ,url_display_file => $uri_file
                ,display_ip => $display_ip
                ,display_port => $display_port
                ,description => $description
                ,login => $c->session('login'));
}

sub _message_timeout {
    my $domain = shift;
    my $msg_timeout = "in ".int($domain->run_timeout / 60 )
        ." minutes.";

    for my $request ( $domain->list_requests ) {
        if ( $request->command eq 'shutdown' ) {
            my $t1 = Time::Piece->localtime($request->at_time);
            my $t2 = localtime();

            $msg_timeout = " in ".($t1 - $t2)->pretty;
        }
    }
    return $msg_timeout;
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

sub _init_user_group {
    return if $>;

    my ($run_dir) = $CONFIG_FRONT->{hypnotoad}->{pid_file} =~ m{(.*)/.*};
    mkdir $run_dir if ! -e $run_dir;

    my $user = $CONFIG_FRONT->{user};
    my $group = $CONFIG_FRONT->{group};

    if (defined $group) {
        $group = getgrnam($group) or die "CRITICAL: I can't find user $group\n"
            if $group !~ /^\d+$/;

    }
    if (defined $user) {
        $user = getpwnam($user) or die "CRITICAL: I can't find user $user\n"
            if $user !~ /^\d+$/;

    }
    chown $user,$group,$run_dir or die "$! chown $user,$group,$run_dir"
        if defined $user;

    if (defined $group) {
        $) = $group;
    }
    if (defined $user) {
        $> = $user;
    }

}

sub init {
    check_back_running() or warn "CRITICAL: rvd_back is not running\n";

    _init_user_group();
    my $home = Mojo::Home->new();
    $home->detect();

    if (exists $ENV{MORBO_VERBOSE}
        || (exists $ENV{MOJO_MODE} && $ENV{MOJO_MODE} =~ /devel/i )) {
            return if -e $home->rel_file("public");
    }
    app->static->paths->[0] = ($CONFIG_FRONT->{dir}->{public}
            or $home->rel_file("public"));
    app->renderer->paths->[0] =($CONFIG_FRONT->{dir}->{templates}
            or $home->rel_file("templates"));
    app->renderer->paths->[1] =($CONFIG_FRONT->{dir}->{custom}
            or $home->rel_file("templates"));

}

sub _search_requested_machine {
    my $c = shift;
    confess "Missing \$c" if !defined $c;

    my $id = $c->stash('id');
    my $type = $c->stash('type');

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
    my $id = $c->stash('id');

    Ravada::Auth::SQL::make_admin($id);
    return $c->render(inline => "1");
}

sub register {

    my $c = shift;

    my @error = ();

    my $username = $c->param('username');
    my $password = $c->param('password');

   if($username) {
       my @list_users = Ravada::Auth::SQL::list_all_users();
       warn join(", ", @list_users);

       if (grep {$_ eq $username} @list_users) {
           push @error,("Username already exists, please choose another one");
           $c->render(template => 'bootstrap/new_user',error => \@error);
       }
       else {
           #username don't exists
           Ravada::Auth::SQL::add_user(name => $username, password => $password);
           return $c->render(template => 'bootstrap/new_user_ok' , username => $username);
       }
   }
   $c->render(template => 'bootstrap/new_user');


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

    Ravada::Request->shutdown_domain(id_domain => $domain->id, uid => $USER->id)   if $c->param('shutdown');
    Ravada::Request->start_domain( uid => $USER->id
                                 ,name => $domain->name
                           , remote_ip => _remote_ip($c)
    )   if $c->param('start');
    Ravada::Request->pause_domain(name => $domain->name, uid => $USER->id)
        if $c->param('pause');

    Ravada::Request->resume_domain(name => $domain->name, uid => $USER->id)   if $c->param('resume');

    $c->stash(domain => $domain);

    _enable_buttons($c, $domain);

    $c->render( template => 'main/manage_machine');
}

sub settings_machine {
    my $c = shift;
    my ($domain) = _search_requested_machine($c);

    return access_denied($c)    if !$domain;

    return access_denied($c)
        unless $USER->is_admin
        || $domain->id_owner == $USER->id;

    return $c->render("Domain not found")   if !$domain;

    $c->stash(domain => $domain);
    $c->stash(USER => $USER);

    my $req = Ravada::Request->shutdown_domain(id_domain => $domain->id, uid => $USER->id)
            if $c->param('shutdown') && $domain->is_active;

    $req = Ravada::Request->start_domain(
                        uid => $USER->id
                     , name => $domain->name
                , remote_ip => _remote_ip($c)
            ) if $c->param('start') && !$domain->is_active;

    _enable_buttons($c, $domain);

    $c->stash(message => '');
    my @reqs = ();
    for (qw(sound video network image jpeg zlib playback streaming)) {
        my $driver = "driver_$_";
        if ( $c->param($driver) ) {
            my $req2 = Ravada::Request->set_driver(uid => $USER->id
                , id_domain => $domain->id
                , id_option => $c->param($driver)
            );
            $c->stash(message => 'Changes will apply on next start');
            push @reqs,($req2);
        }
    }

    for my $option (qw(description run_timeout)) {
        if ( defined $c->param($option) ) {
            my $value = $c->param($option);
            $value *= 60 if $option eq 'run_timeout';
            $domain->set_option($option, $value);
            $c->stash(message => "\U$option changed!");
        }
    }

    for my $req (@reqs) {
        $RAVADA->wait_request($req, 60)
    }
    return $c->render(template => 'main/settings_machine'
        , list_clones => [map { $_->{name} } $domain->clones]
        , action => $c->req->url->to_abs->path);
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

    return login($c) unless ( defined $USER && $USER->is_temporary) || _logged_in($c);

    $domain =  _search_requested_machine($c) if !$domain;
    return $c->render(template => 'main/fail') if !$domain;

    return show_link($c, $domain);
}

sub clone_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);
    _init_error($c);

    my $base = _search_requested_machine($c);
    if (!$base ) {
        $c->stash( error => "Unknown base ") if !$c->stash('error');
        return $c->render(template => 'main/fail');
    };
    return quick_start_domain($c, $base->id);
}

sub shutdown_machine {
    my $c = shift;
    return login($c) if !_logged_in($c);

    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->shutdown_domain(id_domain => $domain->id, uid => $USER->id);

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

    $c->render(json => { request => $req->id});
}

sub remove_machine {
    my $c = shift;
    return login($c)    if !_logged_in($c);
    return _do_remove_machine($c,@_);#   if $c->param('sure') && $c->param('sure') =~ /y/i;

}

sub remove_clones {
    my $c = shift;

    my $domain = _search_requested_machine($c);
    my @req;
    for my $clone ( $domain->clones) {
        my $req = Ravada::Request->remove_domain(
            name => $clone->{name}
            ,uid => $USER->id
        );
        push @req,({ request => $req->id });
    }
    $c->render(json => \@req );

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

sub copy_screenshot {
    my $c = shift;
    return login($c)    if !_logged_in($c);

    my $domain = _search_requested_machine($c);

    my $file_screenshot = "$DOCUMENT_ROOT/img/screenshots/".$domain->id.".png";
    my $req = Ravada::Request->copy_screenshot (
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
    if (! -e $file_screenshot && $domain->can_screenshot()
            && $domain->is_active) {
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
    return $c->render(text => "Domain not found") if !$domain;

    my $req = Ravada::Request->start_domain( uid => $USER->id
                                           ,name => $domain->name
                                      ,remote_ip => _remote_ip($c)
    );

    return $c->render(json => { req => $req->id });
}

sub copy_machine {
    my $c = shift;

    return login($c) if !_logged_in($c);
    

    my $id_base= $c->param('id_base');

    my $ram = $c->param('copy_ram');
    $ram = 0 if $ram !~ /^\d+(\.\d+)?$/;
    $ram = int($ram*1024*1024);

    my $disk= $c->param('copy_disk');
    $disk = 0 if $disk && $disk !~ /^\d+(\.\d+)?$/;
    $disk = int($disk*1024*1024*1024)   if $disk;

    my ($param_name) = grep /^copy_name_\d+/,(@{$c->req->params->names});

    my $base = $RAVADA->search_domain_by_id($id_base);
    my $name = $c->req->param($param_name) if $param_name;
    $name = $base->name."-".$USER->name if !$name;

    my @create_args =( memory => $ram ) if $ram;
    push @create_args , ( disk => $disk ) if $disk;
    my $req2 = Ravada::Request->clone(
              uid => $USER->id
            ,name => $name
       , id_domain => $base->id
       ,@create_args
    );
    $c->redirect_to("/admin/machines");#    if !@error;
}

sub machine_is_public {
    my $c = shift;
    my $id_machine = $c->stash('id');
    my $value = $c->stash('value');
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
    my $id_domain = $c->stash('id');
    my $new_name = $c->stash('value');
    return login($c) if !_logged_in($c);
    return access_denied($c)    if !$USER->is_admin();

    #return $c->render(data => "Machine id not found in $uri ")
    return $c->render(data => "Machine id not found")
        if !$id_domain;
    #return $c->render(data => "New name not found in $uri")
    return $c->render(data => "New name not found")
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

sub hybernate_machine {
    my $c = shift;
    my ($domain, $type) = _search_requested_machine($c);
    my $req = Ravada::Request->hybernate(id_domain => $domain->id, uid => $USER->id);

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

    $c->render(template => 'main/list_bases2'
        , _logged_in => undef
        , _anonymous => 1
        , machines => $bases_anonymous
        , user => undef
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

sub _get_anonymous_user {
    my $c = shift;

    $c->stash(_user => undef);
    my $name = $c->session('anonymous_user');

    my $user= Ravada::Auth::SQL->new( name => $name );

    confess "user ".$user->name." has no id, may not be in table users"
        if !$user->id;

    return $user;
}

# get or create a new anonymous user
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
    my $ret = substr($$,3);
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
        $name = "anon".substr($name_mojo,0,$n);
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

app->secrets($CONFIG_FRONT->{secrets})  if $CONFIG_FRONT->{secrets};
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
