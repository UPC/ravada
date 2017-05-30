.. highlight:: perl


****
NAME
****


Ravada::Auth::SQL - SQL authentication library for Ravada

BUILD
=====


Internal OO build method


search_by_id
============


Searches a user by its id


.. code-block:: perl

     my $user = Ravada::Auth::SQL->search_by_id( $id );



list_all_users
==============


Returns a list of all the usernames


add_user
========


Adds a new user in the SQL database. Returns nothing.


.. code-block:: perl

     Ravada::Auth::SQL::add_user(
                  name => $user
            , password => $pass
            , is_admin => 0
        , is_temporary => 0
     );



login
=====


Logins the user


.. code-block:: perl

      my $ok = $user->login($password);
      my $ok = Ravada::LDAP::SQL::login($name, $password);


returns true if it succeeds


make_admin
==========


Makes the user admin. Returns nothing.


.. code-block:: perl

      Ravada::Auth::SQL::make_admin($id);



remove_admin
============


Remove user admin privileges. Returns nothing.


.. code-block:: perl

      Ravada::Auth::SQL::remove_admin($id);



is_admin
========


Returns true if the user is admin.


.. code-block:: perl

     my $is = $user->is_admin;



is_external
===========


Returns true if the user authentication is not from SQL


.. code-block:: perl

     my $is = $user->is_external;



is_temporary
============


Returns true if the user is admin.


.. code-block:: perl

     my $is = $user->is_temporary;



id
==


Returns the user id


.. code-block:: perl

     my $id = $user->id;



change_password
===============


Changes the password of an User


.. code-block:: perl

     $user->change_password();


Arguments: password


language
========



.. code-block:: perl

   Updates or selects the language selected for an User
 
     $user->language();
 
   Arguments: lang



remove
======


Removes the user


.. code-block:: perl

     $user->remove();



can_do
======


Returns if the user is allowed to perform a privileged action


.. code-block:: perl

     if ($user->can_do("remove")) { 
         ...



grant_user_permissions
======================


Grant an user permissions for normal users


grant_operator_permissions
==========================


Grant an user operator permissions, ie: hibernate all


grant_manager_permissions
=========================


Grant an user manager permissions, ie: hibernate all clones


grant_admin_permissions
=======================


Grant an user all the permissions


grant
=====


Grant an user a specific permission, or revoke it


.. code-block:: perl

     $admin_user->grant($user2,"clone");    # both are 
     $admin_user->grant($user3,"clone",1);  # the same
 
     $admin_user->grant($user4,"clone",0);  # revoke a grant



revoke
======


Revoke a permission from an user


.. code-block:: perl

     $admin_user->revoke($user2,"clone");



list_all_permissions
====================


Returns a list of all the available permissions


list_permissions
================


Returns a list of all the permissions granted to the user


