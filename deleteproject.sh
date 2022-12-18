#!/bin/bash

while true; do

echo "!!! DANGER !!! you are going to delete project" "=>" $1

read -p "Are you shure to clean this project? (Y/N) " yn

case $yn in
        [yY] ) echo ok, we will proceed;
                break;;
        [nN] ) echo exiting...;
                exit;;
        * ) echo invalid response;;
esac

done

echo "cleaning project ..."

for SERVER_ID in $(openstack  server list --project $1 --format json | jq -r '.[] | .ID')
do
openstack server delete $SERVER_ID
done
echo "Servers Has been deleted"

sleep 10

for VOLUME_ID in $(openstack volume list --project $1 --format json | jq -r '.[] | .ID')
do
openstack volume delete $VOLUME_ID
done
echo "Volumes Has been deleted"


for FLOAT_ID in $(openstack floating ip list --project $1 --format json | jq -r '.[] | .ID')
do
openstack floating ip delete $FLOAT_ID
done
echo "Float IP Has been Removed"

echo "Now loadbalancer deletion in progress if exist"
for LDB in $(openstack loadbalancer list --project $1 --format json | jq -r '.[].id')
do
openstack loadbalancer delete --cascade --wait $LDB
done

for SECGRP in $(openstack security group list --project $1 --format json | jq -r '.[].ID')
do
openstack security group delete $SECGRP
done
echo "security group has been delete"

ROUTER_ID=$(openstack router list --project $1 --format json | jq -r '.[] | .ID')

for ROUTER_PORTS in $(openstack router show $ROUTER_ID --format json | jq -r '.interfaces_info[]' | jq -r '.port_id')
do
openstack router remove port $ROUTER_ID $ROUTER_PORTS
done
openstack router unset --external-gateway $ROUTER_ID && openstack router delete $ROUTER_ID
echo "Router has been removed"

sleep 2

for PORT_ID in $(openstack port list --project $1 --format json |  jq -r '.[] | .ID')
do
openstack port delete $PORT_ID
done
echo "ALL ports Has been removed"


for SUBNETS_ID in $(openstack network list --project $1 --format json |  jq -r '.[] | .Subnets[]')
do
openstack subnet delete $SUBNETS_ID
done
echo "All Subnets Has been deleted"


for NETWORK_ID in $(openstack network list --project $1 --format json |  jq -r '.[] | .ID')
do
openstack network delete $NETWORK_ID
done
echo "All Networks Has been deleted"

TENANTID=$(openstack project show $1 --format json | jq -r '.id')

AGGRID=$(openstack aggregate list --long --format json | jq '.[] | {ID, "filter_tenant_id": .Properties["filter_tenant_id"] }' | jq -r 'select(.filter_tena>

if [ -z $AGGRID ];
then echo "Host aggrigate not exist!" ;
else
for AGGRHOST in $(openstack aggregate show $AGGRID --format json | jq -r '.hosts[]') ; do openstack aggregate remove host $AGGRID $AGGRHOST > /dev/null;don>sleep 10 && openstack aggregate delete $AGGRID && echo "Host aggregate Has been destroyed"
fi

openstack project set --disable $TENANTID

echo " *** The Project has been cleaned up and disabled *** "
