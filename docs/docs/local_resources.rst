Local js and css files
======================

Local vs CDN this is the question. For default we used CDN. But in some specific cases it may be useful to have the libraries Js and css locally.

You need to run:

::

	$ cd /usr/share/ravada
	$ yarn config set -- --modules-folder /usr/share/ravada/public/fallback
	$ yarn

Yarn reads from ``package.json`` the requirements and download locally in ``/usr/share/ravada/public/fallback``.

To finish enable the ``fallback`` parameter in /etc/rvd_front.conf and restart the rvd_front.service to apply changes.

:: 	

	fallback => 1
