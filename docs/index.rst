.. Ravada VDI documentation master file, created by
   sphinx-quickstart on Thu May 25 15:31:50 2017.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to Ravada VDI documentation
===================================

The chances are you're here because you've been searching for free Virtual Desktop Infrastructure (`VDI`_) documentation.
Whether it is a large or a small project, you can start with VDI and see its benefits right away! We assume you
do want to start your `VDI`_ project as quickly as possible. Therefore, RAVADA VDI is the perfect software for you!

`Ravada VDI`_ is a free and open-source project that allows users to connect to a virtual desktop. So it is a `VDI`_ `broker`_.

Ravada delivers
---------------

By following the documentation `Read the Docs`_ and editing some configuration files, you'll be able to deploy a VM within minutes.

Who is Ravada meant for?
------------------------

Ravada is meant for sysadmins who have some background in GNU/Linux, and want to deploy a VDI project.

.. note:: Get started with `VDI`_, without reinventing the wheel.

We have written some documentation and hosted it on `Read the Docs`_ for you.
This documentation is *on-going*, so if there is something you think is missing, don't hesitate and drop us a line! In the
meantime, we are still improving RAVADA VDI and its documentation, so new sections will be popping out from time to time.

Our code uses the `AGPL`_ license and it is `available on GitHub`_.

.. _Ravada VDI: https://ravada.upc.edu/
.. _VDI: https://en.wikipedia.org/wiki/Desktop_virtualization
.. _broker: https://en.wikipedia.org/wiki/Connection_broker
.. _AGPL: https://github.com/UPC/ravada/blob/master/LICENSE
.. _Read the Docs: http://readthedocs.org/
.. _available on GitHub: https://github.com/UPC/ravada

Ravada VDI documentation
------------------------

The main documentation for the site is divided into three main sections:

* :ref:`admin-docs`
* :ref:`feature-docs`
* :ref:`guest-docs`

Do you feel like giving us a hand? Here you have all the information you need as *a developer*:

* :ref:`dev-docs`

.. _admin-docs:

.. toctree::
   :caption: Administrator Documentation
   :maxdepth: 2

   docs/INSTALL
   docs/INSTALL_Ubuntu
   docs/INSTALL_Debian
   docs/Debian_install
   docs/INSTALL_Fedora
   docs/INSTALL_Rocky9
   docs/INSTALL_ubuntu_xenial.rst
   docs/INSTALLfromDockers.rst
   docs/production
   docs/logs
   docs/recomendations
   docs/INSTALL_devel
   docs/add_kvm_storage_pool
   docs/apache
   docs/convert_from_virtualbox
   docs/How_Create_Virtual_Machine
   docs/dump_hard_drive
   docs/ldap_local
   docs/new_kvm_template
   docs/new_iso_image
   docs/Localized_ISO_download
   docs/OpenGnsys_import_image.rst
   docs/OpenGnsys_iPXE_support.rst
   docs/operation
   docs/swap_partition
   docs/troubleshooting
   docs/update
   docs/update_safe
   docs/update_rollback
   docs/windows_clients
   docs/mac_clients
   docs/macos_spice_client
   docs/RDP_connection
   docs/change_windows_driver_to_virtio
   docs/Backup
   docs/migrate_manual
   docs/Kiosk_mode
   docs/volatile
   docs/nodes
   docs/How_to_make_virtual_machine_sparse
   docs/Server_Hardware
   docs/Cluster_Hardware
   docs/CLI
   docs/Automatic_daily_operations
   docs/sso_login
   docs/auth_openid
   docs/apparmor
   docs/status
   docs/compact
   docs/install_tpm
   docs/mount_virtual_volume
   docs/replace_server
   docs/report_rrdgraph
   docs/users_upload
   docs/volume_differences
   docs/ROADMAP

.. _feature-docs:

.. toctree::
   :maxdepth: 2
   :glob:
   :caption: Feature Documentation

   docs/custom
   docs/custom_login
   docs/custom_footer
   docs/Disable_spice_password
   docs/advanced_settings
   docs/new_documentation
   docs/auth_ldap
   docs/auth_active_directory
   docs/sso_login
   docs/access_restrictions
   devel-docs/test_ad
   docs/tuning
   docs/monitoring
   docs/guide
   docs/local_resources
   docs/expose_machine
   docs/expose_ports
   docs/Rebase
   docs/spinoff_clone
   docs/chatwoot
   docs/pci_passthrough
   docs/network_bridge
   docs/Virtiofs
   docs/Firewall

.. _guest-docs:

.. toctree::
   :maxdepth: 2
   :caption: Guest VM section

   docs/install_guest_linux
   docs/install_guest_alpine
   docs/install_guest_windows10
   docs/install_guest_windows11
   docs/resize_hard_drive_windows
   docs/resize_hard_drive_linux_machine
   docs/grow_hard_drive_linux_lvm
   docs/config_console
   docs/reduce-size-image
   docs/qemu_ga
   docs/set_hostname


.. _about-docs:

.. toctree::
   :maxdepth: 2
   :caption: About Ravada

.. _dev-docs:

.. toctree::
   :maxdepth: 2
   :caption: Developer Documentation

   devel-docs/development_tools
   devel-docs/commit-rules
   devel-docs/database_changes
   devel-docs/create_grants
   devel-docs/profiling
   devel-docs/editor-rules
   devel-docs/local_iso_server
   devel-docs/run
   devel-docs/test
   devel-docs/create_test
   devel-docs/translations
   devel-docs/documentation
   devel-docs/frontend_libraries.rst
   docs/spice_tls
