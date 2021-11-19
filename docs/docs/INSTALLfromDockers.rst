Install Ravada from dockers
===========================

Requirements
------------

OS
--

Install `Docker <https://docs.docker.com/>`_ and `docker-compose <https://docs.docker.com/compose/install/>`_ on your local machine.

.. note ::
  There are several versions of the Compose file format – 1, 2, 2.x, and 3.x. For now, we use 2.2
  keep this in mind https://docs.docker.com/compose/compose-file/

As of now[at the time of writing this doc], we recommend

.. prompt:: bash $

  docker --version
   Docker version 10.7.0, build a872fc2f86
  docker-compose --version
   docker-compose version 0.8.0, build d4d1b42b

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

.. info:: Ravada source must be (locally) in: ``~/src/ravada``  

Follow this steps:

.. prompt:: bash $

   cd ~
   mkdir src
   cd src/
   git clone https://github.com/UPC/ravada.git 
   cd ravada/dockerfy
   
.. prompt:: bash $

   docker-compose pull
   docker-compose up -d


Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

Connect to ravada-back docker: (We'll implement an automatically solution to avoid this case)

.. prompt:: bash $

   ~/src/ravada/dockerfy> docker exec -it ravada-back bash
   root@6c3089f22e77:/ravada# PERL5LIB=./lib ./script/rvd_back --add-user admin
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

Dockers troubleshoots
---------------------

* Check if all dockers are up

.. prompt:: bash $
   
  docker-compose ps
  
* No such file or directory
   If you see this message remember that the source project must be in your HOME directory inside src directory:
   ~/src/ravada
   
.. prompt:: bash
  
  root@6f8d2946c40c:/ravada# PERL5LIB=./lib ./script/rvd_back --add-user soporte
  bash: ./script/rvd_back: No such file or directory


* Let's do a reset:
   We want to return to an initial starting point
   Remove all dockers and volume associated. 
   
.. prompt:: bash $
  
  cd ~/src/ravada/dockerfy/utils
  ./remove_all.sh 

Help
----

Struggling with the installation procedure ? We tried to make it easy but
let us know if you need `assistance <http://ravada.upc.edu/#help>`__.

Maybe this `slides <https://fv3rdugo.github.io/ravada-docker-slides/index.html#/>`_ can help you.

There is also a `troubleshooting <troubleshooting.html>`__ page with common problems that
admins may face.

  
