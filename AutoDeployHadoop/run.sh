#!/bin/bash
# Simple Hadoop Deploy Script
# All the hosts have the same password for root user
# Allow SSH login as root
# Eth0 is the active network device(/24)
# Author:BlueLight
# Date:2016-08-30

if [ ! $USER = root ];then 
    echo "Please run this script as root ." 
    exit 1 
fi 

read -p "Input root password for all hosts:" -s passwd

echo "***********************************************************************"
echo "AutoDeployScript for Hadoop  by BlueLight @ 2016-08-30"
echo "***********************************************************************"

# Install soft ware.
echo "Install necessary soft ware..."
apt-get update
apt-get install expect dos2unix pdsh libxml2-utils -y

if [ $? -ne 0 ];then
    echo "Install soft failed. Please check the network."
    exit 1
fi

# Check available hosts.
echo "Checking available hosts..."
rm -rf /tmp/hosts.tmp
net=`ifconfig eth0 | awk '/inet addr/{print substr($2,6)}'|awk -F '.' '{print $1"."$2"."$3}'`
for i in {1..254}
do
    echo "Checking $net.$i ... ($i/254)"
    nc -w 1 $net.$i 22 &> /dev/null && \
    expect <<EOF
    log_file /tmp/hosts.tmp
    spawn  ssh $net.$i "hostname > /tmp/host;echo $net.$i >>/tmp/host;sed 'N;s/\\\n/ /g' /tmp/host"
    expect {
        "*yes/no" {send "yes\r" ;exp_continue}
        "*password:" {send "$passwd\r" ;exp_continue  }
    }
EOF
done
dos2unix /tmp/hosts.tmp 
cat /tmp/hosts.tmp | grep ' [0-9]\+\.'| awk '$0 !~ /^spawn/{print $2" "$1}' | sort -t '.' -k4n > /tmp/hosts.data
echo "The checked result is :"
cat /tmp/hosts.data

# Rebuild hosts file.
echo "Rebuild hosts file..."
echo "# The following lines are desirable for IPv6 capable hosts" > /etc/hosts
echo "::1     localhost ip6-localhost ip6-loopback" >> /etc/hosts
echo "ff02::1 ip6-allnodes" >> /etc/hosts
echo "ff02::2 ip6-allrouters" >> /etc/hosts
echo "# The following lines are are desirable for hadoop hosts" >> /etc/hosts
cat /tmp/hosts.data >> /etc/hosts

# Generate SSH file.
echo "Generate SSH file..."
rm -rf ~/.ssh/
ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa

# Transform SSH file to other hosts.
echo "Transform SSH file to other hosts..."
cat /tmp/hosts.data | awk '{print $2}' | while read host
do
expect <<EOF
  spawn  scp -r /root/.ssh/  $host:/root/
  expect {
    "*yes/no" {send "yes\r" ;exp_continue}
    "*password:" {send "$passwd\r" ;exp_continue  }
  }
EOF
sleep 1
expect <<EOF
    spawn  ssh-copy-id  -i /root/.ssh/id_rsa.pub $host
    expect {
      "*yes/no" {send "yes\r" ;exp_continue}
      "*password:" {send "$passwd\r" ;exp_continue  }
    }
EOF
done
echo "Test and copy hosts file..."
cat /tmp/hosts.data | awk '{print $2}' | while read host
do
expect <<EOF
    spawn ssh $host 
    expect {
      "*yes/no" {send "yes\r" ;exp_continue}
      "*password:" {send "$passwd\r" ;exp_continue  }
    }
    sleep 1
    send "exit\r"
EOF
done 

echo `cat /tmp/hosts.data | awk '{print $2}' | sed ':a;N;$!ba;s/\n/,/g'` > all_hosts

pdsh -R ssh -w ^all_hosts "apt-get update;apt-get install pdsh -y"
success=`pdsh -R ssh -w ^all_hosts "which pdsh" | wc -l`
total=`cat /tmp/hosts.data | wc -l`
while [[ $success -lt $total ]]
do
    echo "Waiting for pdsh installed ... ($success/$total)"
    sleep 60
    pdsh -R ssh -w ^all_hosts "apt-get install pdsh -y"
    sleep 60
    success=`pdsh -R ssh -w ^all_hosts "which pdsh" | wc -l`
done

pdcp -R ssh -w ^all_hosts /etc/hosts /etc/  

# Install hadoop.
echo "Install hadoop..."
source ./hadoop-xml-conf.sh
NN_DATA_DIR=/var/data/hadoop/hdfs/nn
SNN_DATA_DIR=/var/data/hadoop/hdfs/snn
DN_DATA_DIR=/var/data/hadoop/hdfs/dn
YARN_LOG_DIR=/var/log/hadoop/yarn
HADOOP_LOG_DIR=/var/log/hadoop/hdfs
HADOOP_MAPRED_LOG_DIR=/var/log/hadoop/mapred
YARN_PID_DIR=/var/run/hadoop/yarn
HADOOP_PID_DIR=/var/run/hadoop/hdfs
HADOOP_MAPRED_PID_DIR=/var/run/hadoop/mapred
HOSTNAME=`hostname`

JAVA_HOME=/opt/`gzip -dc jdk-*.tar.gz | tar tvf - | head -n 1 | awk '{print substr($6,0,length($6)-1)}'`
HADOOP_HOME=/opt/`ls hadoop-*.tar.gz|awk -F '.tar.gz' '{print $1}'`

HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"

rm -rf *.xml && cp ./conf/*.xml .
cat /tmp/hosts.data | awk '{print $2}' > slaves && sed -i '/'$(hostname)'/d' slaves
echo `cat slaves | sed ':a;N;$!ba;s/\n/,/g'` > dn_hosts
echo $HOSTNAME > nn_host
echo $HOSTNAME > snn_host

echo "Copying Hadoop and jdk to all hosts..."
pdcp -R ssh -w ^all_hosts jdk-*.tar.gz /opt
pdcp -R ssh -w ^all_hosts hadoop-*.tar.gz /opt

echo "Setting JAVA_HOME and HADOOP_HOME environment variables on all hosts..."
pdsh -R ssh -w ^all_hosts "echo export JAVA_HOME=$JAVA_HOME > /etc/profile.d/java.sh"
pdsh -R ssh -w ^all_hosts "source /etc/profile.d/java.sh"
pdsh -R ssh -w ^all_hosts "echo export HADOOP_HOME=$HADOOP_HOME > /etc/profile.d/hadoop.sh"
pdsh -R ssh -w ^all_hosts 'echo export HADOOP_PREFIX=$HADOOP_HOME >> /etc/profile.d/hadoop.sh'
pdsh -R ssh -w ^all_hosts "source /etc/profile.d/hadoop.sh"

echo "Extracting Hadoop and jdk distribution on all hosts..."
pdsh -R ssh -w ^all_hosts tar -zxf /opt/`ls hadoop-*.tar.gz` -C /opt
pdsh -R ssh -w ^all_hosts tar -zxf /opt/`ls jdk-*.tar.gz` -C /opt
pdsh -R ssh -w ^all_hosts "chmod -R 777 $HADOOP_HOME/bin/"
pdcp -R ssh -w ^all_hosts slaves $HADOOP_HOME/etc/hadoop/

echo "Creating system accounts and groups on all hosts..."
pdsh -R ssh -w ^all_hosts groupadd hadoop
pdsh -R ssh -w ^all_hosts useradd -g hadoop yarn
pdsh -R ssh -w ^all_hosts useradd -g hadoop hdfs
pdsh -R ssh -w ^all_hosts useradd -g hadoop mapred

echo "Creating HDFS data directories on NameNode host, Secondary NameNode host, and DataNode hosts..."
pdsh -R ssh -w ^nn_host "mkdir -p $NN_DATA_DIR && chown hdfs:hadoop $NN_DATA_DIR"
pdsh -R ssh -w ^snn_host "mkdir -p $SNN_DATA_DIR && chown hdfs:hadoop $SNN_DATA_DIR"
pdsh -R ssh -w ^dn_hosts "mkdir -p $DN_DATA_DIR && chown hdfs:hadoop $DN_DATA_DIR"

echo "Creating log directories on all hosts..."
pdsh -R ssh -w ^all_hosts "mkdir -p $YARN_LOG_DIR && chown yarn:hadoop $YARN_LOG_DIR"
pdsh -R ssh -w ^all_hosts "mkdir -p $HADOOP_LOG_DIR && chown hdfs:hadoop $HADOOP_LOG_DIR"
pdsh -R ssh -w ^all_hosts "mkdir -p $HADOOP_MAPRED_LOG_DIR && chown mapred:hadoop $HADOOP_MAPRED_LOG_DIR"

echo "Creating pid directories on all hosts..."
pdsh -R ssh -w ^all_hosts "mkdir -p $YARN_PID_DIR && chown yarn:hadoop $YARN_PID_DIR"
pdsh -R ssh -w ^all_hosts "mkdir -p $HADOOP_PID_DIR && chown hdfs:hadoop $HADOOP_PID_DIR"
pdsh -R ssh -w ^all_hosts "mkdir -p $HADOOP_MAPRED_PID_DIR && chown mapred:hadoop $HADOOP_MAPRED_PID_DIR"

echo "Editing Hadoop environment scripts for log directories on all hosts..."
pdsh -R ssh -w ^all_hosts echo "export HADOOP_LOG_DIR=$HADOOP_LOG_DIR >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"
pdsh -R ssh -w ^all_hosts echo "export YARN_LOG_DIR=$YARN_LOG_DIR >> $HADOOP_HOME/etc/hadoop/yarn-env.sh"
pdsh -R ssh -w ^all_hosts echo "export HADOOP_MAPRED_LOG_DIR=$HADOOP_MAPRED_LOG_DIR >> $HADOOP_HOME/etc/hadoop/mapred-env.sh"

echo "Editing Hadoop environment scripts for pid directories on all hosts..."
pdsh -R ssh -w ^all_hosts echo "export HADOOP_PID_DIR=$HADOOP_PID_DIR >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"
pdsh -R ssh -w ^all_hosts echo "export YARN_PID_DIR=$YARN_PID_DIR >> $HADOOP_HOME/etc/hadoop/yarn-env.sh"
pdsh -R ssh -w ^all_hosts echo "export HADOOP_MAPRED_PID_DIR=$HADOOP_MAPRED_PID_DIR >> $HADOOP_HOME/etc/hadoop/mapred-env.sh"

echo "Creating base Hadoop XML config files..."
create_config --file core-site.xml
put_config --file core-site.xml --property fs.default.name --value "hdfs://$HOSTNAME:9000"
put_config --file core-site.xml --property hadoop.http.staticuser.user --value "hdfs"
create_config --file hdfs-site.xml
put_config --file hdfs-site.xml --property dfs.namenode.name.dir --value "$NN_DATA_DIR"
put_config --file hdfs-site.xml --property fs.checkpoint.dir --value "$SNN_DATA_DIR"
put_config --file hdfs-site.xml --property fs.checkpoint.edits.dir --value "$SNN_DATA_DIR"
put_config --file hdfs-site.xml --property dfs.datanode.data.dir --value "$DN_DATA_DIR"
put_config --file hdfs-site.xml --property dfs.namenode.http-address --value "$HOSTNAME:50070"
put_config --file hdfs-site.xml --property dfs.namenode.secondary.http-address --value "$HOSTNAME:50090"
create_config --file mapred-site.xml
put_config --file mapred-site.xml --property mapreduce.framework.name --value yarn
put_config --file mapred-site.xml --property mapreduce.jobhistory.address --value "$HOSTNAME:10020"
put_config --file mapred-site.xml --property mapreduce.jobhistory.webapp.address --value "$HOSTNAME:19888"
put_config --file mapred-site.xml --property yarn.app.mapreduce.am.staging-dir --value /mapred
create_config --file yarn-site.xml
put_config --file yarn-site.xml --property yarn.nodemanager.aux-services --value mapreduce_shuffle
put_config --file yarn-site.xml --property yarn.nodemanager.aux-services.mapreduce.shuffle.class --value org.apache.hadoop.mapred.ShuffleHandler
put_config --file yarn-site.xml --property yarn.web-proxy.address --value "$HOSTNAME:8081"
put_config --file yarn-site.xml --property yarn.resourcemanager.scheduler.address --value "$HOSTNAME:8030"
put_config --file yarn-site.xml --property yarn.resourcemanager.resource-tracker.address --value "$HOSTNAME:8031"
put_config --file yarn-site.xml --property yarn.resourcemanager.address --value "$HOSTNAME:8032"
put_config --file yarn-site.xml --property yarn.resourcemanager.admin.address --value "$HOSTNAME:8033"
put_config --file yarn-site.xml --property yarn.resourcemanager.webapp.address --value "$HOSTNAME:8088"

echo "Copying base Hadoop XML config files to all hosts..."
pdcp -R ssh -w ^all_hosts core-site.xml hdfs-site.xml mapred-site.xml yarn-site.xml $HADOOP_HOME/etc/hadoop/

echo "Fix JAVA_HOME Env"
pdsh -R ssh -w ^all_hosts echo "export JAVA_HOME=${JAVA_HOME} >> $HADOOP_HOME/etc/hadoop/hadoop-env.sh"
pdsh -R ssh -w ^all_hosts echo "export JAVA_HOME=${JAVA_HOME} >> /etc/profile"
pdsh -R ssh -w ^all_hosts echo "export CLASSPATH=.:${JAVA_HOME}/lib >> /etc/profile"
pdsh -R ssh -w ^all_hosts echo "export PATH=.:${JAVA_HOME}/bin:${PATH} >> /etc/profile"

echo "Cleaning..."
rm -rf *.xml
rm -rf all_hosts slaves dn_hosts nn_host snn_host

echo "***********************************************************************"
echo "Deploy Success! Please format hdfs and start service at $HOSTNAME"
echo "***********************************************************************"





