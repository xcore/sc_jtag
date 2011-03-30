JTAG communication
..................

:Stable release:  unreleased

:Status:  Feature complete

:Maintainer:  https://github.com/mattfyles

:Description:  Master JTAG communication, XCore JTAG access.


Key Features
============

* Master JTAG implementation
* Protocol to implement interaction with XCore over JTAG

To Do
=====

* Slave JTAG

Firmware Overview
=================

This repo contains modules to communicate over JTAG. The lowest
level modules implement the JTAG protocol. The high level modules
implement debug protocols over JTAG.

Known Issues
============

* None

Required Repositories
================

* xcommon git\@github.com:xcore/xcommon.git

Support
=======

Issues may be submitted via the Issues tab in this github repo. Response to any issues submitted as at the discretion of the maintainer for this line.
