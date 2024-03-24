#!/bin/bash

# F5 XC tenant details
tenant="xc-tenant"
namespace="app-namespace"
p12_file="./scripts/api_credential.p12"
export VES_P12_PASSWORD=""

# Check if the XC creds .p12 file exists
if [ -e "$p12_file" ]; then
    echo "The .p12 file exists. Continuing..."
else
    echo "Error: The .p12 file does not exist. Exiting."
    exit 1  # Exit the script with an error code
fi

# Setup vesctl
echo "Configuring vesctl..."
echo "server-urls: https://$tenant.console.ves.volterra.io/api" > ./scripts/.vesconfig
echo "p12-bundle: $p12_file" >> ./scripts/.vesconfig
echo "vesctl configured successfully."

# Script specific directories
certs_dir="./certs"
pub_dir="./sorted-keys"

# Create working directories if they don't exist
mkdir -p "$pub_dir"
echo "Working directories created successfully."

## Functions
# Function to extract Common Name
extract_cn() {
    cert_file=$1
    openssl x509 -noout -subject -in "$cert_file" | sed -n 's/^subject.*CN *= *\([^ ]*\).*$/\1/p'
}

# Function to check if the modulus of the private key matches the modulus of the corresponding public key
check_key_pair() {
    private_key=$1
    public_key=$2
    private_modulus=$(openssl rsa -in "$private_key" -noout -modulus)
    public_modulus=$(openssl x509  -noout -modulus -in "$public_key")
    if [ "$private_modulus" == "$public_modulus" ]; then
        echo "Matching pair found:"
        echo "Private Key: $private_key"
        echo "Public Key: $public_key"
        return 0
    else
        echo "No matching pair found for: $private_key"
        return 1
    fi
}

# Move public keys to public-keys directory
for file in "$certs_dir"/*.pem "$certs_dir"/*.crt; do
    if grep -q "CERTIFICATE" "$file"; then
        cn=$(extract_cn "$file")
        cp "$file" "$pub_dir/${cn}-pub.pem"
        echo "Public key moved: $file to $pub_dir/${cn}-pub.pem"
        echo "Public key moved: $file to $pub_dir/${cn}-pub.pem" >> script.log
    fi
done

# Loop through each public key and then another loop through each private key to find a match
for pub_key_file in "$pub_dir"/*.pem; do
    if [ -f "$pub_key_file" ]; then
        cn=$(basename "$pub_key_file" .pem)
        cn=${cn%-pub}
        for private_key_file in "$certs_dir"/*.pem "$certs_dir"/*.key; do
            if grep -q "PRIVATE" "$private_key_file"; then
                if check_key_pair "$private_key_file" "$pub_key_file"; then
                    cp "$private_key_file" "$pub_dir/${cn}-key.pem"
                    echo "Private key moved: $private_key_file to $pub_dir/${cn}-key.pem"
                    echo "Private key moved: $private_key_file to $pub_dir/${cn}-key.pem" >> script.log
                fi
            fi
        done
    fi
done

# Call Blindfold and vesctl
for public_key in "$pub_dir"/*-pub.pem; do
    base_name=$(basename -s -pub.pem "$public_key")
    private_key="$pub_dir/${base_name}-key.pem"
    # Execute blindfold if found private and public keys pair by name
    if [ -f "$private_key" ]; then
        echo "Processing keys for $base_name..."
        echo "Executing vesctl and Blindfold for public=$public_key and private=$private_key..."
        echo "Processing keys for $base_name..." >> script.log
        echo "Executing vesctl and Blindfold for public=$public_key and private=$private_key..." >> script.log
        blindfold_private_key=$(./scripts/blindfold.sh "$public_key" "$private_key" > blindfolded.tmp)
        cert_url=$(jq -r .cert blindfolded.tmp)
        location=$(jq -r .blindfold blindfolded.tmp)
        cert_name=$(basename "$public_key" | tr '.' '-')
        echo "Uploading certificate to Volterra..."
        echo "Uploading certificate to Volterra..." >> script.log
        curl --location "https://$tenant.console.ves.volterra.io/api/config/namespaces/$namespace/certificates" \
            --cert-type P12 \
            --cert $p12_file:$VES_P12_PASSWORD \
            --header 'Content-Type: application/json' \
            --data '{
                "metadata": {
                    "name": "'"$cert_name"'",
                    "namespace": "'"$namespace"'",
                    "labels": {},
                    "annotations": {},
                    "disable": false
                },
                "spec": {
                    "certificate_url": "'"$cert_url"'",
                    "private_key": {
                        "blindfold_secret_info": {
                            "location": "'"$location"'",
                            "decryption_provider": null,
                            "store_provider": null
                        },
                        "blindfold_secret_info_internal": null,
                        "secret_encoding_type": "EncodingNone"
                    },
                    "infos": []
                }
            }'
        # Sleep to avoid XC API rate limits    
        echo "Waiting before next iteration..."
        echo "Waiting before next iteration..." >> script.log
        sleep 3
    else
        echo "Error: Matching private key not found for $base_name."
        echo "Error: Matching private key not found for $base_name." >> script.log
    fi
done

# Clear blindfolded.tmp
echo "Clearing blindfolded.tmp..."
echo "Clearing blindfolded.tmp..." >> script.log
> blindfolded.tmp
echo "Script execution completed."
echo "Script execution completed." >> script.log

