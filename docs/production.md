# Running Ravada in production

Ravada has two daemons that must run on the production server:

- rvd_back : must run as root and manages the virtual machines
- rvd_front : is the web frontend that sends requests to the backend

## Apache

It is advised to run an apache server or similar before the frontend.

    # apt-get install apache2

## Systemd


### Configuration for boot start

There are two _systemd_ services to start and stop the two ravada daemons:

After install or upgrade you may have to refresh the systemd service units:

    $ sudo systemctl daemon-reload

Check the services are enabled to run at startup

    $ sudo systemctl enable rvd_back
    $ sudo systemctl enable rvd_front

### Start or stop

    $ sudo systemctl start rvd_back
    $ sudo systemctl start rvd_front


## Firewall

Ravada uses `iptables` to restrict the access to the virtual machines. 
Thes iptables rules grants acess to the admin workstation to all the domains
and disables the access to everyone else.
When the users access through the web broker they are allowed to the port of
their virtual machines. Ravada uses its own iptables chain called 'ravada' to
do so:

    -A INPUT -p tcp -m tcp -s ip.of.admin.workstation --dport 5900:7000 -j ACCEPT
    -A INPUT -p tcp -m tcp --dport 5900:7000 -j DROP

