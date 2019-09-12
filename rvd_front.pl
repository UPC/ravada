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
use Mojo::JSON qw(decode_json encode_json);
use Time::Piece;
#use Mojolicious::Plugin::I18N;
use Mojo::Home;

use I18N::LangTags::Detect;
#####
#my $self->plugin('I18N');
#package Ravada::I18N:en;
#####
#
no warnings "experimental::signatures";
use feature qw(signatures);

use lib 'lib';

use Ravada::Front;
use Ravada::Front::Domain;
use Ravada::Auth;
use POSIX qw(locale_h);

my $help;

my $FILE_CONFIG = "/etc/rvd_front.conf";

my $error_file_duplicated = 0;
for my $file ( "/etc/rvd_front.conf" , ($ENV{HOME} or '')."/rvd_front.conf") {
    warn "WARNING: Found config file at $file and at $FILE_CONFIG\n"
        if -e $file && $FILE_CONFIG && $file ne $FILE_CONFIG;
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
                                              ,fallback => 0
                                              ,guide_custom => ''
                                              ,admin => {
                                                    hide_clones => 15
                                                    ,autostart => 0
                                              }
                                              ,config => $FILE_CONFIG_RAVADA
                                              ,auto_view => 0
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

  $USER = undef;

  $c->stash(version => $RAVADA->version);
  my $url = $c->req->url->to_abs->path;
  my $host = $c->req->url->to_abs->host;
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
            ,monitoring => 0
            ,fallback => $CONFIG_FRONT->{fallback}
            ,check_netdata => 0
            ,guide => $CONFIG_FRONT->{guide}
            ,host => $host
            );

    return if _logged_in($c);
    return if $url =~ m{^/(anonymous|login|logout|requirements|robots.txt)}
           || $url =~ m{^/(css|font|img|js)}
	   || $url =~ m{^/fallback/.*\.(css|js|map)$};

    # anonymous URLs
    if (($url =~ m{^/machine/(clone|display|info|view)/}
        || $url =~ m{^/(list_bases_anonymous|request/)}i
        ) && !_logged_in($c)) {
        $USER = _anonymous_user($c);
        return if $USER->is_temporary;
    }
    return access_denied($c)
        if $url =~ /(screenshot|\.json)/
        && !_logged_in($c);
    return login($c) if !_logged_in($c);

    if ($USER && $USER->is_admin && $CONFIG_FRONT->{monitoring}) {
        if (!defined $c->session('monitoring')) {
            $c->stash(check_netdata => "https://$host:19999/index.html");
        }
        $c->stash( monitoring => 1) if $c->session('monitoring');
    }
        $c->stash( fallback => 1) if $c->session('fallback');
};


############################################################################3

any '/robots.txt' => sub {
    my $c = shift;
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

any '/admin/#type' => sub {
  my $c = shift;

  return admin($c)  if $c->stash('type') eq 'machines'
                        && $USER->is_operator;

  return access_denied($c)    if !$USER->is_operator;

  return admin($c);
};

any '/new_machine' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER->can_create_machine;
    return new_machine($c);
};

any '/copy_machine' => sub {
    my $c = shift;
    return new_machine_copy($c);
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

get '/list_nodes.json' => sub {
    my $c = shift;
    $c->render(json => [$RAVADA->list_vms]);
};

get '/node/enable/(:id).json' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->is_admin;
    return $c->render(json => {enabled => $RAVADA->enable_node($c->stash('id'),1)});
};

get '/node/disable/(:id).json' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->is_admin;

    my $machines = $RAVADA->_list_machines_vm($c->stash('id'));
    for ( @$machines ) {
        my $req = Ravada::Request->shutdown_domain( uid => $USER->id , id_domain => $_->{id} );
    }
    return $c->render(json => {enabled => $RAVADA->enable_node($c->stash('id'),0)});
};
get '/node/remove/(:id).json' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->is_admin;
    return $c->render(json => {remove => $RAVADA->remove_node($c->stash('id'),1)});
};

get '/node/shutdown/(:id).json' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->is_admin;

    my $machines = $RAVADA->_list_machines_vm($c->stash('id'));
    for ( @$machines ) {
        my $req = Ravada::Request->shutdown_domain(
                    uid => $USER->id
            , id_domain => $_->{id}
        );
    }
    my $at = 0;
    if (@$machines) {
        $at = time + 60 + scalar @$machines;
    }
    my $req = Ravada::Request->shutdown_node(
                id_node => $c->stash('id')
                ,at => $at
    );
    Ravada::Request->connect_node(
                id_node => $c->stash('id')
                ,at => $at + 10
    );
    return $c->render(json => {id_req => $req->id });
};

get '/node/start/(:id).json' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->is_admin;
    my $req = Ravada::Request->start_node(
                id_node => $c->stash('id')
    );
    for my $seconds ( 30,60,90,120 ) {
        Ravada::Request->connect_node(
            id_node => $c->stash('id')
            ,at => time + $seconds
        );
    }

    return $c->render(json => {id_req => $req->id });

};

any '/new_node' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER->is_admin;
    return new_node($c);
};

get '/node/connect/(#backend)/(#hostname)' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER->is_admin;
    my $req = Ravada::Request->connect_node(
                backend => $c->stash('backend')
                    ,hostname => $c->stash('hostname')
    );
    return $c->render(json => {id_req => $req->id });
};

get '/node/connect/(#id)' => sub {
    my $c = shift;
    return access_denied($c)    if !$USER->is_admin;
    my $req = Ravada::Request->connect_node(
        id_node => $c->stash('id')
    );
    return $c->render(json => {id_req => $req->id });
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

    return access_denied($c) unless _logged_in($c)
        && $USER->can_create_machine();

    my $vm_name = $c->param('backend');

    $c->render(json => $RAVADA->list_iso_images($vm_name or undef));
};

get '/iso_file.json' => sub {
    my $c = shift;
    return access_denied($c) unless _logged_in($c)
        && $USER->can_create_machine();
    my @isos =('<NONE>');
    push @isos,(@{$RAVADA->iso_file('KVM')});
    $c->render(json => \@isos);
};

get '/list_machines.json' => sub {
    my $c = shift;

    return access_denied($c) unless _logged_in($c)
        && (
            $USER->can_list_machines
            || $USER->can_list_own_machines()
            || $USER->can_list_clones()
            || $USER->can_list_clones_from_own_base()
            || $USER->is_admin()
        );

    return $c->render( json => $RAVADA->list_machines($USER) );

};

get '/list_machines_user.json' => sub {
    my $c = shift;
    return $c->render( json => $RAVADA->list_machines_user($USER));
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

    return access_denied($c,"Access denied to user ".$USER->name) unless $USER->can_manage_machine($domain->id);

    my $info = $domain->info($USER);
    if ($domain->is_active && !$info->{ip}) {
        Ravada::Request->refresh_machine(id_domain => $domain->id, uid => $USER->id);
    }
    return $c->render(json => $info);
};

get '/machine/requests/(:id).json' => sub {
    my $c = shift;
    my $id_domain = $c->stash('id');
    return access_denied($c) unless $USER->can_manage_machine($id_domain);

    $c->render(json => $RAVADA->list_requests($id_domain,10));
};

any '/machine/manage/(:id).(:type)' => sub {
   	 my $c = shift;
     Ravada::Request->refresh_machine(id_domain => $c->stash('id'), uid => $USER->id);
     return manage_machine($c);
};

any '/hardware/(:id).(:type)' => sub {
   	 my $c = shift;
     return $c->render(template => 'main/hardware');
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

any '/machine/clone/(:id).(:type)' => sub {
    my $c = shift;

    return clone_machine($c)    if $USER && $USER->can_clone() && !$USER->is_temporary();

    my $bases_anonymous = $RAVADA->list_bases_anonymous(_remote_ip($c));
    for (@$bases_anonymous) {
        if ($_->{id} == $c->stash('id') ) {
            return clone_machine($c,1);
        }
    }

    return login($c)    if !$USER || $USER->is_temporary;
    return access_denied($c);
};

get '/machine/shutdown/(:id).(:type)' => sub {
        my $c = shift;
    return access_denied($c)        if !$USER ->can_shutdown($c->stash('id'));

        return shutdown_machine($c);
};

any '/machine/remove/(:id).(:type)' => sub {
        my $c = shift;
    return access_denied($c)       if !$USER->can_remove_machine($c->stash('id'));
        return remove_machine($c);
};

any '/machine/remove_clones/(:id).(:type)' => sub {
    my $c = shift;

    # TODO : call to $domain->_allow_remove();
	return access_denied($c)
        unless
            $USER -> can_remove_clone_all()
	        || $USER->can_remove_clone()
            || $USER->can_remove_all();
    return remove_clones($c);
};

get '/machine/prepare/(:id).(:type)' => sub {
        my $c = shift;
        return prepare_machine($c);
};

get '/machine/set_base_vm/(:id_vm)/(:id_domain).(:type)' => sub {
    my $c = shift;
    return set_base_vm($c, 1);
};

get '/machine/remove_base_vm/(:id_vm)/(:id_domain).(:type)' => sub {
    my $c = shift;
    return set_base_vm($c, 0);
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
        my $domain = _search_requested_machine($c);
        return access_denied($c)   if (!$USER->can_screenshot() || $domain->is_base());
        return screenshot_machine($c);
};

get '/machine/copy_screenshot/(:id).(:type)' => sub {
        my $c = shift; 
        my $domain = _search_requested_machine($c);
        return access_denied($c) if (!$USER->is_admin() || $domain->id_base() == NULL );
        return copy_screenshot($c);
};

get '/machine/pause/(:id).(:type)' => sub {
        my $c = shift;
        return pause_machine($c);
};

get '/machine/hibernate/(:id).(:type)' => sub {
        my $c = shift;
          return access_denied($c)
             unless $USER->is_admin() || $USER->can_shutdown($c->stash('id'));

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

post '/machine/hardware/change' => sub {
    my $c = shift;
    my $arg = decode_json($c->req->body);

    my $domain = Ravada::Front::Domain->open(delete $arg->{id_domain});

    return access_denied($c)
        unless $USER->id == $domain->id_owner || $USER->is_admin;

    my $hardware = delete $arg->{hardware} or die "Missing hardware name";
    my $index = delete $arg->{index};
    my $data = delete $arg->{data};

    die "Unknown fields in request ".Dumper($arg) if keys %{$arg};
    return $c->render(json => { req => Ravada::Request->change_hardware(
                id_domain => $domain->id
                ,hardware => $hardware
                ,index => $index
                ,data => $data
                ,uid => $USER->id
            )
    });
};

get '/node/exists/#name' => sub {
    my $c = shift;
    my $name = $c->stash('name');

    return $c->render(json => $RAVADA->node_exists($name));

};
get '/machine/rename/#id/#value' => sub {
    my $c = shift;
    return access_denied($c)       if !$USER->can_manage_machine($c->stash('id'));
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

get '/machine/set/#id/#field/#value' => sub {
    my $c = shift;
    my $id = $c->stash('id');
    my $field = $c->stash('field');
    my $value = $c->stash('value');

    return access_denied($c)       if !$USER->can_manage_machine($c->stash('id'));

    my $domain = Ravada::Front::Domain->open($id) or die "Unkown domain $id";
    return $c->render(json => { $field => $domain->_data($field, $value)});
};

get '/machine/autostart/#id/#value' => sub {
    my $c = shift;
    my $req = Ravada::Request->domain_autostart(
        id_domain => $c->stash('id')
           ,value => $c->stash('value')
             ,uid => $USER->id
    );
    return $c->render(json => { request => $req->id});
};

get '/machine/display/(:id).vv' => sub {
    my $c = shift;

    my $id = $c->stash('id');

    my $domain = $RAVADA->search_domain_by_id($id);
    return $c->render(text => "unknown machine id=$id") if !$id;

    return access_denied($c)
        if $USER->id ne $domain->id_owner
        && !$USER->is_admin;

    $c->res->headers->content_type('application/x-virt-viewer');
        $c->res->headers->content_disposition(
        "inline;filename=".$domain->id.".vv");

    return $c->render(data => $domain->display_file($USER), format => 'vv');
};

get '/machine/display-tls/(:id)-tls.vv' => sub {
    my $c = shift;

    my $id = $c->stash('id');

    my $domain = $RAVADA->search_domain_by_id($id);
    return $c->render(text => "unknown machine id=$id") if !$id;

    return access_denied($c)
        if $USER->id ne $domain->id_owner
        && !$USER->is_admin;

    $c->res->headers->content_type('application/x-virt-viewer');
        $c->res->headers->content_disposition(
        "inline;filename=".$domain->id."-tls.vv");

    return $c->render(data => $domain->display_file_tls($USER), format => 'vv');
};

# Network ##########################################################3

get '/network/interfaces/(:vm_type)/(:type)' => sub {
    my $c = shift;

    my $vm_type = $c->stash('vm_type');
    my $type = $c->stash('type');

    return $c->render( json => $RAVADA->list_network_interfaces(
               user => $USER
              ,type => $type
           ,vm_type => $vm_type
       )
    );
};

# Users ##########################################################3

##add user

any '/users/register' => sub {

       my $c = shift;
       return access_denied($c) if !$USER->is_admin();
       return register($c);
};

any '/admin/user/(:id).(:type)' => sub {
    my $c = shift;
    return access_denied($c) if !$USER->can_manage_users() && !$USER->can_grant();

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

get '/list_ldap_attributes/(#cn)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $cn = $c->stash('cn');
    my $user;
    eval {
        ($user) = Ravada::Auth::LDAP::search_user($cn);
    };
    return $c->render(json => { error => $@ }) if $@;
    return $c->render(json => []) if !$user;

    $c->session(ldap_attributes_cn => $cn) if $user;
    return $c->render(json => {attributes => [sort $user->attributes]});
};

get '/count_ldap_entries/(#attribute)/(#value)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my @entries;
    eval {
        @entries = Ravada::Auth::LDAP::search_user(
            field => $c->stash('attribute')
            ,name => $c->stash('value')
            ,typesonly => 1
        );
    };
    @entries = [ 'too many' ] if $@ =~ /Sizelimit exceeded/;
    return $c->render(json => { entries => scalar @entries });
};

get '/add_ldap_access/(#id_domain)/(#attribute)/(#value)/(#allowed)/(#last)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $domain_id = $c->stash('id_domain');
    my $domain = Ravada::Front::Domain->open($domain_id);

    my $attribute = $c->stash('attribute');
    my $value = $c->stash('value');
    my $allowed = 1;
    if ($c->stash('allowed') eq 'false') {
        $allowed = 0;
    }
    my $last = 1;
    if ($c->stash('last') eq 'false') {
        $last = 0;
    }
    $last = 1 if !$allowed;

    eval { $domain->allow_ldap_access($attribute => $value, $allowed, $last ) };
    _fix_default_ldap_access($c, $domain, $allowed) if !$@;
    return $c->render(json => { error => $@ }) if $@;
    return $c->render(json => { ok => 1 });

};

sub _fix_default_ldap_access($c, $domain, $allowed) {
    my @list = $domain->list_ldap_access();
    my $default_found;
    for ( @list ) {
        if ( $_->{value} eq '*' ) {
            $default_found = $_->{id};
        }
    }
    if ( $default_found ) {
        $domain->move_ldap_access($default_found, +1);
        return;
    }
    my $allowed_default = 0;
    $allowed_default = 1 if !$allowed;
    eval { $domain->allow_ldap_access('DEFAULT' => '*', $allowed_default ) };
    warn $@ if $@;
}

get '/delete_ldap_access/(#id_domain)/(#id_access)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $domain_id = $c->stash('id_domain');
    my $domain = Ravada::Front::Domain->open($domain_id);

    $domain->delete_ldap_access($c->stash('id_access'));

    # delete default if it is the only one left
    my @ldap_access = $domain->list_ldap_access();
    if (scalar @ldap_access == 1 && $ldap_access[0]->{value} eq '*') {
        $domain->delete_ldap_access($ldap_access[0]->{id});
    }

    return $c->render(json => { ok => 1 });
};

get '/list_ldap_access/(#id_domain)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $domain_id = $c->stash('id_domain');
    my $domain = Ravada::Front::Domain->open($domain_id);

    my @ldap_access = $domain->list_ldap_access();
    my $default = {};
    if (scalar @ldap_access && $ldap_access[-1]->{value} eq '*') {
        $default = pop @ldap_access;
    }
    return $c->render(json => {list => \@ldap_access, default => $default} );
};

get '/move_ldap_access/(#id_domain)/(#id_access)/(#count)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $domain_id = $c->stash('id_domain');
    my $domain = Ravada::Front::Domain->open($domain_id);

    $domain->move_ldap_access($c->stash('id_access'), $c->stash('count'));

    return $c->render(json => { ok => 1});
};

get '/set_ldap_access/(#id_domain)/(#id_access)/(#allowed)/(#last)' => sub {
    my $c = shift;

    return _access_denied($c) if !$USER->is_admin;

    my $domain_id = $c->stash('id_domain');
    my $domain = Ravada::Front::Domain->open($domain_id);

    my $allowed = $c->stash('allowed');
    if ($allowed =~ /false/ || !$allowed) {
        $allowed = 0;
    } else {
        $allowed = 1;
    }
    my $last= $c->stash('last');
    if ($last=~ /false/ || !$last) {
        $last= 0;
    } else {
        $last= 1;
    }
    warn "last = $last";

    $domain->set_ldap_access($c->stash('id_access'), $allowed, $last);
    return $c->render(json => { ok => 1});
};
##############################################

post '/request/(:name)/' => sub {
    my $c = shift;

    my $args = decode_json($c->req->body);
    warn Dumper($args);

    my $req = Ravada::Request->new_request(
        $c->stash('name')
        ,uid => $USER->id
        ,%$args
    );
    return $c->render(json => { ok => 1 });
};

get '/request/(:id).(:type)' => sub {
    my $c = shift;
    my $id = $c->stash('id');

    if (!$USER) {
        $USER = _get_anonymous_user($c) or access_denied($c);
    }
    if ($c->stash('type') eq 'json') {
        my $request = Ravada::Request->open($id);
        return $c->render(json => $request->info($USER));
    }
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
    return access_denied($c) unless _logged_in($c)
        && $USER->is_admin;
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

get '/machine/hardware/remove/(#id_domain)/(#hardware)/(#index)' => sub {
    my $c = shift;
    my $hardware = $c->stash('hardware');
    my $index = $c->stash('index');
    my $domain_id = $c->stash('id_domain');

    my $domain = Ravada::Front::Domain->open($domain_id);

    return access_denied($c)
        unless $USER->id == $domain->id_owner || $USER->is_admin;
    
    my $req = Ravada::Request->remove_hardware(uid => $USER->id
        , id_domain => $domain_id
        , name => $hardware
        , index => $index
    );
    
    $RAVADA->wait_request($req,60);  
    
    return $c->render( json => { ok => "Hardware Modified" });
};

post '/machine/hardware/add' => sub {
    my $c = shift;
    my $arg = decode_json($c->req->body);

    my $domain = Ravada::Front::Domain->open($arg->{id_domain});
    return access_denied($c)
        unless $USER->id == $domain->id_owner || $USER->is_admin;

    my $hardware = delete $arg->{hardware} or die "Missing hardware name";
    my $number = ( $arg->{number} or undef );

    my @fields;
    push @fields, ( number => $arg->{number} )
        if exists $arg->{number} && defined $arg->{number};
    push @fields, ( data => $arg->{data} ) if exists $arg->{data};

    my $req = Ravada::Request->add_hardware(
        uid => $USER->id
        ,name => $hardware
        ,id_domain => $domain->id
        ,@fields
    );
    return $c->render( json => { request => $req->id } );
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
        Ravada::Request->post_login(
                user => $USER->name
            , locale => $changed_lang);
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
    if ($USER && !$USER->is_admin) {
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
#
# session settings
#
get '/session/(#tag)/(#value)' => sub {
    my $c = shift;
    my %allowed = map { $_ => 1 } qw(monitoring);

    my $tag = $c->stash('tag');
    my $value = $c->stash('value');

    return $c->render( json => { error => "Session $tag not allowed" }) if !$allowed{$tag};

    $c->session($tag => $value);
    return $c->render( json => { ok => "Session $tag set to $value " });
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
    my $url = ($c->param('url') or $c->req->url->to_abs->path);
    $url = '/' if $url =~ m{^/login};

    my @error =();

    if (defined $login || defined $password || $c->param('submit')) {
        push @error,("Empty login name")  if !length $login;
        push @error,("Empty password")  if !length $password;
    }

    if ( !@error && defined $login && defined $password) {
        my $auth_ok;
        eval { $auth_ok = Ravada::Auth::login($login, $password)};
        if ( $auth_ok && !$@) {
            $c->session('login' => $login);
            my $expiration = $SESSION_TIMEOUT;
            $expiration = $SESSION_TIMEOUT_ADMIN    if $auth_ok->is_admin;
            my @languages = I18N::LangTags::implicate_supers(
                I18N::LangTags::Detect::detect()
            );
            my $header = $c->req->headers->header('accept-language');
            my @languages2 = map {s/^(.*?)[;-].*/$1/; $_ } split /,/,$header;

            Ravada::Request->post_login(
                user => $auth_ok->name
                , locale => [@languages, @languages2]
            );

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
                      ,error => \@error
                      ,login_header => $CONFIG_FRONT->{login_header}
                      ,login_message => $CONFIG_FRONT->{login_message}
                      ,guide => $CONFIG_FRONT->{guide}
                      ,login_hash => ''
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
    my $anonymous = (shift or 0);

    if ($CONFIG_FRONT->{guide_custom}) {
        push @{$c->stash->{js}}, $CONFIG_FRONT->{guide_custom};
    } else {
        push @{$c->stash->{js}}, '/js/ravada_guide.js';
    }
    return $c->render(
        template => 'main/list_bases_ng'
        ,user => $USER
        ,_anonymous => $anonymous
    );
}

sub quick_start_domain {
    my ($c, $id_base, $name) = @_;
    my $anonymous = (shift or 0);
    
    return $c->redirect_to('/login') if !$USER;

    confess "Missing id_base" if !defined $id_base;
    $name = $USER->name    if !$name;

    my $base = $RAVADA->search_domain_by_id($id_base) or die "I can't find base $id_base";

    my $domain_name = $base->name."-".$name;
    $domain_name =~ tr/[\.]/[\-]/;

    my $domain = $RAVADA->search_clone(id_base => $base->id, id_owner => $USER->id);
    $domain_name = $domain->name if $domain;

    return run_request($c,provision_req($c, $id_base, $domain_name), $anonymous);

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
        return access_denied($c)    if !$USER->is_admin && !$USER->can_manage_users && !$USER->can_grant;
        $c->stash(list_users => []);
        $c->stash(name => $c->param('name' or ''));
        if ( $c->param('name') ) {
            $c->stash(list_users => $RAVADA->list_users($c->param('name') ))
        }
    }
    if ($page eq 'machines') {
        Ravada::Request->refresh_vms();
        $c->stash(n_clones_hide => ($CONFIG_FRONT->{admin}->{hide_clones} or 10) );
        $c->stash(autostart => ( $CONFIG_FRONT->{admin}->{autostart} or 0));

        if ($USER && $USER->is_admin && $CONFIG_FRONT->{monitoring}) {
            if (!defined $c->session('monitoring')) {
                my $host = $c->req->url->to_abs->host;
                $c->stash(check_netdata => "https://$host:19999/index.html");
            }
            $c->stash( monitoring => 1 ) if $c->session('monitoring');
        }
    }
    if ($page eq 'nodes') {
        Ravada::Request->refresh_vms();
    }
    $c->render( template => 'main/admin_'.$page);
};

sub new_machine {
    my $c = shift;
    my @error ;
    if ($c->param('submit')) {
        push @error,("Name is mandatory")   if !$c->param('name');
        push @error,("Invalid name '".$c->param('name')."'"
                .".It can only contain alphabetic, numbers, undercores and dashes.")
            if $c->param('name') && $c->param('name') !~ /^[a-zA-Z0-9_-]+$/;
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

sub new_node {
    my $c = shift;

    push @{$c->stash->{css}}, '/css/admin.css';
    push @{$c->stash->{js}}, '/js/admin.js';

    if ($c->param('_submit')) {
        $c->req->params->remove('_submit');
        my $pairs = $c->req->params()->pairs;
        $RAVADA->add_node(@$pairs);
	return $c->render(template => 'main/admin_nodes');
    }
    return $c->render(template => 'main/new_node');
}

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
    my $msg = shift;

    if (!$msg) {
        $msg = 'Access denied to '.$c->req->url->to_abs->path;
        $msg .= ' for user '.$USER->name if $USER && !$USER->is_temporary;
    }

    if (defined $c->stash('type') && $c->stash('type') eq 'json') {
        return $c->render(json => { error => $msg }, status => 403);
    }
    return $c->render(text => $msg, status => 403);
}

sub base_id {
    my $name = shift;
    my $base = $RAVADA->search_domain($name);

    return $base->id;
}

sub provision_req($c, $id_base, $name, $ram=0, $disk=0) {

    if ( $RAVADA->domain_exists($name) ) {
        my $domain = $RAVADA->search_domain($name);
        if ( $domain->id_owner == $USER->id
                && $domain->id_base == $id_base && !$domain->is_base ) {
            if ($domain->is_active) {
                return Ravada::Request->open_iptables(
                    uid => $USER->id
                , id_domain => $domain->id
                , remote_ip => _remote_ip($c)
                );
            }
            return Ravada::Request->start_domain(
                uid => $USER->id
                , id_domain => $domain->id
                , remote_ip => _remote_ip($c)
            )
        }
        $name = _new_domain_name($name);
    }
    my @create_args = ( start => 1, remote_ip => _remote_ip($c));
    push @create_args, ( memory => $ram ) if $ram;
    push @create_args, (   disk => $disk) if $disk;
    my $req = Ravada::Request->create_domain(
             name => $name
        , id_base => $id_base
       , id_owner => $USER->id
       ,@create_args
    );

}

sub _new_domain_name {
    my $name = shift;
    my $count = 1;
    my $name2;
    for ( ;; ) {
        $name2 = "$name-".++$count;
        return $name2 if !$RAVADA->domain_exists($name2);
    }
}

sub run_request($c, $request, $anonymous = 0) {
    my $timeout = $SESSION_TIMEOUT;
    $timeout = $SESSION_TIMEOUT_ADMIN    if $USER->is_admin;
    return $c->render(template => 'main/run_request', request => $request
        , auto_view => ( $CONFIG_FRONT->{auto_view} or $c->session('auto_view') or 0)
        , anonymous => $anonymous
        , timeout => $timeout * 1000
    );
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
        #$c->stash( error => "Unknown domain id=$id");
        $c->stash( error => "This machine doesn't exist. Probably it has been deleted recently.");
        return;
    };

    return ($domain,$type) if wantarray;
    return $domain;
}

sub register {

    my $c = shift;

    my @error = ();

    my $username = $c->param('username');
    my $password = $c->param('password');

   if($username) {
       my @list_users = Ravada::Auth::SQL::list_all_users();

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
    my ($domain) = _search_requested_machine($c);
    return access_denied($c)    if !$domain;
  	return access_denied($c)    if !($USER->can_manage_machine($domain->id)
                                    || $USER->is_admin
    );

    $c->stash(domain => $domain);
    $c->stash(USER => $USER);
    $c->stash(list_users => $RAVADA->list_users);
    $c->stash(ldap_attributes_cn => ( $c->session('ldap_attributes_cn') or $USER->name or ''));

    $c->stash(  ram => int( $domain->get_info()->{max_mem} / 1024 ));
    $c->stash( cram => int( $domain->get_info()->{memory} / 1024 ));
    $c->stash( needs_restart => $domain->needs_restart );
    my @messages;
    my @errors;
    my @reqs = ();

    if ($c->param("ram") && ($domain->get_info())->{max_mem}!=$c->param("ram")*1024 && $USER->is_admin){
        $c->stash( needs_restart => 1 ) if $domain->is_active;
        my $req_mem = Ravada::Request->change_max_memory(uid => $USER->id, id_domain => $domain->id, ram => $c->param("ram")*1024);
        push @reqs,($req_mem);
        $c->stash(ram => $c->param('ram'));
        
        push @messages,("MAx memory changed from "
                    .int($domain->get_info()->{max_mem}/1024)." to ".$c->param('ram'));
    }
    if ($c->param("cram") && int($domain->get_info()->{memory} / 1024) !=$c->param("cram")){
        $c->stash(cram => $c->param('cram'));
        if ($c->param("cram")*1024<=($domain->get_info())->{max_mem}){
            my $req_mem = Ravada::Request->change_curr_memory(uid => $USER->id, id_domain => $domain->id, ram => $c->param("cram")*1024);
            push @reqs,($req_mem);
            push @messages,("Current memory changed from "
                    .int($domain->get_info()->{memory} / 1024)." to ".$c->param('cram'));
        }  else {
            push @errors, ('Current memory must be less than max memory');
        }
    }

    if (defined $c->param("start-clones") && $c->param("start-clones") ne "") {
        my $req = Ravada::Request->start_clones(
            id_domain => $domain->id,
            ,uid => $USER->id
            ,remote_ip => _remote_ip($c)
        );
    }
    my $req = Ravada::Request->shutdown_domain(id_domain => $domain->id, uid => $USER->id)
            if $c->param('shutdown') && $domain->is_active;

    $req = Ravada::Request->start_domain(
                        uid => $USER->id
                     , name => $domain->name
                , remote_ip => _remote_ip($c)
            ) if $c->param('start') && !$domain->is_active;

    _enable_buttons($c, $domain);

    my %cur_driver;
    for my $driver (qw(sound video network image jpeg zlib playback streaming)) {
        next if !$domain->drivers($driver);
        $cur_driver{$driver} = $domain->get_driver_id($driver);
        my $value = $c->param("driver_$driver");
        next if !defined $value
                || !$value
                || (defined $domain->get_driver_id($driver)
                    && $value eq $domain->get_driver_id($driver));
            my $req2 = Ravada::Request->set_driver(uid => $USER->id
                , id_domain => $domain->id
                , id_option => $value
            );
            $cur_driver{$driver} = $value;
            my $msg = "Driver changed: $driver.";
            $msg .= " Changes will apply on next start."    if $domain->is_active;
            push @messages,($msg);
            push @reqs,($req2);
        
    }
    $c->stash(cur_driver => \%cur_driver);

    for (qw(usb)) {#add hardware here
        my $hardware = "hardware_$_";
        if ( defined $c->param($hardware) ) {
            my $req3 = Ravada::Request->add_hardware(uid => $USER->id
                , id_domain => $domain->id
                , name => $hardware
                , number => $c->param($hardware)
            );
            push @messages,('Changes will apply on next start');
            push @reqs, ($req3);
        }
    }

    for my $option (qw(autostart description run_timeout volatile_clones id_owner)) {

        next if $option eq 'description' && !$c->param('btn_description');
        next if $option ne 'description' && !$c->param('btn_options');

            return access_denied($c)
                if $option =~ /^(id_owner|run_timeout)$/ && !$USER->is_admin;


            my $old_value = $domain->_data($option);
            my $value = $c->param($option);
            
            $value= 0 if $option =~ /volatile_clones|autostart/ && !$value;

            if ( $option eq 'run_timeout' ) {
                $value = 0 if !$value;
                $value *= 60;
            }

            next if defined $domain->_data($option) && defined $value
                    && $domain->_data($option) eq $value;
            next if !$domain->_data($option) && !$value;

            $domain->set_option($option, $value);
            my $option_txt = $option;
            $option_txt =~ s/_/ /g;
            push @messages,("\u$option_txt changed.");
    }
    $c->stash(messages => \@messages);
    $c->stash(errors => \@errors);
    return $c->render(template => 'main/settings_machine'
        , nodes => [$RAVADA->list_vms($domain->type)]
        , isos => $RAVADA->iso_file($domain->type)
        , list_clones => [map { $_->{name} } $domain->clones]
        , action => $c->req->url->to_abs->path
    );
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

    return run_request($c, Ravada::Request->start_domain(
                    uid => $USER->id
             ,id_domain => $domain->id
            , remote_ip => _remote_ip($c)
            )
    );
}

sub clone_machine($c, $anonymous=0) {
    return login($c) unless $anonymous || _logged_in($c);
    _init_error($c);

    my $base = _search_requested_machine($c);
    if (!$base ) {
        $c->stash( error => "Unknown base ") if !$c->stash('error');
        return $c->render(template => 'main/fail');
    };
    return quick_start_domain($c, $base->id, $USER->name, $anonymous);
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

sub set_base_vm( $c, $new_value) {

    my $id_vm = $c->stash('id_vm');
    my $domain = Ravada::Front::Domain->open($c->stash('id_domain'));

    if ($USER->id != $domain->id && !$USER->is_admin) {
        return $c->render(json => {message => 'access denied'});
    }

    if ($new_value) {
        my $req = Ravada::Request->set_base_vm(
        id_vm => $id_vm
        , id_domain => $domain->id
        , uid => $USER->id
        );
    } else {
        my $req = Ravada::Request->remove_base_vm(
            id_vm => $id_vm
            , id_domain => $domain->id
            , uid => $USER->id
        );
    }
    return $c->render(json => {message => 'processing request'});
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

    my $arg = decode_json($c->req->body);

    my $number = $arg->{copy_number};
    my $id_base= $arg->{id_base} or confess "Missing param id_base";
    my $ram = $arg->{copy_ram};
    $ram = 0 if !$ram || $ram !~ /^\d+(\.\d+)?$/;
    $ram = int($ram*1024*1024);

    my $base = $RAVADA->search_domain_by_id($id_base) or confess "I can't find domain $id_base";
    my $name = ( $arg->{new_name} or $base->name."-".$USER->name );

    my @create_args = ( from_pool => 0 );
    push @create_args,( memory => $ram ) if $ram;
    my @reqs;
    if ($number == 1 ) {
        my $req2 = Ravada::Request->clone(
            uid => $USER->id
            ,name => $name
            , id_domain => $base->id
            ,@create_args
        );
        push @reqs, ( $req2 );
    } else {
        push @reqs,(copy_machine_many($base, $number, \@create_args));
    }
    return $c->render(json => { request => [map { $_->id } @ reqs ] } );
}

sub new_machine_copy($c) {
    my $id_base = $c->param('src_machine');
    my $copy_name = $c->param('copy_name');

    my $ram = $c->param('copy_ram');
    $ram = 0 if !$ram || $ram !~ /^\d+(\.\d+)?$/;
    $ram = int($ram*1024*1024);

    my $req = Ravada::Request->clone(
        uid => $USER->id
        ,id_domain => $id_base
        ,name => $copy_name
        ,memory => $ram
    );

   return $c->redirect_to("/admin/machines");
}

sub copy_machine_many($base, $number, $create_args) {
    my $domains = $RAVADA->list_domains;
    my %domain_exists = map { $_->{name} => 1 } @$domains;

    my @reqs;
    for ( 1 .. $number ) {
        my $n = $_;
        my $name;
        for ( ;; ) {
            while (length($n) < length($number)) { $n = "0".$n };
            $name = $base->name."-".$n;
            last if !$domain_exists{$name}++;
            $n++;
        }
        my $req2 = Ravada::Request->clone(
            uid => $USER->id
            ,name => $name
            , id_domain => $base->id
            ,@$create_args
        );
        push @reqs, ( $req2 );
    }
    return @reqs;
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

    return render_machines_user($c,1);
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

    if ( !$user->id ) {
        $name = _new_anonymous_user($c);
        $c->session(anonymous_user => $name);
        $user= Ravada::Auth::SQL->new( name => $name );

        confess "USER $name has no id after creation"
            if !$user->id;
    }

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

    my $name_mojo = reverse($c->signed_cookie('mojolicious'));

    my $length = 32;
    $name_mojo = _random_name($length)    if !$name_mojo;

    $name_mojo =~ tr/[^a-z][^A-Z][^0-9]/___/c;

    my $name;
    for my $n ( 4 .. $length ) {
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

my $routes = app->routes->children;
for my $route (@$routes){
    $route->pattern->quote_start('(');
    $route->pattern->quote_end(')');
    $route->pattern->parse($route->pattern->unparsed);
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
