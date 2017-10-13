Test Active Directory
=====================

This document is a guide to test Active Directory features from Ravada source.

If you want to test the active directory you must create 2 files: one for the
ravada configuration parameters, and another one with AD user and password to test.

Ravada Conf
-----------

Create a file : t/etc/ravada_ad.conf with these contents:

::

    ActiveDirectory:
        host: thehost
        port: 389
        domain: thedomain
        principal: theprincipalwhatever it is

Auth data
---------
It is required a valid user and password to test AD. Put them in the file t/etc/test_ad_data.conf

::
    name: theusername
    password: thepassword

Run the tests
-------------

From the source root directory run:

::
    $ perl Makefile.PL
    $ make && prove -b t/67_user_ad.t


