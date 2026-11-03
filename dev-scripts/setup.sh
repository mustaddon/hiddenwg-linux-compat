apt-get install libelf-dev linux-headers-$(uname -r) build-essential pkg-config

curl -O https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
sudo bash wireguard-install.sh

#openssl req -new -nodes -utf8 -sha512 -days 36500 -batch -x509 -config x509.genkey -outform DER -out signing_key.x509 -keyout signing_key.pem
#sudo mv signing_key.pem signing_key.x509 `find /lib/modules/$(uname -r)/build/certs`
