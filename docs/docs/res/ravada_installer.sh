RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
echo "///////////////////////////////"
echo "       RAVADA INSTALLER        "
echo "///////////////////////////////"
OS=''
VER=''
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
  VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  OS=$(lsb_release -si)
  VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
  . /etc/lsb-release
  OS=$DISTRIB_ID
  VER=$DISTRIB_RELEASE
elif [ -f /etc/redhat-release ]; then
  . /etc/redhat-release
  OS=$NAME
  VER=$VERSION_ID
fi
echo "Detected OS=$OS VERSION=$VER"
if [[ $OS = *"Ubuntu"* || $OS = *"Fedora"* && $VER > '25' ]]; then
  echo "Starting Installation!"
  echo ""
else
  echo "This script doesn't support your OS, try to install ravada following the oficial instructions."
  exit 1
fi

if [[ $OS = *"Ubuntu"* && $VER > '16.04' ]]; then
  echo "Downloading..."
  sudo apt-get install libmojolicious-plugin-renderfile-perl -y &> /dev/null

  wget http://infoteleco.upc.edu/img/debian/ravada_2.1.7_ubuntu-18.04_all.deb
  sudo dpkg -i ravada_2.1.7_ubuntu-18.04_all.deb &> /dev/null
  echo "Installing Dependencies..."
  sudo apt-get update -y &> /dev/null
  sudo apt-get -f -y install &> /dev/null

  if [[ $? = 0 ]]; then
  	echo ""
  	echo -e "${GREEN}¡RAVADA Installed!${NC}"
  	echo ""
  	echo ""
  else
  	echo -e "${RED}There were an error installing dependencies...${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  # A veces se queda dpkg bloqueado..
  if lsof /var/lib/dpkg/lock >> /dev/null; then
  	#Esta bloqueado, la ultima aplicación no lo ha liberado?
  	echo -e "${RED}dpkg is busy, execute me again when it finishes..${NC}"
  	echo "If dpkg keeps busy, try rebooting you system or 'sudo rm -f /var/lib/dpkg/lock'"
  	exit 1
  fi
  echo "Going to install MySQL"
  echo "What root password would you like to use?"
  read mpass
  echo "mysql-server-5.7 mysql-server/root_password password $mpass" | sudo debconf-set-selections
  echo "mysql-server-5.7 mysql-server/root_password_again password $mpass" | sudo debconf-set-selections
  sudo apt-get -y install mysql-server &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "MySQL installed!"
  else
  	echo -e "${RED}Error Installing MySQL..${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi

  echo "Creating the database.."
  sudo mysqladmin -uroot -p$mpass create ravada
  echo ""
  echo "Password for mysql rvd_user?"
  read rvdPass
  sudo mysql -u root -p$mpass ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by '$rvdPass'" &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "rvd_user Correctly created!"
  else
  	echo -e "${RED}Error creating rvd_user!${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  sudo sed -i -e "s/changeme/$rvdPass/g" /etc/ravada.conf &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "Ravada Configurated!"
  else
  	echo -e "${RED}Error Configurating Ravada. Does /etc/ravada.conf exists?${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Creating Ravada Web User"
  echo "Name for your web user:"
  read webuser
  sudo /usr/sbin/rvd_back --add-user $webuser
  if [[ $? = 0 ]]; then
  	echo "Ravada Web User Correctly Created!"
  else
  	echo -e "${RED}Error creating Ravada Web User${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Enabling and starting daemons.."
  sudo systemctl daemon-reload &> /dev/null
  sudo systemctl enable rvd_back &> /dev/null
  sudo systemctl enable rvd_front &> /dev/null
  sudo systemctl start rvd_back &> /dev/null
  sudo systemctl start rvd_front &> /dev/null
  if [[ $? = 0 ]]; then
  	echo ""
  	echo "You should probably configure your firewall:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo "And better securitize your production server:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo ""
  	echo -e "${GREEN}Thank you to use Ravada.${NC}"
  else
  	echo -e "${RED}Error enabling and starting daemons...${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi

elif [[ $OS = *"Ubuntu"* ]]; then
  wget http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb &> /dev/null
	sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb &> /dev/null

  wget http://infoteleco.upc.edu/img/debian/ravada_2.1.7_all.deb &> /dev/null
  sudo dpkg -i ravada_2.1.7_all.deb &> /dev/null
  echo "Installing Dependencies..."
  sudo apt-get update -y &> /dev/null
  sudo apt-get -f -y install &> /dev/null

  if [[ $? = 0 ]]; then
  	echo ""
  	echo -e "${GREEN}¡RAVADA Installed!${NC}"
  	echo ""
  	echo ""
  else
  	echo -e "${RED}There were an error installing dependencies...${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  # A veces se queda dpkg bloqueado..
  if lsof /var/lib/dpkg/lock >> /dev/null; then
  	#Esta bloqueado, la ultima aplicación no lo ha liberado?
  	echo -e "${RED}dpkg is busy, execute me again when it finishes..${NC}"
  	echo "If dpkg keeps busy, try rebooting you system or 'sudo rm -f /var/lib/dpkg/lock'"
  	exit 1
  fi

  #install correct version of mysql..
  echo "Going to install MySQL"
  echo "What root password would you like to use?"
  read mpass
  echo "mysql-server-5.6 mysql-server/root_password password $mpass" | sudo debconf-set-selections
  echo "mysql-server-5.6 mysql-server/root_password_again password $mpass" | sudo debconf-set-selections
  sudo apt-get -y install mysql-server-5.6 &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "MySQL installed!"
  else
  	echo -e "${RED}Error Installing MySQL..${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi

  echo "Creating the database.."
  sudo mysqladmin -uroot -p$mpass create ravada
  echo ""
  echo "Password for mysql rvd_user?"
  read rvdPass
  sudo mysql -u root -p$mpass ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by '$rvdPass'" &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "rvd_user Correctly created!"
  else
  	echo -e "${RED}Error creating rvd_user!${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  sudo sed -i -e "s/changeme/$rvdPass/g" /etc/ravada.conf &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "Ravada Configurated!"
  else
  	echo -e "${RED}Error Configurating Ravada. Does /etc/ravada.conf exists?${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Creating Ravada Web User"
  echo "Name for your web user:"
  read webuser
  sudo /usr/sbin/rvd_back --add-user $webuser
  if [[ $? = 0 ]]; then
  	echo "Ravada Web User Correctly Created!"
  else
  	echo -e "${RED}Error creating Ravada Web User${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Enabling and starting daemons.."
  sudo systemctl daemon-reload &> /dev/null
  sudo systemctl enable rvd_back &> /dev/null
  sudo systemctl enable rvd_front &> /dev/null
  sudo systemctl start rvd_back &> /dev/null
  sudo systemctl start rvd_front &> /dev/null
  if [[ $? = 0 ]]; then
  	echo ""
  	echo "You should probably configure your firewall:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo "And better securitize your production server:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo ""
  	echo -e "${GREEN}Thank you to use Ravada.${NC}"
  else
  	echo -e "${RED}Error enabling and starting daemons...${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi

elif [[ $OS = *"Fedora"* ]]; then
  sudo dnf copr enable eclipseo/ravada -y &> /dev/null
  sudo dnf install ravada -y &> /dev/null
  if [[ $? = 0 ]]; then
    echo ""
    echo -e "${GREEN}¡RAVADA Installed!${NC}"
    echo ""
    echo ""
  else
    echo -e "${RED}There were an error installing dependencies...${NC}"
    echo -e "${RED}Check the installation guide to find a solution:${NC}"
    echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
    exit 1
  fi
  echo "Installing MariaDB"
  sudo dnf install mariadb mariadb-server -y &> /dev/null
  if [[ $? = 0 ]];then
    echo "MariaDB correctly installed."
  else
    echo "${RED}Error installing mariadb..${NC}"
    exit 1
  fi
  echo "Starting MariaDB service."
  sudo systemctl enable --now mariadb.service &> /dev/null
  sudo systemctl start mariadb.service &> /dev/null

  echo "Creating the database.."
  sudo mysqladmin -uroot create ravada
  echo ""
  echo "Password for mysql rvd_user?"
  read rvdPass
  sudo mysql -u root ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by '$rvdPass'" &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "rvd_user Correctly created!"
  else
  	echo -e "${RED}Error creating rvd_user!${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  sudo sed -i -e "s/changeme/$rvdPass/g" /etc/ravada.conf &> /dev/null
  if [[ $? = 0 ]]; then
  	echo "Ravada Configurated!"
  else
  	echo -e "${RED}Error Configurating Ravada. Does /etc/ravada.conf exists?${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Creating Ravada Web User"
  echo "Name for your web user:"
  read webuser
  sudo /usr/sbin/rvd_back --add-user $webuser
  if [[ $? = 0 ]]; then
  	echo "Ravada Web User Correctly Created!"
  else
  	echo -e "${RED}Error creating Ravada Web User${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi
  echo ""
  echo "Enabling and starting daemons.."
  sudo systemctl daemon-reload &> /dev/null
  sudo systemctl enable rvd_back &> /dev/null
  sudo systemctl enable rvd_front &> /dev/null
  sudo systemctl start rvd_back &> /dev/null
  sudo systemctl start rvd_front &> /dev/null
  if [[ $? = 0 ]]; then
  	echo ""
  	echo "You should probably configure your firewall:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo "And better securitize your production server:"
  	echo " http://ravada.readthedocs.io/en/latest/docs/production.html"
  	echo ""
  	echo -e "${GREEN}Thank you to use Ravada.${NC}"
  else
  	echo -e "${RED}Error enabling and starting daemons...${NC}"
  	echo -e "${RED}Check the installation guide to find a solution:${NC}"
  	echo "https://ravada.readthedocs.io/en/latest/docs/INSTALL.html"
  	exit 1
  fi

fi
