.. Ravada VDI documentation master file, created by
   sphinx-quickstart on Thu May 25 15:31:50 2017.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Ravada VDI documentation
===================================

Chances are you're here because you searched information about free Virtual Desktop Infraestructure.
Whether it is a large or a small project, you can start in VDI and see its benefits. We are assuming that you want to start your VDI project as quickly as possible.

`Ravada VDI`_ is a software that allows the user to connect to an virtual desktop. So it is a **VDI broker**.

Ravada delivers
---------------

With some configurations and following the documentation, you'll be ready to deploy a VM in just a few hours.

Who is Ravada meant for?
------------------------

Ravada is meant for sysadmins who have some background in GNU/Linux, and want to deploy a VDI project.

.. note:: Get started on VDI, without reinvent the wheel.

We're proud to program it in `Perl`_. Perl 5 is a highly capable, feature-rich programming language with over 29 years of development. `More about why we love Perl...`_.
We use `Mojolicious`_, a real-time web framework. We use `MySQL`_. It's the world's most popular open source database. With its proven performance, reliability, and ease-of-use.
We use a lot of powerful free source like `GNU`_/Linux `Ubuntu`_, `KVM`_ or `Spice`_, among others. Responsive web made with `Bootstrap`_ and `AngularJS`_.

We use `Transifex`_ to provide a cleaner and easy to use interface for translators. It's meant for adapting applications and text to enable their usability in a particular cultural or linguistic market.

Then we build documentation and host it in `Read the Docs`_ for you.

Think of it as *Continuous Documentation*.

Our code is licensed with `AGPL`_ and is `available on GitHub`_.

.. _Ravada VDI: https://ravada.upc.edu/
.. _Perl: https://www.perl.org/
.. _More about why we love Perl...: https://www.perl.org/about.html
.. _Mojolicious: http://www.mojolicious.org/
.. _Mysql: https://www.mysql.com/
.. _GNU: https://www.gnu.org/
.. _Ubuntu: https://www.ubuntu.com/server
.. _KVM: http://www.linux-kvm.org/
.. _Spice: https://www.spice-space.org/
.. _Bootstrap: getbootstrap.com/
.. _AngularJS: https://angularjs.org/
.. _Transifex: https://www.transifex.com/ravada/ravada/
.. _AGPL: https://github.com/UPC/ravada/blob/master/LICENSE
.. _Read the Docs: http://readthedocs.org/
.. _available on GitHub: https://github.com/UPC/ravada

The main documentation for the site is organized into a couple sections:

* :ref:`user-docs`
* :ref:`feature-docs`
* :ref:`about-docs`

Information about development is also available:

* :ref:`dev-docs`

.. _user-docs:

.. toctree::
   :caption: User Documentation
   :maxdepth: 2
   
   docs/INSTALL
   docs/INSTALL_devel
   docs/Ubuntu_Installation
   docs/add_kvm_storage_pool
   docs/apache
   docs/convert_from_virtualbox
   docs/custom
   docs/How_Create_Virtual_Machine
   docs/dump_hard_drive
   docs/ldap_local
   docs/new_iso_image
   docs/operation
   docs/production
   docs/swap_partition
   docs/troubleshooting
   docs/update
   docs/windows_clients
   docs/custom_login

.. _feature-docs:

.. toctree::
   :maxdepth: 2
   :glob:
   :caption: Feature Documentation
   docs/new_documentation
   devel-docs/translations
         
.. _about-docs:

.. toctree::
   :maxdepth: 2
   :caption: About Ravada

.. _dev-docs:

.. toctree::
   :maxdepth: 2
      :caption: Developer Documentation

   devel-docs/commit-rules
   devel-docs/database_changes
   devel-docs/editor-rules
   devel-docs/local_iso_server
   devel-docs/release
   devel-docs/run
   devel-docs/test
