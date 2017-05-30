.. highlight:: perl


###############
Ravada::Network
###############

****
NAME
****


Ravada::Network - Networks management library for Ravada


***********
Description
***********



.. code-block:: perl

     my $net = Ravada::Network->new(address => '127.0.0.1/32');
     if ( $net->allowed( $domain->id ) ) {


allowed
=======


Returns true if the IP is allowed to run a domain


.. code-block:: perl

     if ( $net->allowed( $domain->id ) ) {



requires_password
=================


Returns true if running a domain from this network requires a password


.. code-block:: perl

     if ($net->requires_password) {
         .....
     }



