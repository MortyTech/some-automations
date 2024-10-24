for i in $(ls -l /sys/class/net/ | egrep 'vlan|bond|pci|br' | grep -v bonding_masters | awk {'print $9'}) \
; do ip -br a | grep $i | awk '{print $1, $2, $3}' \
; done | sort | uniq | sed "s/^/$HOSTNAME /" | sed 's/ /,/g' | tee /tmp/interface.txt
for j in $(for i in $(ls -l /sys/class/net/ | egrep 'vlan|bond|pci|br' | grep -v bonding_masters | awk {'print $9'}) \
; do ip -br a | grep $i | awk '{print $1, $2, $3}' ; done | sort | uniq | awk {'print $1'}) \
; do echo $(sudo lldpcli show neighbors ports $j summary | grep PortDescr | awk {'print $2'}) $(sudo lldpcli show neighbors ports $j summary | grep SysName | awk {'print $2'}) ; done | tee /tmp/neighbor.txt
paste -d ',' /tmp/interface.txt /tmp/neighbor.txt | sed 's/ /,/g' | \
sed '1i hostname,interface,status,IPv4,neighbor port,neighbor hostname' | tee ~/portmap.csv
