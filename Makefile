HOST='root@erebe.eu'
RASPBERRY='pi@10.200.200.2'

.PHONY: install deploy release dns sudo ssh package iptables kubernetes_install k8s dovecot postfix nextcloud nextcloud_resync_file backup app wireguard pihole webhook blog minio

deploy: dns sudo ssh package iptables k8s dovecot postfix nextcloud webhook backup wireguard blog

release:
ifdef ARGS
	$(eval SECRET := $(shell sops exec-env secrets/webhook.yml 'echo $${DEPLOYER_SECRET}'))
	curl -i -X POST  \
		-H 'Content-Type: application/json' \
		-H 'X-Webhook-Token: '${SECRET} \
		-d '{ "application_name": "$(ARGS)", "image_tag": "latest" }' \
		-s https://hooks.erebe.eu/hooks/deploy 
endif
		
install:
	sops -d --extract '["public_key"]' --output ~/.ssh/erebe_eu.pub secrets/ssh.yml
	sops -d --extract '["private_key"]' --output ~/.ssh/erebe_eu secrets/ssh.yml
	chmod 600 ~/.ssh/erebe_eu*
	grep -q erebe.eu ~/.ssh/config > /dev/null 2>&1 || cat config/ssh_client_config >> ~/.ssh/config
	mkdir ~/.kube || exit 0
	sops -d --output ~/.kube/config secrets/kubernetes-config.yml


dns:
	sops -d --output secrets_decrypted/gandi.yml secrets/gandi.yml
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eu -f dns/erebe.eu.zones
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.dev -f dns/erebe.dev.zones

ssh:
	ssh ${HOST} "cat /etc/ssh/sshd_config" | diff  - config/sshd_config \
		|| (scp config/sshd_config ${HOST}:/etc/ssh/sshd_config && ssh ${HOST} systemctl restart sshd)

sudo:
	scp config/sudoers ${HOST}:/etc/sudoers.d/erebe

package:
	scp wireguard/wireguard-backport.list ${HOST}:/etc/apt/sources.list.d/
	ssh ${HOST} 'apt-get update && apt-get install -y curl htop mtr tcpdump ncdu vim dnsutils strace linux-perf iftop wireguard'
	# Enable automatic security Updates
	ssh ${HOST} 'echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections && apt-get install unattended-upgrades -y'
	# IPv6
	sops -d --output secrets_decrypted/dhclient6.conf secrets/dhclient6.conf
	scp secrets_decrypted/dhclient6.conf ${HOST}:/etc/dhcp/dhclient6.conf
	scp config/dhclient6.service ${HOST}:/etc/systemd/system/
	ssh ${HOST} 'systemctl daemon-reload && systemctl enable dhclient6.service && systemctl restart dhclient6.service'

iptables:	
	scp config/iptables ${HOST}:/etc/network/if-pre-up.d/iptables-restore
	ssh ${HOST} 'chmod +x /etc/network/if-pre-up.d/iptables-restore && sh /etc/network/if-pre-up.d/iptables-restore'
	
kubernetes_install:
	ssh ${HOST} 'export INSTALL_K3S_EXEC=" --no-deploy servicelb --no-deploy traefik --no-deploy local-storage --disable-cloud-controller --disable-network-policy --advertise-address 10.200.200.1 "; \
		curl -sfL https://get.k3s.io | sh -'
	#ssh ${HOST} "cat /etc/systemd/system/k3s.service" | diff  - k8s/k3s.serivce \
		|| (scp k8s/k3s.service ${HOST}:/etc/systemd/system/k3s.serviceg && ssh ${HOST} 'systemctl daemon-reload && systemctl restart k3s.service')

k8s:
	#helm3 repo add stable https://kubernetes-charts.storage.googleapis.com/
	#helm3 repo update
	kubectl apply -f k8s/ingress-nginx-v1.1.0.yml
	kubectl apply --validate=false -f k8s/cert-manager-v1.6.1.yml
	kubectl apply -f k8s/lets-encrypt-issuer.yml

dovecot:
	sops -d --output secrets_decrypted/dovecot.yml secrets/dovecot.yml
	kubectl apply -f secrets_decrypted/dovecot.yml
	kubectl apply -f dovecot/dovecot.yml

postfix:
	sops -d --output secrets_decrypted/fetchmail.yml secrets/fetchmail.yml
	kubectl apply -f secrets_decrypted/fetchmail.yml
	kubectl apply -f postfix/postfix.yml

nextcloud:
	kubectl apply -f nextcloud/config.nginx.site-confs.default.yml
	kubectl apply -f nextcloud/nextcloud.yml

nextcloud_resync_file:
	kubectl exec -t $(shell kubectl get pods -n default -l app=nextcloud -o json | jq .items[].metadata.name) -- sudo -u abc /config/www/nextcloud/occ files:scan --all

backup:
	sops -d --output secrets_decrypted/backup_ftp_credentials.yml secrets/backup_ftp_credentials.yml
	kubectl apply -f secrets_decrypted/backup_ftp_credentials.yml
	kubectl apply -f backup/backup-cron.yml

webhook:
	sops exec-env secrets/webhook.yml 'cp webhook/webhook.yml secrets_decrypted/; for i in $$(env | grep _SECRET | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/webhook.yml ; done'
	kubectl apply -f secrets_decrypted/webhook.yml

app:
	kubectl apply -f app/couber.yml
	kubectl apply -f app/crawler.yml
	kubectl apply -f app/wstunnel.yml

blog:
	kubectl apply -f blog/blog.yml

wireguard:
	sops exec-env secrets/wireguard.yml 'cp wireguard/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
	ssh ${HOST} "cat /etc/wireguard/wg0.conf" | diff  - secrets_decrypted/wg0.conf \
		|| (scp secrets_decrypted/wg0.conf ${HOST}:/etc/wireguard/wg0.conf && ssh ${HOST} systemctl restart wg-quick@wg0)
	ssh ${HOST} 'systemctl enable wg-quick@wg0'


pihole:
	sops exec-env secrets/wireguard.yml 'cp pihole/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
	rsync --rsync-path="sudo rsync" secrets_decrypted/wg0.conf ${RASPBERRY}:/etc/wireguard/wg0.conf 
	ssh ${RASPBERRY} 'sudo systemctl enable wg-quick@wg0; sudo systemctl restart wg-quick@wg0'
	kubectl apply -f pihole/pihole.yml

minio:
	sops -d --output secrets_decrypted/minio.yml secrets/minio.yml
	kubectl apply -f secrets_decrypted/minio.yml
	kubectl apply -f minio/minio.yml
