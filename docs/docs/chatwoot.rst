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

.. image:: images/chat_login.png

.. image:: images/chat_inside.png

And restart rvd_front service:

.. prompt:: bash #

    systemctl restart rvd_front
