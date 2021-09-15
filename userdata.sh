#!/bin/bash

echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
echo "LANG=en_US.utf-8" >> /etc/environment
echo "LC_ALL=en_US.utf-8" >> /etc/environment

echo "password123" | passwd root --stdin
sed  -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
service sshd restart


yum install httpd php git -y
git clone https://github.com/ajish-antony/ansible-website.git /var/git/
cp -pr /var/git/* /var/www/html/
rm -rf /var/www/html/.git
service httpd restart
chkconfig httpd on
