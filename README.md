# shibboleth-idp-quickstart

### What is it

This is a simple script to install tomcat/jetty and shibboleth idp, and configure them to work.

Currently, it only supports the recently Ubuntu(like Ubuntu 18.04) or Centos(like Centos 7), other version of Ubuntu/Centos is not tested. Other OS support like SUSE may come soon.

### How to use it

> All you need it clone or download zip, cd the root directory, modify config.properties which is self-explained, and run install.sh as **root** user.

Because some attribute settings are too complex for different environment, and you should modify these file like `/opt/shibboleth-idp/conf/attribute-filter.xml`, `/opt/shibboleth-idp/conf/attribute-resolver.xml` and so on. See https://wiki.carsi.edu.cn/pages/viewpage.action?pageId=1998859 for more detailed instructions.

_PR is welcome!_

### Todos

- [x] Add colored output message.
- [ ] Add some kind attribute-resolver/attribute-filter automatic replacement support.
- [ ] Add SUSE support.

### Snapshots

![quickstart](resources/quickstart.svg)

### LICENSE

MIT License

Copyright (c) 2020 liudonghua
