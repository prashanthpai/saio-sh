#!/bin/sh -x

# FEDORA ONLY

if [ $EUID -ne 0 ]; then
        echo "This script must be run as root"
        exit 1
fi

if [ $# -ne 2 ]; then
    echo -e "USAGE:\n       sudo $0 <ip> <grizzly/havana/master>"
    echo -e "EXAMPLE:\n       sudo $0 192.168.56.101 havana"
    echo -e "\nSpecify ip address of this machine (not localhost/127.0.0.1) and swift version to install."
    exit 1
fi

if [[ $2 == "grizzly" || $2 == "havana" || $2 == "master" ]]; then
    version=$2
else
    echo -e "Invalid swift version as argument. Choosing havana..."
    version="havana"
fi

# Host IP Address
H=$1

# Fix for gcc update conflict
yum update -y audit

# Installing swift dependencies
yum install -y curl memcached rsync sqlite xfsprogs git-core xinetd python-setuptools python-coverage python-devel python-nose python-simplejson pyxattr python-eventlet python-greenlet python-paste-deploy python-netifaces python-pip python-dns python-mock pyxattr rsyslog libffi-devel

# Installing gluster dependencies
yum install -y bison flex autoconf automake libtool portmap fuse fuse-devel libxml2 dkms libxml2-devel openssl openssl-devel gcc

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
        git checkout master
        pip install -r requirements.txt
        pip install -r test-requirements.txt
elif [ $version == "master" ]; then
        git checkout master
        pip install -r requirements.txt
        pip install -r test-requirements.txt
fi
python setup.py develop
cd -

# Install Gluster
git clone https://github.com/gluster/glusterfs.git
cd glusterfs; ./autogen.sh && ./configure --enable-debug --disable-syslog && make -j4 CFALGS='-ggdb -O0'; make install; ldconfig; cd -
echo "export PATH=\$PATH:/usr/local/sbin/" >> ~/.bashrc
. ~/.bashrc

# Install gluster-swift
git clone https://github.com/gluster/gluster-swift.git
cd gluster-swift
if [ $version == "grizzly" ]; then
        git checkout grizzly
elif [ $version == "havana" ]; then
        git checkout master
fi
pip install -r tools/test-requires
python setup.py develop
cd -

# Create and use a loop-back device as bricks for glusterfs
truncate -s 500MB /srv/brick1 /srv/brick2 /srv/brick3 /srv/brick4
for i in {1..4}; do
        mkfs.xfs -f -i size=512 /srv/brick$i
done

# Add brick partitions to fstab
mkdir -p /brick/b1 /brick/b2 /brick/b3 /brick/b4
for i in {1..4}; do
        echo "/srv/brick$i /brick/b$i xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0" >> /etc/fstab
done

# Mount bricks
for i in {1..4}; do
        mount /brick/b$i
done

# Start glusterd daemon
systemctl --system daemon-reload
systemctl enable glusterd
systemctl start glusterd

# Create distributed volume
gluster --mode=script volume create test $H:/brick/b1 $H:/brick/b2 force
gluster volume start test

# Create replicated volume
gluster --mode=script volume create test2 replica 2 $H:/brick/b3 $H:/brick/b4 force
gluster volume start test2

# Copy and rename gluster specific swift configuration
\rm -rf /etc/swift
mkdir /etc/swift
\cp -Rf ./gluster-swift/etc/* /etc/swift/
cd /etc/swift
for i in `ls`; do
        newname=`echo $i | sed s/-gluster//`
        mv $i $newname
done
cd -

# Copy swift test configuration file
\cp -Rf swift/test/sample.conf /etc/swift/test.conf
echo "export SWIFT_TEST_CONFIG_FILE=/etc/swift/test.conf" >> ~/.bashrc

# For running g4s functional tests
yum install -y rpm-build
if [ $version == "havana" ]; then
        yum install -y http://rdo.fedorapeople.org/openstack/openstack-havana/rdo-release-havana.rpm
elif [ $version == "grizzly" ]; then
        yum install -y http://rdo.fedorapeople.org/openstack/openstack-grizzly/rdo-release-grizzly.rpm
fi

# Make ring files for gluster volumes
/usr/bin/gluster-swift-gen-builders test test2

# Setting up memcached
systemctl start memcached
systemctl enable memcached
chkconfig memcached on

# Start swift
swift-init main start
