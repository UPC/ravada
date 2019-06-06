Install Ravada from dockers
===========================

Requirements
------------

OS
--

Install `Docker <https://docs.docker.com/v17.12/install/>` and `docker-compose <https://docs.docker.com/compose/install/>` on your local machine.

Hardware
--------

It depends on the number and type of virtual machines. For common scenarios are server memory, storage and network bandwidth the most critical requirements.

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have.

Disks
~~~~~

The faster the disks, the better. Ravada uses incremental files for the
disks images, so clones won't require many space.

Install Ravada from dockers
---------------------------

.. note :: 
   We are working to improve this steps and to make it all automatic

For now, ravada source must be (locally) in: ```~/src/ravada```, you need to clone repository:

.. prompt:: bash $
   cd ~
   mdir src
   git clone https://github.com/UPC/ravada.git
   cd dockerfy
   
.. prompt:: bash $
   cd dockerfy
   docker-compose pull
   docker-compose up -d


Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

Connect to ravada-back docker: (We'll implement an automatically solution to avoid this case)

.. prompt:: bash $
   ~/src/ravada/dockerfy≻ docker exec -it ravada-back bash
   root@6c3089f22e77:/ravada# bin/rvd_back.pl --add-user admin
   admin password: acme
   is admin ? : [y/n] y

It's over!
You can connect to: http://localhost:3000

Client
------

The client must have a spice viewer such as virt-viewer. There is a
package for linux and it can also be downloaded for windows.

Run
---

The Ravada server is now installed, learn
`how to run and use it <http://ravada.readthedocs.io/en/latest/docs/production.html>`__.

Help
----

Struggling with the installation procedure ? We tried to make it easy but
let us know if you need `assistance <http://ravada.upc.edu/#help>`__.

There is also a `troubleshooting <troubleshooting.html>`__ page with common problems that
admins may face.
