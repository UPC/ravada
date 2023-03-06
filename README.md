# ravada 

[![GitHub version](https://img.shields.io/badge/version-1.8.0-brightgreen.svg)](https://github.com/UPC/ravada/releases) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://github.com/UPC/ravada/blob/master/LICENSE)
[![Documentation Status](https://readthedocs.org/projects/ravada/badge/?version=latest)](http://ravada.readthedocs.io/en/latest/?badge=latest)
[![Follow twitter](https://img.shields.io/twitter/follow/ravada_vdi.svg?style=social&label=Twitter&style=flat-square)](https://twitter.com/ravada_vdi)
[![Telegram Group](https://img.shields.io/badge/Telegram-Group-blue.svg)](https://t.me/ravadavdi)
[![Project Status: Active - The project has reached a stable, usable state and is being actively developed.](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)
[![Translation status](https://hosted.weblate.org/widgets/ravada/-/svg-badge.svg)](https://hosted.weblate.org/engage/ravada/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

## Remote Virtual Desktops Manager

Ravada is a software that allows the user to connect to a
remote virtual desktop.
Ravada is meant for sysadmins who have some background in GNU/Linux, and want to deploy a VDI project.

Its back-end has been designed and implemented in order to allow future hypervisors to be added to the framework. Currently, it supports KVM and LXC is in the works.

The client only requirements are: a web-browser and a remote viewer supporting the spice protocol.

In the current release we use the
KVM Hypervisors: [KVM](http://www.linux-kvm.org/) as the backend for the Virtual Machines.
 [LXC](https://linuxcontainers.org/) support is currently in development.

### Features

 * KVM backend for Windows and Linux Virtual machines
 * LDAP and SQL authentication
 * Kiosk mode
 * Remote Access with [Spice](http://www.spice-space.org/) for Windows and Linux
 * Light and fast virtual machine clones for each user
 * Instant clone creation
 * USB redirection
 * Easy and customizable end users interface
 * Administration from a web browser

## Install

Read [INSTALL](http://ravada.readthedocs.io/en/latest/docs/INSTALL.html).


### Production

See [production](http://ravada.readthedocs.io/en/latest/docs/production.html)
for production fine-tuning guidelines.

### Operation

See [operation](http://ravada.readthedocs.io/en/latest/docs/operation.html).

### Update

See [update](http://ravada.readthedocs.io/en/latest/docs/update.html).
