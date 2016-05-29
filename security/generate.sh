#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
openssl genrsa -out "$DIR/hologram.key" 1024
openssl req -new -key "$DIR/hologram.key" -out "$DIR/hologram.csr"
openssl x509 -req -days 10000 -in "$DIR/hologram.csr" -signkey "$DIR/hologram.key" -out "$DIR/hologram.crt"
