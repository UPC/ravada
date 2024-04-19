Offline libraries in frontend
=============================

Javascript and CSS libraries can be configured in the local server
instead of using a CDN. 

- CDNs deliver faster loading speeds for users
- CDNs lower the cost of bandwidth.
- Improved SEO
- Handling spikes in traffic

But some users behind firewalls may experience rendering problems, from China i.e.
By default we use CDN versions of the JavaScript and CSS libraries.
In some specific cases it may be useful to have those libraries in
the same server as the Ravada web frontend runs.

Since Ravada 0.5 release we package the required javascript and CSS files.
You can enable the local copy setting the file ``/etc/rvd_front.conf`` in your
host.

::

	fallback => 1

and restart the rvd_front.service to apply changes.

.. prompt:: bash #

	systemctl restart rvd_front.service

Refresh your browser cache and now Ravada use JS and CSS downloaded from your
own server.
