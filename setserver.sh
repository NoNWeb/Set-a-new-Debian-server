#!/bin/bash
#
# Set up a new *Debian* server with Apache, Mysql, Php and VsFTP, and secures all of the previous + SSH.
#
#
######################################################################
#
# more credits
# http://plusbryan.com/my-first-5-minutes-on-a-server-or-essential-security-for-linux-servers
#
#######################################################################
#
#  Copyright (c) 2014 Daddydy 
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: 
#
#  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. 
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#  --> Licensed under the MIT license: http://www.opensource.org/licenses/mit-license.php
#
######################################################################

# First of all, we check if the user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

#Fix dpkg was interrupted
read -e -p "Fix dpkg for the installations? [Y/n] : " fix_dpkg
if [[ ("$fix_dpkg" == "y" || "$fix_dpkg" == "Y" || "$fix_dpkg" == "") ]]; then
    dpkg --configure -a
fi

# Changing the password of the root user
read -e -p "Do you want to change the root password? [Y/n] : " change_password
if [[ ("$change_password" == "y" || "$change_password" == "Y" || "$change_password" == "") ]]; then
    passwd
fi

# install ntp and set the time
read -e -p "Install ntp and set the time ? [Y/n] : " install_ntp
if [[ ("$install_ntp" == "y" || "$install_ntp" == "Y" || "$install_ntp" == "") ]]; then
    apt-get --yes install ntp
    Set server timezone
    dpkg-reconfigure tzdata
    systemctl restart cron.service
fi 

# Installing sendmail
read -e -p "Do you want to install sendmail utils? [Y/n] : " install_sendmail
if [[ ("$install_sendmail" == "y" || "$install_sendmail" == "Y" || "$install_sendmail" == "") ]]; then
   apt-get --yes install sendmail-bin mailutils
fi
 
read -e -p "Admin contact email : " root_email
 
if [[ "$root_email" != "" ]]; then
    echo $root_email > ~/.email
    echo $root_email > ~/.forward
 
    read -e -p "Send an mail to test the smtp service? [Y/n] : " send_email
    if [[ ("$send_email" == "y" || "$send_email" == "Y" || "$send_email" == "") ]]; then
        echo "This is a mail test for the SMTP Service." > /tmp/email.message
        echo "You should receive this !" >> /tmp/email.message
        echo "" >> /tmp/email.message
        echo "Cheers!" >> /tmp/email.message
        mail -s "SMTP Testing" $root_email < /tmp/email.message
 
        rm -f /tmp/email.message
        echo "Mail sent"
    fi
fi
 

# Creating multiple users
create_user=true
while $create_user; do
    read -e -p "Create a new user? [y/N] : " new_user
 
    if [[ ("$new_user" == "y" || "$new_user" == "Y") ]]; then
        read -e -p "Username : " user_name
        adduser $user_name
        adduser $user_name sudo
    else
        create_user=false
    fi
done
 
# SSH Server
echo "Improving security on SSH"
 
echo " * Allow AuthorizedKeyFiles"
sed -i "s/#AuthorizedKeysFile/AuthorizedKeysFile/" /etc/ssh/sshd_config
 
echo " * Disallow X11Forwarding"
sed -i "s/X11Forwarding yes/X11Forwarding no/" /etc/ssh/sshd_config
 
echo " * Removing Root Login"
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
 
read -e -p "SSH Allowed users (space separated) : " ssh_users
if [[ "$ssh_users" -ne "" ]]; then
    echo "AllowUsers $ssh_users" >> /etc/ssh/sshd_config
fi
 
/etc/init.d/ssh restart
 
read -e -p "Force update the server? [Y/n] : " force_update
if [[ ("$force_update" == "y" || "$force_update" == "Y" || "$force_update" == "") ]]; then
    apt-get --yes update && apt-get --yes upgrade
fi
 
# install Fail2ban
read -e -p "Install Fail2ban? [Y/n] : " install_fail2ban
if [[ ("$install_fail2ban" == "y" || "$install_fail2ban" == "Y" || "$install_fail2ban" == "") ]]; then
    apt-get --yes install fail2ban
fi

# install Apache2 
read -e -p "Install Apache? [Y/n] : " install_apache
if [[ ("$install_apache" == "y" || "$install_apache" == "Y" || "$install_apache" == "") ]]; then
    apt-get --yes install apache2
    a2dismod userdir suexec cgi cgid dav include autoindex authn_file status env headers proxy proxy_balancer proxy_http headers
    a2enmod expires rewrite setenvif ssl
 
    sed -i "s/ServerTokens.*/ServerTokens Prod/g" /etc/apache2/conf.d/security
    sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf.d/security
 
    /etc/init.d/apache2 restart
fi
 
# install MySQL
read -e -p "Install MySQL? [Y/n] : " install_mysql
if [[ ("$install_mysql" == "y" || "$install_mysql" == "Y" || "$install_mysql" == "") ]]; then
    apt-get --yes install mysql-server
 
    # bind-address & skip-networking are correctly managed by debian
    sed -i "s/\[mysqldump\]/# Personal settings:\nset-variable=local-infile=0\n\n\[mysqldump\]/" /etc/mysql/my.cnf
 
    read -e -p "Execute mysql_secure_installation ? [Y/n] : " mysql_secure
    if [[ ("$mysql_secure" == "y" || "$mysql_secure" == "Y" || "$mysql_secure" == "") ]]; then
        mysql_secure_installation
    fi
fi

# install PHP
read -e -p "Install PHP? [Y/n] : " install_php
if [[ ("$install_php" == "y" || "$install_php" == "Y" || "$install_php" == "") ]]; then
    apt-get --yes install php5 libapache2-mod-php5 php5-cli php5-mysql php5-curl php5-gd php5-mcrypt php5-memcache php5-memcached 
 
# install PHPMyAdmin
    read -e -p "Install PHPMyAdmin? [Y/n] : " install_pma
    if [[ ("$install_pma" == "y" || "$install_pma" == "Y" || "$install_pma" == "") ]]; then
        apt-get --yes install phpmyadmin
    fi
 
    /etc/init.d/apache2 restart
fi

# install Drush for Drupal
read -e -p "Install Drush for Drupal ? [Y/n] : " install_drush
if [[ ("$install_drush" == "y" || "$install_drush" == "Y" || "$install_drush" == "") ]]; then
    apt-get --yes install drush
fi

# install Pydio
read -e -p "Install Pydio ? [Y/n] : " install_pydio
if [[ ("$install_pydio" == "y" || "$install_pydio" == "Y" || "$install_pydio" == "") ]]; then
    # manually append the following lines in your /etc/apt/sources.list file
    echo "deb http://dl.ajaxplorer.info/repos/apt stable main" | tee -a /etc/apt/sources.list >> /dev/null
    echo "deb-src http://dl.ajaxplorer.info/repos/apt stable main" | tee -a /etc/apt/sources.list >> /dev/null
    wget -O - http://dl.ajaxplorer.info/repos/charles@ajaxplorer.info.gpg.key | apt-key add -
    apt-get --yes update
    apt-get --yes install pydio
    cp /usr/share/doc/pydio/apache2.sample.conf /etc/apache2/sites-enabled/pydio.conf
fi

# install VsFTP
read -e -p "Install VsFTP ? [Y/n] : " install_vsftpd
if [[ ("$install_vsftpd" == "y" || "$install_vsftpd" == "Y" || "$install_vsftpd" == "") ]]; then
    apt-get --yes install vsftpd
fi


    
perl -pi -e "s/anonymous_enable\=YES/\#anonymous_enable\=YES/g" /etc/vsftpd.conf
perl -pi -e "s/connect_from_port_20\=YES/#connect_from_port_20\=YES/g" /etc/vsftpd.conf
echo "listen_port=2121" | tee -a /etc/vsftpd.conf >> /dev/null
echo "ssl_enable=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "allow_anon_ssl=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "force_local_data_ssl=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "force_local_logins_ssl=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "ssl_tlsv1=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "ssl_sslv2=NO" | tee -a /etc/vsftpd.conf >> /dev/null
echo "ssl_sslv3=NO" | tee -a /etc/vsftpd.conf >> /dev/null
echo "require_ssl_reuse=NO" | tee -a /etc/vsftpd.conf >> /dev/null
echo "ssl_ciphers=HIGH" | tee -a /etc/vsftpd.conf >> /dev/null
echo "rsa_cert_file=/etc/ssl/private/vsftpd.pem" | tee -a /etc/vsftpd.conf >> /dev/null
echo "local_enable=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "write_enable=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "local_umask=022" | tee -a /etc/vsftpd.conf >> /dev/null
echo "chroot_local_user=YES" | tee -a /etc/vsftpd.conf >> /dev/null
echo "chroot_list_file=/etc/vsftpd.chroot_list" | tee -a /etc/vsftpd.conf >> /dev/null

#install all needed packages
apt-get --yes install apache2 apache2-utils autoconf build-essential ca-certificates comerr-dev curl cfv quota mktorrent dtach htop irssi libapache2-mod-php5 libcloog-ppl-dev libcppunit-dev libcurl3 libcurl4-openssl-dev libncurses5-dev libterm-readline-gnu-perl libsigc++-2.0-dev libperl-dev openvpn libssl-dev libtool libxml2-dev ncurses-base ncurses-term ntp openssl patch libc-ares-dev pkg-config php5 php5-cli php5-dev php5-curl php5-geoip php5-mcrypt php5-gd php5-xmlrpc pkg-config python-scgi screen ssl-cert subversion texinfo unzip zlib1g-dev expect joe automake1.9 flex bison debhelper binutils-gold ffmpeg libarchive-zip-perl libnet-ssleay-perl libhtml-parser-perl libxml-libxml-perl libjson-perl libjson-xs-perl libxml-libxslt-perl libxml-libxml-perl libjson-rpc-perl sudo libarchive-zip-perl znc tcpdump

# install RAR
apt-get --yes install rar
if [ $? -gt 0 ]; then
  apt-get --yes install rar-free
fi

# install UNRAR
apt-get --yes install unrar
if [ $? -gt 0 ]; then
  apt-get --yes install unrar-free
fi

echo ""
echo ""
echo ""
echo ""
echo ""
echo "Looks like everything is set."
echo ""
echo ""
echo ""
echo ""
echo ""

# Reboot?
read -e -p "Reboot the server ? [Y/n] : " reboot
if [[ ("$reboot" == "y" || "$reboot" == "Y" || "$reboot" == "") ]]; then
    reboot
fi

exit 0;
