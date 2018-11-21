You need a LDAP server to run the ldap tests

# Install 389 directory server

## Install and configure 389-ds

Install this package, when configuring write down the user
and password of the Directory Manager.

    $ sudo apt-get install 389-ds-base
    $ sudo setup-ds

## Start ds

    $ sudo systemctl start dirsrv.target

<<<<<<< HEAD
or you may have to start the specific instance, that is probably the hostname

    $ sudo systemctl start dirsrv@instance.target


=======
>>>>>>> c746a4990c05199c191f5611f367b57c3f4c912c
# Add a test config file

We need to run the tests on this LDAP server,
edit thes file and add there the information
you set up before

- t/etc/ravada_ldap.conf

Example:

    ---
    ldap:
      admin_user:
        dn: cn=Directory Manager
        password: 12345678
      auth: match
      base: 'dc=yournetwork,dc=comorwhatever'
      posix_group: rvd_posix_group
