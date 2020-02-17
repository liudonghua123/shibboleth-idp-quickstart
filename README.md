# shibboleth-idp-quickstart

This is a simple script to install tomcat/jetty and shibboleth idp, and configure them to work.

Currently，it only supports the recently Ubuntu(like Ubuntu 18.04) or Centos(like Centos 7), other version of Ubuntu/Centos is not tested. Other OS support like SUSE may come soon.

> All you need it clone or download zip, cd the root directory, and run install.sh as **root** user.

Because some attribute settings are too complex, and you should modify these file like `/opt/shibboleth-idp/conf/attribute-filter.xml`, `/opt/shibboleth-idp/conf/attribute-resolver.xml` and so on.