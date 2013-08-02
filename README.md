saio-sh
=======

Swift All In One - Shell Script

A shell script to automate setting up of a VM for development of OpenStack Swift as per :
http://docs.openstack.org/developer/swift/development_saio.html

###Warning
* For Fedora 18 and 19 only
* Run this script only after a clean install of fedora in a VM.

###saio-sh Usage
./saio-sh.sh  \[swift-version\]  
Example: ./saio-sh.sh grizzly  

###g4s Usage
Use glusterfs as backend for swift  
./g4s.sh  \[ip\] \[swift-version\]  
Example: ./g4s.sh 192.168.56.101 grizzly  
