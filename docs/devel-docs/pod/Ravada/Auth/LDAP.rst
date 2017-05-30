.. highlight:: perl


****
NAME
****


Ravada::Auth::LDAP - LDAP library for Ravada

BUILD
=====


Internal OO build


add_user
========


Adds a new user in the LDAP directory


.. code-block:: perl

     Ravada::Auth::LDAP::add_user($name, $password, $is_admin);



remove_user
===========


Removes the user


.. code-block:: perl

     Ravada::Auth::LDAP::remove_user($name);



search_user
===========


Search user by uid


.. code-block:: perl

   my $entry = Ravada::Auth::LDAP::search_user($uid);



add_group
=========


Add a group to the LDAP


remove_group
============


Removes the group from the LDAP directory. Use with caution


.. code-block:: perl

     Ravada::Auth::LDAP::remove_group($name, $base);



search_group
============



.. code-block:: perl

     Search group by name



add_to_group
============


Adds user to group


.. code-block:: perl

     add_to_group($uid, $group_name);



login
=====



.. code-block:: perl

     $user->login($name, $password);



is_admin
========


Returns wether an user is admin


is_external
===========


Returns true if the user authentication is external to SQL, so true for LDAP users always


init
====


LDAP init, don't call, does nothing


