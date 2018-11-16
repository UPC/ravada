==============
Ravada Cluster
==============
----------------------------------------
Adding support for multiple Ravada nodes
----------------------------------------

Description
===========

From release 0.4 we have clustering support for Ravada. This allows the administrator
to add more physical hosts so virtual machines are balanced and distributed among all
them.

.. image:: images/nodes_machines.png

This feature is currently in alpha stage. It works but the management forms are ugly
and we need to test it more.

Nodes
=====

A node is a Ravada backend server that runs the virtual machines. With the current
implementation it is required a main master node and secondary nodes can be added
later. The master node, also known as local node should be a rock solid server.
It will also run some of the virtual machines as they get balanced among all the nodes.
Having fault tolerance master node is beyond the scope of this document, but we expect
to add a new document for examples of how to achieve it in the future. Contributions
welcome.

Secondary nodes are disposible physical hosts. It is our goal to allow theses nodes
be up and down at the administrator will and that they could be easily added
to a cluster.
Ravada should be able to cope with sudden death of those nodes, though it is better if
they are disabled and shut down nicely from the Ravada node administation frontend.

Storage
=======

Shared storage is not necessary nor supported in this current release. All the nodes
must have their own isolated storage. It is advisable to have it on local fast drives
for better performance. When bases are created, the administrator can configure on
which nodes will be available for the virtual machines.

All the master and nodes must have the same storage pools configuration.

New node
========

Requirements
------------

To add a new node to a Ravada cluster you have to install a minimal Linux operating
system with some specific applications. ( TODO: review this )

- ssh
- libvirt-bin
- qemu

It is possible to have nodes with heterogeneous operative systems: different Ubuntus,
Debians, even RedHats or Fedoras can be added, though it should be easier if all of
them are similar or identical if possible.

Configuration
-------------

The master ravada node needs to access to the secondary nodes through SSH. So password-less
access must be configured between them. This is an example of configuring in Debian and
Ubuntu servers. Other flavours of linux should be quite the same.

First, temporary allow *root* access with *ssh* to the remote node.

.. code-block:: bash

    root@node:~# vi /etc/ssh/sshd_config
    PermitRootLogin yes

Then set a root password and restart ssh service:

.. code-block:: bash

    root@node:~# passwd
    Enter new UNIX password: *******
    root@node:~# systemctl restart ssh

Check you can access with *root* from master to node:

.. code-block:: bash

    root@master:~# ssh nenufar


You may already have a public/private key created in the master node. Check if there
are id*pub files in /root/.ssh directory. Create the keys otherwise:

.. code-block:: bash

    root@master:~# ls /root/.ssh/id*pub || ssh-keygen

Now you must copy the public ssh key from master to node:

.. code-block:: bash

    root@master:~# ssh-copy-id -i /root/.ssh/id_rsa.pub node

Check it works:

.. code-block:: bash

    root@master:~# ssh node

Now you can restore the *PermitRootLogin* entry to the former state in
the file */etc/ssh/sshd_config* at *node*.

Security
--------

It is advisable have a firewall configured in the node. Access restrictions
should be enforced carefully. Only allow ssh login from the master server
and other operational hosts from your network.

Operation
=========

Add nodes in the new section *Admin Tools - Nodes*

Allow a base to create clones in nodes checking them in the machine management section,
at the *Base* tab.

.. image:: images/nodes_base.png

Now try to create multiple clones from a base, they should get balanced
among all the nodes including the master one.

TODO
====

We already know we have to improve:

- administration forms in the web front end
- check if nodes storage gets filled

This is a new feature, we are currently testing. Feedback welcome through our
Telegram public forum http://t.me/ravadavdi
