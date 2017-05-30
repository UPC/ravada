.. highlight:: perl


****
NAME
****


Ravada::Auth - Authentication library for Ravada users

init
====


Initializes the submodules


login
=====


Tries login in all the submodules


.. code-block:: perl

     my $ok = Ravada::Auth::login($name, $pass);



LDAP
====


Sets or get LDAP support.


.. code-block:: perl

     Ravada::Auth::LDAP(0);
 
     print "LDAP is supported" if Ravada::Auth::LDAP();



