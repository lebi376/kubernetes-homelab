echo "Sealing cloudflare-secret.yaml"
kubeseal --cert public-key.pem --format yaml < ../secrets/cloudflare-secret.yaml > ../cloudflare/cloudflare-sealed-secret.yaml
echo "Sealing hetzner-sb-creds.yaml"
kubeseal --cert public-key.pem --format yaml < ../secrets/hetzner-sb-creds.yaml > ../storage-provisioner/hetzner-sealed-sb-creds.yaml
echo "Sealing nextcloud-db-creds.yaml"
kubeseal --cert public-key.pem --format yaml < ../secrets/nextcloud-db-creds.yaml > ../nextcloud/nextcloud-sealed-db-creds.yaml
echo "Sealing vaultwarden-db-creds.yaml"
kubeseal --cert public-key.pem --format yaml < ../secrets/vaultwarden-db-creds.yaml > ../vaultwarden/vaultwarden-sealed-db-creds.yaml
echo "Sealing vaultwarden-admin-vars.yaml"
kubeseal --cert public-key.pem --format yaml < ../secrets/vaultwarden-admin-vars.yaml > ../vaultwarden/vaultwarden-sealed-admin-vars.yaml