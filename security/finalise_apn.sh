if [ ! -f hologram_apn_encoded.cer ]; then
   echo "Read README.md, could not find hologram_apn_encoded.cer"
   exit 1
fi

openssl x509 -in hologram_apn_encoded.cer -inform der -out hologram_apn.cer
cat hologram_apn.cer hologram_apn.key > hologram_private.cer
