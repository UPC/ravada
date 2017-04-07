
# Create users


    sudo ./bin/rvd_back.pl --add-user=username

    sudo ./bin/rvd_back.pl --add-user-ldap=username


# Import KVM virtual machines.

Usually, virtual machines are created within ravada, but they can be
imported from existing KVM domains. Once the domain is created :

    sudo ./bin/rvd_back.pl --import-domain=a

It will ask the name of the user the domain will be owned by.


# View all rvd_back options

In order to manage your backend easily, rvd_back has a few flags that
lets you made different things (like changing the password for an user).

If you want to view the full list, execute:

    sudo rvd_back --help
    
