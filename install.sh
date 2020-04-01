#!/usr/bin/env bash

# read property utility
CONFIG_FILE=config.properties
function get_property() {
  grep "^$1=" $CONFIG_FILE | cut -d'=' -f2-
}

function get_os() {
  cat /etc/os-release | grep "^ID=" | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

important() {
  echo -e "\e[35m${1}\e[0m"
}

info() {
  echo -e "\e[32m${1}\e[0m"
}

warn() {
  echo -e "\e[33m${1}\e[0m"
}

error() {
  echo -e "\e[31m${1}\e[0m"
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
shibcas_casServerUrlPrefix=$(get_property shibcas.casServerUrlPrefix)
shibcas_casServerLoginUrl=$(get_property shibcas.casServerLoginUrl)

# define the filename const
IDP_FILENAME=shibboleth-identity-provider-3.4.6
TOMCAT_FILENAME=apache-tomcat-8.5.51

# get the os, like ubuntu, centos
OS=$(get_os)

function set_java_environment() {
  JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
  JRE_HOME="$(dirname $(dirname $(readlink -f $(which javac))))/jre"
  grep JAVA_HOME /etc/environment 2>/dev/null && info "JAVA_HOME already set" || echo "export JAVA_HOME=$JAVA_HOME" >>/etc/environment
  grep JRE_HOME /etc/environment 2>/dev/null && info "JRE_HOME already set" || echo "export JRE_HOME=$JRE_HOME" >>/etc/environment
  source /etc/environment
}

function check_java() {
  important "checking java!"
  which java
  if [ $? -ne 0 ]; then
    info "You should install java and set JAVA_HOME/JRE_HOME correctly before this operation"
    info "Now install java..."
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
        error "Unsupport OS, please contact liudonghua123@gmail.com"
        exit 1
        ;;
    esac
    set_java_environment
  elif [ -z "$JAVA_HOME" -o -z "$JRE_HOME" ]; then
    warn "JAVA_HOME/JRE_HOME not set correctly, set them in /etc/environment"
    set_java_environment
    info "Java installed and configured ok"
  fi
}

function install_ldap_util() {
  important "install ldap utils"
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
      error "Unsupport OS, please contact liudonghua123@gmail.com"
      exit 1
      ;;
  esac
}

function install_credentials() {
  import "checking and creating credentials keystore!"
  # check whether credentials exist
  if [ ! -f "$credentials_keystore_path" ]; then
    mkdir -p /opt/credentials 2>/dev/null
    warn "keystore $credentials_keystore_path not exist, try to check whether $credentials_key_path exists"
    if [ ! -f "$credentials_key_path" ]; then
      warn "key $credentials_key_path not exits, will generate a self signed key ($credentials_key_path) and cert ($credentials_certs_path) pair in pem format"
      openssl req -x509 -sha256 -nodes -days 3650 -subj "/CN=*.$idp_scope" -newkey rsa:2048 -keyout $credentials_key_path -out $credentials_certs_path
    fi
    # now the key and cert are prepared
    openssl pkcs12 -export -out $credentials_keystore_path -inkey $credentials_key_path -in $credentials_certs_path -passout pass:changeit
  fi
  info "credentials keystore prepared!"
}

function install_tomcat() {
  important "extract $TOMCAT_FILENAME.tar.gz to /opt/"
  tar -xzf $TOMCAT_FILENAME.tar.gz -C /opt/
}

function install_idp() {
  important "extract $IDP_FILENAME.tar.gz to /opt"
  tar -xzf $IDP_FILENAME.tar.gz -C /opt
  info "patch bin/build.xml for correctly set sealer password"
  mv /opt/$IDP_FILENAME/bin/build.xml /opt/$IDP_FILENAME/bin/build.xml.default
  cp conf/build.xml /opt/$IDP_FILENAME/bin/build.xml
  # run install of idp
  info "install the $IDP_FILENAME to $idp_target_dir"
  info "running... /opt/$IDP_FILENAME/bin/install.sh \
    -Didp.src.dir=$idp_src_dir \
    -Didp.target.dir=$idp_target_dir \
    -Didp.host.name=$idp_host_name \
    -Didp.entityID="https://$idp_host_name/idp/shibboleth" \
    -Didp.scope=$idp_scope \
    -Didp.keystore.password=$credentials_keystore_password \
    -Didp.sealer.password=$credentials_keystore_password"
  /opt/$IDP_FILENAME/bin/install.sh \
    -Didp.src.dir=$idp_src_dir \
    -Didp.target.dir=$idp_target_dir \
    -Didp.host.name=$idp_host_name \
    -Didp.entityID="https://$idp_host_name/idp/shibboleth" \
    -Didp.scope=$idp_scope \
    -Didp.keystore.password=$credentials_keystore_password \
    -Didp.sealer.password=$credentials_keystore_password
}

function update_tomcat_credential_settings() {
  important "update credentials.keystore.path/credentials.keystore.password settings in tomcat configuration files"
  credentials_keystore_path=$credentials_keystore_path
  credentials_keystore_password=$credentials_keystore_password
  # https://linuxize.com/post/how-to-use-sed-to-find-and-replace-string-in-files/
  grep -rl "#credentials.keystore.path" /opt/$TOMCAT_FILENAME | xargs sed -i "s|#credentials.keystore.path|${credentials_keystore_path}|g"
  grep -rl "#credentials.keystore.password" /opt/$TOMCAT_FILENAME | xargs sed -i "s/#credentials.keystore.password/${credentials_keystore_password}/g"
}

function checking_ldap_connectivity() {
  important "trying to connect ldap to test its connectivity"
  install_ldap_util
  ldapwhoami -h $ldap_ip -D $idp_authn_LDAP_bindDN -w $idp_authn_LDAP_bindDNCredential
  $? && warn "ldap connection seems not correct" || info "ldap connection ok"
}

function update_idp_configurations() {
  important "update idp configurations"
  # backup
  cp $idp_target_dir/conf/idp.properties $idp_target_dir/conf/idp.properties.default
  cp $idp_target_dir/conf/attribute-resolver.xml $idp_target_dir/conf/attribute-resolver.xml.default
  cp $idp_target_dir/conf/audit.xml $idp_target_dir/conf/audit.xml.default
  cp $idp_target_dir/conf/metadata-providers.xml $idp_target_dir/conf/metadata-providers.xml.default
  # copy the metadata files
  cp conf/metadata/* $idp_target_dir/metadata/
  # use configurated files
  cp conf/attribute-filter.xml $idp_target_dir/conf/attribute-filter.xml
  cp conf/attribute-resolver.xml $idp_target_dir/conf/attribute-resolver.xml
  cp conf/audit.xml $idp_target_dir/conf/audit.xml
  cp conf/metadata-providers.xml $idp_target_dir/conf/metadata-providers.xml
  # updating...
  # https://wiki.carsi.edu.cn/pages/viewpage.action?pageId=1998863
  # https://github.com/Unicon/shib-cas-authn3/releases/tag/3.3.0
  grep -rl "idp.authn.flows=Password" $idp_target_dir/conf/idp.properties | xargs sed -i "s|idp.authn.flows=Password|idp.authn.flows=External|g"
  echo -n "
shibcas.casServerUrlPrefix=$shibcas_casServerUrlPrefix
shibcas.casServerLoginUrl=$shibcas_casServerLoginUrl
shibcas.serverName=https://$idp_host_name
" >> /opt/shibboleth-idp/conf/idp.properties
  # copy CARSI Certificate
  cp conf/dsmeta.pem $idp_target_dir/credentials/
  # copy zh-CN translations
  cp conf/messages_zh_CN.properties $idp_target_dir/system/messages/
  # copy cas releated files
  cp conf/cas-client-core-3.6.0.jar /opt/shibboleth-idp/edit-webapp/WEB-INF/lib/
  cp conf/shib-cas-authenticator-3.3.0.jar /opt/shibboleth-idp/edit-webapp/WEB-INF/lib/
  cp conf/web.xml /opt/shibboleth-idp/edit-webapp/WEB-INF/
}

function install_service() {
  important "installing tomcat system service"
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

" >/etc/systemd/system/tomcat.service
    systemctl daemon-reload
    # auto start when reboot
    systemctl enable tomcat
  else
    # https://mkyong.com/tomcat/how-to-install-apache-tomcat-8-on-debian/
    # https://coderwall.com/p/yqrusq/tomcat-7-init-d-script
    cat >/etc/init.d/tomcat <<EOL
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
" >>/etc/init.d/tomcat
    cat >>/etc/init.d/tomcat <<EOL
export PATH=$JAVA_HOME/bin:$PATH

tomcat_pid() {
    echo $(ps -fe | grep $CATALINA_HOME | grep -v grep | tr -s " " | cut -d" " -f2)
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

function process_log() {
  important "processing log configurations"
  mkdir -p /var/www/html/auditlog/ 2>/dev/null
  cat >/var/www/html/auditlog/auditlog.sh <<EOL
#!/usr/bin/env bash

rm -rf /var/www/html/auditlog/auditlog-$(date -d -24hours +%Y-%m-%d-%H).log
grep $(date -d -1hours +%Y-%m-%dT%H) /opt/shibboleth-idp/logs/idp-audit.log > /var/www/html/auditlog/auditlog-$(date -d -1hours +%Y-%m-%d-%H).log
EOL
  chmod a+x /var/www/html/auditlog/auditlog.sh
  # create symbol link for auditlog
  if [ ! -f /opt/$TOMCAT_FILENAME/webapps/auditlog ]; then
    ln -s /var/www/html/auditlog /opt/$TOMCAT_FILENAME/webapps/auditlog
  fi
  # install crontab if necessary
  crontab -l >/tmp/tmp_crontab
  grep auditlog /tmp/tmp_crontab
  if [ "$?" -ne 0 ]; then
    warn "auditlog crontab job not found, installing..."
    echo "0 */1 * * * sh /var/www/html/auditlog/auditlog.sh >/dev/null 2>&1" >>/tmp/tmp_crontab
    crontab /tmp/tmp_crontab
  fi
  rm -rf /tmp/tmp_crontab
}

function process_ntp() {
  # before installing ntpd, we should turn off timesyncd
  timedatectl set-ntp no
  # check ntpd installed?
  which ntpd
  if [ "$?" -ne 0 ]; then
    case "$OS" in
      ubuntu)
        apt-get install -y ntp
        ;;
      centos)
        yum install -y ntp
        ;;
      *)
        error "Unsupport OS, please contact liudonghua123@gmail.com"
        exit 1
        ;;
    esac
  fi
  info "updating time from ntp.aliyun.com"
  ntpdate -u ntp.aliyun.com
  info "setting timezone to Asia/Shanghai"
  timedatectl set-timezone Asia/Shanghai
  if [ ! -f /etc/ntp.conf.default ]; then
    cp /etc/ntp.conf /etc/ntp.conf.default
    echo "server ntp.aliyun.com" >/etc/ntp.conf
    service ntpd restart
  fi
}

function post_work() {
  important "Now almost everything configurated, but you should modify attribute-resolver.xml/attribute-filter.xml according to your actural settings"
  important "You can start/stop/status your tomcat service use service command!"
}

function startup() {
  check_java
  process_ntp
  install_credentials
  install_tomcat
  install_idp
  update_tomcat_credential_settings
  # checking_ldap_connectivity
  update_idp_configurations
  install_service
  process_log
  post_work
}

startup
