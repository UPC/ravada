
# Create users


    sudo ./bin/rvd_back.pl --add-user=username

    sudo ./bin/rvd_back.pl --add-user-ldap=username


# Import KVM virtual machines.

Usually, virtual machines are created within ravada, but they can be
imported from existing KVM domains. Once the domain is created :

    sudo ./bin/rvd_back.pl --import-domain=a

It will ask the name of the user the domain will be owned by.
