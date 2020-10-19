Use a CAS login service to login into Ravada
============================================

In order to authenticate users into Ravada using a external CAS service you need to 
configure the URL of the external CAS service into ravada.conf YML file.

Configuration
-------------

The config file usually is /etc/ravada.conf. Add this configuration:

::

    cas:
        url: https://cas.upc.edu			        # External CAS Service location
        service: http://localhost:3000/login		# Ravada Service URL 
        cookie:
            priv_key: /etc/ravada/cas/priv_key.pem	# Pathname of the private key of the certificate that we will use to generate / validate session cookies
            pub_key: /etc/ravada/cas/pub_key.pem	# Pathname of the public key of the certificate that we will use to generate / validate session cookies
            type: rsa					            # Signature algorith: dsa, rsa,...
            timeout: 36000			                # Session cookie lifetime (in seconds)	

External libraries
------------------

You will need the Authen::ModAuthPubTkt library that can be downloaded from CPAN 

.. prompt:: bash

    sudo cpanm Authen::ModAuthPubTkt

How it works
------------

When an unauthenticated connection to Ravada is detected, the user is redirected to the CAS service authentication URL.

The CAS service authenticates the user and jumps to the Ravada service address by sending a session ticket as a parameter.

Ravada authenticates the ticket, obtains the user code and generates a session cookie for future user connections (since the ticket can only be authenticated once).

