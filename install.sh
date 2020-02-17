#!/usr/bin/env bash

CONFIG_FILE=config.properties

# read property utility
function get_property
{
    grep "^$1=" $CONFIG_FILE | cut -d'=' -f2-
}

function cleanup
{
    rm -rf /opt/credentials
    rm -rf /opt/apache-tomcat-8.5.51
    rm -rf /opt/shibboleth-idp
}

function get_os
{
    cat /etc/os-release | grep "^ID=" |  cut -d= -f2-
}

function set_java_environment
{
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
    JRE_HOME="$(dirname $(dirname $(readlink -f $(which javac))))/jre"
    grep JAVA_HOME /etc/environment 2>/dev/null && echo "JAVA_HOME already set" || echo "export JAVA_HOME=$JAVA_HOME" >> /etc/environment
    grep JRE_HOME /etc/environment 2>/dev/null && echo "JRE_HOME already set" || echo "export JRE_HOME=$JRE_HOME" >> /etc/environment
    source /etc/environment
}

function check_java
{
    echo "checking java!"
    which java
    if [ $? -ne 0 ]; then
        echo "You should install java and set JAVA_HOME/JRE_HOME correctly before this operation"
        echo "Now install java..."
        OS=$(get_os)
        case "$OS" in
        ubuntu)
            apt-get update
            apt-get install -y openjdk-8-jdk
            ;;
        centos)
            yum update -y
            yum install -y java-1.8.0-openjdk-devel java-1.8.0-openjdk
            ;;
        *)
            echo "Unsupport OS, please contact liudonghua123@gmail.com"
            exit 1
            ;;
        esac
        set_java_environment
    elif [ -z "$JAVA_HOME" -o -z "$JRE_HOME" ]; then
        echo "JAVA_HOME/JRE_HOME not set correctly, set them in /etc/environment"
        set_java_environment
        echo "Java installed and configured ok"
    fi
}

function install_ldap_util
{
    OS=$(get_os)
    case "$OS" in
    ubuntu)
        apt-get update
        apt-get install -y ldap-utils
        ;;
    centos)
        yum update -y
        yum install -y openldap-clients
        ;;
    *)
        echo "Unsupport OS, please contact liudonghua123@gmail.com"
        exit 1
        ;;
    esac
}

function install_credentials
{
    echo "checking and creating credentials keystore!"
    # check whether credentials exist
    if [ ! -f "$(get_property credentials.keystore.path)" ]; then
        mkdir -p /opt/credentials 2>/dev/null
        echo "keystore $(get_property credentials.keystore.path) not exist, try to generate from pem format of $(get_property credentials.key.path) and $(get_property credentials.certs.path)"
        if [ ! -f "$(get_property credentials.key.path)" ]; then
            echo "key $(get_property credentials.key.path) not exits, will generate a self signed key and cert pair"
            openssl req -x509 -sha256 -nodes -days 3650 -subj "/CN=*.ynu.edu.cn"  -newkey rsa:2048 -keyout $(get_property credentials.key.path) -out $(get_property credentials.certs.path)
        fi
        # now the key and cert are prepared
        openssl pkcs12 -export -out $(get_property credentials.keystore.path) -inkey $(get_property credentials.key.path) -in $(get_property credentials.certs.path) -passout pass:changeit
    fi
    echo "credentials keystore prepared!"
}

function install_tomcat
{
    echo "extract apache-tomcat-8.5.51.tar.gz to /opt/"
    tar -xzf apache-tomcat-8.5.51.tar.gz -C /opt/
}

function install_idp
{
    echo "extract shibboleth-identity-provider-3.4.6 to $(get_property idp.target.dir)"
    tar -xzf shibboleth-identity-provider-3.4.6.tar.gz -C $(get_property idp.target.dir)
    # run install of idp
    echo "install the shibboleth-identity-provider-3.4.6 to $(get_property idp.target.dir)"
    echo execute /opt/shibboleth-identity-provider-3.4.6/bin/install.sh \
        -Didp.src.dir=$(get_property idp.src.dir) \
        -Didp.target.dir=$(get_property idp.target.dir) \
        -Didp.host.name=$(get_property idp.host.name) \
        -Didp.entityID="https://$(get_property idp.scope)/idp/shibboleth" \
        -Didp.scope=$(get_property idp.scope) \
        -Didp.keystore.password=$(get_property credentials.keystore.password) \
        -Didp.sealer.password=$(get_property credentials.keystore.password)
    /opt/shibboleth-identity-provider-3.4.6/bin/install.sh \
        -Didp.src.dir=$(get_property idp.src.dir) \
        -Didp.target.dir=$(get_property idp.target.dir) \
        -Didp.host.name=$(get_property idp.host.name) \
        -Didp.entityID="https://$(get_property idp.scope)/idp/shibboleth" \
        -Didp.scope=$(get_property idp.scope) \
        -Didp.keystore.password=$(get_property credentials.keystore.password) \
        -Didp.sealer.password=$(get_property credentials.keystore.password)
}

function update_tomcat_credential_settings
{
    echo "update credentials.keystore.path/credentials.keystore.password settings in tomcat configuration files"
    credentials_keystore_path=$(get_property credentials.keystore.path)
    credentials_keystore_password=$(get_property credentials.keystore.password)
    # https://linuxize.com/post/how-to-use-sed-to-find-and-replace-string-in-files/
    grep -rl "#credentials.keystore.path" /opt/apache-tomcat-8.5.51 | xargs sed -i "s|#credentials.keystore.path|${credentials_keystore_path}|g" 
    grep -rl "#credentials.keystore.password" /opt/apache-tomcat-8.5.51 | xargs sed -i "s/#credentials.keystore.password/${credentials_keystore_password}/g" 
}

function checking_ldap_connectivity
{
    echo "trying to connect ldap to test its connectivity"
    install_ldap_util
    ldapwhoami -h $(get_property ldap.ip) -D $(get_property idp.authn.LDAP.bindDN) -w $(get_property idp.authn.LDAP.bindDNCredential)
    $? && echo "ldap connection seems not correct" ||echo "ldap connection ok"
}

function update_idp_configurations
{
    echo update_ldap_settings_of_idp
    # backup
    cp /opt/shibboleth-idp/conf/ldap.properties /opt/shibboleth-idp/conf/ldap.properties.default
    cp /opt/shibboleth-idp/conf/attribute-resolver.xml /opt/shibboleth-idp/conf/attribute-resolver.xml.default
    cp /opt/shibboleth-idp/conf/audit.xml /opt/shibboleth-idp/conf/audit.xml.default
    cp /opt/shibboleth-idp/conf/metadata-providers.xml /opt/shibboleth-idp/conf/metadata-providers.xml.default
    # use configurated files
    cp conf/ldap.properties /opt/shibboleth-idp/conf/ldap.properties
    cp conf/attribute-filter.xml /opt/shibboleth-idp/conf/attribute-filter.xml
    cp conf/attribute-resolver.xml /opt/shibboleth-idp/conf/attribute-resolver.xml
    cp conf/audit.xml /opt/shibboleth-idp/conf/audit.xml
    cp conf/metadata-providers.xml /opt/shibboleth-idp/conf/metadata-providers.xml
    # updating...
    grep -rl "#idp.authn.LDAP.ldapURL" /opt/shibboleth-idp/conf | xargs sed -i "s|#idp.authn.LDAP.ldapURL|$(get_property idp.authn.LDAP.ldapURL)|g"
    grep -rl "#idp.authn.LDAP.baseDN" /opt/shibboleth-idp/conf | xargs sed -i "s|#idp.authn.LDAP.baseDN|$(get_property idp.authn.LDAP.baseDN)|g"
    grep -rl "#idp.authn.LDAP.userFilter" /opt/shibboleth-idp/conf | xargs sed -i "s|#idp.authn.LDAP.userFilter|$(get_property idp.authn.LDAP.userFilter)|g"
    grep -rl "#idp.authn.LDAP.bindDNCredential" /opt/shibboleth-idp/conf | xargs sed -i "s|#idp.authn.LDAP.bindDNCredential|$(get_property idp.authn.LDAP.bindDNCredential)|g"
    grep -rl "#idp.authn.LDAP.bindDN" /opt/shibboleth-idp/conf | xargs sed -i "s|#idp.authn.LDAP.bindDN|$(get_property idp.authn.LDAP.bindDN)|g"
}

function install_service
{
    export CATALINA_HOME=/opt/apache-tomcat-8.5.50
    which systemctl
    if [ "$?" -eq 0 ]; then
        echo -n "# Systemd unit file for tomcat
[Unit]
Description=Apache Tomcat Web Application Container
After=syslog.target network.target

[Service]
Type=forking

Environment=JAVA_HOME=$JAVA_HOME
Environment=CATALINA_PID=$CATALINA_HOME/temp/tomcat.pid
Environment=CATALINA_HOME=$CATALINA_HOME
Environment=CATALINA_BASE=$CATALINA_HOME
Environment='CATALINA_OPTS=-Xms1024M -Xmx2048M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=$CATALINA_HOME/bin/startup.sh
ExecStop=/bin/kill -15 $MAINPID

User=root
Group=root
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target

"  > /etc/systemd/system/tomcat.service
        systemctl daemon-reload
        # auto start when reboot
        systemctl enable tomcat
    else
        # https://mkyong.com/tomcat/how-to-install-apache-tomcat-8-on-debian/
        # https://coderwall.com/p/yqrusq/tomcat-7-init-d-script
        cat > /etc/init.d/tomcat <<EOL
#!/bin/bash
#
#https://wiki.debian.org/LSBInitScripts
### BEGIN INIT INFO
# Provides:          tomcat
# Required-Start:    $local_fs $remote_fs $network
# Required-Stop:     $local_fs $remote_fs $network
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Tomcat.
# Description:       Start the Tomcat servlet engine.
### END INIT INFO

EOL
        echo -n "
export CATALINA_HOME=$CATALINA_HOME
export JAVA_HOME=$JAVA_HOME
" >> /etc/init.d/tomcat
        cat >> /etc/init.d/tomcat <<EOL

export PATH=$JAVA_HOME/bin:$PATH

tomcat_pid() {
    echo `ps -fe | grep $CATALINA_HOME | grep -v grep | tr -s " "|cut -d" " -f2`
}
start() {
    echo "Starting Tomcat..."
    /bin/su -s /bin/bash tomcat -c $CATALINA_HOME/bin/startup.sh
}
stop() {
    echo "Stopping Tomcat..."
    /bin/su -s /bin/bash tomcat -c $CATALINA_HOME/bin/shutdown.sh
}
status(){
    pid=$(tomcat_pid)
    if [ -n "$pid" ]; then echo -e "\e[00;32mTomcat is running with pid: $pid\e[00m"
    else echo -e "\e[00;31mTomcat is not running\e[00m"
    fi
}
case $1 in
    start|stop|status) $1;;
    restart) stop; start;;
    *) echo "Usage : $0 <start|stop|status|restart>"; exit 1;;
esac

exit 0
EOL
        chmod 755 /etc/init.d/tomcat
        # auto start when reboot
        update-rc.d tomcat defaults
    fi
    service tomcat start
    service tomcat status
}

function post_work
{
    echo "Now almost everything configurated, but you should modify attribute-resolver.xml/attribute-filter.xml according to your actural settings"
    echo "You can start/stop/status your tomcat service use service command!"
}

function startup
{
    check_java
    install_credentials
    install_tomcat
    install_idp
    update_tomcat_credential_settings
    checking_ldap_connectivity
    update_idp_configurations
    install_service
    post_work
}

startup