package Ravada::Auth::SQL;

use warnings;
use strict;

=head1 NAME

Ravada::Auth::SQL - SQL authentication library for Ravada

=cut

use Carp qw(carp);

use Ravada;
use Ravada::Utils;
use Ravada::Front;
use Digest::SHA qw(sha1_hex);
use Hash::Util qw(lock_hash);
use Moose;

use feature qw(signatures);
no warnings "experimental::signatures";

use vars qw($AUTOLOAD);

use Data::Dumper;

with 'Ravada::Auth::User';


our $CON;

sub _init_connector {
    my $connector = shift;

    $CON = \$connector                 if defined $connector;
    return if $CON;

    $CON= \$Ravada::CONNECTOR          if !$CON || !$$CON;
    $CON= \$Ravada::Front::CONNECTOR   if !$CON || !$$CON;

    if (!$CON || !$$CON) {
        my $connector = Ravada::_connect_dbh();
        $CON = \$connector;
    }

    die "Undefined connector"   if !$CON || !$$CON;
}


=head2 BUILD

Internal OO build method

=cut

sub BUILD {
    _init_connector();

    my $self = shift;

    $self->_load_data();

    return if !$self->password();

    die "ERROR: Login failed ".$self->name
        if !$self->login();#$self->name, $self->password);

    return $self;
}

=head2 search_by_id

Searches a user by its id

    my $user = Ravada::Auth::SQL->search_by_id( $id );

=cut

sub search_by_id {
    my $self = shift;
    my $id = shift;
    my $data = _load_data_by_id($id);
    return if !keys %$data;
    return Ravada::Auth::SQL->new(name => $data->{name});
}

=head2 list_all_users

Returns a list of all the usernames

=cut

sub list_all_users() {
    my $sth = $$CON->dbh->prepare(
        "SELECT(name) FROM users ORDER BY name"
    );
    $sth->execute;
    my @list;
    while (my $row = $sth->fetchrow) {
        push @list,($row);
    }
    return @list;
}

=head2 add_user

Adds a new user in the SQL database. Returns nothing.

    Ravada::Auth::SQL::add_user(
                 name => $user
           , password => $pass
           , is_admin => 0
       , is_temporary => 0
    );

=cut

sub add_user {
    my %args = @_;

    _init_connector();

    my $name= $args{name};
    my $password = $args{password};
    my $is_admin = ($args{is_admin} or 0);
    my $is_temporary= ($args{is_temporary} or 0);
    my $is_external= ($args{is_external} or 0);
    my $external_auth = $args{external_auth};

    delete @args{'name','password','is_admin','is_temporary','is_external', 'external_auth'};

    confess "WARNING: Unknown arguments ".Dumper(\%args)
        if keys %args;


    my $sth;
    eval { $sth = $$CON->dbh->prepare(
            "INSERT INTO users (name,password,is_admin,is_temporary, is_external, external_auth)"
            ." VALUES(?,?,?,?,?,?)");
    };
    confess $@ if $@;
    if ($password) {
        $password = sha1_hex($password);
    } else {
        $password = '*LK* no pss';
    }
    $sth->execute($name,$password,$is_admin,$is_temporary, $is_external, $external_auth);
    $sth->finish;

    $sth = $$CON->dbh->prepare("SELECT id FROM users WHERE name = ? ");
    $sth->execute($name);
    my ($id_user) = $sth->fetchrow;
    $sth->finish;

    my $user = Ravada::Auth::SQL->search_by_id($id_user);

    Ravada::Utils::user_daemon->grant_user_permissions($user);
    if (!$is_admin) {
        Ravada::Utils::user_daemon->grant_user_permissions($user);
        return $user;
    }
    Ravada::Utils::user_daemon->grant_admin_permissions($user);
    return $user;
}

sub _search_id_grant($self, $type) {

    return $self->{_grant_id}->{$type}
        if exists $self->{_grant_id}->{$type};

    $self->_load_grants();

    my @names = $self->_grant_alternate_name($type);

    my $sth = $$CON->dbh->prepare("SELECT id FROM grant_types WHERE "
        .join( " OR ",  map { "name=?"}@names));
    $sth->execute(@names);
    my ($id) = $sth->fetchrow;
    $sth->finish;

    confess "Unknown grant $type\n".Dumper($self->{_grant_alias}, $self->{_grant})   if !$id;

    $self->{_grant_id}->{$type} = $id;

    return $id;
}

sub _load_data {
    my $self = shift;
    _init_connector();

    die "No login name nor id " if !$self->name && !$self->id;

    confess "Undefined \$\$CON" if !defined $$CON;
    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM users WHERE name=? ");
    $sth->execute($self->name);
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    return if !$found->{name};

    delete $found->{password};
    lock_hash %$found;
    $self->{_data} = $found if ref $self && $found;
}

sub _load_data_by_id {
    my $id = shift;
    _init_connector();

    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM users WHERE id=? ");
    $sth->execute($id);
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    delete $found->{password};
    lock_hash %$found;

    return $found;
}

sub _load_data_by_username {
    my $username = shift;
    _init_connector();

    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM users WHERE name=? ");
    $sth->execute($username);
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    delete $found->{password};
    lock_hash %$found;

    return $found;
}

=head2 login

Logins the user

     my $ok = $user->login($password);
     my $ok = Ravada::LDAP::SQL::login($name, $password);

returns true if it succeeds

=cut


sub login {
    my $self = shift;

    _init_connector();

    my ($name, $password);

    if (ref $self) {
        $name = $self->name;
        $password = $self->password;
        $self->{_data} = {};
    } else { # old login API
        $name = $self;
        $password = shift;
    }


    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM users WHERE name=? AND password=?");
    $sth->execute($name , sha1_hex($password));
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    if ($found) {
        lock_hash %$found;
        $self->{_data} = $found if ref $self && $found;
    }

    return 1 if $found;

    return;
}

=head2 make_admin

Makes the user admin. Returns nothing.

     Ravada::Auth::SQL::make_admin($id);

=cut

sub make_admin($self, $id) {
    my $sth = $$CON->dbh->prepare(
            "UPDATE users SET is_admin=1 WHERE id=?");

    $sth->execute($id);
    $sth->finish;

    my $user = $self->search_by_id($id);
    $self->grant_admin_permissions($user);

}

=head2 remove_admin

Remove user admin privileges. Returns nothing.

     Ravada::Auth::SQL::remove_admin($id);

=cut

sub remove_admin($self, $id) {
    my $sth = $$CON->dbh->prepare(
            "UPDATE users SET is_admin=NULL WHERE id=?");

    $sth->execute($id);
    $sth->finish;

    my $user = $self->search_by_id($id);
    $self->revoke_all_permissions($user);
    $self->grant_user_permissions($user);
}

=head2 external_auth

Sets or gets the external auth value of an user.

=cut

sub external_auth($self, $value=undef) {
    if (!defined $value) {
        return $self->{_data}->{external_auth};
    }
    my $sth = $$CON->dbh->prepare(
        "UPDATE users set external_auth=? WHERE id=?"
    );
    $sth->execute($value, $self->id);
    $self->_load_data();
}

=head2 is_admin

Returns true if the user is admin.

    my $is = $user->is_admin;

=cut


sub is_admin {
    my $self = shift;
    return ($self->{_data}->{is_admin} or 0);
}

=head2 is_user_manager

Returns true if the user is user manager

=cut

sub is_user_manager {
    my $self = shift;
    return 1 if $self->can_grant()
            || $self->can_manage_users();
    return 0;
}

=head2 is_operator

Returns true if the user is admin or has been granted special permissions

=cut

sub is_operator {
    my $self = shift;
    return 1 if $self->can_list_own_machines()
            || $self->can_list_clones()
            || $self->can_list_clones_from_own_base()
            || $self->can_list_machines()
            || $self->is_user_manager();
    return 0;
}

=head2 can_list_own_machines

Returns true if the user can list her own virtual machines at the web frontend
(can_XXXXX)

=cut

sub can_list_own_machines {
    my $self = shift;
    return 1 if $self->can_create_base()
            || $self->can_create_machine()
            || $self->can_rename()
            || $self->can_list_clones()
            || $self->can_list_machines();
    return 0;
}

=head2 can_list_clones_from_own_base

Returns true if the user can list all machines that are clones from his bases
(can_XXXXX_clones)

=cut

sub can_list_clones_from_own_base($self) {
    return 1 if $self->can_change_settings_clones()
            || $self->can_remove_clones()
            || $self->can_rename_clones()
            || $self->can_shutdown_clones()
            || $self->can_list_clones()
            || $self->can_list_machines();
    return 0;
}

=head2 can_list_clones

Returns true if the user can list all machines that are clones and its bases
(can_XXXXX_clones_all)

=cut

sub can_list_clones {
    my $self = shift;
    return 1 if $self->can_remove_clone_all()
            || $self->can_list_machines();
    return 0;
  
}

=head2 can_list_machines

Returns true if the user can list all the virtual machines at the web frontend
(can_XXXXX_all or is_admin)

=cut

sub can_list_machines {
    my $self = shift;
    return 1 if $self->is_admin()
            || $self->can_change_settings_all()
            || $self->can_clone_all()
            || $self->can_remove_all()
            || $self->can_rename_all()
            || $self->expose_ports()
            || $self->can_shutdown_all();
    return 0;
}


=head2 is_external

Returns true if the user authentication is not from SQL

    my $is = $user->is_external;

=cut


sub is_external {
    my $self = shift;
    return $self->{_data}->{is_external};
}


=head2 is_temporary

Returns true if the user is admin.

    my $is = $user->is_temporary;

=cut


sub is_temporary{
    my $self = shift;
    return $self->{_data}->{is_temporary};
}


=head2 id

Returns the user id

    my $id = $user->id;

=cut

sub id {
    my $self = shift;
    my $id;
    eval { $id = $self->{_data}->{id} };
    confess $@ if $@;

    return $id;
}

=head2 change_password

Changes the password of an User

    $user->change_password();

Arguments: password

=cut

sub change_password {
    my $self = shift;
    my $password = shift or die "ERROR: password required\n";

    _init_connector();

    die "Password too small" if length($password)<6;

    my $sth= $$CON->dbh->prepare("UPDATE users set password=?"
        ." WHERE name=?");
    $sth->execute(sha1_hex($password), $self->name);
}

=head2 compare_password

Changes the input with the password of an User

    $user->compare_password();

Arguments: password

=cut

sub compare_password {
    my $self = shift;
    my $password = shift or die "ERROR: password required\n";
    
    _init_connector();
    
    my $sth= $$CON->dbh->prepare("SELECT password FROM users WHERE name=?");
    $sth->execute($self->name);
    my $hex_pass = $sth->fetchrow();
    if ($hex_pass eq sha1_hex($password)) {
        return 1;
    }
    else {
        return 0;
    }
}

=head2 language

  Updates or selects the language selected for an User

    $user->language();

  Arguments: lang

=cut

  sub language {
    my $self = shift;
    my $tongue = shift;
    if (defined $tongue) {
      my $sth= $$CON->dbh->prepare("UPDATE users set language=?"
          ." WHERE name=?");
      $sth->execute($tongue, $self->name);
    }
    else {
      my $sth = $$CON->dbh->prepare(
         "SELECT language FROM users WHERE name=? ");
      $sth->execute($self->name);
      return $sth->fetchrow();
    }
  }


=head2 remove

Removes the user

    $user->remove();

=cut

sub remove($self) {
    my $sth = $$CON->dbh->prepare("DELETE FROM users where id=?");
    $sth->execute($self->id);
    $sth->finish;
}

=head2 can_do

Returns if the user is allowed to perform a privileged action

    if ($user->can_do("remove")) { 
        ...

=cut

sub can_do($self, $grant) {
    $self->_load_grants();

    confess "Wrong grant '$grant'\n".Dumper($self->{_grant_alias})
        if $grant !~ /^[a-z_]+$/;

    $grant = $self->_grant_alias($grant);

    confess "Wrong grant '$grant'\n".Dumper($self->{_grant_alias})
        if $grant !~ /^[a-z_]+$/;

    return $self->{_grant}->{$grant} if defined $self->{_grant}->{$grant};

    confess "Unknown permission '$grant'. Maybe you are using an old release.\n"
            ."Try removing the table grant_types and start rvd_back again:\n"
            ."mysql> drop table grant_types;\n"
            .Dumper($self->{_grant}, $self->{_grant_alias})
        if !exists $self->{_grant}->{$grant};
    return $self->{_grant}->{$grant};
}

=head2 can_do_domain

Returns if the user is allowed to perform a privileged action in a virtual machine

    if ($user->can_do_domain("remove", $domain)) {
        ...

=cut

sub can_do_domain($self, $grant, $domain) {
    my %valid_grant = map { $_ => 1 } qw(change_settings shutdown rename);
    confess "Invalid grant here '$grant'"   if !$valid_grant{$grant};

    return 0 if !$self->can_do($grant) && !$domain->id_base;

    return 1 if $self->can_do("${grant}_all");
    return 1 if $domain->id_owner == $self->id && $self->can_do($grant);

    if ($self->can_do("${grant}_clones") && $domain->id_base) {
        my $base = Ravada::Front::Domain->open($domain->id_base);
        return 1 if $base->id_owner == $self->id;
    }
    return 0;
}

sub _load_grants($self) {
    $self->_load_aliases();
    return if exists $self->{_grant};

    my $sth;
    eval { $sth= $$CON->dbh->prepare(
        "SELECT gt.name, gu.allowed, gt.enabled"
        ." FROM grant_types gt LEFT JOIN grants_user gu "
        ."      ON gt.id = gu.id_grant "
        ."      AND gu.id_user=?"
    );
    $sth->execute($self->id);
    };
    confess $@ if $@;
    my ($name, $allowed, $enabled);
    $sth->bind_columns(\($name, $allowed, $enabled));

    while ($sth->fetch) {
        my $grant_alias = $self->_grant_alias($name);
        $self->{_grant}->{$grant_alias} = $allowed     if $enabled;
        $self->{_grant_disabled}->{$grant_alias} = !$enabled;
    }
    $sth->finish;
}

sub _reload_grants($self) {
    delete $self->{_grant};
    return $self->_load_grants();
}

sub _grant_alias($self, $name) {
    my $alias = $name;
    return $self->{_grant_alias}->{$name} if exists $self->{_grant_alias}->{$name};
    return $name;# if exists $self->{_grant}->{$name};

}

sub _grant_alternate_name($self,$name_req) {
    my %name = ( $name_req => 1);
    while (my($name, $alias) = each %{$self->{_grant_alias}}) {
        $name{$name} = 1 if $name_req eq $alias;
        $name{$alias} = 1 if $name_req eq $name;
    }
    return keys %name;
}

sub _load_aliases($self) {
    return if exists $self->{_grant_alias};

    my $sth = $$CON->dbh->prepare("SELECT name,alias FROM grant_types_alias");
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        $self->{_grant_alias}->{$row->{name}} = $row->{alias};
    }

}

=head2 grant_user_permissions

Grant an user permissions for normal users

=cut

sub grant_user_permissions($self,$user) {
    $self->grant($user, 'clone');
    $self->grant($user, 'change_settings');
    $self->grant($user, 'remove');
    $self->grant($user, 'shutdown');
    $self->grant($user, 'screenshot');
}

=head2 grant_operator_permissions

Grant an user operator permissions, ie: hibernate all

=cut

sub grant_operator_permissions($self,$user) {
    $self->grant($user, 'hibernate_all');
    #TODO
}

=head2 grant_manager_permissions

Grant an user manager permissions, ie: hibernate all clones

=cut

sub grant_manager_permissions($self,$user) {
    $self->grant($user, 'hibernate_clone');
    #TODO
}

=head2 grant_admin_permissions

Grant an user all the permissions

=cut

sub grant_admin_permissions($self,$user) {
    my $sth = $$CON->dbh->prepare(
            "SELECT name FROM grant_types "
            ." WHERE enabled=1"
    );
    $sth->execute();
    while ( my ($name) = $sth->fetchrow) {
        $self->grant($user,$name);
    }
    $sth->finish;
}

=head2 revoke_all_permissions

Revoke all permissions from an user

=cut

sub revoke_all_permissions($self,$user) {
    my $sth = $$CON->dbh->prepare(
            "SELECT name FROM grant_types WHERE enabled=1"
    );
    $sth->execute();
    while ( my ($name) = $sth->fetchrow) {
        $self->revoke($user,$name);
    }
    $sth->finish;

}


=head2 grant

Grant an user a specific permission, or revoke it

    $admin_user->grant($user2,"clone");    # both are 
    $admin_user->grant($user3,"clone",1);  # the same

    $admin_user->grant($user4,"clone",0);  # revoke a grant

=cut

sub grant($self,$user,$permission,$value=1) {

    confess "ERROR: permission '$permission' disabled "
        if $self->{_grant_disabled}->{$permission};

    if ( !$self->can_grant() && $self->name ne Ravada::Utils::user_daemon->name ) {
        my @perms = $self->list_permissions();
        confess "ERROR: ".$self->name." can't grant permissions for ".$user->name."\n"
            .Dumper(\@perms);
    }

    return 0 if !$value && !$user->can_do($permission);

    my $value_sql = $user->can_do($permission);
    return $value if defined $value_sql && $value_sql eq $value;

    $permission = $self->_grant_alias($permission);
    my $id_grant = $self->_search_id_grant($permission);
    if (! defined $user->can_do($permission)) {
        my $sth = $$CON->dbh->prepare(
            "INSERT INTO grants_user "
            ." (id_grant, id_user, allowed)"
            ." VALUES(?,?,?) "
        );
        $sth->execute($id_grant, $user->id, $value);
        $sth->finish;
    } else {
        my $sth = $$CON->dbh->prepare(
            "UPDATE grants_user "
            ." set allowed=?"
            ." WHERE id_grant = ? AND id_user=?"
        );
        $sth->execute($value, $id_grant, $user->id);
        $sth->finish;
    }
    $user->{_grant}->{$permission} = $value;
    confess "Unable to grant $permission for ".$user->name ." expecting=$value "
            ." got= ".$user->can_do($permission)
        if $user->can_do($permission) ne $value;
    return $value;
}

=head2 revoke

Revoke a permission from an user

    $admin_user->revoke($user2,"clone");

=cut

sub revoke($self,$user,$permission) {
    return $self->grant($user,$permission,0);
}


=head2 list_all_permissions

Returns a list of all the available permissions

=cut

sub list_all_permissions($self) {
    return if !$self->is_admin && !$self->can_grant();
    $self->_load_grants();

    my $sth = $$CON->dbh->prepare(
        "SELECT * FROM grant_types"
        ." WHERE enabled=1 "
        ." ORDER BY name "
    );
    $sth->execute;
    my @list;
    while (my $row = $sth->fetchrow_hashref ) {
        $row->{name} = $self->_grant_alias($row->{name});
        lock_hash(%$row);
        push @list,($row);
    }
    return @list;
}

=head2 list_permissions

Returns a list of all the permissions granted to the user

=cut

sub list_permissions($self) {
    $self->_load_grants();
    my @list;
    for my $grant (sort keys %{$self->{_grant}}) {
        push @list , (  [$grant => $self->{_grant}->{$grant} ] )
            if $self->{_grant}->{$grant};
    }
    return @list;
}

=pod

sub can_change_settings($self, $id_domain=undef) {
    if (!defined $id_domain) {
        return $self->can_do("change_settings");
    }
    return 1 if $self->can_change_settings_all();

    return 0 if !$self->can_change_settings();

    my $domain = Ravada::Front::Domain->open($id_domain);
    return 1 if $self->id == $domain->id_owner;

    return 0;
}

=cut

=head2 can_manage_machine

The user can change settings, remove or change other things yet to be defined.
Some changes require special permissions granted.

Unlinke change_settings that any user is granted to his own machines by default.

=cut

sub can_manage_machine($self, $domain) {
    return 1 if $self->is_admin;

    $domain = Ravada::Front::Domain->open($domain)  if !ref $domain;

    return 1 if $self->can_clone_all
                || $self->can_change_settings($domain)
                || $self->can_rename_all
                || $self->can_remove_all
                || ($self->can_remove_clone_all && $domain->id_base)
                || ($self->can_remove && $domain->id_owner == $self->id);

    if ( ($self->can_remove_clones || $self->can_change_settings_clones || $self->can_rename_clones) 
         && $domain->id_base ) {
        my $base = Ravada::Front::Domain->open($domain->id_base);
        return 1 if $base->id_owner == $self->id;
    }
    return 0;
}

=head2 can_remove_clones

Returns true if the user can remove clones.

Arguments:

=over

=item * id_domain: optional

=back

=cut

sub can_remove_clones($self, $id_domain=undef) {

    return $self->can_do('remove_clones') if !$id_domain;

    my $domain = Ravada::Front::Domain->open($id_domain);
    confess "ERROR: domain is not a base "  if !$domain->id_base;

    return 1 if $self->can_remove_clone_all();

    return 0 if !$self->can_remove_clones();

    my $base = Ravada::Front::Domain->open($domain->id_base);
    return 1 if $base->id_owner == $self->id;
    return 0;
}

=head2 can_remove_machine

Return true if the user can remove this machine

Arguments:

=over

=item * domain

=back

=cut

sub can_remove_machine($self, $domain) {
    return 1 if $self->can_remove_all();
    #return 0 if !$self->can_remove();

    $domain = Ravada::Front::Domain->open($domain)   if !ref $domain;

    if ( $domain->id_owner == $self->id ) {
        return 1 if $self->can_do("remove");
    }

    return $self->can_remove_clones($domain->id) if $domain->id_base;
    return 0;
}

=head2 can_shutdown_machine

Return true if the user can shutdown this machine

Arguments:

=over

=item * domain

=back

=cut

sub can_shutdown_machine($self, $domain) {

    return 1 if $self->can_shutdown_all();

    $domain = Ravada::Front::Domain->open($domain)   if !ref $domain;

    return 1 if $self->id == $domain->id_owner;

    if ($domain->id_base && $self->can_shutdown_clone()) {
        my $base = Ravada::Front::Domain->open($domain->id_base);
        return 1 if $base->id_owner == $self->id;
    }

    return 0;
}

=head2 grants

Returns a list of permissions granted to the user in a hash

=cut

sub grants($self) {
    $self->_load_grants();
    return () if !$self->{_grant};
    return %{$self->{_grant}};
}

=head2 ldap_entry

Returns the ldap entry as a Net::LDAP::Entry of the user if it has
LDAP external authentication

=cut

sub ldap_entry($self) {
    confess "Error: User ".$self->name." is not in LDAP external auth"
        if !$self->external_auth || $self->external_auth ne 'ldap';

    return $self->{_ldap_entry} if $self->{_ldap_entry};

    my @entries = Ravada::Auth::LDAP::search_user( name => $self->name );
    $self->{_ldap_entry} = $entries[0];

    return $self->{_ldap_entry};
}

sub AUTOLOAD($self, $domain=undef) {

    my $name = $AUTOLOAD;
    $name =~ s/.*://;

    confess "Can't locate object method $name via package $self"
        if !ref($self) || $name !~ /^can_(.*)/;

    my ($permission) = $name =~ /^can_([a-z_]+)/;
    return $self->can_do($permission)   if !$domain;

    $domain = Ravada::Front::Domain->open($domain)      if !ref $domain;
    return $self->can_do_domain($permission,$domain);
}

1;
