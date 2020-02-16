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

function check_java
{
    echo "checking java!"
    which java
    if [ $? -ne 0 ]; then
        echo "You should install java and set JAVA_HOME/JRE_HOME correctly before this operation"
        exit 1
    elif [ -z "$JAVA_HOME" -o -z "$JRE_HOME" ]; then
        echo "JAVA_HOME/JRE_HOME not set correctly, set them in /etc/environment, For example"
        cat <<- EOF
#cat /etc/environment 
JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
JRE_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:$JAVA_HOME/bin:$JRE_HOME/bin"
EOF
    else
        echo "Java installed and configured ok"
    fi
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
    #TODOs
    echo "ldap connection ok"
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

function startup
{
    check_java
    install_credentials
    install_tomcat
    install_idp
    update_tomcat_credential_settings
    checking_ldap_connectivity
    update_idp_configurations
}

startup