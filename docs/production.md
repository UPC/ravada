#Running Ravada in production

Ravada has two daemons that must run on the production server:

- rvd_back : must run as root and manages the virtual machines
- rvd_front : is the web frontend that sends requests to the backend

## Application directory

The ravada application should be installed
in /var/www/ravada

## Ravada system user

The frontend daemon must run as a non-privileged user.

    # useradd ravada

Allow it to write to some diretories inside /var/www/ravada/

    # mkdir /var/www/ravada/log
    # chown ravada /var/www/ravada/log
    # chgrp ravada /etc/ravada.conf
    # chmod g+r /etc/ravada.conf
    # mkdir -p /var/www/img/screenshots/
    # chown ravada /var/www/img/screenshots

## Apache

It is advised to run an apache server or similar before the frontend.

    # apt-get install apache2
    
## Systemd


### Configuration for boot start

First you have to copy the service scripts to the systemd directory:

    $ cd ravada/etc/systemd/
    $ sudo cp *service /lib/systemd/system/

Edit _/lib/systemd/system/rvd_front.service_ and change `User=****` to the _ravada_
user just created.



Then enable the services to run at startup

    $ sudo systemctl enable rvd_back
    $ sudo systemctl enable rvd_front

### Start or stop

    $ sudo systemctl stop rvd_back
    $ sudo systemctl stop rvd_front

## Other systems

For production mode you must run the front end with a high perfomance server like hypnotoad:

    $ hypnotoad ./rvd_front.pl

And the backend must run from root
    # ./bin/rvd_back.pl &


## Firewall

Ravada uses `iptables` to restrict the access to the virtual machines. 
Thes iptables rules grants acess to the admin workstation to all the domains
and disables the access to everyone else.
When the users access through the web broker they are allowed to the port of
their virtual machines. Ravada uses its own iptables chain called 'ravada' to
do so:

    -A INPUT -p tcp -m tcp -s ip.of.admin.workstation --dport 5900:7000 -j ACCEPT
    -A INPUT -p tcp -m tcp --dport 5900:7000 -j DROP
