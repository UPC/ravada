You need a LDAP server to run the ldap tests

# Install 389 directory server

## Install and configure 389-ds

Install this package, when configuring write down the user
and password of the Directory Manager. In this example it is
cn=Directory Manager, password: 12345678

    $ sudo apt-get install 389-ds-base
    $ sudo setup-ds

## Start ds

    $ sudo systemctl start dirsrv.target

or you may have to start the specific instance, that is probably the hostname

    $ sudo systemctl start dirsrv@instance.target


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

# Run only the ldap tests

Build the source lib dirs and Makefiles

    $ perl Makefile.PL

Run the tests each time you change the source file

    $ make && prove -b t/65*t t/front/60_ldap.t t/front/70_ldap_access.t
