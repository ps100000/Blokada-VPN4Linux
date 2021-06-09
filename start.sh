start_wireguard () {
	echo "Start wireguard interface now [Y/n]?"
	read -n 1 start
	echo ""
	case $start in
		y|Y)
			sudo wg-quick up blokada >& /dev/null
			if [[ $? == 0 ]]; then
				echo "Wireguard started successfully."
			else
				echo "Something went wrong; the connection couldn't build up."
				exit 1
			fi
			;;
		n|N)
			echo "All right, exiting now."
			exit 0
			;;
		*)
			echo "This is not a valid option. Type y(es) or n(o)."
			start_wireguard
			;;
	esac
}

echo "                                                           "
echo "                        //         /////((((.         ((   "
echo "                       /////////////////((((((((((((((((.  "
echo "                       ////////////////     *((((((((((((  "
echo "                       ///   ///////////(/           .(((  "
echo "                       ///      ////////((((          (((  "
echo "                       ///         /////(((((((       (((  "
echo "                       ///,////       //((((((((((   *(((  "
echo "                       ////  ///////     (((((((((((,(((,  "
echo "                        ///    /////////(   ((((((((((((   "
echo "                        .///     ,//////(((((, ((((((((    "
echo "                         ,///       ////((((((((((((((     "
echo "                          ,////       //(((((((((((((      "
echo "                            ////         (((((((((((       "
echo "                             /////         (((((((         "
echo "                               /////        (((((          "
echo "                                 /////    (((((            "
echo "                                   /////(((((              "
echo "                                     ///((*                "



echo "What's your account id?(press enter to create a new one)"
read -n 12 accid
echo ""


echo "Checking for curl and jq installation..."

if  which dpkg-query apt >& /dev/null; then
	dpkg-query -W curl jq >& /dev/null
	if (( $? != 0 )) ; then
		echo "Installing curl and jq..."
		sudo apt install -y curl jq >& /dev/null
	fi
elif which pacman >& /dev/null ; then
	pacman -Qi curl jq >& /dev/null
	if (( $? != 0 )) ; then
		echo "Installing curl and jq..." ;
		sudo pacman -S --noconfirm curl jq >& /dev/null;
	fi
else
	echo "unsupported package manager"
	exit -1	
fi
if (( $? != 0 )); then
	echo "Failed to install curl or jq"
	exit -1
fi

if [[ -z $accid ]]; then
	echo "Creating new account..."
	accid=$(curl -# -XPOST https://api.blocka.net/v1/account | jq .account.id | sed -e 's/\"//g')
	if [[ -n $(echo $accid | sed -E -e 's/[a-z]{12}//') ]]; then
		echo "Failed to create new account."
		exit -1
	fi
	echo "Your new account id is $accid. Please write it down as there is no way to recover it later."
	sleep 5
	echo "After your done press enter."
	read
	echo "Activate your account under https://app.blokada.org/activate/$accid"
	sleep 5
	echo "After your done press enter." 
	read
fi

if [[ -n $(echo $accid | sed -E -e 's/[a-z]{12}//') ]]; then
	echo "invalid account id."
	exit -1
fi

echo "Checking account state..."
if [[ $(curl -# "https://api.blocka.net/v1/account?account_id=$accid" | jq .account.active ) == true ]] ; then
	echo "Account is active. Starting wireguard setup."
else
	echo "Account is inactive. Activate your account under https://app.blokada.org/activate/$accid and try again."
	exit -1
fi


echo "Checking for Wireguard installation..."

if  which dpkg-query apt >& /dev/null ; then
	dpkg-query -W wireguard resolvconf >& /dev/null
	if (( $? != 0 )) ; then
		echo "Installing wireguard..."
		if [[ -n $(cat /etc/os-release | grep -i 'name=.*kali') ]]; then
			echo "I <3 Kali"
		elif [[ -n $(cat /etc/os-release | grep -E -i 'name=.*(buntu|mint)') ]]; then
			sudo add-apt-repository ppa:wireguard/wireguard
			sudo apt-get update
		elif [[ -n $(cat /etc/os-release | grep -i 'name=.*debian') ]]; then
			echo "deb http://deb.debian.org/debian/ unstable main" | sudo tee /etc/apt/sources.list.d/unstable.list
			printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' | sudo tee /etc/apt/preferences.d/limit-unstable
			sudo apt update
		else
			echo "unknown distro"
			exit -1
		fi
		sudo apt install -y wireguard resolvconf >& /dev/null
	fi
elif which pacman >& /dev/null ; then
	pacman -Qi wireguard-tools wireguard-arch >& /dev/null
	if (( $? != 0 )) ; then
		echo "Installing wireguard..." ;
		sudo pacman -S --noconfirm wireguard-tools wireguard-arch >& /dev/null;
	fi
else
	echo "unsupported package manager"
	exit -1	
fi
if (( $? != 0 )); then
	echo "Failed to install wireguard"
	exit -1
fi

echo "Wireguard installation found"
echo "Checking for runing Blokada VPN..."
sudo wg show blokada >& /dev/null
if (( $? == 0 )) ; then
	echo "Stoping Blokada VPN..."
	sudo wg-quick down blokada >& /dev/null
	sleep 5
fi

echo "Checking for existing keypair..."
sudo mkdir -p /etc/wireguard/
sudo chmod 700 /etc/wireguard/
cd /etc/wireguard/
sudo [ -d /etc/wireguard/ ] || (echo "Failed creating /etc/wireguard/"; exit -1)
if sudo test ! -s "/etc/wireguard/blokada_pub" ; then
	echo "No keypair found. Creating..."
	sudo wg genkey | sudo tee blokada_privatekey | sudo wg pubkey | sudo tee blokada_pub
	echo "Keypair generated."
else
	echo "Keypair found."
fi

GATEWAYS=$(curl -# "https://api.blocka.net/v1/gateway")
echo "Gateways:"
for ((i=0;i<=$(echo $GATEWAYS | jq '.gateways | length - 1');i++)); do
  echo -n $i ':'
  echo $( echo $GATEWAYS | jq ".gateways[$i].location" ) | sed -E -e 's/[-"]/ /g' -e 's/\b(.)/\u\1/g'
done

while [[ -z $selgateway ]] || [[ $(echo $GATEWAYS | jq ".gateways[$selgateway]") == null ]]
do
	echo "Which gateway do you want to use?"
	read selgateway
done

GATEWAYPUB=$(echo $GATEWAYS | jq ".gateways[$selgateway].public_key")
CLIENTPUB=$(sudo cat blokada_pub)

echo "Looking for existing lease..."

LEASES=$(curl -# "https://api.blocka.net/v1/lease?account_id=$accid")
LEASE=$(echo $LEASES | jq ".leases | map(select(.account_id == \"$accid\")) | map(select(.public_key == \"$CLIENTPUB\"))[0]")
if [[ $(echo $LEASE | jq ".gateway_id") == $GATEWAYPUB ]] ; then
	echo "Already active."
else
	if [[ $LEASE != "null" ]] ; then
		echo "Deleting old lease..."
	 	curl -# -d "{\"account_id\":\"${accid}\",\
\"public_key\":\"$CLIENTPUB\",\
\"gateway_id\":\"$(echo $LEASE | jq ".gateway_id")\"}"\
			-X "DELETE" "http://api.blocka.net/v1/lease"
 		sleep 5
	fi

	if sudo test -s /etc/wireguard/blokada.conf ; then
		ALIAS=$(sudo grep "#Alias = .*" /etc/wireguard/blokada.conf | sed -e "s/#Alias = //")
	fi
	if [[ -z $ALIAS ]]; then
		echo "What Alias do you want to use? (empty for default)"
		read ALIAS
		if [[ -z $ALIAS ]]; then
			ALIAS="Linux in a box"
		fi
	fi

	echo "Creating lease..."
	LEASE=$(curl -# -d "{\"account_id\":\"$accid\",\
\"public_key\":\"$CLIENTPUB\",\
\"gateway_id\":$GATEWAYPUB,\
\"alias\":\"$ALIAS\"}" \
"http://api.blocka.net/v1/lease" | jq ".lease")
	sleep 5
fi

echo "Checking old config..."

if sudo test -s /etc/wireguard/blokada.conf && [[ -n $(sudo grep -z "$(sudo cat blokada_privatekey).*$(echo $GATEWAYPUB | sed -e 's/\"//g' )" /etc/wireguard/blokada.conf | tr '\0' '0') ]]; then
	echo "No changes in config."
	start_wireguard
fi

if sudo test -s /etc/wireguard/blokada.conf ; then
	DNS=$(sudo grep "DNS = .*" /etc/wireguard/blokada.conf | sed -e "s/DNS = //")
fi
if [[ -z $DNS ]]; then
	echo "What DNS do you want to use?"
	read DNS
fi

ADDRESS=$(echo $LEASE | jq ".vip4" | sed -e 's/\"//g')
ENDPOINT="$(echo $GATEWAYS | jq ".gateways[$selgateway].ipv4" | sed -e 's/\"//g'):$(echo $GATEWAYS | jq ".gateways[$selgateway].port")"

echo "Creating new config..."
echo "[Interface]" | sudo tee /etc/wireguard/blokada.conf
echo "Address = $ADDRESS/32" | sudo tee -a /etc/wireguard/blokada.conf
echo "PrivateKey = $(sudo cat blokada_privatekey)" | sudo tee -a /etc/wireguard/blokada.conf
echo "DNS = $DNS" | sudo tee -a /etc/wireguard/blokada.conf
echo "" | sudo tee -a /etc/wireguard/blokada.conf
echo "[Peer]" | sudo tee -a /etc/wireguard/blokada.conf
echo "PublicKey = $(echo $GATEWAYPUB | sed -e 's/\"//g' )" | sudo tee -a /etc/wireguard/blokada.conf
echo "Endpoint = $ENDPOINT" | sudo tee -a /etc/wireguard/blokada.conf
echo "AllowedIPs = 0.0.0.0/0,::/0" | sudo tee -a /etc/wireguard/blokada.conf
echo "PersistentKeepalive = 21" | sudo tee -a /etc/wireguard/blokada.conf
echo "#Alias = $ALIAS" | sudo tee -a /etc/wireguard/blokada.conf
echo "" | sudo tee -a /etc/wireguard/blokada.conf

echo "Done!"
echo ""

start_wireguard
