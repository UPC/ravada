Testing environment
===================

At the project root directory run:

.. prompt:: bash $

    perl Makefile.PL
    sudo make test

At the end, in "Test Summary Report" you can check the result.

If something goes wrong you see: Result: FAIL

Run a single test
-----------------

Tests are in the *t* directory.

.. prompt:: bash $

    make; sudo prove -l t/vm/05_open.t


Advanced Features tests
-----------------------

LDAP
~~~~

Install a `local LDP server  <http://ravada.readthedocs.io/en/latest/docs/ldap_local.html>`_
to run the LDAP tests.

Nodes
~~~~~

Install two virtual machines called ztest-1 and ztest-2 with these features:

 - Disk Size: 20 GB
 - RAM : At least 4 GB

Follow the remote nodes configuration guide so those machines can be accessed
from root in the test host. Also, KVM virtual packages are required. The easiest
way is install a virtual machine and clone it twice.
Both machines must answer to two IPs as defined in the configurationa.

Place in t/etc/remote_vm.conf this config file:

::

   ztest-1:
       vm:
           - KVM
           - Void
       host: 192.168.122.151
       public_ip: 192.168.122.251
   ztest-2:
       vm:
           - KVM
           - Void
       host: 192.168.122.152
       public_ip: 192.168.122.252


Base Test machine
~~~~~~~~~~~~~~~~~~

Create a small virtual machine called z-test-base:

 - OS: Debian Stretch 64 Bits
 - Disk: size: 6 GB
 - RAM: 1 GB

Configure the `Set Hostname <http://ravada.readthedocs.io/en/latest/docs/set_hostname.html>`_
so it gets automatically changed on statup.

You can remove office packages and trim it down with virt-sparsify.
Install openssh-server in base.

Allow root user from host test machine password-less ssh to the PCs.

When everything is set up prepare this machine as a base. When it is done you can run
the tests and it will be used to create clones and check stuff on it.

