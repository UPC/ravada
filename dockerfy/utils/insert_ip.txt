Issue 1194 

Step to follow to change IP temporary:

docker exec -it ravada-mysql bash
mysql -u root -p 
mysql> update vms set public_ip="<HOST_IP>" where id=1;

