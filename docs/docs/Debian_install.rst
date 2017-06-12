Install on a Debian
===================

https://wiki.debian.org/KVM

qemu-kvm is compiled without --enable-spice

From ``/usr/src/qemu-2.1+dfsg/debian/rules``

::

	dd another set of configure options from debian/control common_configure_opts = \
        —with-pkgversion="Debian $(DEB_VERSION)" \
        —extra-cflags="$(CFLAGS) $(CPPFLAGS) -DCONFIG_QEMU_DATAPATH='\"${DATAPATH}\"' -DVENDOR_$(VENDOR)" \
        —extra-ldflags="$(LDFLAGS) -Wl,--as-needed" \
        —prefix=/usr \
        —sysconfdir=/etc \
        —libexecdir=/usr/lib/qemu \
        —localstatedir=/var \
        —disable-blobs \
        —disable-strip \
        —with-system-pixman \
        —interp-prefix=/etc/qemu-binfmt/%M \
        —localstatedir=/var \

You must compile with spice support.

::

	spice support     yes (0.12.7/0.12.5)
