echo "What's the account id?"
read -n 12 accid
echo ""

echo "Checking for curl and jq installation..."
dpkg-query -W curl jq >& /dev/null
if (( $? != 0 )) ; then
	echo "Installing curl and jq..."
	sudo apt install -y curl jq >& /dev/null
fi
dpkg-query -W curl >& /dev/null
if (( $? != 0 )); then
	echo "Failed to install curl or jq"
	exit -1
fi

echo "Checking account state..."
if [[ $(curl -# "https://api.blocka.net/v1/account?account_id=$accid" | jq .account.active ) == true ]] ; then
	echo "Account is active. Starting wireguard setup."
else
	echo "Account is inactive. Activate your account and try again."
	exit -1
fi


echo "Checking for Wireguard installation..."
dpkg-query -W wireguard >& /dev/null
if (( $? != 0 )) ; then
	echo "Installing wireguard..."
	sudo apt install -y wireguard resolvconf >& /dev/null
fi
dpkg-query -W wireguard >& /dev/null
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
sudo chmod +rwx /etc/wireguard/
cd /etc/wireguard/
umask 077  # This makes sure credentials don't leak in a race condition.
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

	echo "Creating lease..."
	LEASE=$(curl -# -d "{\"account_id\":\"$accid\",\
\"public_key\":\"$CLIENTPUB\",\
\"gateway_id\":$GATEWAYPUB}" \
"http://api.blocka.net/v1/lease" | jq ".lease")
	sleep 5
fi

echo "Checking old config..."

if sudo test -s /etc/wireguard/blokada.conf && [[ -n $(sudo grep -z "$(sudo cat blokada_privatekey).*$GATEWAYPUB" /etc/wireguard/blokada.conf | tr '\0' '0') ]]; then
	echo "No changes in config."
	echo "Start wireguard interface now[Y/n]?"
	read -n 1 start
	echo ""
	if [[ -z $start ]] || [[ $start == "y" ]] || [[ $start == "Y" ]]; then
		sudo wg-quick up blokada >& /dev/null
		echo "Wireguard started."
	fi
	exit 0
fi

if sudo test -s /etc/wireguard/blokada.conf ; then
	DNS=$(sudo grep "DNS = .*" /etc/wireguard/blokada.conf | sed -e "s/DNS = //")
	if [[ -z $DNS ]]; then
		echo "What DNS do you want to use?"
		read DNS
	fi
else
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
echo "AllowedIPs = 0.0.0.0/0" | sudo tee -a /etc/wireguard/blokada.conf
echo "PersistentKeepalive = 21" | sudo tee -a /etc/wireguard/blokada.conf
echo "" | sudo tee -a /etc/wireguard/blokada.conf
sudo chmod -rwx /etc/wireguard/

echo "Done!"
echo ""
echo "Start wireguard interface now[Y/n]?"
read -n 1 start
echo ""
if [[ -z $start ]] || [[ $start == "y" ]] || [[ $start == "Y" ]]; then
	sudo wg-quick up blokada >& /dev/null
	echo "Wireguard started."
fi