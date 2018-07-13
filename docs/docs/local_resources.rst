Local js and css files
======================

Local vs CDN this is the question. 
For default we used CDN, but in some specific cases it may be useful to have the libraries JS and CSS locally.

You need to install `yarn <https://yarnpkg.com/en/docs/install#debian-stable>`_.

You need to run:

::

	$ cd /usr/share/ravada
	$ yarn config set -- --modules-folder /usr/share/ravada/public/fallback
	$ yarn

`Yarn <https://yarnpkg.com>`_ reads from ``package.json`` the requirements and download locally in ``/usr/share/ravada/public/fallback``.

To finish, enable the ``fallback`` parameter in /etc/rvd_front.conf and restart the rvd_front.service to apply changes.

:: 	

	fallback => 1

Refresh your browser cache and now Ravada use JS and CSS locally.
