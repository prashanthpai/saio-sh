#!/bin/sh -x

# FEDORA ONLY

if [ $EUID -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
fi

if [ $# -ne 1 ]; then
        echo -e "USAGE:\nsudo $0 <swift-version>"
        echo -e "<swift-version> can be grizzly or havana"
        exit 1
fi

if [[ $1 == "grizzly" || $1 == "havana" ]]; then
        version=$1
else
        echo -e "Invalid swift version as argument. Choosing grizzly..."
        version="grizzly"
fi


# Fix for gcc update conflict
yum update -y audit

# Installing dependencies
yum install -y curl memcached rsync sqlite xfsprogs git-core xinetd python-setuptools python-coverage python-devel python-nose python-simplejson pyxattr python-eventlet python-greenlet python-paste-deploy python-netifaces python-pip python-dns python-mock pyxattr rsyslog gcc libffi libffi-devel

# Create and use a loop-back device for storage
truncate -s 1GB /srv/swift-disk
mkfs.xfs /srv/swift-disk
echo "/srv/swift-disk /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0" >> /etc/fstab
mkdir /mnt/sdb1
mount /mnt/sdb1
mkdir /mnt/sdb1/1 /mnt/sdb1/2 /mnt/sdb1/3 /mnt/sdb1/4

for i in {1..4}; do
        ln -s /mnt/sdb1/$i /srv/$i
done

mkdir -p /etc/swift/object-server /etc/swift/container-server /etc/swift/account-server 

for i in {1..4}; do
        mkdir -p /srv/$i/node/sdb$i
done

echo "mkdir -p /var/cache/swift /var/cache/swift2 /var/cache/swift3 /var/cache/swift4
chown swift:swift /var/cache/swift*
mkdir -p /var/run/swift
chown swift:swift /var/run/swift" >> /etc/rc.local

# Setting up rsync and memcached
cp ./rsyncd.conf /etc/rsyncd.conf
echo -e "service rsync{\ndisable = no\nsocket_type = stream\nwait = no\nuser = root\nserver = /usr/bin/rsync\nserver_args = --daemon\nlog_on_failure += USERID\n}" > /etc/xinetd.d/rsync
service xinetd restart
chkconfig xinetd on
service memcached restart
chkconfig memcached on

# Locate pip
which pip
if [ $? -ne 0 ]; then
        alias pip = python-pip
fi

# Install python-swiftclient
git clone https://github.com/openstack/python-swiftclient.git
cd python-swiftclient; pip install -r requirements.txt; pip install -r test-requirements.txt; python setup.py develop; cd -

# Install Swift
git clone https://github.com/openstack/swift.git
cd swift
if [ $version == "grizzly" ]; then
        git checkout stable/grizzly
        pip install -r tools/pip-requires
        pip install -r tools/test-requires
elif [ $version == "havana" ]; then
        git checkout stable/havana
        pip install -r requirements.txt
        pip install -r test-requirements.txt
fi
python setup.py develop
cd -

# Create configuration files for swift
\cp -Rf ./conf/* /etc/swift/

# For running swift functional and unit tests
\cp -Rf swift/test/sample.conf /etc/swift/test.conf
echo "export SWIFT_TEST_CONFIG_FILE=/etc/swift/test.conf" >> ~/.bashrc

mkdir ~/swift-bin
\cp -Rf bin/* ~/swift-bin/
chmod +x ~/swift-bin/*
echo "export PATH=\${PATH}:~/swift-bin" >> ~/.bashrc
. ~/.bashrc
bin/remakerings
swift-init main start
