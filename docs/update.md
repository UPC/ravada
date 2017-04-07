In order to update your ravada, you have to do a few
steps from the install and production documents that
we will show here.


# Steps for a clean update

Step 1: Download the _deb_ package of the new version
        found at the [UPC ETSETB repository](http://infoteleco.upc.edu/img/debian/).

Step 2: Install the _deb_ package.

    $ sudo dpkg -i ravada_0.1.2_all.deb
    
Step 3: Reconfigurate the systemd.

    $ sudo systemctl daemon-reload
    $ sudo systemctl enable rvd_back
    $ sudo systemctl enable rvd_front
    
Step 4: Start the services.

    $ sudo systemctl start rvd_back
    $ sudo systemctl start rvd_front
    
