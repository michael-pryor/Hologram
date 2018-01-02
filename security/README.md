# Security
This folder contains scripts which generate certificates and private keys using openssl.

There are two places where SSL is used.
1. Communication between the commander and governor. The commander routes clients (app users) to the governor; the governor does all the heavy lifting. Commander and governor communicate with each other, discussing governor load so that the commander can route to the governor with the most available bandwidth.
2. Communication with Apple APN servers to facilitate remote push notifications to the iOS application. These must be renewed yearly.

# generate.sh
This script will generate hologram.crt, hologram.csr and hologram.key, which are used exclusively for communication between the commander and governor. There should be no complications in this step, simply run the script.

# generate_apn_cert.sh
This script will generate hologram_apn.key and hologram_apn_request.csr, which are used exclusively with Apple APN servers.

hologram_apn.key is the private key; be sure not to disclose this to untrusted third parties. hologram_apn_request.csr is a certificate signing request and should be provided to Apple in their configuration portal; they ask for a .certSigningRequest, this is the same as a .csr file.

Apple's certificate generation process produces a DER encoded certificate file. You should copy this onto your server's security folder and call it hologram_apn_encoded.cer. The script finalise_apn.sh will convert this from DER into a plain text certificate, outputting to hologram_apn.cer. The script will then produce a file called hologram_private.cer which contains both the certificate and private key in plain text form - you should see BEGIN CERTIFICATE and BEGIN RSA PRIVATE KEY if everything worked properly.

