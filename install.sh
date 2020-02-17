#!/usr/bin/env bash

# read property utility
CONFIG_FILE=config.properties
function get_property
{
    grep "^$1=" $CONFIG_FILE | cut -d'=' -f2-
}

function get_os
{
    cat /etc/os-release | grep "^ID=" |  cut -d= -f2-
}

# read properties as bash variable
credentials_key_path=$(get_property credentials.key.path)
credentials_certs_path=$(get_property credentials.certs.path)
credentials_keystore_path=$(get_property credentials.keystore.path)
credentials_keystore_password=$(get_property credentials.keystore.password)
idp_src_dir=$(get_property idp.src.dir)
idp_target_dir=$(get_property idp.target.dir)
idp_host_name=$(get_property idp.host.name)
idp_scope=$(get_property idp.scope)
ldap_ip=$(get_property ldap.ip)
idp_authn_LDAP_ldapURL=$(get_property idp.authn.LDAP.ldapURL)
idp_authn_LDAP_baseDN=$(get_property idp.authn.LDAP.baseDN)
idp_authn_LDAP_userFilter=$(get_property idp.authn.LDAP.userFilter)
idp_authn_LDAP_bindDN=$(get_property idp.authn.LDAP.bindDN)
idp_authn_LDAP_bindDNCredential=$(get_property idp.authn.LDAP.bindDNCredential)

# define the filename const
IDP_FILENAME=shibboleth-identity-provider-3.4.6
TOMCAT_FILENAME=apache-tomcat-8.5.51

# get the os, like ubuntu, centos
OS=$(get_os)

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
    if [ ! -f "$credentials_keystore_path" ]; then
        mkdir -p /opt/credentials 2>/dev/null
        echo "keystore $credentials_keystore_path not exist, try to generate from pem format of $credentials_key_path and $credentials_certs_path"
        if [ ! -f "$credentials_key_path" ]; then
            echo "key $credentials_key_path not exits, will generate a self signed key and cert pair"
            openssl req -x509 -sha256 -nodes -days 3650 -subj "/CN=*.ynu.edu.cn"  -newkey rsa:2048 -keyout $credentials_key_path -out $credentials_certs_path
        fi
        # now the key and cert are prepared
        openssl pkcs12 -export -out $credentials_keystore_path -inkey $credentials_key_path -in $credentials_certs_path -passout pass:changeit
    fi
    echo "credentials keystore prepared!"
}

function install_tomcat
{
    echo "extract $TOMCAT_FILENAME.tar.gz to /opt/"
    tar -xzf $TOMCAT_FILENAME.tar.gz -C /opt/
}

function install_idp
{
    echo "extract $IDP_FILENAME.tar.gz to /opt"
    tar -xzf $IDP_FILENAME.tar.gz -C /opt
    # run install of idp
    echo "install the $IDP_FILENAME to $idp_target_dir"
    echo execute /opt/$IDP_FILENAME/bin/install.sh \
        -Didp.src.dir=$idp_src_dir \
        -Didp.target.dir=$idp_target_dir \
        -Didp.host.name=$idp_host_name \
        -Didp.entityID="https://$idp_scope/idp/shibboleth" \
        -Didp.scope=$idp_scope \
        -Didp.keystore.password=$credentials_keystore_password \
        -Didp.sealer.password=$credentials_keystore_password
    /opt/$IDP_FILENAME/bin/install.sh \
        -Didp.src.dir=$idp_src_dir \
        -Didp.target.dir=$idp_target_dir \
        -Didp.host.name=$idp_host_name \
        -Didp.entityID="https://$idp_scope/idp/shibboleth" \
        -Didp.scope=$idp_scope \
        -Didp.keystore.password=$credentials_keystore_password \
        -Didp.sealer.password=$credentials_keystore_password
}

function update_tomcat_credential_settings
{
    echo "update credentials.keystore.path/credentials.keystore.password settings in tomcat configuration files"
    credentials_keystore_path=$credentials_keystore_path
    credentials_keystore_password=$credentials_keystore_password
    # https://linuxize.com/post/how-to-use-sed-to-find-and-replace-string-in-files/
    grep -rl "#credentials.keystore.path" /opt/$TOMCAT_FILENAME | xargs sed -i "s|#credentials.keystore.path|${credentials_keystore_path}|g" 
    grep -rl "#credentials.keystore.password" /opt/$TOMCAT_FILENAME | xargs sed -i "s/#credentials.keystore.password/${credentials_keystore_password}/g" 
}

function checking_ldap_connectivity
{
    echo "trying to connect ldap to test its connectivity"
    install_ldap_util
    ldapwhoami -h $ldap_ip -D $idp_authn_LDAP_bindDN -w $idp_authn_LDAP_bindDNCredential
    $? && echo "ldap connection seems not correct" ||echo "ldap connection ok"
}

function update_idp_configurations
{
    echo update_ldap_settings_of_idp
    # backup
    cp $idp_target_dir/conf/ldap.properties $idp_target_dir/conf/ldap.properties.default
    cp $idp_target_dir/conf/attribute-resolver.xml $idp_target_dir/conf/attribute-resolver.xml.default
    cp $idp_target_dir/conf/audit.xml $idp_target_dir/conf/audit.xml.default
    cp $idp_target_dir/conf/metadata-providers.xml $idp_target_dir/conf/metadata-providers.xml.default
    # use configurated files
    cp conf/ldap.properties $idp_target_dir/conf/ldap.properties
    cp conf/attribute-filter.xml $idp_target_dir/conf/attribute-filter.xml
    cp conf/attribute-resolver.xml $idp_target_dir/conf/attribute-resolver.xml
    cp conf/audit.xml $idp_target_dir/conf/audit.xml
    cp conf/metadata-providers.xml $idp_target_dir/conf/metadata-providers.xml
    # updating...
    grep -rl "#idp.authn.LDAP.ldapURL" $idp_target_dir/conf | xargs sed -i "s|#idp.authn.LDAP.ldapURL|$idp_authn_LDAP_ldapURL|g"
    grep -rl "#idp.authn.LDAP.baseDN" $idp_target_dir/conf | xargs sed -i "s|#idp.authn.LDAP.baseDN|$idp_authn_LDAP_baseDN|g"
    grep -rl "#idp.authn.LDAP.userFilter" $idp_target_dir/conf | xargs sed -i "s|#idp.authn.LDAP.userFilter|$idp_authn_LDAP_userFilter|g"
    grep -rl "#idp.authn.LDAP.bindDNCredential" $idp_target_dir/conf | xargs sed -i "s|#idp.authn.LDAP.bindDNCredential|$idp_authn_LDAP_bindDNCredential|g"
    grep -rl "#idp.authn.LDAP.bindDN" $idp_target_dir/conf | xargs sed -i "s|#idp.authn.LDAP.bindDN|$idp_authn_LDAP_bindDN|g"
}

function install_service
{
    export CATALINA_HOME=/opt/$TOMCAT_FILENAME
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