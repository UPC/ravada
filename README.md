# ravada

[![GitHub version](https://img.shields.io/badge/version-1.8.0-brightgreen.svg)](https://github.com/UPC/ravada/releases) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/UPC/ravada/blob/master/LICENSE)
[![Documentation Status](https://readthedocs.org/projects/ravada/badge/?version=latest)](http://ravada.readthedocs.io/en/latest/?badge=latest)
[![Follow twitter](https://img.shields.io/twitter/follow/ravada_vdi.svg?style=social&label=Twitter&style=flat-square)](https://twitter.com/ravada_vdi)
[![Telegram Group](https://img.shields.io/badge/Telegram-Group-blue.svg)](https://t.me/ravadavdi)
[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Translation status](https://hosted.weblate.org/widgets/ravada/-/svg-badge.svg)](https://hosted.weblate.org/engage/ravada/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

## Remote Virtual Desktops Manager

Ravada is an open-source project that provides a web-based user interface for managing and accessing virtual machines (VMs) based on the QEMU/KVM virtualization technology. Ravada aims to simplify the management of virtual machines by offering a user-friendly interface accessible through a web browser.Ravada is meant for sysadmins who have some background in GNU/Linux, and want to deploy a VDI project.

Users can use Ravada to create, configure, and manage virtual machines without the need for a dedicated desktop client. It provides features such as remote console access, snapshot management, and the ability to manage multiple VMs from a central interface. Ravada's back-end has been designed and implemented in order to allow future hypervisors to be added to the framework.

The client only requirements are: a web-browser and a remote viewer supporting the spice protocol.

In the current release we use the
KVM Hypervisors: [KVM](http://www.linux-kvm.org/) as the backend for the Virtual Machines.

### Features

- KVM backend for Windows and Linux Virtual machines
- LDAP and SQL authentication
- Kiosk mode
- Remote Access with [Spice](http://www.spice-space.org/) for Windows and Linux
- Light and fast virtual machine clones for each user
- Instant clone creation
- USB redirection
- Easy and customizable end users interface
- Administration from a web browser

## Install

Read [INSTALL](http://ravada.readthedocs.io/en/latest/docs/INSTALL.html).

Install Ravada in [Ubuntu](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Ubuntu.html)
Install Ravada in [Debian](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Debian.html)
Install Ravada on [Fedora](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Fedora.html)
Install Ravada on [Rocky Linux 9 or RHEL9](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Rocky9.html#install-ravada-on-rocky-linux-9-or-rhel9)
Install Ravada - [Ubuntu Xenial](https://ravada.readthedocs.io/en/latest/docs/INSTALL_ubuntu_xenial.html)

### Production

See [production](http://ravada.readthedocs.io/en/latest/docs/production.html)
for production fine-tuning guidelines.

### Operation

See [operation](http://ravada.readthedocs.io/en/latest/docs/operation.html).

- [Create users](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Ubuntu.html)
- [Import KVM virtual machines](https://ravada.readthedocs.io/en/latest/docs/INSTALL_Ubuntu.html)
- [View all rvd_back options](https://ravada.readthedocs.io/en/latest/docs/operation.html#view-all-rvd-back-options)
- [Admin Operations](https://ravada.readthedocs.io/en/latest/docs/operation.html#admin)

### Update

See [update](http://ravada.readthedocs.io/en/latest/docs/update.html).
