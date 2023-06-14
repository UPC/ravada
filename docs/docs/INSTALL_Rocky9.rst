Install Ravada on Rocky Linux 9 or RHEL9
========================

Add Pre-Requisite Software
------------
.. prompt:: bash $
    sudo dnf install mariadb-server
.. prompt:: bash $

And don't forget to enable and start the server process:

.. prompt:: bash $

    sudo systemctl enable --now mariadb.service
    sudo systemctl start mariadb.service

MySQL database and user
~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. Warning:: If installing ravada on Ubuntu 18 or newer you should enter your user's password instead of mysql's root password.

Create the database:

.. prompt:: bash $

    sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

.. prompt:: bash $

    sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by 'Pword12345*'"

Add Another Pre-Requisite Software
------------
.. prompt:: bash $
    sudo dnf install httpd

Enable and Start HTTPD service
.. prompt:: bash $
    sudo systemctl start httpd
    sudo systemctl enable httpd
    sudo systemctl status httpd


Allow firewallD service
.. prompt:: bash $
    sudo firewall-cmd --permanent --add-port=80/tcp
    sudo firewall-cmd --permanent --add-port=443/tcp
    sudo firewall-cmd --reload


Requirements
------------

.. prompt:: bash $
    sudo dnf install qemu-kvm libvirt virt-manager virt-install iptables-services httpd mysql-server perl git


Install Required Perl Module using CPAN Shell
Open CPAN shell using
.. prompt:: bash $
    perl -MCPAN -e shell



Install Required Perl Modules using inside CPAN shell using
.. prompt:: bash $
    install Authen::SASL Authen::ModAuthPubTkt Authen::Passphrase Authen::Passphrase::SaltedDigest Carp DBIx::Connector Data::Dumper DateTime DateTime::Duration DateTime::Format::DateParse Digest::MD5 Digest::SHA Encode Encode::Locale Fcntl File::Basename File::Copy File::Path File::Rsync File::Tee Getopt::Long Hash::Util I18N::LangTags::Detect IO::Interface IO::Interface::Simple IO::Socket IPC::Run3 Image::Magick Image::Magick::Q16HDRI JSON::XS LWP::UserAgent Locale::Maketext Locale::Maketext::Lexicon MIME::Base64 Mojo::DOM Mojo::Home Mojo::JSON Mojo::Template Mojo::UserAgent Mojolicious Mojolicious::Lite Mojolicious::Plugin::Config Mojolicious::Plugin::I18N Moose Moose::Role Moose::Util::TypeConstraints MooseX::Types::NetAddr::IP Net::DNS Net::Domain Net::LDAP Net::LDAP::Entry Net::LDAP::Util Net::LDAPS Net::OpenSSH Net::Ping NetAddr::IP PBKDF2::Tiny POSIX Proc::PID::File Ravada Socket Storable Sys::Hostname Sys::Virt Sys::Virt::Domain Sys::Virt::Stream Time::HiRes Time::Piece URI URI::Escape XML::LibXML YAML base feature locale strict utf8 vars warnings          



OS
--

Ravada works in any Linux distribution.

.. note:: RPM packages are kindly built by a third party. Please check the release available. If you want the latest verstion it is adviced to install it on top of Ubuntu or Debian.

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

Make sure you are in root folder
-------------
.. prompt:: bash $
    cd /root


Download Ravada from Git Repo
--------------
.. prompt:: bash $
    git clone https://github.com/UPC/ravada.git


Install Ravada
--------------

Go to Ravada folder
.. prompt:: bash $
    cd ravada


Once Inside the Ravada folder, Install using make
.. prompt:: bash $
    make
    make install


Once Ravada Perl module has been installed, confirm the file has been installed perl libaries by typing
.. prompt:: bash $
    ls /usr/local/share/perl5/5.32/


If you "Ravada" folder and all the lib folders installed, you have successfully installed Ravada Perl module

Now, it's time to copy essential files 
.. prompt:: bash $
    cp -r /root/ravada /usr/share/ravada
    cp -r /root/ravada/etc/systemd/* /etc/systemd/system/
    cp /root/ravada/etc/ravada.conf /etc/
    cp /root/ravada/etc/rvd_front.conf.example /etc/rvd_front.conf
    sudo systemctl daemon-reload


Modify the rvd_front.conf accordingly

Now, it's time to install rvd_back service
.. prompt:: bash $
    perl /root/ravada/script/rvd_back
.

Once the rvd_back is installed, we need to add the admin for the web interface:
Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

When asked if this user is admin answer *yes*.
.. prompt:: bash $
    sudo /usr/sbin/rvd_back --add-user admin



We can enable the rvd_back and rvd_front service
.. prompt:: bash $
    sudo systemctl daemon-reload
    sudo systemctl enable rvd_back
    sudo systemctl enable rvd_front
    sudo systemctl start rvd_back
    sudo systemctl start rvd_front


Change the Qemu config
.. prompt:: bash $
    vim /etc/libvirt/qemu.conf 


Uncomment the following line:
.. prompt:: bash $
    save_image_format = "bzip2"


You have to restart libvirt after changing this file:
.. prompt:: bash $
    sudo systemctl restart libvirtd


Add link to kvm-spice
~~~~~~~~~~~~~~~~~~~~~
This may change in the future but actually a link to kvm-spice is required. Create it this way:

.. prompt:: bash $
    ln -s /usr/bin/qemu-kvm /usr/bin/kvm-spice


Finally, we need to copy the xml template to the location below:
.. prompt:: bash $
    mkdir /var/lib/ravada
    cp -r /root/ravada/etc/xml /var/lib/ravada/


Go ahead and restart rvd_back, rvd_front, and libvirtd to ensure everything is working as expected 
.. prompt:: bash $
    sudo systemctl restart rvd_back
    sudo systemctl restart rvd_front
    sudo systemctl restart libvirtd


Once everything goes as expected, you should be able to get to ravada web user-interface at:
 http://your.ip:8081/ or http://127.0.0.1:8081 if you run it in your own workstation.