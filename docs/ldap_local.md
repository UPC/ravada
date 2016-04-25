#How to Install a local LDAP

##Install and configure 389-ds

    $ sudo apt-get install 389-ds-base
    $ sudo setup-ds

##Insert one test user

First create the file user.ldif. Use the domain name that your host belongs to
in the first line:

    dn: uid=jdoe,ou=People,dc=domain,dc=name
    objectClass: top
    objectClass: person
    objectClass: organizationalPerson
    objectClass: inetOrgPerson
    uid: jdoe
    cn: John Doe
    displayName: John Doe
    givenName: John
    sn: Doe
    userPassword: test


Insert that file in the ldap server:

    $ ldapadd -h 127.0.0.1 -x -D "cn=Directory Manager" -W -f user.ldif

Now you can user the former user with the login name "jdoe" and password "test"

