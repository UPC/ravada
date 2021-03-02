Live web Chatwoot
=================

If you want to offer a communication channel for users. We propose this simple and powerful solution.

`Chatwoot <https://chatwoot.com>`_ is live chat software. It's open source and has a great community. You can access the code `here <https://github.com/chatwoot/>`_.

You need a Chatwoot server, you have differents options. If you are interested in self-hosted follow this `guide <https://www.chatwoot.com/docs/deployment/architecture>`_.

Here you will not find a `chatwoot manual <https://www.chatwoot.com/docs/channels/website>`_, only a few steps to embed your widget code.

Once you have the widget you have to paste it in two files.

Define widget in rvd_front.conf
-------------------------------
In ``/etc/rvd_front.conf`` configure the path to widget code. For example, ```chatwoot_widget.js```

.. code-block::

    ,widget => '/js/custom/chatwoot_widget.js'

Copy your code in the file: ``/usr/share/ravada/public/js/custom/chatwoot_widget.js``.

.. code-block::
	1 (function(d,t) {
	2   var BASE_URL = "https://chatwoot_server";
	3         var g=d.createElement(t),s=d.getElementsByTagName(t)[0];
	4         g.src= BASE_URL + "/packs/js/sdk.js";
	5         s.parentNode.insertBefore(g,s);
	6         g.onload=function(){
	7           window.chatwootSettings = {
	8             locale: 'ca',
	9             type: 'expanded_bubble',
	10             launcherTitle: 'Some message',
	11             showPopoutButton: true
	12           }
	13           window.chatwootSDK.run({
	14             websiteToken: 'xxxxxxxxx4Yh7RkXPtt1',
	15             baseUrl: BASE_URL
	16           })
	17         }
	18 })(document,"script");

.. image:: images/chat_login.png

.. image:: images/chat_inside.png

And restart rvd_front service:

.. prompt:: bash #

    systemctl restart rvd_front
